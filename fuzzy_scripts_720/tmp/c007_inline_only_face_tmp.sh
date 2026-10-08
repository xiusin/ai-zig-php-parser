#!/bin/bash
# CODEGEN-007 单变量归因臂（任务 #94 第三阶段，只读、零源码改动）
#
# 背景：release-fast 面 sweep（c007_releasefast_face_tmp.sh，68 语料）测得
#       gen_drift=67/67、pass=48、diff=17、runtime_fail=2、compile_fail=0；
#       默认档对照臂（c007_rf_control_tmp.sh）19/19 全绿，且两臂 zig `-O` 恒为 ReleaseFast
#       （>200KB 尺寸规则 native_linker.zig:32445-32446，实测最小语料 f040 = 278,560 bytes）
#       ⇒ 红面完全由 IR pass 集造成。但 `--optimize=release-fast` 一次翻动 **13 枚** PassConfig 字段
#       （optimizer.zig:175-199 vs :203-222），CODEGEN-007 的 `function_inlining` 只是其中一枚。
# 本臂用纯 CLI 通道（main.zig:311 --aot-enable-pass + compiler.zig:662-666 applyPassOverrides）
#   在默认档之上**只翻 function_inlining + inline_threshold=50** ⇒ 把内联单变量从 13 变量里摘出来。
# 判据三件事：
#   (1) 输出面 vs PHP 真值（官方 harness 同款归一化）
#   (2) main.zig md5 vs 冻结默认档基线          ⇒ 内联单变量的生成码漂移面
#   (3) main.zig md5 vs release-fast 臂 md5     ⇒ 逐脚本判断「13 变量的漂移是否只由内联贡献」
# 产物：/tmp/c007_inline_only_work，TSV/HDR 同名；禁止删 .php 源。
cd /Users/wangjianjun/products/parser || exit 1

PASS_DIR="fuzzy_scripts_720/pass"
BASELINE="fuzzy_scripts_720/baseline_main_zig_md5.tsv"
RF_TSV="fuzzy_scripts_720/tmp/c007_rf_face_tmp.tsv"
BIN="zig-out/bin/php-interpreter"
PHP_BIN="/opt/homebrew/bin/php"
WORK="/tmp/c007_inline_only_work"
TSV="fuzzy_scripts_720/tmp/c007_inline_only_face_tmp.tsv"
rm -rf "$WORK"
mkdir -p "$WORK"

{
  echo "# c007 inline-only attribution arm $(date '+%Y-%m-%d %H:%M:%S')"
  echo "bin_md5=$(md5 -q "$BIN")"
  echo "native_linker=$(md5 -q src/aot/native_linker.zig)/$(wc -l < src/aot/native_linker.zig | tr -d ' ')"
  echo "optimizer=$(md5 -q src/aot/optimizer.zig)"
  echo "flags=--compile --no-debug-info --aot-enable-pass=inline --aot-inline-threshold=50"
} > "fuzzy_scripts_720/tmp/c007_inline_only_face_tmp_hdr.txt"
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

should_exclude() {
    if grep -qE '\b(yield\b|Fiber|fiber\(|coroutine|swoole_|eval\s*\()' "$1" 2>/dev/null; then
        return 0
    fi
    return 1
}

total=0; g_same=0; g_drift=0; same_as_rf=0; diff_as_rf=0
r_pass=0; r_diff=0; r_rfail=0; r_cfail=0; r_skip=0

