#!/usr/bin/env python3
# AOT-CODEGEN-007 §7.5 留口收口（轮次 #111）：把生成码里「已实测定位到的崩点语句」的操作数在**运行时**打出来。
#
# 输入 = KEEP_TEMP 生成码 main.zig 的 **/tmp 副本** + 崩点行号（由同份生成码 -ODebug 重建后的 Zig 栈追踪给出）。
# 输出 = 插好 print 探针的 main_probe.zig（原副本不动，只新增文件）。
#
# 为什么只新增文件：本脚本是取证工具，禁止编辑 src/**，也不改动已对账过的原始 main.zig ⇒
#   探针与原文的差异行数由本脚本自己打印，可被 diff 复算。
#
# 探针取值纪律（表达式已逐枚核实 src/aot/runtime_lib_template.zig 与 src/aot/nanbox_abi.zig，禁凭推测写）：
#   Value = struct{ val: u64 }；谓词实测有 isNull / isArray / isRef / isString / isFunction，
#     对象判定是自由函数 runtime.Value_isObject(v)（isNil / isObject / isInteger / asObject **不存在** ⇒ 写进探针即编译失败）；
#   PHPArray = { elements: Elements{ packed_values: ArrayListUnmanaged(Value), mixed: ?ArrayHashMap, ... },
#                next_index: i64, ref_count: usize, ... }；
#   decodePtr(v) = v & ADDR_MASK（nanbox_abi.zig:36，无 @import ⇒ 探针副本可直接 @import 该模块，不算重实现）；
#   asArray() = @ptrFromInt(decodePtr(val))。
#
# 三条实测教训（首轮踩到，禁再犯）：
#   ① **`@ptrFromInt` 在 Debug 下会做对齐检查** ⇒ 对**坏指针**调 `asArray()` 会先抛 `incorrect alignment`，
#      探针本身变成新崩点（首轮 reg_6 即如此）。⇒ 取址必须先判 isArray()，坏值只打 **位模式 + decodePtr 整数**。
#   ② 崩点语句里的寄存器可能是 **引用槽** `var reg_N: *runtime.Value`（`reg_3.*` 形态）⇒
#      直接 `const _v = reg_N` 编译失败（首轮 T=45 即如此）。⇒ 必须回溯声明行判定类型，引用槽取 `reg_N.*`，
#      并**额外打印槽地址本身**（`@intFromPtr(reg_N)`）⇒ 使「槽指针坏」与「槽所指的值坏」可分。
#   ③ 语句原文以 {s} 实参传入，不拼进格式串 ⇒ 避免语句里的花括号被当格式占位符。
#
# 用法：python3 c007_segv_probe_tmp.py --main <main.zig> --line <N> --out <main_probe.zig> [--window 12]

import argparse
import re

REG_RE = re.compile(r"\breg_(\d+)\b")
SRCLOC_RE = re.compile(r'setSourceLocation\([^,]+,\s*(\d+)\)')
DECL_RE = re.compile(r'\b(?:var|const)\s+(reg_\d+)\s*:\s*(\*?\s*runtime\.Value|\*runtime\.Value)\b')
IMPORT_ANCHOR = 'const runtime = @import("runtime_lib.zig");'


def resolve_slot(lines, idx, reg):
    """自崩点行向上找该寄存器的声明行，判定是否为引用槽（*runtime.Value）。"""
    for k in range(idx, -1, -1):
        m = DECL_RE.search(lines[k])
        if m and m.group(1) == reg:
            return "*" in m.group(2).replace(" ", "")
        if re.search(r"^\s*pub fn @", lines[k]):   # 越出当前函数即停，防跨帧误判
            return False
    return False


