#!/bin/bash
# AOT-OPT-001 §5.6 残红五形「承重 pass 二分」臂（任务 #99 第三阶段，只读、零源码改动、非门控）
#
# 已知（同代次，前两轮读数）：
#   · 组 I（f117 f161）：`--aot-enable-pass=licm`（默认档 max_iterations=3）即红；`--aot-max-iterations=5` 单用全绿。
#   · 组 II（f051 f061 f135）：须 licm × 迭代 5 轮才红 ⇒ LICM 必要 + 轮数 ≥4 必要。
#   · 陈旧提升两枚结构探针（C4 pre-header 操作数定义在循环内、C4bh pre-header 读指令 + 循环内非 store 改写）
#     在 5 形 × 4 臂 **全 0** ⇒ 「提升取了陈旧值」被否证。
#   · 关 cfg_cleanup 在 5 形 × 2 臂（licmnc/li5nc）**一枚都不转绿**，且症状形态改变 ⇒ R2 链在场但非承重。
# 本轮定位「LICM 造出条件之后，是哪一枚 pass 把语义毁掉」：CLI 可关的 pass 名恰 11 枚
#   （main.zig:124-169 applyPassToggle → compiler.zig:662-677 applyPassOverrides）
#   dce constprop box-unbox inline typespec cse licm strength mem2reg unroll cfg-cleanup
#   默认档 inline/unroll 本就关，licm 是引爆子不可关，cfg-cleanup 上一轮已测 ⇒
#   二分集 = {dce, constprop, box-unbox, typespec, cse, strength, mem2reg} 七枚。
#   ⚠ sccp / copy-propagation / gvn / advanced_sccp / rc-elision / scalar-replacement **不在 applyPassToggle 表内**
#     ⇒ 这几枚无法用 CLI 二分，属本方法的硬边界（要判必须走插桩或源码，已登记为门控项）。
# 判据：某臂 PASS ⇒ 该 pass 为此形的承重共因；全臂 DIFF ⇒ 共因在不可 CLI 关闭的 pass 集合内。
# 生效性自证：每臂 main.zig md5 必须 ≠ 本形 trig 臂 md5，否则该读数标 NO_EFFECT。
# 真值 /opt/homebrew/bin/php；归一化 = 官方 harness 同款。铁律：禁删 .php 源；产物 aot_compile_* 即时删；全命令带 timeout。
cd /Users/wangjianjun/products/parser || exit 1

BIN="zig-out/bin/php-interpreter"
PHP_BIN="/opt/homebrew/bin/php"
SRC_DIR="fuzzy_scripts_720/pass"
TMP_DIR="fuzzy_scripts_720/tmp"
WORK="/tmp/opt001_resid_bisect_work"
TSV="$TMP_DIR/opt001_resid_pass_bisect_tmp.tsv"

PASSES="dce constprop box-unbox typespec cse strength mem2reg"

rm -rf "$WORK"; mkdir -p "$WORK"
{
  echo "# opt001 §5.6 residual pass bisection $(date '+%Y-%m-%d %H:%M:%S')"
  echo "bin_md5=$(md5 -q "$BIN")"
  echo "optimizer=$(md5 -q src/aot/optimizer.zig)/$(wc -l < src/aot/optimizer.zig | tr -d ' ')"
  echo "native_linker=$(md5 -q src/aot/native_linker.zig)/$(wc -l < src/aot/native_linker.zig | tr -d ' ')"
  echo "level=default(无 --optimize) 触发臂=各形最小红配置 二分集=$PASSES"
} > "$TSV"

normalize_output() {
    sed -E \
        -e 's/[[:space:]]*$//' \
        -e 's/^[[:space:]]*//' \
        -e 's/0x[0-9a-fA-F]{8,}/0xADDR/g' \
        -e 's|/tmp/aot_[a-z0-9_]+|TMPDIR|g' \
        -e 's/microtime\(true\)/MICROTIME/g' \
        -e 's/[0-9]+\.[0-9]{12,}/FLOAT/g' \
        -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?/TIMESTAMP/g' \
        -e 's/in[[:space:]]+[^[:space:]:]+\.php:[0-9]+/in FILE:LINE/g' \
        | tr -s '\n' \
        | sed -E -e '/^$/d'
}

trig_of() {
  case "$1" in
    f117*|f161*) echo "--aot-enable-pass=licm" ;;
    *)           echo "--aot-enable-pass=licm --aot-max-iterations=5" ;;
  esac
}

