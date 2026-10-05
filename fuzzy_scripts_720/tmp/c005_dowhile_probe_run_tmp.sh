#!/bin/bash
# AOT-CODEGEN-005 do-while 侧同族审计门（2026-10-04 立项）：F-I / F-J 两形逐形等值。
#   F-I = 外层 foreach + 臂内嵌 do-while + 臂尾裸 continue + 兄弟语句 $hit++（与 F-F 仅内层关键字之差）
#   F-J = 外层 for + 臂内嵌 do-while + 臂尾裸 continue + 兄弟语句 $hit++（与 F-H 仅内层关键字之差）
# 判据：两形必须与 /opt/homebrew/bin/php 逐字节等值，末行 `DOWHILE_PROBE_DONE total=2 same=2 differs=0`。
# 独立门，**不并入** 17 形等值门（`c005_probe_run_tmp.sh`），避免追溯性改动 RC-4/RC-5 验收记录。
# 已知机制（见工单 §4「do-while 侧站点③ 审计」）：含 do-while 的函数被函数级门控
#   （`has_do_while` 否决 AST-direct 与结构化两条原生路径）整体回退到 `switch (current_block)` 状态机，
#   故本门两形**不经过** `generateDoWhileFromLabels` 的外层 latch 分支 ⇒ 本门只证「输出等值」，
#   不证站点③ 正确，也不否证它；站点③ 仍是未覆盖缺口。
cd /Users/wangjianjun/products/parser || exit 1
PHP=/opt/homebrew/bin/php
BIN=./zig-out/bin/php-interpreter
total=0
same=0
differs=0
for f in c005_rc5fi_only_tmp c005_rc5fj_only_tmp; do
  src="fuzzy_scripts_720/tmp/$f.php"
  out="/tmp/aot_compile_$f"
  timeout 300 "$BIN" --compile --no-debug-info --output="$out" "$src" 2>/tmp/aotc_$f.err
  rc_c=$?
  if [ $rc_c -ne 0 ]; then
    echo "COMPILE_FAIL|$f|rc=$rc_c"
    cat /tmp/aotc_$f.err
    differs=$((differs + 1))
    total=$((total + 1))
    continue
  fi
  timeout 10 "$out" > /tmp/aot_$f.out 2>/tmp/aot_$f.err
  rc_r=$?
  timeout 10 "$PHP" "$src" > /tmp/php_$f.out 2>/tmp/php_$f.err
  total=$((total + 1))
  if cmp -s /tmp/aot_$f.out /tmp/php_$f.out; then
    echo "IDENTICAL|$f|rc=$rc_r"
    same=$((same + 1))
  else
    echo "DIFFERS|$f|rc=$rc_r"
    echo "  PHP: $(tr '\n' '|' < /tmp/php_$f.out)"
    echo "  AOT: $(tr '\n' '|' < /tmp/aot_$f.out)"
    differs=$((differs + 1))
  fi
  rm -f "$out"
done
echo "DOWHILE_PROBE_DONE total=$total same=$same differs=$differs"
