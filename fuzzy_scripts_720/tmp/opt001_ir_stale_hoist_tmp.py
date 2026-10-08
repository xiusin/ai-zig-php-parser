#!/usr/bin/env python3
"""AOT-OPT-001 §5.6 只读 IR 结构分析器（无源码改动、无插桩）。

输入：php-interpreter --compile --no-debug-info --no-link --emit-ir=<dump> 的 IR 文本
逻辑：按函数建 CFG（终止符边）→ DFS 找回边 → 回边导出「循环 = 头 + 能不经头到达源点的块」
      → pre-header = 头的唯一循环外前驱 → 扫描 pre-header 指令的寄存器操作数定义位置

IR 侧七枚计数器（全部为静态签名，不做价值判断）：
  C1   同一 phi 有重复入边块且取值不同        （OPT-001 §5.3 既有金丝雀，此处复算）
  C4   pre-header 指令的操作数寄存器定义在**该循环内** ⇒ 提升后取值冻结（陈旧提升）
  C4h  C4 的提升限定版：仅计本臂相对基线臂**新落入** pre-header 的那批指令
       ⇒ 排除「基线臂本就存在、未参与本次提升」的结构性噪声
  C4b  pre-header 内有读指令（load/array.get/property.get/global.get），
       且同一循环内含 array.set / property.set / 任何有副作用调用，
       但循环内**没有** .store ⇒ hasStoreInLoop(:1078-1088) 的盲区
  C4bh C4b 的提升限定版，口径同 C4h
  C7   新落入 pre-header 的指令，其在**基线臂**的定义块属于同一循环体、却不支配该循环的全部
       latch（即只在部分迭代执行）⇒ LICM 无控制流敏感度，把臂内指令提升为无条件执行
       自证分母随 H 输出：hm=可在基线按 id 查到定义块的枚数，hl=基线存在同名循环头的枚数；
       hm 或 hl < H 时跨臂匹配失效，C7=0 **不可**解读为「无臂内提升」
  H    双臂联表：本臂相对基线臂**新落入** pre-header 的指令枚数（需 --base 参数）

生成码侧两枚计数器（需 --zig 参数，由 --dump-zig-path 产出）：
  C2   「声明但无正常流赋值」寄存器枚数。**严格版**：异常清理块的
       `reg_N.release(…); reg_N = initNull();`（≥8 空格缩进）不算正常流赋值，
       故与 §5.3 的**宽松版 C2 数值不可直接比较**（宽松版会把每个停初值寄存器洗白）
  C6   仍带 `// PHI: reg_N (handled in terminator)` 标记却无正常流赋值
       ⇒ §5.2 R5「发射静默」的直接落点
"""
import re
import sys
from collections import defaultdict

RESULT_RE = re.compile(r'^\s*\.\{ \.id = (\d+),.*? \} = ([a-z_.]+)(.*)$')
ID_RE = re.compile(r'\.id = (\d+)')
BLOCK_RE = re.compile(r'^([a-z_][a-z_0-9]*):$')
BR_UNCOND = re.compile(r'^\s*br ([a-z_][a-z_0-9]*)\s*$')
BR_COND = re.compile(r'^\s*br \.\{.*?\}, ([a-z_][a-z_0-9]*), ([a-z_][a-z_0-9]*)\s*$')
PHI_EDGE = re.compile(r'\[\.\{ \.id = (\d+),.*? \}, ([a-z_][a-z_0-9]*)\]')

READ_OPS = {"load", "array.get", "property.get", "global.get", "capture_get", "array_key_exists"}
MUT_OPS = {"array.set", "property.set", "array.unset", "unset", "push", "array.push"}
CALL_OPS = {"call", "method.call", "static.call", "call.indirect", "new"}
STORE_OPS = {"store"}
PURE_OPS = {"param", "alloca", "nop", "const_int", "const.i64", "phi"}


def parse(path):
    funcs = []
    cur = None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.startswith("define "):
                cur = {"name": line.strip(), "blocks": defaultdict(list), "order": []}
                funcs.append(cur)
                blk = "entry"
                cur["order"].append(blk)
                continue
            if cur is None:
                continue
            m = BLOCK_RE.match(line.strip())
            if m:
                blk = m.group(1)
                if blk not in cur["order"]:
                    cur["order"].append(blk)
                continue
            if line.startswith("}") and not line.startswith("  "):
                cur = None
                continue
            stripped = line.strip()
            if not stripped or stripped.startswith(";"):
                continue
            rm = RESULT_RE.match(line)
            if rm:
                rid, op, rest = int(rm.group(1)), rm.group(2).rstrip(":"), rm.group(3)
                # 操作数 = 等号右侧出现的全部寄存器，排除自身
                operands = [int(x) for x in ID_RE.findall(rest)]
                cur["blocks"][blk].append(
                    {"id": rid, "op": op, "text": stripped, "operands": operands, "line": line.rstrip("\n")}
                )
            else:
                op = stripped.split(" ")[0].rstrip(".")
                operands = [int(x) for x in ID_RE.findall(stripped)]
                cur["blocks"][blk].append(
                    {"id": None, "op": op, "text": stripped, "operands": operands, "line": line.rstrip("\n")}
                )
    return funcs