for f in "$PASS_DIR"/*.php; do
  name=$(basename "$f" .php)
  total=$((total + 1))
  if should_exclude "$f"; then
    printf "%s|SKIP|EXCLUDED||||||harness-excluded\n" "$name" >> "$TSV"
    r_skip=$((r_skip + 1)); continue
  fi
  php_out=$(timeout 10 "$PHP_BIN" "$f" 2>&1)
  if [ $? -ne 0 ]; then
    printf "%s|SKIP|EXCLUDED||||||php_exit!=0\n" "$name" >> "$TSV"
    r_skip=$((r_skip + 1)); continue
  fi

  c_err="$WORK/${name}.cerr"
  out_bin="$WORK/aot_compile_${name}"
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info \
    --aot-enable-pass=inline --aot-inline-threshold=50 --output="$out_bin" "$f" >"$c_err" 2>&1
  c_rc=$?
  tdir=$(awk '/preserved/ {print $NF; exit}' "$c_err")
  oflag=$(grep -o -m1 -- '-O[A-Za-z]*' "$c_err")

  if [ $c_rc -ne 0 ]; then
    reason=$(grep -m1 "error:" "$c_err" | head -c 220 | tr '\n' ' ')
    printf "%s|COMPILE_FAIL|COMPILE_FAIL|||%s|%s|-||%s\n" "$name" "$oflag" "-" "$reason" >> "$TSV"
    r_cfail=$((r_cfail + 1))
    [ -n "$tdir" ] && rm -rf "$tdir"; rm -f "$out_bin"; continue
  fi

  c_md5=""; c_lines=""
  if [ -n "$tdir" ] && [ -f "$tdir/main.zig" ]; then
    c_md5=$(md5 -q "$tdir/main.zig")
    c_lines=$(wc -l < "$tdir/main.zig" | tr -d ' ')
  fi
  [ -n "$tdir" ] && rm -rf "$tdir"

  exp=$(awk -F'\t' -v n="$name" '$1==n {print $3}' "$BASELINE")
  if [ -z "$c_md5" ]; then vs_base="NOTEMP"
  elif [ "$c_md5" = "$exp" ]; then vs_base="BASE_SAME"; g_same=$((g_same + 1))
  else vs_base="BASE_DRIFT"; g_drift=$((g_drift + 1)); fi

  rf_md5=$(awk -F'|' -v n="$name" '$1==n {print $5}' "$RF_TSV")
  if [ -z "$rf_md5" ] || [ -z "$c_md5" ]; then vs_rf="NA"
  elif [ "$c_md5" = "$rf_md5" ]; then vs_rf="RF_SAME"; same_as_rf=$((same_as_rf + 1))
  else vs_rf="RF_DIFF"; diff_as_rf=$((diff_as_rf + 1)); fi

  aot_out=$(timeout 10 "$out_bin" 2>&1)
  a_rc=$?
  rm -f "$out_bin"
  if [ $a_rc -ne 0 ]; then
    det=$(echo "$aot_out" | tail -3 | tr '\n' ' ' | head -c 200)
    printf "%s|%s|RUNTIME_FAIL|%s|%s|%s|%s|-|exit=%d %s\n" "$name" "$vs_base" "$c_lines" "$c_md5" "$vs_rf" "$oflag" "$a_rc" "$det" >> "$TSV"
    r_rfail=$((r_rfail + 1)); continue
  fi
  np=$(normalize_output <<< "$php_out")
  na=$(normalize_output <<< "$aot_out")
  if [ "$np" = "$na" ]; then
    printf "%s|%s|PASS|%s|%s|%s|%s||\n" "$name" "$vs_base" "$c_lines" "$c_md5" "$vs_rf" "$oflag" >> "$TSV"
    r_pass=$((r_pass + 1))
  else
    det=$(diff <(printf "%s\n" "$np") <(printf "%s\n" "$na") | head -8 | tr '\n' '~' | head -c 300)
    printf "%s|%s|DIFF|%s|%s|%s|%s|%s\n" "$name" "$vs_base" "$c_lines" "$c_md5" "$vs_rf" "$oflag" "$det" >> "$TSV"
    r_diff=$((r_diff + 1))
  fi
done
echo "INLINE_ONLY_DONE total=$total base_same=$g_same base_drift=$g_drift rf_same=$same_as_rf rf_diff=$diff_as_rf pass=$r_pass diff=$r_diff runtime_fail=$r_rfail compile_fail=$r_cfail skip=$r_skip" | tee -a "$TSV"
