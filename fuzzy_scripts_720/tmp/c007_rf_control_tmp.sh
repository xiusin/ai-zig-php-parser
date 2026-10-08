#!/bin/bash
# CODEGEN-007 release-fast 红形的默认档对照臂（任务 #94 第二阶段，只读、零源码改动）
#
# 目的：release-fast 面 sweep（c007_releasefast_face_tmp.sh）测得 19 枚红形（17 DIFF + 2 RUNTIME_FAIL）。
#   本脚本用**完全相同的归一化判据**在默认档（`--compile --no-debug-info`，不带 --optimize）复跑这 19 枚，
#   同时抓 zig build-exe 的 `-O` 旗标与 main.zig 字节数 ⇒
#   (1) 证明红-绿差由档造成，而非语料本底已红；
#   (2) 证明两臂 `-O` 相同（>200KB 尺寸规则把默认档也抬到 ReleaseFast）⇒ 漂移只归因 IR pass 集。
# 名单来源：fuzzy_scripts_720/tmp/c007_rf_face_tmp.tsv 中 DIFF/RUNTIME_FAIL 行。
cd /Users/wangjianjun/products/parser || exit 1

PASS_DIR="fuzzy_scripts_720/pass"
BIN="zig-out/bin/php-interpreter"
PHP_BIN="/opt/homebrew/bin/php"
WORK="/tmp/c007_rf_ctrl"
TSV="fuzzy_scripts_720/tmp/c007_rf_control_tmp.tsv"
rm -rf "$WORK"
mkdir -p "$WORK"
> "$TSV"

normalize_output() {
    sed -E \
        -e 's/[[:space:]]*$//' \
        -e 's/^[[:space:]]*//' \
        -e 's/0x[0-9a-fA-F]{8,}/0xADDR/g' \
        -e 's|/tmp/aot_[a-z0-9_]+|TMPDIR|g' \
        -e 's/microtime\(true\)/MICROTIME/g' \
        -e 's/[0-9]+\.[0-9]{12,}/FLOAT/g' \
        -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?/TIMESTAMP/g' \
        -e 's/in[[:space:]]+[^[:space:]:]+\.php:[0-9]+/in FILE:LINE/g' \
        | tr -s '\n' \
        | sed -E -e '/^$/d'
}

NAMES=$(awk -F'|' '$3=="DIFF" || $3=="RUNTIME_FAIL" {print $1}' fuzzy_scripts_720/tmp/c007_rf_face_tmp.tsv)
total=0; pass=0; dif=0; rf=0; cf=0
for name in $NAMES; do
  total=$((total + 1))
  f="$PASS_DIR/${name}.php"
  php_out=$(timeout 10 "$PHP_BIN" "$f" 2>&1)
  c_err="$WORK/${name}.cerr"
  out_bin="$WORK/aot_compile_${name}"
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info --output="$out_bin" "$f" >"$c_err" 2>&1
  c_rc=$?
  tdir=$(awk '/preserved/ {print $NF; exit}' "$c_err")
  oflag=$(grep -o -m1 -- '-O[A-Za-z]*' "$c_err")
  mb=""
  if [ -n "$tdir" ] && [ -f "$tdir/main.zig" ]; then mb=$(wc -c < "$tdir/main.zig" | tr -d ' '); fi
  [ -n "$tdir" ] && rm -rf "$tdir"
  if [ $c_rc -ne 0 ]; then
    printf "%s|COMPILE_FAIL|%s|%s|\n" "$name" "$oflag" "$mb" >> "$TSV"
    cf=$((cf + 1)); rm -f "$out_bin"; continue
  fi
  aot_out=$(timeout 10 "$out_bin" 2>&1)
  a_rc=$?
  rm -f "$out_bin"
  if [ $a_rc -ne 0 ]; then
    printf "%s|RUNTIME_FAIL|%s|%s|exit=%d\n" "$name" "$oflag" "$mb" "$a_rc" >> "$TSV"
    rf=$((rf + 1)); continue
  fi
  np=$(normalize_output <<< "$php_out")
  na=$(normalize_output <<< "$aot_out")
  if [ "$np" = "$na" ]; then
    printf "%s|PASS|%s|%s||\n" "$name" "$oflag" "$mb" >> "$TSV"
    pass=$((pass + 1))
  else
    d=$(diff <(printf "%s\n" "$np") <(printf "%s\n" "$na") | head -6 | tr '\n' '~' | head -c 240)
    printf "%s|DIFF|%s|%s|%s\n" "$name" "$oflag" "$mb" "$d" >> "$TSV"
    dif=$((dif + 1))
  fi
done
echo "CTRL_DONE total=$total pass=$pass diff=$dif runtime_fail=$rf compile_fail=$cf" | tee -a "$TSV"