def probe_block(reg, indent, slot):
    """单枚寄存器两行探针：第一行零解引用，第二行仅在 isArray() 时解引用。"""
    val_expr = f"{reg}.*" if slot else reg
    slot_col = (f'slot=0x{{x}} ' if slot else '')
    slot_arg = (f', @intFromPtr({reg}) ' if slot else '')
    line1 = (f'{indent}{{ const _v = {val_expr}; std.debug.print('
             f'"PROBE {reg}{" SLOT" if slot else ""} val=0x{{x}} nil={{d}} arr={{d}} ref={{d}} str={{d}} '
             f'obj={{d}} dp=0x{{x}}{slot_col}\\n", '
             f'.{{ _v.val, @intFromBool(_v.isNull()), @intFromBool(_v.isArray()), @intFromBool(_v.isRef()), '
             f'@intFromBool(_v.isString()), @intFromBool(runtime.Value_isObject(_v)), __nb.decodePtr(_v.val)'
             f'{slot_arg} }}); }}\n')
    line2 = (f'{indent}if ({val_expr}.isArray()) {{ const _a = {val_expr}.asArray(); std.debug.print('
             f'"PROBE-ARR {reg} ref_count={{d}} next_index={{d}} packed_len={{d}} mixed={{d}}\\n", '
             f'.{{ _a.ref_count, _a.next_index, _a.elements.packed_values.items.len, '
             f'@intFromBool(_a.elements.mixed != null) }}); }}\n')
    return line1 + line2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--main", required=True)
    ap.add_argument("--line", required=True, type=int)
    ap.add_argument("--out", required=True)
    ap.add_argument("--window", type=int, default=12, help="取操作数集合的行窗（崩点行上下各 N 行）")
    a = ap.parse_args()

    with open(a.main, encoding="utf-8") as fh:
        lines = fh.readlines()
    idx = a.line - 1
    if not (0 <= idx < len(lines)):
        raise SystemExit(f"PROBE_GEN_FAIL line={a.line} out_of_range={len(lines)}")

    lo, hi = max(0, idx - a.window), min(len(lines), idx + a.window + 1)
    regs = sorted({f"reg_{m}" for m in REG_RE.findall("".join(lines[lo:hi]))},
                  key=lambda s: int(s.split("_")[1]))
    if not regs:
        raise SystemExit(f"PROBE_GEN_FAIL no_reg_tokens_in_window lines={lo + 1}..{hi}")

    srcline = ""
    for k in range(idx, lo - 1, -1):
        m = SRCLOC_RE.search(lines[k])
        if m:
            srcline = m.group(1)
            break

    stmt = lines[idx].strip()
    safe_stmt = stmt.replace('\\', '/').replace('"', "'")
    indent = lines[idx][: len(lines[idx]) - len(lines[idx].lstrip())]
    header = (f'{indent}std.debug.print("PROBE-CTX fault_line={{d}} php_src_line={{s}} stmt={{s}}\\n", '
              f'.{{ {a.line}, "{srcline or "?"}", "{safe_stmt}" }});\n')
    slots = {r: resolve_slot(lines, idx, r) for r in regs}
    probe = header + "".join(probe_block(r, indent, slots[r]) for r in regs)

    # 顶部注入 __nb（decodePtr 的唯一来源），找不到锚点即拒绝生成（禁凭推测继续）
    anchor = next((i for i, l in enumerate(lines) if IMPORT_ANCHOR in l), None)
    if anchor is None:
        raise SystemExit(f"PROBE_GEN_FAIL no_import_anchor lines={len(lines)}")

    with open(a.out, "w", encoding="utf-8") as fh:
        fh.writelines(lines[:anchor + 1])
        fh.write('const __nb = @import("nanbox_abi.zig");  // probe-only\n')
        fh.writelines(lines[anchor + 1:idx])
        fh.write(probe)
        fh.writelines(lines[idx:])

    nl = probe.count("\n") + 1
    nslot = sum(1 for v in slots.values() if v)
    print(f"PROBE_GEN out={a.out} inserted_lines={nl} regs={len(regs)} slots={nslot} "
          f"reg_list={','.join(regs)} slot_list={','.join(r for r in regs if slots[r])} "
          f"php_src_line={srcline or 'NONE'} orig_lines={len(lines)} new_lines={len(lines) + nl} "
          f"stmt={stmt[:120]}")


if __name__ == "__main__":
    main()
