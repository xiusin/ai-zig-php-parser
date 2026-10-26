#!/usr/bin/env bash
# 永久侧门 C328：资源引用计数泄漏（F-180；fopen/fclose、opendir/closedir 族）
#   判据（泄漏臂 a1~a4）：N=1000 与 N=3000 双跑，Δlive_bytes==0 ∧ Δlive_allocs==0 且 rc=0
#     （读数取 stderr 的 ALLOC_STATS 行；该行行尾是字面 \n 两字符，grep -o 截取数字）
#   判据（行为臂 b1）：fclose/closedir 后的语义面与 PHP 8.5.8 逐字节一致
#     （is_resource=false、gettype="resource (closed)"、closedir 后 readdir(null) 的
#      Deprecated+TypeError 守卫）——防归零修复引入双重释放/语义回归。
#   判据（敏感度臂 s1）：每轮故意保留一枚字符串 ⇒ Δlive_allocs>0 ∧ Δlive_bytes>0
#     （证明量具能看见泄漏；量具瞎了门必须红）。
#   纪律：仓库根；全命令 timeout；产物 aot_compile_* 落临时目录并清理；TSV 走 TSV_OUT；
#   门臂一律 heredoc；禁在循环体内用三元实参（F-117 伪影）。
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 90
PHP=/opt/homebrew/bin/php
AOT="${AOT_BIN:-zig-out/bin/php-interpreter}"
T="$(mktemp -d /tmp/c328res.XXXXXX)"
trap 'rm -rf "$T"' EXIT
OUT="${TSV_OUT:-fuzzy_scripts_720/tmp/c328_resource_refcount_tmp.tsv}"

sfield() { # $1=stderr文件 $2=字段名 => 数字
  grep -m1 ALLOC_STATS "$1" 2>/dev/null | grep -o "$2=[0-9]*" | head -1 | tr -dc '0-9'
}

cat > "$T/a1.php" <<'PHP'
<?php
$N = (int)($argv[1] ?? "1000");
$p = $argv[2];
for ($i = 0; $i < $N; $i++) {
  $f = fopen($p, 'w');
  fclose($f);
}
echo "A1\n";
PHP

cat > "$T/a2.php" <<'PHP'
<?php
$N = (int)($argv[1] ?? "1000");
$d = $argv[2];
for ($i = 0; $i < $N; $i++) {
  $h = opendir($d);
  closedir($h);
}
echo "A2\n";
PHP

cat > "$T/a3.php" <<'PHP'
<?php
$N = (int)($argv[1] ?? "1000");
$p = $argv[2];
for ($i = 0; $i < $N; $i++) {
  $f = fopen($p, 'w');
  fwrite($f, "abc");
  fclose($f);
  $g = fopen($p, 'r');
  fread($g, 2);
  fgets($g);
  fclose($g);
}
echo "A3\n";
PHP

cat > "$T/a4.php" <<'PHP'
<?php
$N = (int)($argv[1] ?? "1000");
$d = $argv[2];
for ($i = 0; $i < $N; $i++) {
  $h = opendir($d);
  unset($h);
}
echo "A4\n";
PHP

cat > "$T/b1.php" <<'PHP'
<?php
$d = $argv[1];
$p = "$d/b1.txt";
$f = fopen($p, 'w');
fwrite($f, "x");
fclose($f);
echo "isres|", var_export(is_resource($f), true), "|", gettype($f), "\n";
$h = opendir($d);
closedir($h);
echo "isres_dir|", var_export(is_resource($h), true), "|", gettype($h), "\n";
try { readdir(null); echo "bad|NO_THROW\n"; } catch (\Throwable $x) { echo "null_after_close|", get_class($x), "|", $x->getMessage(), "\n"; }
$g = fopen($p, 'r');
$ok = fread($g, 1);
fclose($g);
echo "reopen|", $ok, "|", var_export(is_resource($g), true), "\n";
echo "END\n";
PHP

cat > "$T/s1.php" <<'PHP'
<?php
$N = (int)($argv[1] ?? "1000");
$keep = [];
for ($i = 0; $i < $N; $i++) {
  $keep[] = "sens";
}
echo "S1|", count($keep), "\n";
PHP

norm() { sed -E -e 's/^[[:space:]]+//' -e 's~[A-Za-z0-9_./-]*/[A-Za-z0-9_.-]+\.php~@FILE@~g' -e 's/on line [0-9]+/on line @N@/g'; }

: > "$OUT"
START=$(date +%s); narms=0; same=0; diff=0; cfail=0
verdict_leak() { # $1=臂名 $2=php脚本 $3=arg路径 判 Δ==0
  local a="$1" scr="$T/$2" argp="$3" lo1 lo2 la1 la2 rc1 rc2
  narms=$((narms+1))
  timeout 120 "$AOT" --compile --output="$T/aot_compile_$a" "$scr" >"$T/$a.c.log" 2>&1
  if [ $? -ne 0 ] || [ ! -s "$T/aot_compile_$a" ]; then
    printf '%s\tCOMPILE_FAIL\t-\t%s\n' "$a" "$(grep -m1 'error:' "$T/$a.c.log" | cut -c1-160)" >>"$OUT"; cfail=$((cfail+1)); rm -f "$T/aot_compile_$a"; return
  fi
  ZIGPHP_ALLOC_STATS=1 timeout 60 "$T/aot_compile_$a" 1000 "$argp" >"$T/$a.1.out" 2>"$T/$a.1.err"; rc1=$?
  ZIGPHP_ALLOC_STATS=1 timeout 60 "$T/aot_compile_$a" 3000 "$argp" >"$T/$a.2.out" 2>"$T/$a.2.err"; rc2=$?
  lo1=$(sfield "$T/$a.1.err" live_bytes); lo2=$(sfield "$T/$a.2.err" live_bytes)
  la1=$(sfield "$T/$a.1.err" live_allocs); la2=$(sfield "$T/$a.2.err" live_allocs)
  if [ "$rc1" = "0" ] && [ "$rc2" = "0" ] && [ -n "$lo1" ] && [ "$lo1" = "$lo2" ] && [ "$la1" = "$la2" ]; then
    printf '%s\tSAME\tlb=%s/%s la=%s/%s\n' "$a" "$lo1" "$lo2" "$la1" "$la2" >>"$OUT"; same=$((same+1))
  else
    printf '%s\tDIFF\trc=%s/%s lb=%s/%s la=%s/%s\n' "$a" "$rc1" "$rc2" "$lo1" "$lo2" "$la1" "$la2" >>"$OUT"; diff=$((diff+1))
  fi
  rm -f "$T/aot_compile_$a"
}

