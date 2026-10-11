#!/usr/bin/env bash
# 永久侧门 O = AOT-CODEGEN-011 面C（default 臂位次丢失）验收门
#   （D-4 裁决新建；原拟名「门 M」已被 012 类名 CI 门占用 ⇒ 改名门 O；2026-10-11 新建）
#   6 形 = default 首臂 / 末 case 落入 default（假执行）/ 中臂 default / 未匹配中臂 /
#         控制臂（default 末臂）/ 多臂复现；判读 = R-C1+R-C2 落地后 6 形全绿。
#   机制：臂尾 fall-through 按源码序（default 参与），分发侧（switch_/比较链）不变。
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/c011_default_slot_tmp.tsv"
T=$(mktemp -d /tmp/c010o.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() {
  sed -E -e 's/[[:space:]]*$//' \
         -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' \
         -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' \
         -e '/^Stack trace:/,$d' \
         -e '/^$/d'
}

body_for() {
  case "$1" in
    o_default_first) printf '<?php\nswitch (1) { default: echo "D"; case 2: echo "C"; }\n' ;;
    o_lastcase_fall) printf '<?php\nswitch (2) { default: echo "D"; case 2: echo "C"; }\n' ;;
    o_middle_default) printf '<?php\nswitch (1) { case 1: echo "a"; default: echo "d"; case 2: echo "b"; }\n' ;;
    o_no_match) printf '<?php\nswitch (9) { case 1: echo "a"; default: echo "d"; case 2: echo "b"; }\n' ;;
    o_ctl_default_last) printf '<?php\nswitch (1) { case 1: echo "a"; case 2: echo "b"; default: echo "d"; }\n' ;;
    o_multi) printf '<?php\nswitch (0) { case 1: echo "a"; default: echo "d"; case 2: echo "b"; case 3: echo "c"; }\n' ;;
  esac
}

: > "$OUT"
red=0; green=0; compile_fail=0; bad_probe=0
for s in o_default_first o_lastcase_fall o_middle_default o_no_match o_ctl_default_last o_multi; do
  f="$T/${s}.php"
  body_for "$s" > "$f"
  if ! timeout 10 "$PHP" -l "$f" >/dev/null 2>&1; then
    printf '%s\tBAD_PROBE_PHP_LINT\n' "$s" >>"$OUT"; bad_probe=$((bad_probe+1)); continue
  fi
  ph=$(timeout 10 "$PHP" "$f" 2>&1 | norm)
  if [ -z "$ph" ]; then
    printf '%s\tBAD_PROBE_PHP_EMPTY\n' "$s" >>"$OUT"; bad_probe=$((bad_probe+1)); continue
  fi
  timeout 120 "$BIN" --compile --no-debug-info --output="$T/aot_compile_${s}_tmp" "$f" >"$T/${s}.clog" 2>&1
  if [ -x "$T/aot_compile_${s}_tmp" ]; then
    ao=$(timeout 10 "$T/aot_compile_${s}_tmp" 2>&1 | norm)
    if [ "$ph" = "$ao" ]; then cls="SAME"; else cls="DIFF"; fi
    printf '%s\t%s\tPHP[%s]\tAOT[%s]\n' "$s" "$cls" "$ph" "$ao" >>"$OUT"
    [ "$cls" = "SAME" ] && green=$((green+1)) || red=$((red+1))
  else
    printf '%s\tCOMPILE_FAIL\tPHP[%s]\tAOT[no product]\n' "$s" "$ph" >>"$OUT"
    compile_fail=$((compile_fail+1))
  fi
  rm -f "$T/aot_compile_${s}_tmp"
done
residue=$(ls -d .zigphp_aot_build_* aot_compile_* 2>/dev/null | wc -l | tr -d ' ')
END=$(date +%s)
echo "C011O_DONE shapes=6 red=$red green=$green compile_fail=$compile_fail bad_probe=$bad_probe repo_build_residue=$residue SMOKE_ONLY=0 ELAPSED=$((END-START))s" >>"$OUT"
tail -1 "$OUT"
