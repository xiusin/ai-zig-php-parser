#!/usr/bin/env bash
# 永久侧门 N = AOT-CODEGEN-011 面B（case/default 臂终止符位）PHP 真值注册门
#   （R-B1 前置，承 CODEGEN-010 门 L 做法；2026-10-11 立单取证轮新建）
#   形态：case X: / case X;（PHP 8.5 Deprecated 但合法）/ default: / default; /
#         替代语法支 / 双分号 BOTH_REJECT 控制臂。
#   判读口径：norm 剥两侧的 Deprecated 行（R-B1 落地口径 = 接受分号终结符但不发
#   PHP 风格 Deprecated ⇒ 该残差登记为 P2 消息面，不参与门判定）；
#   值输出（A/D 等标记）逐字节比对。
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN="zig-out/bin/php-interpreter"
PHP="/opt/homebrew/bin/php"
OUT="fuzzy_scripts_720/tmp/c011_terminator_tmp.tsv"
T=$(mktemp -d /tmp/c010n.XXXXXX)
trap 'rm -rf "$T"' EXIT
START=$(date +%s)

norm() {
  sed -E -e 's/[[:space:]]*$//' \
         -e '/^PHP Deprecated:/d' -e '/^Deprecated:/d' \
         -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' \
         -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' \
         -e '/^Stack trace:/,$d' \
         -e '/^$/d'
}

body_for() {
  case "$1" in
    n_case_colon)    printf '<?php\nswitch (1) { case 1: echo "A"; }\necho "|end";\n' ;;
    n_case_semi)     printf '<?php\nswitch (1) { case 1; echo "A"; }\necho "|end";\n' ;;
    n_default_colon) printf '<?php\nswitch (1) { default: echo "D"; }\n' ;;
    n_default_semi)  printf '<?php\nswitch (1) { default; echo "D"; }\n' ;;
    n_alt_case_semi) printf '<?php\nswitch (1): case 1; echo "A"; endswitch;\n' ;;
    n_alt_default_semi) printf '<?php\nswitch (1): default; echo "D"; endswitch;\n' ;;
    n_two_semi)      printf '<?php\nswitch (1) { case 1;; echo "A"; }\n' ;;
  esac
}

: > "$OUT"
red=0; green=0; compile_fail=0; bad_probe=0
for s in n_case_colon n_case_semi n_default_colon n_default_semi n_alt_case_semi n_alt_default_semi n_two_semi; do
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
echo "C011N_DONE shapes=7 red=$red green=$green compile_fail=$compile_fail bad_probe=$bad_probe repo_build_residue=$residue SMOKE_ONLY=0 ELAPSED=$((END-START))s" >>"$OUT"
tail -1 "$OUT"
