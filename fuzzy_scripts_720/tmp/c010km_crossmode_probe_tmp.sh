#!/usr/bin/env bash
# 一次性跨模式探针（登记于 `fuzzy_scripts_720/tmp/`，与永久侧门同址；探针 .php 与编译产物写在 mktemp 目录并随 trap 删除）：
# 门 K 面孔 B（分号臂假拒绝）与面孔 C（default 臂位次）
# 在 tree / bytecode / AOT 三模式下的实测结局 ⇒ 判定修复面是否必须跨模式（宪法 §五/§六 问询前置）。
# 纪律：仓库根执行（--compile 越界 cwd 报 FileNotFound）；全命令带 timeout；产物名 aot_compile_*；
#       编译失败判据取「产物可执行」不取 rc（规则 21）；零 src/ 改动；零语料 .php 删除。
set -u
cd /Users/wangjianjun/products/parser || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
T=$(mktemp -d /tmp/c010km.XXXXXX)
trap 'rm -rf "$T"' EXIT

norm() { sed -E -e 's/[[:space:]]*$//' -e '/^Stack trace:/,$d' -e '/^=== PHP Interpreter Performance Statistics ===$/,$d' -e '/^$/d' ; }

specs() {
  cat <<'SPEC'
b_case_semi|switch (1) { case 1; echo "S"; }
b_default_semi|switch (1) { default; echo "D"; }
c_default_first|switch (1) { default: echo "D"; case 2: echo "C"; }
c_lastcase_fall_into_default|switch (2) { default: echo "D"; case 2: echo "C"; }
c_middle_default|switch (1) { case 1: echo "a"; default: echo "d"; case 2: echo "b"; }
c_ctl_default_last|switch (1) { case 1: echo "a"; case 2: echo "b"; default: echo "d"; }
SPEC
}

printf 'shape|mode|rc|out\n'
while IFS='|' read -r sid body; do
  [ -z "$sid" ] && continue
  SRC="$T/c010km_${sid}_tmp.php"
  printf '<?php\n%s\n' "$body" > "$SRC"

  timeout 10 "$PHP" "$SRC" >"$T/$sid.php.out" 2>&1; prc=$?
  printf '%s|php|%s|%s\n' "$sid" "$prc" "$(norm <"$T/$sid.php.out" | tr '\n' '~')"

  timeout 10 "$BIN" --mode=tree "$SRC" >"$T/$sid.tree.out" 2>&1; trc=$?
  printf '%s|tree|%s|%s\n' "$sid" "$trc" "$(norm <"$T/$sid.tree.out" | tr '\n' '~')"

  timeout 10 "$BIN" --mode=bytecode "$SRC" >"$T/$sid.bc.out" 2>&1; brc=$?
  printf '%s|bytecode|%s|%s\n' "$sid" "$brc" "$(norm <"$T/$sid.bc.out" | tr '\n' '~')"

  timeout 120 "$BIN" --compile --no-debug-info --output="$T/aot_compile_c010km_${sid}_tmp" "$SRC" >"$T/$sid.clog" 2>&1
  if [ ! -x "$T/aot_compile_c010km_${sid}_tmp" ]; then
    printf '%s|aot|NA|compile_fail %s\n' "$sid" "$(sed -E -e 's/^Error: //' -e 's/ on line [0-9]+$/ on line LINE/' "$T/$sid.clog" | tr '\n' '~')"
  else
    timeout 10 "$T/aot_compile_c010km_${sid}_tmp" >"$T/$sid.aot.out" 2>&1; arc=$?
    printf '%s|aot|%s|%s\n' "$sid" "$arc" "$(norm <"$T/$sid.aot.out" | tr '\n' '~')"
    rm -f "$T/aot_compile_c010km_${sid}_tmp"
  fi
done < <(specs)

echo "RESID=$(find . -maxdepth 1 \( -name '.zigphp_aot_build_*' -o -name 'aot_compile_*' \) 2>/dev/null | wc -l | tr -d ' ')"
echo "C010KM_DONE shapes=6"
