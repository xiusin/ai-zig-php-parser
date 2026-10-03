#!/bin/bash
# AOT-CODEGEN-005 RC-4 取证/验收探针：臂尾裸 break·continue 后折进内层循环出口边的六形 + 最小单形
cd /Users/wangjianjun/products/parser || exit 1
PHP=/opt/homebrew/bin/php
BIN=./zig-out/bin/php-interpreter
PROBES="
c005_rc4_min_y1_tmp
c005_rc4_break_after_nested_loop_tmp
c005_rc4_min_y6_tmp
ref003_crash_attr_tmp
"
same=0
diff=0
for f in $PROBES; do
  src="fuzzy_scripts_720/tmp/$f.php"
  out="/tmp/aot_compile_$f"
  timeout 300 "$BIN" --compile --no-debug-info --output="$out" "$src" 2>/tmp/aotc_$f.err
  rc_c=$?
  if [ $rc_c -ne 0 ]; then
    echo "COMPILE_FAIL|$f|rc=$rc_c"
    cat /tmp/aotc_$f.err
    diff=$((diff+1))
    continue
  fi
  timeout 10 "$out" > /tmp/aot_$f.out 2>/tmp/aot_$f.err
  rc_r=$?
  timeout 10 "$PHP" "$src" > /tmp/php_$f.out 2>/tmp/php_$f.err
  if cmp -s /tmp/aot_$f.out /tmp/php_$f.out; then
    echo "IDENTICAL|$f|rc=$rc_r"
    same=$((same+1))
  else
    echo "DIFFERS|$f|rc=$rc_r"
    echo "  PHP: $(tr '\n' '|' < /tmp/php_$f.out)"
    echo "  AOT: $(tr '\n' '|' < /tmp/aot_$f.out)"
    diff=$((diff+1))
  fi
  rm -f "$out"
done
echo "RC4_PROBE_DONE total=$(echo $PROBES | wc -w | tr -d ' ') same=$same differs=$diff"
