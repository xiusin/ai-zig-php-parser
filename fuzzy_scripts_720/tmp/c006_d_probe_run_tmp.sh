#!/usr/bin/env bash
# AOT-CODEGEN-006 D 批双臂发射门：形 8 同几何的另外两条取臂路径（D-1 末节点 then 臂 / D-2 首臂）。
# 立门理由：9 形门（c006_tl_probe_run_tmp.sh）在 D 批落地前已把 `total=9` 写进验收记录，
# 禁止追溯性改写 ⇒ 新增臂取用面单独立门，逐形与 /opt/homebrew/bin/php 逐字节等值。
# 判据：`C006_D_GATE_DONE total=2 same=2 differs=0`；任一变红即 D 批双臂发射的臂互斥/臂尾接法有缺陷。
# 编译档位 release-fast（与探针等值门一致）；产物按宪法命名 aot_compile_{filename}，跑完即删。
set -u
cd "$(dirname "$0")/../.." || exit 1
PHP=/opt/homebrew/bin/php
BIN="${AOT_BIN:-./zig-out/bin/php-interpreter}"
TMP=/tmp/c006_d_gate
mkdir -p "$TMP"

files=(
  c006_tl_two_elseif_then_tmp
  c006_tl_two_elseif_early_tmp
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
echo "C006_D_GATE_DONE total=${#files[@]} same=$same differs=$differs"
