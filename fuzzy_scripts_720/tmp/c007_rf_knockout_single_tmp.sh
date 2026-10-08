#!/bin/bash
# CODEGEN-007 / PERF-001「单旋钮归因臂」（任务 #95 第二阶段，只读、零源码改动、纯 CLI）
#
# 前置（#95 第一臂，c007_rf_knockout_tmp.sh）实测：release-fast 扣掉 5 枚可达旋钮
#   （function_inlining / inline_threshold / type_specialization / licm / max_iterations）后
#   ⇒ 68 语料 gen_same=67 gen_drift=0 pass=67 diff=0 runtime_fail=0，且 A 臂 19 枚红形 19/19 转绿、main.zig 逐字节回到冻结基线。
#   ⇒ 抬档的全部漂移与红面**只由这 5 枚旋钮造成**，另 8 枚不可达字段在语料上发射中性（无需改 optimizer.zig 即可完成归因）。
#
# 本脚本 = 在**默认档**（releaseSmall，与冻结基线同档）之上**只加一枚旋钮**，跑 A 臂的 19 枚红形：
#   用法：bash c007_rf_knockout_single_tmp.sh <arm>
#     单旋钮：
#       typespec = --aot-enable-pass=typespec
#       licm     = --aot-enable-pass=licm
#       iter5    = --aot-max-iterations=5
#       （内联单独一臂已在 c007_inline_only_face_tmp.sh：inline + threshold 50 ⇒ 只点亮 f152）
#     组合（测必要性 / 模型一致性）：
#       trip  = typespec + licm + iter5（= 可达集去掉内联）
#       ti    = typespec + iter5（去掉 licm 也去掉内联 ⇒ 测「LICM 是否为红面必要条件」）
#       li5   = licm + iter5（测 iter5 对内联无关红族的放大作用）
#       all5  = 五枚可达旋钮全开 ⇒ 若与 A 臂（整档 release-fast）红面相同，则「13 枚差集中只有这 5 枚起作用」模型自证
#   名单来源：fuzzy_scripts_720/tmp/c007_rf_face_tmp.tsv 的 DIFF/RUNTIME_FAIL 行（19 枚）。
# 判据同第一臂：生成码面 GEN_SAME/GEN_DRIFT（对冻结默认档基线）＋ 输出面 PASS/DIFF/RUNTIME_FAIL。
# 产物：/tmp/c007_knob_<arm>_work（临时，收尾删）；TSV 为永久取证资产；禁止删除任何 .php 源。
cd /Users/wangjianjun/products/parser || exit 1

ARM="$1"
NAMES_ALLOWED="typespec licm iter5 trip ti li5 all5"
case "$ARM" in
  typespec) KNOB_FLAGS=(--aot-enable-pass=typespec) ;;
  licm)     KNOB_FLAGS=(--aot-enable-pass=licm) ;;
  iter5)    KNOB_FLAGS=(--aot-max-iterations=5) ;;
  trip)     KNOB_FLAGS=(--aot-enable-pass=typespec --aot-enable-pass=licm --aot-max-iterations=5) ;;
  ti)       KNOB_FLAGS=(--aot-enable-pass=typespec --aot-max-iterations=5) ;;
  li5)      KNOB_FLAGS=(--aot-enable-pass=licm --aot-max-iterations=5) ;;
  all5)     KNOB_FLAGS=(--aot-enable-pass=inline --aot-enable-pass=typespec --aot-enable-pass=licm --aot-max-iterations=5 --aot-inline-threshold=50) ;;
  *) echo "unknown arm: $ARM (allowed: $NAMES_ALLOWED)"; exit 2 ;;
esac

PASS_DIR="fuzzy_scripts_720/pass"
BASELINE="fuzzy_scripts_720/baseline_main_zig_md5.tsv"
BIN="zig-out/bin/php-interpreter"
PHP_BIN="/opt/homebrew/bin/php"
WORK="/tmp/c007_knob_${ARM}_work"
TSV="fuzzy_scripts_720/tmp/c007_knob_${ARM}_tmp.tsv"
rm -rf "$WORK"
mkdir -p "$WORK"
> "$TSV"

