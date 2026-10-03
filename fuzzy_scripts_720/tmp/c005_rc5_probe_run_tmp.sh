#!/bin/bash
# AOT-CODEGEN-005 RC-5 诊断门：臂尾裸 break/continue × 真实 merge/else 延续块的八形（F-A..F-H）。
# 判据（2026-10-01 实测登记）：F-A/F-C/F-G 必须等值（正对照），其余五形为 RC-5 已知红点，
# 出现清单外差异即视为有新缺陷。非等值门，不并入 17 形等值门（避免追溯性改变 RC-4 验收记录）。
cd /Users/wangjianjun/products/parser || exit 1
PHP=/opt/homebrew/bin/php
BIN=./zig-out/bin/php-interpreter
f=c005_rc5_merge_loss_tmp
src="fuzzy_scripts_720/tmp/$f.php"
out="/tmp/aot_compile_$f"
timeout 300 "$BIN" --compile --no-debug-info --output="$out" "$src" 2>/tmp/aotc_$f.err
rc_c=$?
if [ $rc_c -ne 0 ]; then
  echo "COMPILE_FAIL|$f|rc=$rc_c"
  cat /tmp/aotc_$f.err
  exit 1
fi
timeout 10 "$out" > /tmp/aot_$f.out 2>/tmp/aot_$f.err
rc_r=$?
timeout 10 "$PHP" "$src" > /tmp/php_$f.out 2>/tmp/php_$f.err
if cmp -s /tmp/aot_$f.out /tmp/php_$f.out; then
  echo "IDENTICAL|$f|rc=$rc_r"
else
  echo "DIFFERS|$f|rc=$rc_r"
  echo "  PHP: $(tr '\n' '|' < /tmp/php_$f.out)"
  echo "  AOT: $(tr '\n' '|' < /tmp/aot_$f.out)"
fi
rm -f "$out"
echo "RC5_PROBE_DONE file=$f"
