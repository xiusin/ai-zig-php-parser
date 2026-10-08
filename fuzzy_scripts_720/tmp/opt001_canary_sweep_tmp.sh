#!/bin/bash
# AOT-OPT-001 §5.4 共因面扫（任务 #97，只读、零源码改动、非门控）
#
# 已取证（#96，f016 双臂只读，见 OPT-001 §5.3/§5.4）：LICM 红面的机制链五环 =
#   LICM 把 coalesce_rhs_N 臂内唯一指令（const）提升走 → 臂块清空
#   → cfg_cleanup tryRemoveTrampolineBlock 删该空臂块并把前驱 cond_br 的 then 边重联到 merge
#   → simplifyTrivialConditionalBranches 见 then==else 把 cond_br 折叠成 br（条件消失）
#   → merge 的 phi 出现「同前驱、异取值」双入边（选择语义永久丢失）
#   → 发射侧对同源双入边不发臂拷贝 ⇒ 交汇寄存器停在声明初值 initNull() ⇒ 静默错值
#
# 本脚本用四枚**静态金丝雀**在 19 枚红形上量化该链的命中面（唯一变量 = --aot-enable-pass=licm）：
#   C1（IR 侧）：优化后 IR 中「同一 phi 有重复入边块且取值不同」的枚数
#   C2（生成码侧）：main.zig 中「在本顶层功能区间内声明却无正常流赋值」的 reg 枚数（严格版）
#   C6／C9（生成码侧，见下方第 2 代口径）：R5 全拷贝丢失／R3′ 半拷贝
# 全程 --no-link（跳过 zig build-exe，只跑 parse→IR→优化→发射），产物即时删除。
# 判据含义：delta>0 ⇒ 该枚红形由本链解释；delta=0 ⇒ 该枚红形另有机制（本链非共因）。
# **口径第 2 代（#99 刷新）**：
#   · C2 改为「严格版 + 按顶层功能区间归一」（`reg_N` 每功能复用，全文口径会洗白站点级零拷贝）
#     ⇒ 与 #97 第 1 代数值**不可直接比较**；第 1 代读数已归档为
#       `opt001_canary_sweep_tmp.tsv.r1-global-c2`，禁止覆盖删除。
#   · 新增 C6（本功能区间内 `// PHI: reg_N` 标记却无正常流赋值 ⇒ R5 全拷贝丢失）
#     与 C9（该标记的 if/else 一臂空、另一臂有赋值 ⇒ R3′ 半拷贝），二者取双臂 delta，
#     汇成第二判据列 `EMIT_HIT`／`EMIT_BLIND`（发射侧签名面）。
# 铁律：禁止删除任何 .php 源；aot_compile_* 产物与临时目录收尾清空。
cd /Users/wangjianjun/products/parser || exit 1

BIN="zig-out/bin/php-interpreter"
PASS_DIR="fuzzy_scripts_720/pass"
WORK="/tmp/opt001_canary_work"
TSV="fuzzy_scripts_720/tmp/opt001_canary_sweep_tmp.tsv"
PY="fuzzy_scripts_720/tmp/opt001_ir_stale_hoist_tmp.py"
rm -rf "$WORK"; mkdir -p "$WORK"

ARMS="base licm"

canary() {
  # $1=ir file  $2=zig file  $3=base ir（可选，用于 H/C4h 等联表字段，本脚本不读）
  # -> CSV: c1,c4,c4h,c4b,c4bh,c7,h,hmatch,hloop,c2,c6,c9
  # 口径第 2 代：改用永久分析器（DRY），C2/C6 为**严格版 + 按顶层功能区间归一**
  #   （`reg_N` 编号在每个 PHP 功能内复用；全文口径会把站点级零拷贝洗白 ⇒ 第 1 代 C2 数值不可比）
  python3 "$PY" "$1" --zig "$2" --csv
}

> "$TSV"
echo "# opt001 canary sweep $(date '+%Y-%m-%d %H:%M:%S') bin=$(md5 -q "$BIN") optimizer=$(md5 -q src/aot/optimizer.zig) flags=--compile --no-debug-info --no-link" >> "$TSV"

