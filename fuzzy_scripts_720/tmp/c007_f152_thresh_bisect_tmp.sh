#!/bin/bash
# AOT-CODEGEN-007：f152 的**最小内联引爆阈值**二分实测（任务 #104，只读、零插桩、**零源码改动**、非门控）
#
# 起因（承 OPT-001 §5.9.7 遗留 ①，读数见该节）：
#   #94 的 inline-only 臂 = 默认档 + `--aot-enable-pass=inline --aot-inline-threshold=50`
#     （c007_inline_only_face_tmp.sh:34/:78）⇒ 单变量点亮 f152 `RUNTIME_FAIL`（exit=139）
#   #102 的 release-safe 臂（`inline_threshold=15`，optimizer.zig:154，但同批还开 licm/iter3/gvn/copy_prop）
#     ⇒ f152 **PASS**（opt001_releasesafe_face_tmp.tsv 实测）⇒ 引爆条件在 (15, 50]
#   ⇒ 本臂族（**只有** inline 旗标 + 阈值，不掺 licm/迭代/gvn）内的**最小引爆阈值** = 未钉的实数。
#   该轴 CLI 可达（main.zig:317 --aot-inline-threshold）⇒ 无需改 optimizer.zig ⇒ 非门控。
#
# 判据：与官方 harness 同款 `normalize_output`，PHP 真值 = /opt/homebrew/bin/php
#   ⇒ PASS / DIFF / RUNTIME_FAIL / COMPILE_FAIL；另记 main.zig 行数+md5（看阈值与产物尺寸是否单调）。
# 产物命名遵守 §三-8：$WORK/aot_compile_f152_closure_arrow_higher_order.t<T>，与 .php 源不同名。
# 用法：bash fuzzy_scripts_720/tmp/c007_f152_thresh_bisect_tmp.sh "15 20 25 30 35 40 45 50"

set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

BIN="zig-out/bin/php-interpreter"
PHP_BIN="/opt/homebrew/bin/php"
SRC="fuzzy_scripts_720/pass/f152_closure_arrow_higher_order.php"
NAME="f152_closure_arrow_higher_order"
WORK="/tmp/c007_f152_thresh_work"
TSV="fuzzy_scripts_720/tmp/c007_f152_thresh_bisect_tmp.tsv"
THRESHOLDS="${1:-15 20 25 30 35 40 45 50}"

[ -x "$BIN" ] || { echo "FATAL: 冻结二进制缺失 $BIN"; exit 1; }
[ -f "$SRC" ] || { echo "FATAL: 探针源缺失 $SRC"; exit 1; }

rm -rf "$WORK"; mkdir -p "$WORK"
START_TS=$(date +%s)

{
  echo "# c007 f152 inline-threshold bisect $(date '+%Y-%m-%d %H:%M:%S')"
  echo "bin_md5=$(md5 -q "$BIN")"
  echo "arm=--compile --no-debug-info --aot-enable-pass=inline --aot-inline-threshold=<T>"
  echo "thresholds=$THRESHOLDS"
  echo "header_cols=shape|T|gen_vs_base|verdict|lines|md5|Oflag|detail"
} > "${TSV%.tsv}_hdr.txt"

normalize_output() {
    sed -E \
        -e 's/[[:space:]]*$//' \
        -e 's/^[[:space:]]*//' \
        -e 's/0x[0-9a-fA-F]{8,}/0xADDR/g' \
        -e 's|/tmp/aot_[a-z0-9_]+|TMPDIR|g' \
        -e 's/microtime\(true\)/MICROTIME/g' \
        -e 's/[0-9]+\.[0-9]{12,}/FLOAT/g'
}

np=$(timeout 10 "$PHP_BIN" "$SRC" 2>&1 | normalize_output)
if [ -z "$np" ]; then echo "FATAL: PHP 真值为空"; exit 1; fi
> "$TSV"

BASE_LINES=""; BASE_MD5=""
run_t() {   # $1 = threshold（0 = 默认档不加旗标，作 base 行与尺寸对照）
  local t="$1"
  local c_err="$WORK/t${t}.cerr" out_bin="$WORK/aot_compile_${NAME}.t${t}"
  local tdir oflag g_stat md5v linesv

  if [ "$t" = "0" ]; then
    ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info \
      --output="$out_bin" "$SRC" >"$c_err" 2>&1
  else
    ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info \
      --aot-enable-pass=inline --aot-inline-threshold="$t" \
      --output="$out_bin" "$SRC" >"$c_err" 2>&1
  fi
  local c_rc=$?
  tdir=$(awk '/preserved/ {print $NF; exit}' "$c_err")
  oflag=$(grep -o -m1 -- '-O[A-Za-z]*' "$c_err")

  if [ $c_rc -ne 0 ] || [ ! -f "$out_bin" ]; then
    printf "%s|%s|COMPILE_FAIL|COMPILE_FAIL|||%s|rc=%s %s\n" \
      "$NAME" "$t" "$oflag" "$c_rc" "$(grep -m1 'error:' "$c_err" | head -c 200 | tr '\n' ' ')" >> "$TSV"
    [ -n "$tdir" ] && rm -rf "$tdir"; rm -f "$out_bin"
    return
  fi

  if [ -z "$tdir" ] || [ ! -f "$tdir/main.zig" ]; then
    g_stat="NOTEMP"; md5v=""; linesv=""
  else
    md5v=$(md5 -q "$tdir/main.zig")
    linesv=$(wc -l < "$tdir/main.zig" | tr -d ' ')
    if [ "$t" = "0" ]; then
      g_stat="BASE"
    elif [ "$md5v" = "$BASE_MD5" ] && [ "$linesv" = "$BASE_LINES" ]; then
      g_stat="BASE_SAME"
    else
      g_stat="BASE_DRIFT"
    fi
  fi
  [ -n "$tdir" ] && rm -rf "$tdir"
  if [ "$t" = "0" ]; then BASE_LINES="$linesv"; BASE_MD5="$md5v"; fi

  local aot_out a_rc na
  aot_out=$(timeout 10 "$out_bin" 2>&1); a_rc=$?
  rm -f "$out_bin"

  if [ $a_rc -ne 0 ]; then
    printf "%s|%s|%s|RUNTIME_FAIL|%s|%s|%s|exit=%s %s\n" \
      "$NAME" "$t" "$g_stat" "$linesv" "$md5v" "$oflag" "$a_rc" \
      "$(printf '%s' "$aot_out" | tail -3 | tr '\n' ' ' | head -c 200)" >> "$TSV"
    return
  fi
  na=$(printf '%s\n' "$aot_out" | normalize_output)
  if [ "$np" = "$na" ]; then
    printf "%s|%s|%s|PASS|%s|%s|%s|\n" "$NAME" "$t" "$g_stat" "$linesv" "$md5v" "$oflag" >> "$TSV"
  else
    printf "%s|%s|%s|DIFF|%s|%s|%s|%s\n" "$NAME" "$t" "$g_stat" "$linesv" "$md5v" "$oflag" \
      "$(diff <(printf '%s\n' "$np") <(printf '%s\n' "$na") | head -10 | tr '\n' '~' | head -c 400)" >> "$TSV"
  fi
}

run_t 0
for t in $THRESHOLDS; do run_t "$t"; done

awk -F'|' '$3!="COMPILE_FAIL"{print $2"|"$4"|"$5}' "$TSV" | tail -n +1
echo "THRESH_BISECT_DONE thresholds=$(($(echo $THRESHOLDS | wc -w)))" >> "$TSV"
echo "ELAPSED=$(( $(date +%s) - START_TS ))s" >> "$TSV"
cat "$TSV"
