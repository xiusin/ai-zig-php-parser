#!/usr/bin/env python3
"""AOT-OPT-001 #110：`rt>0 ∧ 非绿` 形的「P0 站点函数 ∩ 生成码漂移函数」逐枚归因（只读、零插桩）。

输入 = 同一轮、唯一变量为 `--aot-disable-pass=cfg-cleanup` 的两臂产物：
  ON.zig / NC.zig   层 1 通道（`--no-link` ⇒ `<output>.zig` ≡ KEEP_TEMP 的 `main.zig`，#109 已 68/68 自证）
  ON.ir  / NC.ir    层 A 通道（`--emit-ir`；`rc≠0` 时仍落盘 ⇒ #107 既有口径）

两步取数（禁凭推测，全部走实文）：
  ① 漂移函数集合 = 按**顶层 `fn` 区间**（复用 §7 分析器 `_zig_regions`，禁另写切分）逐区间 md5，
     ON ⇄ NC 同区间名不等值、或单侧缺名者入集；首区间前的前言带 `<preamble>` 桶；
     **自证**：全部桶按序拼回必须逐字节 == 整文件（不等 ⇒ verdict=COVERAGE_FAIL，本形作废，
     禁把「区间层面看不出差」读成「无漂移」）。
  ② P0 站点函数集合 = 复用 #107 分析器 `count_arm` 的 detail 行，取 `P0_refuse_tramp` 的
     IR 函数名（= §6 P0 判据在**严格 R2 跳板准入**口径下会拦下删块的那枚 phi 所在函数）。
     另落 `p0_all`（`P0_refuse_all`，宽口径）只作对照，**不作判据**（承 §5.11-3「禁拿 refuse_all 当验收目标」）。
  ③ 侧探针（§7 现成实现，禁另写）= 两臂各自的 C2（声明未赋值 `reg_N`）／C6（`// PHI:` 标记在、本站点无写入）
     ／C9（空臂 PHI）计数 ⇒ 回答「默认档 NC 臂的 12 枚非绿**带不带** R1→R5 链的发射侧签名」。
     若两臂 C6/C9 均 0 ⇒ 逐函数版「Δ症状 ∩ P0」在本档无信号可取，判据只能停在函数交集面。

名字联接：IR `define … @NumberTheory::gcd(.` ⇄ 生成码 `pub fn @"NumberTheory::gcd"(`；
  无 IR 对应的脚手架区（`fn initStaticStrings` 等）与重名区只能落 `<…>`/`#行号` 键 ⇒ 计入 `unmatched`，
  不得凭前缀猜；`unmatched` 里的漂移区**不**参与交集判定（保守：只可能把 UNDETERMINED 判成 NOT_P0）。

判定（§5.13.4 原文口径）：
  交集为空  ⇒ `NOT_P0_ATTRIBUTABLE`（漂移只来自其他清理规则 ⇒ 同 `f085` 口径，可从 P0 语义风险面扣除）
  交集非空  ⇒ `UNDETERMINED`（本层无法区分「P0 改动导致错值」与「其他规则导致错值」⇒ 升级门控插桩议题）
  NC 无产物 ⇒ `NC_NO_EMISSION`（关档臂连生成码都没有 ⇒ 发射侧硬依赖，函数面无法取数）

输出 `--csv`：18 列 = verdict,drift,p0f,inter,donly,reg_on,reg_nc,unmatched,coverage,
  p0_tramp,p0_all,c2_on,c2_nc,c6_on,c6_nc,c9_on,c9_nc,err（err 恒为末列，调用方按首个 `|` 切尾段名字）
用法：opt001_p0site_intersect_tmp.py <ON.zig> <NC.zig> <ON.ir> <NC.ir> [--csv] [--names]
"""
import hashlib
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from opt001_ir_stale_hoist_tmp import (  # 复用同一区间切分与金丝雀实现（DRY，禁另写一份）
    _zig_regions,
    zig_code_canaries,
    zig_partial_arm_copy,
)
from opt001_droppedphi_tmp import count_arm  # 复用 #107 的 P0 站点计数与 detail

HEADER_RE = re.compile(r"^(?:pub )?fn \S")   # 与 _zig_regions 内部字面量逐字一致
IR_NAME = re.compile(r"@([A-Za-z0-9_\\:+-]+)\(")
ZIG_QUOTED = re.compile(r'^(?:pub )?fn @"([^"]+)"')
ZIG_PLAIN = re.compile(r"^(?:pub )?fn ([A-Za-z_][A-Za-z0-9_]*)")
COLS = ("verdict", "drift", "p0f", "inter", "donly", "reg_on", "reg_nc",
        "unmatched", "coverage", "p0_tramp", "p0_all",
        "c2_on", "c2_nc", "c6_on", "c6_nc", "c9_on", "c9_nc", "err")


def md5(text):
    return hashlib.md5(text.encode("utf-8", "replace")).hexdigest()


def z_name(header):
    m = ZIG_QUOTED.search(header) or ZIG_PLAIN.search(header)
    return m.group(1) if m else header.split("(")[0].strip()


def ir_name(defline):
    m = IR_NAME.search(defline)
    return m.group(1) if m else defline.strip()


