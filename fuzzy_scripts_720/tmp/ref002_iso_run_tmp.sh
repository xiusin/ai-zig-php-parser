#!/bin/bash
# AOT-REF-002 归因隔离：对给定探针逐个「编译 + 运行 + 与 PHP 真值逐字节比对」
cd /Users/wangjianjun/products/parser || exit 1
PHP=/opt/homebrew/bin/php
BIN=./zig-out/bin/php-interpreter
for f in "$@"; do
  src="fuzzy_scripts_720/tmp/$f.php"
  out="/tmp/aot_compile_$f"
  timeout 10 "$PHP" "$src" > /tmp/php_$f.out 2>/tmp/php_$f.err
  timeout 300 "$BIN" --compile --no-debug-info --output="$out" "$src" 2>/tmp/aotc_$f.err
  rc_c=$?
  if [ $rc_c -ne 0 ]; then
    echo "COMPILE_FAIL|$f|rc=$rc_c"
    continue
  fi
  timeout 10 "$out" > /tmp/aot_$f.out 2>/tmp/aot_$f.err
  rc_r=$?
  if cmp -s /tmp/aot_$f.out /tmp/php_$f.out; then
    v=IDENTICAL
  else
    v=DIFFERS
  fi
  echo "### $f => $v (run rc=$rc_r)"
  echo "    PHP: $(tr '\n' ' ' < /tmp/php_$f.out)"
  echo "    AOT: $(tr '\n' ' ' < /tmp/aot_$f.out)"
  if [ -s /tmp/aot_$f.err ]; then
    echo "    AOT-stderr: $(head -3 /tmp/aot_$f.err | tr '\n' ' ')"
  fi
  rm -f "$out"
done
echo "ISO_DONE"