def successors(f, blk):
    edges = []
    for inst in f["blocks"].get(blk, []):
        if inst["op"] == "br":
            m = BR_UNCOND.match(inst["line"])
            if m:
                edges.append(m.group(1))
                continue
            m = BR_COND.match(inst["line"])
            if m:
                edges.extend([m.group(1), m.group(2)])
    return edges


def find_loops(f):
    """返回 [(header, frozenset(blocks), preheaders)]；回边由 DFS 灰边判定，循环体按反向可达求。"""
    blocks = [b for b in f["order"] if b in f["blocks"]]
    succ = {b: [s for s in successors(f, b) if s in f["blocks"]] for b in blocks}
    entry = blocks[0] if blocks else None
    color = {b: 0 for b in blocks}  # 0 white 1 gray 2 black
    back = []
    stack = [(entry, iter(succ.get(entry, [])))] if entry else []
    if entry:
        color[entry] = 1
    while stack:
        node, it = stack[-1]
        nxt = next(it, None)
        if nxt is None:
            color[node] = 2
            stack.pop()
            continue
        if color[nxt] == 1:
            back.append((node, nxt))
        elif color[nxt] == 0:
            color[nxt] = 1
            stack.append((nxt, iter(succ.get(nxt, []))))
    loops = []
    preds = defaultdict(set)
    for b in blocks:
        for s in succ[b]:
            preds[s].add(b)
    for src, hdr in back:
        # 循环体 = hdr ∪ {能不经过 hdr 到达 src 的块}
        body = {hdr}
        rev = defaultdict(set)
        for b in blocks:
            for s in succ[b]:
                rev[s].add(b)
        work = [src]
        while work:
            n = work.pop()
            if n in body:
                continue
            body.add(n)
            work.extend(rev[n])
        pre = [p for p in preds[hdr] if p not in body]
        loops.append((hdr, frozenset(body), pre))
    return loops


def dom_sets(blocks, succ):
    """迭代位向量支配：dom(entry)={entry}，dom(n)={n}∪⋂dom(preds)。不可达块保持全集（⊥）。"""
    if not blocks:
        return {}
    valid = set(blocks)
    preds = defaultdict(set)
    for b in blocks:
        for s in succ[b]:
            if s in valid:
                preds[s].add(b)
    entry = blocks[0]
    dom = {b: set(valid) for b in blocks}
    dom[entry] = {entry}
    changed = True
    while changed:
        changed = False
        for b in blocks:
            if b == entry:
                continue
            ps = list(preds[b])
            if not ps:
                continue
            new = {b}
            inter = set.intersection(*[dom[p] for p in ps])
            new |= inter
            if new != dom[b]:
                dom[b] = new
                changed = True
    return dom


def base_loop_info(base_path):
    """基线臂侧信息：(函数名, 循环头名) → 该循环「块在每次迭代必执行」的块集（支配全部 latch）。

    C7 用它判别「提升前该指令只在部分迭代执行」的臂内提升。
    """
    defs = {}
    loops = {}
    for bf in parse(base_path):
        blocks = [b for b in bf["order"] if b in bf["blocks"]]
        succ = {b: [s for s in successors(bf, b) if s in bf["blocks"]] for b in blocks}
        dom = dom_sets(blocks, succ)
        for b in blocks:
            for inst in bf["blocks"][b]:
                if inst["id"] is not None:
                    defs.setdefault((bf["name"], inst["id"]), b)
        for hdr, body, _ in find_loops(bf):
            latches = [b for b in body if hdr in succ.get(b, [])]
            if not latches:
                continue
            safe = frozenset(b for b in blocks if all(l in dom[b] for l in latches))
            loops[(bf["name"], hdr)] = (body, safe)
    return defs, loops


