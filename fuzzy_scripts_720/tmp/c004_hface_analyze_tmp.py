#!/usr/bin/env python3
"""REF-004 H 触发面定价：判定绿色语料生成码中 `&null_val` 回落支的运行时可达性。

输入：KEEP_TEMP 保留目录里的 main.zig 路径。

覆盖的调用形态（实测于 f042/f177 生成码）：
  A. 具名直调      `= try @"Class::m"(ctx, &[_]runtime.Value{...}, alloc);`
  B. 转发器        `return @"Class::m"(ctx, args, alloc);`（args 整组透传 ⇒ 动态面）
  C. 实例派发      `runtime.php_object_call(obj, "m", &[_]runtime.Value{...})`（语料主形态，f177 内 75 处）

引用位索引来自回落句本身（`args.len > I`），与被传实参列表同序（方法的 ctx 不计入 args）。
分类（REF_* ⇒ 回落 else 支不可达；VALUE_PASSED ⇒ else 支可达 = H 的实测命中面）：
  REF_FILLED      实参表达式含 Value.initRef( 或其寄存器最近定义含 make_ref(/Value.initRef(
  REF_FORWARDED   实参寄存器正是**本帧**回落支绑定的引用形参寄存器（上游帧已填 ⇒ 透传）
  REF_GLOBAL      实参寄存器最近定义为 getGlobalVar($x) ⇒ make_ref 会把该全局槽就地改写成 Ref（模板 :3066）⇒ 视为已填但单独计
  ARG_OMITTED     实参个数 <= 引用位索引 ⇒ PHP 侧为「未传参」，走 null 绑定（按设计）
  TRAMPOLINE      整组 args 透传（B 形态）
  VALUE_PASSED    其余 ⇒ else 支可达
"""
import re
import sys

FB = re.compile(
    r'reg_(\d+) = if \(args\.len > (\d+) and !args\[(\d+)\]\.isMissing\(\) and args\[(\d+)\]\.isRef\(\)\)'
    r' args\[\d+\]\.asRef\(\) else &null_val;'
)
FN = re.compile(r'^pub fn @"([^"]+)"\(')
OBJCALL = re.compile(r'runtime\.php_object_call\(')


def split_functions(lines):
    frames, start, name = [], None, None
    for i, ln in enumerate(lines):
        m = FN.match(ln)
        if m:
            if start is not None:
                frames.append((name, start, i))
            name, start = m.group(1), i
    if start is not None:
        frames.append((name, start, len(lines)))
    return frames


def top_level_args(text, open_idx):
    """从 open_idx（指向 '('）开始，返回顶层实参分段列表。"""
    depth, parts, cur, i = 0, [], [], open_idx
    while i < len(text):
        c = text[i]
        if c in "([{":
            depth += 1
            if depth == 1:
                i += 1
                continue
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                parts.append("".join(cur).strip())
                return parts
        if c == "," and depth == 1:
            parts.append("".join(cur).strip())
            cur = []
        else:
            cur.append(c)
        i += 1
    return parts


def value_list(expr):
    e = expr.strip()
    if e.startswith("&[_]runtime.Value{"):
        inner = e.split("{", 1)[1].rsplit("}", 1)[0]
        out, depth, cur = [], 0, []
        for c in inner:
            if c in "([{":
                depth += 1
            elif c in ")]}":
                depth -= 1
            if c == "," and depth == 0:
                out.append("".join(cur).strip())
                cur = []
            else:
                cur.append(c)
        if "".join(cur).strip():
            out.append("".join(cur).strip())
        return out
    return [e]