names=$(awk -F'|' '$3=="DIFF" || $3=="RUNTIME_FAIL" {print $1}' fuzzy_scripts_720/tmp/c007_rf_face_tmp.tsv)

tot=0; explained=0; unexplained=0; cfail=0; emit_hit=0
for n in $names; do
  src="$PASS_DIR/$n.php"
  [ -f "$src" ] || { echo "$n|SKIP|NO_SRC" >> "$TSV"; continue; }
  tot=$((tot+1))
  ok=1
  for arm in $ARMS; do
    fl=""
    [ "$arm" = "licm" ] && fl="--aot-enable-pass=licm"
    ZIGPHP_AOT_KEEP_TEMP=0 timeout 300 "$BIN" --compile --no-debug-info --no-link $fl \
      --output="$WORK/aot_compile_${n}_${arm}" \
      --emit-ir="$WORK/ir_${arm}.txt" --dump-zig-path="$WORK/zig_${arm}.txt" \
      "$src" >"$WORK/${arm}.cerr" 2>&1 || { ok=0; }
    mv "$WORK/ir_${arm}.txt" "$WORK/ir_${n}_${arm}.txt" 2>/dev/null
    mv "$WORK/zig_${arm}.txt" "$WORK/zig_${n}_${arm}.txt" 2>/dev/null
    rm -f "$WORK/aot_compile_${n}_${arm}"
  done
  if [ $ok -eq 0 ]; then
    echo "$n|COMPILE_FAIL||" >> "$TSV"; cfail=$((cfail+1)); continue
  fi
  rb=$(canary "$WORK/ir_${n}_base.txt" "$WORK/zig_${n}_base.txt")
  rl=$(canary "$WORK/ir_${n}_licm.txt" "$WORK/zig_${n}_licm.txt")
  c1b=$(cut -d, -f1 <<<"$rb"); c2b=$(cut -d, -f10 <<<"$rb"); c6b=$(cut -d, -f11 <<<"$rb"); c9b=$(cut -d, -f12 <<<"$rb")
  c1l=$(cut -d, -f1 <<<"$rl"); c2l=$(cut -d, -f10 <<<"$rl"); c6l=$(cut -d, -f11 <<<"$rl"); c9l=$(cut -d, -f12 <<<"$rl")
  d1=$((c1l - c1b)); d2=$((c2l - c2b)); d6=$((c6l - c6b)); d9=$((c9l - c9b))
  if [ $d1 -gt 0 ] || [ $d2 -gt 0 ]; then
    verdict="CHAIN_HIT"
  else
    verdict="NO_HIT"
  fi
  # 发射侧签名（第 2 代口径）：C6 = 全拷贝丢失（R5 零拷贝），C9 = 半拷贝（R3′ 异块改写支）
  if [ $d6 -gt 0 ] || [ $d9 -gt 0 ]; then emit="EMIT_HIT"; else emit="EMIT_BLIND"; fi
  [ "$verdict" = "CHAIN_HIT" ] && explained=$((explained+1)) || unexplained=$((unexplained+1))
  [ "$emit" = "EMIT_HIT" ] && emit_hit=$((emit_hit+1))
  echo "$n|$verdict|C1=$c1b/$c1l(d=$d1)|C2=$c2b/$c2l(d=$d2)|C6=$c6b/$c6l(d=$d6)|C9=$c9b/$c9l(d=$d9)|$emit" >> "$TSV"
  echo "[$tot] $n $verdict $emit C1=$c1b/$c1l C2=$c2b/$c2l C6=$c6b/$c6l C9=$c9b/$c9l"
  rm -f "$WORK/ir_${n}_base.txt" "$WORK/ir_${n}_licm.txt" "$WORK/zig_${n}_base.txt" "$WORK/zig_${n}_licm.txt"
done

echo "CANARY_SWEEP_DONE total=$tot chain_hit=$explained no_hit=$unexplained compile_fail=$cfail emit_hit=$emit_hit" | tee -a "$TSV"
