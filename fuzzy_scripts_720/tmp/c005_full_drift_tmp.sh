#!/bin/bash
# 全量冻结基线漂移核验：逐个语料脚本实时编译（KEEP_TEMP），把 main.zig 的 md5+行数与冻结基线逐行比对。
# 与 5 项抽查（s7_baseline_spotcheck_tmp.sh）同判据，但覆盖全部 pass/*.php ⇒ 用于「先证明语料零漂移再重冻结」。
cd /Users/wangjianjun/products/parser || exit 1
BASELINE="fuzzy_scripts_720/baseline_main_zig_md5.tsv"
BIN="zig-out/bin/php-interpreter"
PASS_DIR="fuzzy_scripts_720/pass"
total=0; ok=0; diff=0; notemp=0; norow=0
for f in "$PASS_DIR"/*.php; do
  name=$(basename "$f" .php)
  total=$((total+1))
  exp=$(awk -F'\t' -v n="$name" '$1==n {print $3}' "$BASELINE")
  exp_lines=$(awk -F'\t' -v n="$name" '$1==n {print $2}' "$BASELINE")
  if [ -z "$exp" ]; then
    echo "NOROW|$name"
    norow=$((norow+1))
    continue
  fi
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info "$f" 2>/tmp/s7_full_drift.err >/dev/null
  rc=$?
  d=$(awk '/preserved/ {print $NF; exit}' /tmp/s7_full_drift.err)
  if [ $rc -ne 0 ]; then
    echo "COMPILE_FAIL|$name|rc=$rc"
    diff=$((diff+1))
    [ -n "$d" ] && rm -rf "$d"
    rm -f "$PASS_DIR/aot_compile_${name}"
    continue
  fi
  if [ -z "$d" ] || [ ! -f "$d/main.zig" ]; then
    echo "NOTEMP|$name"
    notemp=$((notemp+1))
    rm -f "$PASS_DIR/aot_compile_${name}"
    continue
  fi
  got=$(md5 -q "$d/main.zig")
  lines=$(wc -l < "$d/main.zig" | tr -d ' ')
  if [ "$got" = "$exp" ] && [ "$lines" = "$exp_lines" ]; then
    ok=$((ok+1))
  else
    echo "DIFF|$name|live=$lines/$got|frozen=$exp_lines/$exp"
    diff=$((diff+1))
  fi
  rm -rf "$d"
  rm -f "$PASS_DIR/aot_compile_${name}"
done
echo "DRIFT_DONE total=$total ok=$ok diff=$diff notemp=$notemp norow=$norow"
