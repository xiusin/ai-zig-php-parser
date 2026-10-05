#!/usr/bin/env bash
# AOT-CODEGEN-006 顶层臂丢失取证门：逐形 PHP vs AOT 逐字节等值。
# 只覆盖本次新登记的顶层脚本体形状，禁止与 17 形等值门合并（几何不同）。
# 编译档位固定 release-fast（与语料实际档位一致），产物按宪法命名 aot_compile_{filename}。
set -u
cd "$(dirname "$0")/../.." || exit 1
PHP=/opt/homebrew/bin/php
# 默认用工作区二进制；判「是否 RC-5 引入的回归」时用 AOT_BIN 指向 HEAD worktree 的二进制复跑同一门。
BIN="${AOT_BIN:-./zig-out/bin/php-interpreter}"
TMP=/tmp/c006_tl_gate
mkdir -p "$TMP"

files=(
  c006_tl_shape1_tmp
  c006_tl_ifelse_loop_tmp
  c006_tl_else_echo_tmp
  c006_tl_elseif_loop_tmp
  c006_tl_else_while_tmp
  c006_tl_else_loop_tail_tmp
  c006_tl_fncontext_loop_tmp
  c006_tl_two_elseif_loop_tmp
  c006_tl_ifarm_loop_tmp
)

same=0
differs=0
for f in "${files[@]}"; do
  p="fuzzy_scripts_720/tmp/${f}.php"
  out="/tmp/aot_compile_${f}"
  if ! timeout 600 "$BIN" --compile --optimize=release-fast --no-debug-info --output="$out" "$p" >"$TMP/${f}.build.log" 2>&1; then
    echo "FAIL_COMPILE|$f"
    differs=$((differs + 1))
    continue
  fi
  timeout 10 "$PHP" "$p" > "$TMP/${f}.php.out" 2>&1
  timeout 10 "$out" > "$TMP/${f}.aot.out" 2>&1
  if cmp -s "$TMP/${f}.php.out" "$TMP/${f}.aot.out"; then
    echo "IDENTICAL|$f|php=$(head -c 40 "$TMP/${f}.php.out" | tr -d '\n')"
    same=$((same + 1))
  else
    echo "DIFF|$f|php=[$(head -c 60 "$TMP/${f}.php.out" | tr '\n' ' ')]|aot=[$(head -c 60 "$TMP/${f}.aot.out" | tr '\n' ' ')]"
    differs=$((differs + 1))
  fi
  rm -f "$out"
done
echo "C006_TL_GATE_DONE total=${#files[@]} same=$same differs=$differs"