printf "# arm=%s flags=[--compile --no-debug-info %s] bin=%s linker=%s/%s optimizer=%s\n" \
  "$ARM" "${KNOB_FLAGS[*]}" "$(md5 -q "$BIN")" \
  "$(md5 -q src/aot/native_linker.zig)" "$(wc -l < src/aot/native_linker.zig | tr -d ' ')" \
  "$(md5 -q src/aot/optimizer.zig)" >> "$TSV"

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

NAMES=$(awk -F'|' '$3=="DIFF" || $3=="RUNTIME_FAIL" {print $1}' fuzzy_scripts_720/tmp/c007_rf_face_tmp.tsv | sort)
total=0; g_same=0; g_drift=0; r_pass=0; r_diff=0; r_rfail=0; r_cfail=0

for name in $NAMES; do
  total=$((total + 1))
  f="$PASS_DIR/${name}.php"
  php_out=$(timeout 10 "$PHP_BIN" "$f" 2>&1)
  c_err="$WORK/${name}.cerr"
  out_bin="$WORK/aot_compile_${name}"
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info "${KNOB_FLAGS[@]}" --output="$out_bin" "$f" >"$c_err" 2>&1
  c_rc=$?
  tdir=$(awk '/preserved/ {print $NF; exit}' "$c_err")

  if [ $c_rc -ne 0 ]; then
    reason=$(grep -m1 "error:" "$c_err" | head -c 220 | tr '\n' ' ')
    printf "%s|COMPILE_FAIL|COMPILE_FAIL|||%s\n" "$name" "$reason" >> "$TSV"
    r_cfail=$((r_cfail + 1))
    [ -n "$tdir" ] && rm -rf "$tdir"
    rm -f "$out_bin"
    continue
  fi

  g_stat="NOTEMP"; ko_md5=""; ko_lines=""
  if [ -n "$tdir" ] && [ -f "$tdir/main.zig" ]; then
    ko_md5=$(md5 -q "$tdir/main.zig")
    ko_lines=$(wc -l < "$tdir/main.zig" | tr -d ' ')
    exp=$(awk -F'\t' -v n="$name" '$1==n {print $3}' "$BASELINE")
    exp_lines=$(awk -F'\t' -v n="$name" '$1==n {print $2}' "$BASELINE")
    if [ "$ko_md5" = "$exp" ] && [ "$ko_lines" = "$exp_lines" ]; then
      g_stat="GEN_SAME"; g_same=$((g_same + 1))
    else
      g_stat="GEN_DRIFT"; g_drift=$((g_drift + 1))
    fi
    rm -rf "$tdir"
  fi

  aot_out=$(timeout 10 "$out_bin" 2>&1)
  a_rc=$?
  rm -f "$out_bin"

  if [ $a_rc -ne 0 ]; then
    detail=$(echo "$aot_out" | tail -3 | tr '\n' ' ' | head -c 200)
    printf "%s|%s|RUNTIME_FAIL|%s|%s|exit=%d %s\n" "$name" "$g_stat" "$ko_lines" "$ko_md5" "$a_rc" "$detail" >> "$TSV"
    r_rfail=$((r_rfail + 1))
    continue
  fi

  np=$(normalize_output <<< "$php_out")
  na=$(normalize_output <<< "$aot_out")
  if [ "$np" = "$na" ]; then
    printf "%s|%s|PASS|%s|%s||\n" "$name" "$g_stat" "$ko_lines" "$ko_md5" >> "$TSV"
    r_pass=$((r_pass + 1))
  else
    detail=$(diff <(printf "%s\n" "$np") <(printf "%s\n" "$na") | head -10 | tr '\n' '~' | head -c 400)
    printf "%s|%s|DIFF|%s|%s|%s\n" "$name" "$g_stat" "$ko_lines" "$ko_md5" "$detail" >> "$TSV"
    r_diff=$((r_diff + 1))
  fi
done

echo "KNOB_DONE arm=$ARM total=$total gen_same=$g_same gen_drift=$g_drift pass=$r_pass diff=$r_diff runtime_fail=$r_rfail compile_fail=$r_cfail" | tee -a "$TSV"