run_case() {
  # $1=shape $2=label $3=flags(extra, 可为空)  依赖 $php_norm
  local name="$1" label="$2" flags="$3"
  local f="$SRC_DIR/$name.php" out="$WORK/aot_compile_${name}_${label}" cerr="$WORK/${name}_${label}.cerr"
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 $BIN --compile --no-debug-info $TRIG $flags --output="$out" "$f" >"$cerr" 2>&1
  local c_rc=$?
  local tdir gen="NOTEMP"
  tdir=$(awk '/preserved/ {print $NF; exit}' "$cerr")
  if [ $c_rc -ne 0 ]; then
    local reason=$(grep -m1 "error:" "$cerr" | head -c 150 | tr '\n' ' ')
    printf "%s|%s|COMPILE_FAIL|%s\n" "$name" "$label" "$reason" >> "$TSV"
    echo "  [$name $label] COMPILE_FAIL $reason"
    [ -n "$tdir" ] && rm -rf "$tdir"; rm -f "$out" "$cerr"; return
  fi
  local md5=""
  if [ -n "$tdir" ] && [ -f "$tdir/main.zig" ]; then
    gen="[$(wc -l < "$tdir/main.zig" | tr -d ' ')/$(md5 -q "$tdir/main.zig")]"
    md5=$(md5 -q "$tdir/main.zig"); rm -rf "$tdir"
  fi
  local verdict="FAIL"
  local aot_raw a_rc
  aot_raw=$(timeout 10 "$out" 2>&1); a_rc=$?
  rm -f "$out" "$cerr"
  local aot_norm=$(printf '%s\n' "$aot_raw" | normalize_output)
  local neff=""
  if [ -n "$ref_md5" ] && [ -n "$md5" ]; then
    [ "$md5" = "$ref_md5" ] && neff="|NO_EFFECT"
  fi
  if [ $a_rc -ne 0 ]; then
    verdict="RUNTIME_FAIL"; [ $a_rc -eq 124 ] && verdict="TIMEOUT_10S"
    printf "%s|%s|%s|exit=%d%s|\n" "$name" "$label" "$verdict" "$a_rc" "$neff" >> "$TSV"
    echo "  [$name $label] $verdict exit=$a_rc $neff"
    return
  fi
  if [ "$aot_norm" = "$php_norm" ]; then verdict="PASS"; else verdict="DIFF"; fi
  local d=""
  [ "$verdict" = "DIFF" ] && d=$(diff <(printf '%s\n' "$php_norm") <(printf '%s\n' "$aot_norm") | head -6 | tr '\n' '~' | head -c 300)
  printf "%s|%s|%s%s|gen=%s|%s\n" "$name" "$label" "$verdict" "$neff" "$gen" "$d" >> "$TSV"
  echo "  [$name $label] $verdict $neff gen=$gen"
  [ -n "$d" ] && echo "      d=$d"
}

for name in f117_search_engine_inverted_tfidf_bm25 f161_json_xml_csv_parsing \
            f051_validator_rule_chain_batch f061_graph_dijkstra_bellmanford_floyd \
            f135_math_number_theory_crt_miller_rabin; do
  f="$SRC_DIR/$name.php"
  [ -f "$f" ] || { printf "%s|-|SRC_MISSING\n" "$name" >> "$TSV"; continue; }
  php_raw=$(timeout 10 "$PHP_BIN" "$f" 2>&1); [ $? -ne 0 ] && { printf "%s|-|PHP_EXIT\n" "$name" >> "$TSV"; continue; }
  php_norm=$(printf '%s\n' "$php_raw" | normalize_output)
  TRIG=$(trig_of "$name")
  echo "== $name  trigger=[$TRIG]"
  ref_md5=""
  run_case "$name" trig ""
  ref_md5=$(grep -m1 "^$name|trig|" "$TSV" | grep -o -E '[0-9a-f]{32}' | head -1)
  for p in $PASSES; do
    run_case "$name" "no_$p" "--aot-disable-pass=$p"
  done
done

{
  echo "BISECT_SUMMARY"
  # ⚠ 自我更正（#99 收尾）：原实现用 `grep -c "|$p|…|"` 取数，但落盘标签为 `no_$p`（`|no_dce|DIFF|`），
  #   而模式 `|dce|` 因前导 `|` 与 `_` 不匹配 ⇒ **除 trig 外七枚 pass 的汇总行恒为全 0**（缺陷产物，禁止解读为「该 pass 未跑」）。
  #   真实读数必须回到原始行；本轮已核对：40 行全为 `DIFF`、`PASS` 行数 = 0（末行 `pass_rows_total` 即其独立复算）。
  #   NO_EFFECT 的真实分布：`no_constprop`/`no_box-unbox`/`no_typespec` 各 5/5、`no_strength` 4/5（例外为 `f135`）、
  #   `no_dce`/`no_cse`/`no_mem2reg` 0/5（会改码但错值输出逐字不变）。
  echo "labels=trig$(for p in $PASSES; do printf ' no_%s' "$p"; done)"
  for lab in trig $(for p in $PASSES; do printf 'no_%s ' "$p"; done); do
    cnt() { awk -F'|' -v L="$lab" '$2==L && $3==V {n++} END {print n+0}' V="$1" "$TSV"; }
    printf "%s: PASS=%d DIFF=%d RUNTIME_FAIL=%d COMPILE_FAIL=%d NO_EFFECT=%d\n" "$lab" \
      "$(cnt PASS)" "$(cnt DIFF)" "$(cnt RUNTIME_FAIL)" "$(cnt COMPILE_FAIL)" \
      "$(awk -F'|' -v L="$lab" '$2==L && $4=="NO_EFFECT" {n++} END {print n+0}' "$TSV")"
  done
  echo "pass_rows_total=$(awk -F'|' '$3=="PASS" {n++} END {print n+0}' "$TSV")"
} | tee -a "$TSV"
echo "PASS_BISECT_DONE"