touch "$T/leakfile" "$T/b1.txt"
verdict_leak a1 a1.php "$T/leakfile"
verdict_leak a2 a2.php "$T"
verdict_leak a3 a3.php "$T/leakfile"
verdict_leak a4 a4.php "$T"

# b1 行为臂：与 PHP 归一化逐字节比对
narms=$((narms+1)); a=b1
if timeout 120 "$AOT" --compile --output="$T/aot_compile_$a" "$T/$a.php" >"$T/$a.c.log" 2>&1 && [ -s "$T/aot_compile_$a" ]; then
  timeout 20 "$PHP" -d display_errors=1 -d error_reporting=E_ALL "$T/$a.php" "$T" >"$T/$a.p.out" 2>"$T/$a.p.err"; prc=$?
  timeout 20 "$T/aot_compile_$a" "$T" >"$T/$a.a.out" 2>"$T/$a.a.err"; arc=$?
  norm <"$T/$a.p.out" >"$T/$a.p.outn"; norm <"$T/$a.a.out" >"$T/$a.a.outn"
  norm <"$T/$a.p.err" >"$T/$a.p.errn"; norm <"$T/$a.a.err" >"$T/$a.a.errn"
  if [ "$prc" = "$arc" ] && diff -q "$T/$a.p.outn" "$T/$a.a.outn" >/dev/null 2>&1 && diff -q "$T/$a.p.errn" "$T/$a.a.errn" >/dev/null 2>&1; then
    printf '%s\tSAME\trc=%s\tPHP[%s]\n' "$a" "$prc" "$(tr '\n' ' ' <"$T/$a.p.outn")" >>"$OUT"; same=$((same+1))
  else
    printf '%s\tDIFF\tPHPrc=%s AOTrc=%s\tP[%s]|PE[%s] A[%s]|AE[%s]\n' "$a" "$prc" "$arc" \
      "$(tr '\n' ' ' <"$T/$a.p.outn")" "$(tr '\n' ' ' <"$T/$a.p.errn")" \
      "$(tr '\n' ' ' <"$T/$a.a.outn")" "$(tr '\n' ' ' <"$T/$a.a.errn")" >>"$OUT"; diff=$((diff+1))
  fi
  rm -f "$T/aot_compile_$a"
else
  printf '%s\tCOMPILE_FAIL\t-\t%s\n' "$a" "$(grep -m1 'error:' "$T/$a.c.log" | cut -c1-160)" >>"$OUT"; cfail=$((cfail+1))
fi

# s1 敏感度臂：必须看见泄漏（Δ>0），否则量具失效 ⇒ 红
narms=$((narms+1)); a=s1
if timeout 120 "$AOT" --compile --output="$T/aot_compile_$a" "$T/$a.php" >"$T/$a.c.log" 2>&1 && [ -s "$T/aot_compile_$a" ]; then
  ZIGPHP_ALLOC_STATS=1 timeout 60 "$T/aot_compile_$a" 1000 "$T" >"$T/$a.1.out" 2>"$T/$a.1.err"; rc1=$?
  ZIGPHP_ALLOC_STATS=1 timeout 60 "$T/aot_compile_$a" 3000 "$T" >"$T/$a.2.out" 2>"$T/$a.2.err"; rc2=$?
  lo1=$(sfield "$T/$a.1.err" live_bytes); lo2=$(sfield "$T/$a.2.err" live_bytes)
  la1=$(sfield "$T/$a.1.err" live_allocs); la2=$(sfield "$T/$a.2.err" live_allocs)
  if [ "$rc1" = "0" ] && [ "$rc2" = "0" ] && [ -n "$lo1" ] && [ "$lo2" -gt "$lo1" ] && [ "$la2" -gt "$la1" ]; then
    printf '%s\tSAME\tSENS lb=%s/%s la=%s/%s\n' "$a" "$lo1" "$lo2" "$la1" "$la2" >>"$OUT"; same=$((same+1))
  else
    printf '%s\tDIFF\tGAUGE_BLIND rc=%s/%s lb=%s/%s la=%s/%s\n' "$a" "$rc1" "$rc2" "$lo1" "$lo2" "$la1" "$la2" >>"$OUT"; diff=$((diff+1))
  fi
  rm -f "$T/aot_compile_$a"
else
  printf '%s\tCOMPILE_FAIL\t-\t%s\n' "$a" "$(grep -m1 'error:' "$T/$a.c.log" | cut -c1-160)" >>"$OUT"; cfail=$((cfail+1))
fi

echo -e "C328RES_DONE\tarms=$narms\tsame=$same\tdiff=$diff\tcompile_fail=$cfail\tELAPSED=$(( $(date +%s) - START ))s"
