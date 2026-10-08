#!/usr/bin/env python3
"""AOT-OPT-001 #107：被 `cfg_cleanup` 丢弃块内的 phi 计数（只读、零插桩、发射侧修法选型前置）。

取两臂同一轮（唯一变量 = `--aot-disable-pass=cfg-cleanup`）的 `--emit-ir` 全文：
  ON = 清理开（默认发射态，臂块已被删）
  NC = 清理关（臂块保留）
逐顶层 `define` 区间按**块标签集合**对齐 ⇒
  D = 区间内 NC 有、ON 无的块标签 = 本轮被 `cfg_cleanup` 删掉的块。

六类计数（均相对 NC 臂实文，禁凭推测）：
  dropped        |D|                      —— 被删块枚数
  label_only     D 内「除终止符外无指令」的块枚数（宽代理）
  tramp          D 内「唯一指令 = 无条件 br」的块枚数 —— **R2 真实准入**（`optimizer.zig:4319` 块内零指令 ∧ `:4323` `.br`）
  phi_in_dropped D 内 `phi` 指令枚数        —— 被删块自身带 phi（R2 直接抹掉汇合点）
  p0_refuse_all  NC 臂中「至少一枚入边来自 D 内某块，且该入边的**取值寄存器**与其它入边不同」的 phi 枚数
                 ⇒ **上界参考**（含非跳板删块，比 §6 P0 的约束面广）
  p0_refuse_tramp 同上，但入边块限定为 `tramp` 集（R2 真实准入形态）⇒ **P0 判据的命中面**（选型主读数）
  p0_causeless   同 p0_refuse_all 但入边值与他边**全等**（P0 判据放行 ⇒ 该删除仍会改写 phi，属判据盲区）
  on_c1          ON 臂同区间的 C1 计数（§7 分析器既有口径，仅作交叉对账，不作判据）

自证分母：
  blocks_on / blocks_nc / funcs_on / funcs_nc / unmatched_funcs（`define` 行无法对齐的区间枚数，非 0 即本形作废）

输出（`--csv`）：一行 11 列 = dropped,label_only,tramp,phi_in_dropped,p0_refuse_all,p0_refuse_tramp,p0_causeless,on_c1,funcs,unmatched,err
`--detail` 另出逐枚站点原文行（D 内 phi、p0_refuse 的 phi 全文），供变更文档引用。
err 非空表示解析失败，读数不可用。

用法：opt001_droppedphi_tmp.py <ON.ir> <NC.ir> [--csv] [--detail]
"""
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from opt001_ir_stale_hoist_tmp import (  # 复用同一 IR 解析实现（DRY，禁另写一份）
    BR_UNCOND,
    PHI_EDGE,
    parse,
)

TERMINATOR_OPS = {"br", "ret", "unreachable", "switch", "match"}


def is_label_only(insts):
    """宽代理：除终止符外无指令。"""
    return not [i for i in insts if i["op"] not in TERMINATOR_OPS]


def is_tramp(insts):
    """§5.2 R2 `tryRemoveTrampolineBlock` 的真实准入（`optimizer.zig:4319` 块内零指令
    ∧ `:4323` 终止符为 `.br`）⇒ IR 文本上 = 唯一一条指令且为**无条件** br。"""
    return len(insts) == 1 and BR_UNCOND.match(insts[0]["text"]) is not None


def blocks_of(f):
    """块标签 -> 该块指令列表（只含真指令，空标签块以空列表存在）。"""
    out = {}
    for blk in f["order"]:
        out[blk] = f["blocks"].get(blk, [])
    return out


def count_arm(on_path, nc_path):
    r = dict(dropped=0, label_only=0, tramp=0, phi_in_dropped=0, p0_refuse_all=0, p0_refuse_tramp=0,
             p0_causeless=0,
             on_c1=0, funcs=0, unmatched=0, err="")
    detail = []
    try:
        fo = parse(on_path)
        fn = parse(nc_path)
    except Exception as ex:  # noqa: BLE001
        r["err"] = "parse:" + type(ex).__name__ + ":" + str(ex)[:120]
        return r, detail

    by_name_o = defaultdict(list)
    for f in fo:
        by_name_o[f["name"]].append(f)
    used = defaultdict(int)
    for f in fn:
        cand = by_name_o.get(f["name"])
        if not cand or used[f["name"]] >= len(cand):
            r["unmatched"] += 1
            used[f["name"]] += 1
            continue
        g = cand[used[f["name"]]]
        used[f["name"]] += 1
        r["funcs"] += 1
        bo, bn = blocks_of(g), blocks_of(f)
        D = sorted(set(bn) - set(bo))
        TR = set(b for b in D if is_tramp(bn[b]))
        r["dropped"] += len(D)
        r["tramp"] += len(TR)
        for blk in D:
            insts = bn[blk]
            if is_label_only(insts):
                r["label_only"] += 1
            phis = [i for i in insts if i["op"] == "phi"]
            r["phi_in_dropped"] += len(phis)
            for p in phis:
                detail.append(("D_phi", f["name"], blk, p["text"]))
        # p0 判据在 NC 臂实文上取数：入边块属于 D，且取值与其它入边不同
        for blk, insts in bn.items():
            if blk in D:
                continue
            for inst in insts:
                if inst["op"] != "phi":
                    continue
                pairs = PHI_EDGE.findall(inst["text"])
                if not pairs:
                    continue
                blk_of = [b for _, b in pairs]
                val_of = [v for v, _ in pairs]
                from_d = [i for i, b in enumerate(blk_of) if b in D]
                if not from_d:
                    continue
                # §6 P0 原文 = 「该条目的取值与其它入边不同」⇒ 逐枚 D 入边与全部其它入边比
                hit = any(val_of[i] != val_of[j]
                          for i in from_d for j in range(len(val_of)) if j != i)
                from_tramp = [i for i in from_d if blk_of[i] in TR]
                if hit:
                    r["p0_refuse_all"] += 1
                    detail.append(("P0_refuse_all", f["name"], blk, inst["text"]))
                    if from_tramp:
                        r["p0_refuse_tramp"] += 1
                        detail.append(("P0_refuse_tramp", f["name"], blk, inst["text"]))
                else:
                    r["p0_causeless"] += 1
                    detail.append(("P0_causeless", f["name"], blk, inst["text"]))
        # ON 臂 C1（同源异值 phi）交叉对账
        for blk, insts in bo.items():
            for inst in insts:
                if inst["op"] != "phi":
                    continue
                pairs = PHI_EDGE.findall(inst["text"])
                blks = [b for _, b in pairs]
                vals = [v for v, _ in pairs]
                if len(blks) != len(set(blks)) and len(set(vals)) > 1:
                    r["on_c1"] += 1
    return r, detail


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        return 2
    on, nc = args[0], args[1]
    flags = args[2:]
    r, detail = count_arm(on, nc)
    if "--detail" in flags:
        for row in detail:
            print("; " + " | ".join(row))
    if "--csv" in flags:
        print(",".join(str(r[k]) for k in
              ("dropped", "label_only", "tramp", "phi_in_dropped", "p0_refuse_all", "p0_refuse_tramp",
               "p0_causeless", "on_c1", "funcs", "unmatched", "err")))
    else:
        for k in ("dropped", "label_only", "tramp", "phi_in_dropped", "p0_refuse_all", "p0_refuse_tramp",
                  "p0_causeless", "on_c1", "funcs", "unmatched", "err"):
            print(f"{k}={r[k]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
