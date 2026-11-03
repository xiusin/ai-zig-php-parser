#!/usr/bin/env bash
# 永久侧门 C342：sprintf 空格标志（F-167）＋ NAN 字符串化告警（F-168）（R-319 已闭）
#   缺陷①：AOT 把 `% f`/`% d`/`% 05d` 的空格标志当作「补一个前导空格」；PHP 8.5.8 实测**忽略**空格标志
#          （`[% f]`⇒`1.250000`、`[% 5d]`⇒`    3`、`[% 05d]`⇒`00003`、`[% 10s]`⇒8 空格+值）。
#   缺陷②：`echo NAN` 等所有字符串化路径缺 `Warning: unexpected NAN value was coerced to string`
#          （PHP 实测：echo/print/(string)/strval/插值/拼接/sprintf("%s")/print_r/implode 全发，INF 不发，
#           var_export/json_encode 不发，`@` 与 error_reporting 掩码可抑制）。
#   判据：stdout+stderr+rc 与 PHP 8.5.8 逐字节一致（norm：折叠行首空白/路径/行号，丢弃栈帧段）。
#   臂：f1 空格标志矩阵 / n1 echo+print / n2 转型族 / n3 sprintf+implode 计数 /
#       n4 反证（INF、var_export、json_encode、(int) 转换既有告警）/ n5 `@` 与 error_reporting 掩码
#   纪律：门臂一律 heredoc；AOT_BIN=/bin/false 自证必须全 COMPILE_FAIL；TSV 走 TSV_OUT；产物落临时目录并清理。
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 90
PHP=/opt/homebrew/bin/php
AOT="${AOT_BIN:-zig-out/bin/php-interpreter}"
T="$(mktemp -d /tmp/c342nan.XXXXXX)"
trap 'rm -rf "$T"' EXIT
OUT="${TSV_OUT:-fuzzy_scripts_720/tmp/c342_sprintf_nan_tmp.tsv}"
norm() { sed -E -e 's/^[[:space:]]+//' -e 's~[A-Za-z0-9_./-]*/[A-Za-z0-9_.-]+\.php~@FILE@~g' -e 's/on line [0-9]+/on line @N@/g' -e '/^Stack trace:/,$d'; }

cat > "$T/f1.php" <<'PHP'
<?php
printf("[% f][% d][% 5d][%05d][% 05d][% .3f][%+ d]\n", 1.25, 3, 3, 3, 3, 1.25, 3);
printf("[% s][% 10s][%-10s]\n", "ab", "ab", "ab");
printf("[% -5d][% 8.2f]\n", 7, 3.14159);
PHP

cat > "$T/n1.php" <<'PHP'
<?php
$n = NAN;
echo "echo=[", $n, "]\n";
echo "print=["; print $n; echo "]\n";
PHP

cat > "$T/n2.php" <<'PHP'
<?php
$n = NAN;
echo "cast=[", (string)$n, "]\n";
echo "strval=[", strval($n), "]\n";
echo "interp=[$n]\n";
echo "concat=[", $n . "", "]\n";
PHP

cat > "$T/n3.php" <<'PHP'
<?php
$n = NAN;
echo "sprintf=[", sprintf("%s", $n), "]\n";
echo "implode1=[", implode(",", [1, $n]), "]\n";
echo "implode2=[", implode(",", [$n, $n]), "]\n";
echo "twoconcat=[", "x" . $n . "y" . $n, "]\n";
PHP

cat > "$T/n4.php" <<'PHP'
<?php
$n = NAN; $i = INF;
echo "inf=[", $i, "]\n";
echo "ve=[", var_export($n, true), "]\n";
var_dump(json_encode($n));
var_dump((int)$i, (int)$n, (int)-$i);
PHP

cat > "$T/n5.php" <<'PHP'
<?php
$n = NAN;
$s = @(string)$n;
echo "at=[", $s, "]\n";
error_reporting(E_ALL & ~E_WARNING);
echo "er=[", $n, "]\n";
error_reporting(E_ALL);
echo "back=[", $n, "]\n";
PHP

ALL_ARMS="f1 n1 n2 n3 n4 n5"
: > "$OUT"
START=$(date +%s); narms=0; same=0; diff=0; cfail=0; tfail=0
for a in $ALL_ARMS; do
  narms=$((narms+1))
  timeout 300 "$AOT" --compile --output="$T/aot_compile_$a" "$T/$a.php" >"$T/$a.c.log" 2>&1
  if [ $? -ne 0 ] || [ ! -s "$T/aot_compile_$a" ]; then
    printf '%s\tCOMPILE_FAIL\t-\t%s\n' "$a" "$(grep -m1 'error:' "$T/$a.c.log" | cut -c1-160)" >>"$OUT"; cfail=$((cfail+1)); rm -f "$T/aot_compile_$a"; continue
  fi
  timeout 10 "$PHP" -d display_errors=1 -d error_reporting=E_ALL "$T/$a.php" >"$T/$a.p.out" 2>"$T/$a.p.err"; prc=$?
  timeout 10 "$T/aot_compile_$a" >"$T/$a.a.out" 2>"$T/$a.a.err"; arc=$?
  if [ "$arc" = 124 ]; then
    printf '%s\tTIMEOUT\t-\t-\n' "$a" >>"$OUT"; tfail=$((tfail+1)); rm -f "$T/aot_compile_$a"; continue
  fi
  norm <"$T/$a.p.out" >"$T/$a.pn.out"; norm <"$T/$a.a.out" >"$T/$a.an.out"
  norm <"$T/$a.p.err" >"$T/$a.pn.err"; norm <"$T/$a.a.err" >"$T/$a.an.err"
  if [ "$prc" = "$arc" ] && diff -q "$T/$a.pn.out" "$T/$a.an.out" >/dev/null 2>&1 && diff -q "$T/$a.pn.err" "$T/$a.an.err" >/dev/null 2>&1; then
    printf '%s\tSAME\trc=%s\t[%s]\n' "$a" "$prc" "$(tr '\n' ' ' <"$T/$a.pn.out" | cut -c1-120)" >>"$OUT"; same=$((same+1))
  else
    printf '%s\tDIFF\tPHPrc=%s AOTrc=%s\tP[%s]|PE[%s] A[%s]|AE[%s]\n' "$a" "$prc" "$arc" \
      "$(tr '\n' ' ' <"$T/$a.pn.out" | cut -c1-100)" "$(tr '\n' ' ' <"$T/$a.pn.err" | cut -c1-100)" \
      "$(tr '\n' ' ' <"$T/$a.an.out" | cut -c1-100)" "$(tr '\n' ' ' <"$T/$a.an.err" | cut -c1-100)" >>"$OUT"; diff=$((diff+1))
  fi
  rm -f "$T/aot_compile_$a"
done
echo "C342NAN_DONE	arms=$narms	same=$same	diff=$diff	compile_fail=$cfail	timeout=$tfail	ELAPSED=$(( $(date +%s) - START ))s"
echo "TSV=$OUT"
