#!/usr/bin/env bash
# 永久侧门 C343：循环 + if/elseif/else 链式嵌套（R-320：while 侧 w1/w3 闭环）
#   缺陷①（w1）：`while { if(奇){…} elseif(偶){ if(%4==0) continue; $z+=100; } }`
#     —— 嵌套 if 本体被丢弃、其 else 链被当无条件延续（PHP 306 / AOT 606）。
#   缺陷②（w3）：同族另形 `elseif { if(a){x} else {y} }` 编译失败
#     （[AST-DIRECT-FAIL] unprocessed blocks: if_then_*/if_else_*）。
#   修法：while 生成器 elseif 段的嵌套 cond_br 先交 generateNestedContinueChain
#     （then/else 两臂都沿单后继 .br 链折返循环头 ⇒ 链式发射，各自 continue 收尾），失败再走原 spill/范围行走。
#   判据：stdout+stderr+rc 与 PHP 8.5.8 逐字节一致（norm 折叠路径/行号并丢弃栈帧）。
#   臂：w1 continue+后续语句 / w2 语句后 continue / w3 嵌套 if-else / w4 首臂嵌套 continue /
#       d1 do-while 同形（对照）/ f1 foreach elseif+else（对照）/ f2 foreach 嵌套 continue（对照）
#   ★不在门内（仍开，见工单 §226）：f3（foreach 首臂 continue + elseif 嵌套 ⇒ 死循环）、
#     f4（foreach kv 嵌套 if 内 break 丢失）；修好后应作为 f3/f4 臂并入本门。
#   纪律：门臂一律 heredoc；AOT_BIN=/bin/false 自证必须全 COMPILE_FAIL；TSV 走 TSV_OUT；产物落临时目录并清理。
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 90
PHP=/opt/homebrew/bin/php
AOT="${AOT_BIN:-zig-out/bin/php-interpreter}"
T="$(mktemp -d /tmp/c343loop.XXXXXX)"
trap 'rm -rf "$T"' EXIT
OUT="${TSV_OUT:-fuzzy_scripts_720/tmp/c343_loop_elseif_tmp.tsv}"
norm() { sed -E -e 's/^[[:space:]]+//' -e 's~[A-Za-z0-9_./-]*/[A-Za-z0-9_.-]+\.php~@FILE@~g' -e 's/on line [0-9]+/on line @N@/g' -e '/^Stack trace:/,$d'; }

cat > "$T/w1.php" <<'PHP'
<?php
$i=0;$z=0;
while ($i<12) { $i++;
  if ($i%2==1) { $z+=1; }
  elseif ($i%2==0) { if ($i%4==0) { continue; } $z+=100; }
}
echo $z," ",$i,"\n";
PHP

cat > "$T/w2.php" <<'PHP'
<?php
$i=0;$z=0;
while ($i<12) { $i++;
  if ($i%2==1) { $z+=1; }
  elseif ($i%2==0) { $z+=1000; if ($i%4==0) { continue; } }
}
echo $z," ",$i,"\n";
PHP

cat > "$T/w3.php" <<'PHP'
<?php
$i=0;$z=0;
while ($i<12) { $i++;
  if ($i%3==0) { $z+=7; }
  elseif ($i%2==0) { if ($i%4==0) { $z+=2; } else { $z+=3; } }
  else { $z+=1; }
}
echo $z," ",$i,"\n";
PHP

cat > "$T/w4.php" <<'PHP'
<?php
$i=0;$z=0;
while ($i<12) { $i++;
  if ($i%2==1) { if ($i%3==0) { continue; } $z+=1; }
  elseif ($i%2==0) { $z+=10; }
}
echo $z," ",$i,"\n";
PHP

cat > "$T/d1.php" <<'PHP'
<?php
$i=0;$z=0;
do { $i++;
  if ($i%2==1) { $z+=1; }
  elseif ($i%2==0) { if ($i%4==0) { continue; } $z+=100; }
} while ($i<12);
echo $z," ",$i,"\n";
PHP

cat > "$T/f1.php" <<'PHP'
<?php
$z=0;
foreach ([1,2,3,4,5,6,7,8] as $i) {
  if ($i%2==1) { $z+=1; }
  elseif ($i%4==0) { echo "c4\n"; $z+=1000; }
  else { $z+=10; }
}
echo $z,"\n";
PHP

cat > "$T/f2.php" <<'PHP'
<?php
$z=0;
foreach ([1,2,3,4,5,6,7,8] as $i) {
  if ($i%3==0) { $z+=7; }
  elseif ($i%2==0) { if ($i%4==0) { continue; } $z+=100; }
  else { $z+=1; }
}
echo $z,"\n";
PHP

ALL_ARMS="w1 w2 w3 w4 d1 f1 f2"
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
echo "C343LOOP_DONE	arms=$narms	same=$same	diff=$diff	compile_fail=$cfail	timeout=$tfail	ELAPSED=$(( $(date +%s) - START ))s"
echo "TSV=$OUT"