def main(path):
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()

    fb_by_name = {}
    for name, a, b in split_functions(lines):
        idxs, regs = set(), set()
        for ln in lines[a:b]:
            m = FB.search(ln)
            if m:
                idxs.add(int(m.group(2)))
                regs.add(int(m.group(1)))
        if idxs:
            fb_by_name[name] = (idxs, regs)

    frames = split_functions(lines)

    def frame_of(lineno):
        for name, a, b in frames:
            if a < lineno <= b:
                return name
        return None

    by_short = {}
    for name, (idxs, regs) in fb_by_name.items():
        by_short.setdefault(name.split("::")[-1], []).append((name, idxs, regs))

    print(f"# fallback_emitters={len(fb_by_name)} names={sorted(fb_by_name)}")
    stats = {k: 0 for k in ("REF_FILLED", "REF_FORWARDED", "REF_GLOBAL",
                            "ARG_OMITTED", "TRAMPOLINE", "VALUE_PASSED")}
    hits = []

    def classify(enclosing, expr, k, lineno):
        if expr == "args":
            return "TRAMPOLINE", "整组 args 透传"
        if "Value.initRef(" in expr or "make_ref(" in expr:
            return "REF_FILLED", expr[:70]
        rm = re.fullmatch(r"reg_(\d+)", expr)
        if not rm:
            return "VALUE_PASSED", expr[:70]
        r = int(rm.group(1))
        fname = frame_of(lineno)
        if fname and fname in fb_by_name and r in fb_by_name[fname][1]:
            return "REF_FORWARDED", f"reg_{r}（本帧引用形参透传）"
        rhs = None
        for j in range(lineno - 2, -1, -1):
            dm = re.match(rf"\s*reg_{r} = (.*)", lines[j])
            if dm:
                rhs = dm.group(1).strip()
                break
        if rhs is None:
            return "VALUE_PASSED", f"reg_{r} 无定义（形参/入参？）"
        if "make_ref(" in rhs or "Value.initRef(" in rhs:
            return "REF_FILLED", f"reg_{r} <- {rhs[:60]}"
        if rhs.startswith("getGlobalVar("):
            return "REF_GLOBAL", f"reg_{r} <- {rhs[:50]}"
        if re.match(r"^reg_\d+$", rhs):
            return classify(enclosing, rhs, k, j + 1)
        return "VALUE_PASSED", f"reg_{r} <- {rhs[:60]}"

    # A/B 形态：具名 @"Class::m"(
    for name, (idxs, regs) in sorted(fb_by_name.items()):
        pat = re.compile(r'@"' + re.escape(name) + r'"\(')
        for lineno, ln in enumerate(lines, 1):
            m = pat.search(ln)
            if not m or ln.lstrip().startswith("pub fn"):
                continue
            parts = top_level_args(ln, m.end() - 1)
            if len(parts) < 2:
                continue
            for k in sorted(idxs):
                passed = value_list(parts[1])
                if k >= len(passed):
                    stats["ARG_OMITTED"] += 1
                    hits.append(("ARG_OMITTED", name, lineno, f"pos {k} 未传"))
                    continue
                tag, detail = classify(name, passed[k], k, lineno)
                stats[tag] += 1
                hits.append((tag, name, lineno, detail))

    # C 形态：php_object_call(obj, "m", args)
    for lineno, ln in enumerate(lines, 1):
        for m in OBJCALL.finditer(ln):
            parts = top_level_args(ln, m.end() - 1)
            if len(parts) < 3:
                continue
            sm = re.fullmatch(r'"([^"]+)"', parts[1])
            if not sm or sm.group(1) not in by_short:
                continue
            for name, idxs, _ in by_short[sm.group(1)]:
                passed = value_list(parts[2])
                for k in sorted(idxs):
                    if k >= len(passed):
                        stats["ARG_OMITTED"] += 1
                        hits.append(("ARG_OMITTED", name, lineno, f"pos {k} 未传（object_call）"))
                        continue
                    tag, detail = classify(name, passed[k], k, lineno)
                    stats[tag] += 1
                    hits.append((tag, name, lineno, detail))

    for tag, nm, ln, detail in hits:
        print(f"  {tag:14s} @main.zig:{ln:<6d} {nm:34s} {detail}")
    print("CALLSITE_STATS " + " ".join(f"{k}={v}" for k, v in stats.items()))
    print("TOTAL_SITES " + str(sum(stats.values())))


if __name__ == "__main__":
    main(sys.argv[1])