def analyze(path, base_path=None):
    funcs = parse(path)
    base_pre = None
    base_defs = None
    base_loops = None
    if base_path:
        base_pre = set()
        for bf in parse(base_path):
            for hdr, body, pre in find_loops(bf):
                for p in pre:
                    for inst in bf["blocks"][p]:
                        if inst["id"] is not None:
                            base_pre.add((bf["name"], inst["id"]))
        base_defs, base_loops = base_loop_info(base_path)
    c1 = c4 = c4h = c4b = c4bh = c7 = h = hmatch = hloop = 0
    evidence = []
    for f in funcs:
        defs = {}
        for blk in f["order"]:
            for inst in f["blocks"].get(blk, []):
                if inst["id"] is not None:
                    defs.setdefault(inst["id"], blk)
        # C1：phi 同源异值
        for blk in f["order"]:
            for inst in f["blocks"].get(blk, []):
                if inst["op"] != "phi":
                    continue
                pairs = PHI_EDGE.findall(inst["text"])
                blks = [b for _, b in pairs]
                vals = [v for v, _ in pairs]
                if len(blks) != len(set(blks)) and len(set(vals)) > 1:
                    c1 += 1
                    evidence.append(("C1", blk, inst["text"]))
        for hdr, body, pre in find_loops(f):
            for p in pre:
                mutating = set()
                has_store = False
                for blk in body:
                    for inst in f["blocks"].get(blk, []):
                        if inst["op"] in MUT_OPS or inst["op"] in CALL_OPS:
                            mutating.add(inst["op"])
                        if inst["op"] in STORE_OPS:
                            has_store = True
                for inst in f["blocks"].get(p, []):
                    if inst["id"] is None or inst["op"] in PURE_OPS:
                        continue
                    newly = base_pre is None or (f["name"], inst["id"]) not in base_pre
                    if newly:
                        h += 1
                        if base_defs is not None:
                            b0 = base_defs.get((f["name"], inst["id"]))
                            info = base_loops.get((f["name"], hdr))
                            if b0 is not None:
                                hmatch += 1
                            if info:
                                hloop += 1
                            if b0 is not None and info and b0 in info[0] and b0 not in info[1]:
                                c7 += 1
                                evidence.append(("C7", f"{b0}=>{p}->{hdr}", inst["text"]))
                    ins = [o for o in inst["operands"] if defs.get(o) in body and defs[o] != p]
                    if ins:
                        c4 += 1
                        evidence.append(("C4", f"{p}->{hdr}", inst["text"]))
                        if newly:
                            c4h += 1
                            evidence.append(("C4h", f"{p}->{hdr}", inst["text"]))
                    if inst["op"] in READ_OPS and mutating and not has_store:
                        c4b += 1
                        evidence.append(("C4b", f"{p}->{hdr}", inst["text"]))
                        if newly:
                            c4bh += 1
                            evidence.append(("C4bh", f"{p}->{hdr}", inst["text"]))
    return {"c1": c1, "c4": c4, "c4h": c4h, "c4b": c4b, "c4bh": c4bh, "c7": c7,
            "h": h, "hmatch": hmatch, "hloop": hloop, "ev": evidence}


def _zig_regions(lines):
    """按**顶层 `fn `/`pub fn `（第 0 列）**切分生成码功能区间。

    ⚠ 必需：`reg_N` 编号在**每个 PHP 功能内独立复用**，故「全文某处有赋值」不能为
      另一功能里「标记在、本站点无写入」的寄存器洗白 —— 口径更正（实测 f117 licm 臂
      PHP `:92`/`:106` 两处 coalesce 交汇寄存器 `reg_39` 站点级零赋值，旧全文口径 C6 误报 0）。
    """
    starts = [i for i, l in enumerate(lines) if re.match(r"^(?:pub )?fn \S", l)]
    if not starts:
        return [(0, len(lines))]
    spans = []
    for n, s in enumerate(starts):
        spans.append((s, starts[n + 1] if n + 1 < len(starts) else len(lines)))
    return spans


def zig_code_canaries(path):
    """生成码侧两枚金丝雀（OPT-001 §5.2 R5 的直接签名），**按顶层功能区间归一**。

    C2 = 声明为 `var reg_N: runtime.Value` 但**本功能区间内无正常流赋值**的 (功能, 寄存器) 枚数
    C6 = 本功能区间内仍带发射器标记 `// PHI: reg_N (handled in terminator)` 却无正常流赋值的枚数
         ⇒ R5「发射侧对同源双入边 phi 不发臂拷贝」的精确落点（标记在、写入无）
    ⚠ 异常清理惯用法 `reg_N.release(…); reg_N = runtime.Value.initNull();` **不算**正常流赋值，
      否则每个「停初值」寄存器都会被清理块洗白（首轮即因此读数全 0，已更正）。
    """
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    c2set, c6set = set(), set()
    for seq, (a, b) in enumerate(_zig_regions(lines)):
        body = lines[a:b]
        text = "\n".join(body)
        declared = set(re.findall(r"^\s*var (reg_\d+): runtime\.Value", text, re.M))
        assigned = set()
        for idx, line in enumerate(body):
            m = re.match(r"^\s*(?:\[set\]\s*)?(reg_\d+) = ", line)
            if not m:
                continue
            reg = m.group(1)
            if reg not in declared:
                continue
            if "runtime.Value.initNull()" in line and idx > 0:
                indent = len(line) - len(line.lstrip())
                if indent >= 8 and re.match(r"^\s*%s\.release\(" % reg, body[idx - 1]):
                    continue  # 异常清理归零（8 空格缩进的 catch 块），不代表正常流有写入
            assigned.add(reg)
        phi_marked = set(re.findall(r"// PHI: (reg_\d+) \(handled in terminator\)", text))
        for reg in declared - assigned:
            c2set.add((seq, reg))
        for reg in phi_marked - assigned:
            c6set.add((seq, reg))
    return {"c2": len(c2set), "c6": len(c6set),
            "c2list": sorted({r for _, r in c2set}), "c6list": sorted({r for _, r in c6set})}


