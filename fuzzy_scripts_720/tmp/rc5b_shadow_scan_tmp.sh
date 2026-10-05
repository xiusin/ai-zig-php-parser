#!/bin/bash
# 临时：方案 B 影子口径的回归面量化（只编译，不运行；统计 [RC5B-SHADOW] 命中）。用后删除。
cd /Users/wangjianjun/products/parser || exit 1
BIN="zig-out/bin/php-interpreter"
total=0; hit=0; fail=0
T=$(mktemp -d /tmp/rc5b_files.XXXXXX)
ls fuzzy_scripts_720/pass/*.php > "$T/list"
for p in c005_rc5_merge_loss_tmp c005_rc4_min_y6_tmp c005_rc4_min_y1_tmp c005_rc4_break_after_nested_loop_tmp ref003_crash_attr_tmp; do
  echo "fuzzy_scripts_720/tmp/$p.php" >> "$T/list"
done
while IFS= read -r f; do
  name=$(basename "$f" .php)
  total=$((total+1))
  err="/tmp/rc5b_${name}.err"
  timeout 120 "$BIN" --compile --no-debug-info --output="/tmp/aot_compile_rc5b_${name}" "$f" >/dev/null 2>"$err"
  rc=$?
  rm -f "/tmp/aot_compile_rc5b_${name}"
  if [ $rc -ne 0 ]; then
    fail=$((fail+1))
    echo "COMPILE_FAIL|$name|rc=$rc"
  fi
  n=$(grep -c "RC5B-SHADOW" "$err" 2>/dev/null || true)
  [ -z "$n" ] && n=0
  if [ "$n" -gt 0 ]; then
    hit=$((hit+1))
    echo "HIT|$name|shadow_lines=$n"
    grep "RC5B-SHADOW" "$err" | sed 's/^/    /'
  fi
done < "$T/list"
rm -rf "$T"
echo "RC5B_DONE total=$total fail=$fail scripts_with_swallow=$hit"