def regions(path):
    """区间名 -> (md5, 行数)；并自证「桶按序拼回 == 整文件」。"""
    raw = open(path, encoding="utf-8", errors="replace").read()
    lines = raw.split("\n")
    starts = [i for i, l in enumerate(lines) if HEADER_RE.match(l)]
    spans = _zig_regions(lines)
    if starts and len(starts) != len(spans):
        raise RuntimeError("header/region mismatch %d!=%d" % (len(starts), len(spans)))
    out = {}
    if not starts:
        out["<whole>"] = (md5(raw), len(lines))
        return out, "OK"
    parts = ["\n".join(lines[:starts[0]])]
    out["<preamble>"] = (md5(parts[0]), starts[0])
    for n, s in enumerate(starts):
        a, b = spans[n]
        body = "\n".join(lines[a:b])
        parts.append(body)
        name = z_name(lines[a])
        key = name if name not in out else "%s#%d" % (name, a)
        out[key] = (md5(body), b - a)
    # 自证：spans 连续且覆盖 [starts[0], len)，故按序拼回 == 原文件
    cov = "OK" if "\n".join(parts) == raw else "FAIL"
    return out, cov


def main():
    args = sys.argv[1:]
    if len(args) < 4:
        print(__doc__)
        return 2
    on_zig, nc_zig, on_ir, nc_ir = args[:4]
    flags = args[4:]
    r = dict(verdict="ERR", drift=0, p0f=0, inter=0, donly=0, reg_on=0, reg_nc=0,
             unmatched=0, coverage="NO", p0_tramp=0, p0_all=0,
             c2_on="-", c2_nc="-", c6_on="-", c6_nc="-", c9_on="-", c9_nc="-", err="")
    names = []
    try:
        for p, arm in ((nc_zig, "NC_NO_EMISSION"), (on_zig, "ON_NO_EMISSION"),
                       (nc_ir, "NC_IR_MISSING"), (on_ir, "ON_IR_MISSING")):
            if not os.path.isfile(p) or os.path.getsize(p) == 0:
                r["verdict"] = arm
                r["err"] = "missing:" + os.path.basename(p)
                return emit(r, names, flags)
        oo, cov_o = regions(on_zig)
        no, cov_n = regions(nc_zig)
        r["coverage"] = "OK" if (cov_o == "OK" and cov_n == "OK") else ("ON:" + cov_o + "/NC:" + cov_n)
        r["reg_on"], r["reg_nc"] = len(oo), len(no)
        if r["coverage"] != "OK":
            r["verdict"] = "COVERAGE_FAIL"
            r["err"] = "bucket join != file"
            return emit(r, names, flags)

        # 侧探针：两臂各自的发射侧签名计数（默认档有无 R1→R5 链签名 ⇒ 决定 §110 判据要不要升级到逐函数版）
        for tag, p in (("on", on_zig), ("nc", nc_zig)):
            can = zig_code_canaries(p)
            arm = zig_partial_arm_copy(p)
            r["c2_" + tag], r["c6_" + tag], r["c9_" + tag] = can["c2"], can["c6"], arm["c9"]

        drift = set()
        for k, v in oo.items():
            w = no.get(k)
            if w is None or w[0] != v[0]:
                drift.add(k)
        drift |= {k for k in no if k not in oo}

        _, detail = count_arm(on_ir, nc_ir)
        p0_tramp = {ir_name(n) for kind, n, _, _ in detail if kind == "P0_refuse_tramp"}
        p0_all = {ir_name(n) for kind, n, _, _ in detail if kind == "P0_refuse_all"}
        r["p0_tramp"], r["p0_all"] = len(p0_tramp), len(p0_all)
        r["unmatched"] = len([d for d in drift if d.startswith("<") or "#" in d])
        # 自证：漂移键里若仍含 `fn ` ⇒ z_name 正则漏匹配、整行 header 被当函数名
        #        ⇒ 与 IR 名域永不相交 ⇒ 会把 UNDETERMINED 洗成 NOT_P0_ATTRIBUTABLE，本形读数作废
        leak = [d for d in drift if " fn " in d or d.startswith("fn ")]
        inter = sorted(d for d in drift if d in p0_tramp)
        r["drift"], r["inter"], r["p0f"] = len(drift), len(inter), len(p0_tramp)
        r["donly"] = len(drift) - len(inter)
        if leak:
            r["verdict"] = "NAME_EXTRACT_FAIL"
            r["err"] = "name_leak=%d:%s" % (len(leak), leak[0][:60])
        elif not drift:
            r["verdict"] = "NO_DRIFT"
        elif inter:
            r["verdict"] = "UNDETERMINED"
        else:
            r["verdict"] = "NOT_P0_ATTRIBUTABLE"
        names = inter

        if "--names" in flags:
            for d in sorted(drift):
                o = oo.get(d, ("-", 0))
                w = no.get(d, ("-", 0))
                print("; DRIFT %-40s md5_on=%s md5_nc=%s lines=%s/%s p0_tramp=%s p0_all=%s" % (
                    d, o[0][:12], w[0][:12], o[1], w[1],
                    "Y" if d in p0_tramp else "n", "Y" if d in p0_all else "n"))
            for f in sorted(p0_tramp):
                print("; P0SITE %-40s in_drift=%s" % (f, "Y" if f in drift else "n"))
    except Exception as ex:  # noqa: BLE001
        r["verdict"] = "ERR"
        r["err"] = type(ex).__name__ + ":" + str(ex)[:140]
    return emit(r, names, flags)


def emit(r, names, flags):
    row = ",".join(str(r[k]) for k in COLS)
    if names:
        row += "|" + ";".join(names)
    print(row if "--csv" in flags else "\n".join(
        f"{k}={r[k]}" for k in COLS) + ("\ninter=" + ";".join(names) if names else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
