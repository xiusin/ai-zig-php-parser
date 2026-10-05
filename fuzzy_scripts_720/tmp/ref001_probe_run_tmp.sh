#!/bin/bash
# AOT-REF-001 D0/D2 验收：4 个永久探针 AOT 输出 vs PHP 真值逐字节比对
cd /Users/wangjianjun/products/parser || exit 1
PHP=/opt/homebrew/bin/php
BIN=./zig-out/bin/php-interpreter
PROBES="ref_semantics_matrix_probe_tmp ref_rehash_dangling_probe_tmp obj_prop_ref_control_probe_tmp obj_prop_ref_rehash_probe_tmp"
same=0
diff=0
for f in $PROBES; do
  src="fuzzy_scripts_720/tmp/$f.php"
  out="/tmp/aot_compile_$f"
  timeout 300 "$BIN" --compile --no-debug-info --output="$out" "$src" 2>/tmp/aotc_$f.err
  rc_c=$?
  if [ $rc_c -ne 0 ]; then
    echo "COMPILE_FAIL|$f|rc=$rc_c"
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
    diff=$((diff+1))
  fi
  rm -f "$out"
done
echo "PROBE_DONE same=$same differs=$diff"