def zig_partial_arm_copy(path):
    """C9：`// PHI: reg_N` 标记对应的 if/else 里**只有一臂有赋值、另一臂为空臂**。

    这是 §5.2 R3 的「异块改写支」（R3′）在发射侧的落点：被删臂的前驱与另一臂入边块
    **不同名** ⇒ IR 侧不出现「同源异值 phi」（C1=0），但发射侧仍少发一条臂拷贝
    ⇒ 交汇寄存器在该路径保持上一轮值／声明初值。
    """
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")

    def stmt(l):
        s = l.strip()
        return bool(s) and not s.startswith("//") and not s.startswith("runtime.setSourceLocation(")

    hits = []
    for idx, line in enumerate(lines):
        m = re.search(r"// PHI: (reg_\d+) \(handled in terminator\)", line)
        if not m:
            continue
        reg = m.group(1)
        j = idx - 1
        while j >= 0 and not stmt(lines[j]):
            j -= 1
        if j < 0 or lines[j].strip() != "}":
            continue
        depth = 0
        k = j
        while k >= 0:
            depth += lines[k].count("}") - lines[k].count("{")
            if depth == 0 and re.search(r"\bif \(.*\)\s*\{", lines[k]):
                break
            k -= 1
        if k < 0 or depth != 0:
            continue
        opener = k
        # 同层切分 then / else
        depth = 0
        split = None
        for t in range(opener, j + 1):
            s = lines[t].strip()
            if split is None:
                depth += lines[t].count("{") - lines[t].count("}")
                if depth == 1 and re.match(r"^\s*\}\s*else\s*(if\b|\{)", lines[t]):
                    split = t
            else:
                break
        then_lines = [lines[t] for t in range(opener + 1, split if split else j) if stmt(lines[t])]
        else_lines = [lines[t] for t in range((split if split else j) + 1, j) if stmt(lines[t])]
        tn = sum(1 for l in then_lines if re.match(r"^\s*(?:\[set\]\s*)?%s = " % reg, l))
        en = sum(1 for l in else_lines if re.match(r"^\s*(?:\[set\]\s*)?%s = " % reg, l))
        if split is None:
            continue  # 无 else 臂 ⇒ 不是二选一汇合，不计
        if (tn == 0 and en > 0 and not then_lines) or (en == 0 and tn > 0 and not else_lines):
            hits.append((reg, idx + 1, "then" if tn == 0 else "else"))
    return {"c9": len(hits), "hits": hits}


if __name__ == "__main__":
    args = sys.argv[1:]
    base = None
    if "--base" in args:
        i = args.index("--base")
        base = args[i + 1]
        del args[i : i + 2]
    zig = None
    if "--zig" in args:
        i = args.index("--zig")
        zig = args[i + 1]
        del args[i : i + 2]
    r = analyze(args[0], base)
    z = zig_code_canaries(zig) if zig else None
    p = zig_partial_arm_copy(zig) if zig else None
    if "--csv" in args:
        print("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % (
            r["c1"], r["c4"], r["c4h"], r["c4b"], r["c4bh"], r["c7"], r["h"], r["hmatch"], r["hloop"],
            z["c2"] if z else -1, z["c6"] if z else -1, p["c9"] if p else -1))
        raise SystemExit
    limit = int(args[1]) if len(args) > 1 else 12
    print(f"C1={r['c1']} C4={r['c4']} C4h={r['c4h']} C4b={r['c4b']} C4bh={r['c4bh']} "
          f"C7={r['c7']} H={r['h']}(base_id_matched={r['hmatch']} loop_found={r['hloop']})")
    if z:
        print(f"C2={z['c2']} C6={z['c6']} C9={p['c9']}")
        for reg, ln, side in p["hits"][:8]:
            print(f"  [C9 {reg} 空臂={side} 标记行 :{ln}]")
        if z["c6list"]:
            print(f"  C6 regs: {' '.join(z['c6list'][:8])}")
        if z["c2list"]:
            print(f"  C2 regs: {' '.join(z['c2list'][:8])}")
    for tag, where, text in r["ev"][:limit]:
        print(f"  [{tag} {where}] {text[:220]}")
