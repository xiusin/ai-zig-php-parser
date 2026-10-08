#!/bin/bash
# CODEGEN-007 release-fast 档语料面 sweep（任务 #94，只读、非门控、零源码改动）
#
# 唯一差异变量：--optimize=release-fast（其余 flags 与登记的默认档基线 `--compile --no-debug-info` 全等）
#   ⇒ 该变量在默认档之上只翻转 IR pass 集合（optimizer.zig getPassConfig 的 function_inlining），
#     而 -O 链接档位对 >200KB 的 main.zig 本已被 native_linker.zig 的尺寸规则抬到 ReleaseFast。
# 每脚本双判据：
#   (1) 生成码面：release-fast 的 main.zig md5+行数 对比冻结默认档基线行 ⇒ GEN_SAME / GEN_DRIFT / NOROW / NOTEMP
#   (2) 输出面  ：release-fast 产物运行输出 对比 /opt/homebrew/bin/php 真值（官方 harness 同款归一化）
#               ⇒ PASS / DIFF / RUNTIME_FAIL / COMPILE_FAIL
# 产物：/tmp/c007_rf_work（临时）、fuzzy_scripts_720/tmp/c007_rf_face_tmp.tsv、_hdr.txt
# 禁止删除任何 .php 源；本脚本自身为永久取证 harness。
cd /Users/wangjianjun/products/parser || exit 1

PASS_DIR="fuzzy_scripts_720/pass"
BASELINE="fuzzy_scripts_720/baseline_main_zig_md5.tsv"
BIN="zig-out/bin/php-interpreter"
PHP_BIN="/opt/homebrew/bin/php"
WORK="/tmp/c007_rf_work"
TSV="fuzzy_scripts_720/tmp/c007_rf_face_tmp.tsv"
HDR="fuzzy_scripts_720/tmp/c007_rf_face_tmp_hdr.txt"
rm -rf "$WORK"
mkdir -p "$WORK"

{
  echo "# c007 release-fast face sweep $(date '+%Y-%m-%d %H:%M:%S')"
  echo "bin_md5=$(md5 -q "$BIN")"
  echo "native_linker=$(md5 -q src/aot/native_linker.zig)/$(wc -l < src/aot/native_linker.zig | tr -d ' ')"
  echo "ir_generator=$(md5 -q src/aot/ir_generator.zig)"
  echo "optimizer=$(md5 -q src/aot/optimizer.zig)"
  echo "flags=--compile --no-debug-info --optimize=release-fast"
} > "$HDR"

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

total=0; g_same=0; g_drift=0; g_norow=0; g_notemp=0
r_pass=0; r_diff=0; r_rfail=0; r_cfail=0; r_skip=0

for f in "$PASS_DIR"/*.php; do
  name=$(basename "$f" .php)
  total=$((total + 1))
  if should_exclude "$f"; then
    printf "%s|SKIP|EXCLUDED||||harness-excluded\n" "$name" >> "$TSV"
    r_skip=$((r_skip + 1))
    continue
  fi

  php_out=$(timeout 10 "$PHP_BIN" "$f" 2>&1)
  php_rc=$?
  if [ $php_rc -ne 0 ]; then
    printf "%s|SKIP|EXCLUDED||||php_exit=%d\n" "$name" "$php_rc" >> "$TSV"
    r_skip=$((r_skip + 1))
    continue
  fi

  c_err="$WORK/${name}.cerr"
  out_bin="$WORK/aot_compile_${name}"
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info --optimize=release-fast \
    --output="$out_bin" "$f" >"$c_err" 2>&1
  c_rc=$?
  tdir=$(awk '/preserved/ {print $NF; exit}' "$c_err")
  oflag=$(grep -o -m1 -- '-O[A-Za-z]*' "$c_err")

  if [ $c_rc -ne 0 ]; then
    reason=$(grep -m1 "error:" "$c_err" | head -c 220 | tr '\n' ' ')
    printf "%s|COMPILE_FAIL|COMPILE_FAIL|||%s|%s\n" "$name" "$oflag" "$reason" >> "$TSV"
    r_cfail=$((r_cfail + 1))
    [ -n "$tdir" ] && rm -rf "$tdir"
    rm -f "$out_bin"
    continue
  fi

  if [ -z "$tdir" ] || [ ! -f "$tdir/main.zig" ]; then
    g_notemp=$((g_notemp + 1))
    g_stat="NOTEMP"
    rf_md5=""; rf_lines=""
  else
    rf_md5=$(md5 -q "$tdir/main.zig")
    rf_lines=$(wc -l < "$tdir/main.zig" | tr -d ' ')
    exp=$(awk -F'\t' -v n="$name" '$1==n {print $3}' "$BASELINE")
    exp_lines=$(awk -F'\t' -v n="$name" '$1==n {print $2}' "$BASELINE")
    if [ -z "$exp" ]; then
      g_stat="NOROW"; g_norow=$((g_norow + 1))
    elif [ "$rf_md5" = "$exp" ] && [ "$rf_lines" = "$exp_lines" ]; then
      g_stat="GEN_SAME"; g_same=$((g_same + 1))
    else
      g_stat="GEN_DRIFT"; g_drift=$((g_drift + 1))
    fi
  fi
  [ -n "$tdir" ] && rm -rf "$tdir"

  aot_out=$(timeout 10 "$out_bin" 2>&1)
  a_rc=$?
  rm -f "$out_bin"

  if [ $a_rc -ne 0 ]; then
    detail=$(echo "$aot_out" | tail -3 | tr '\n' ' ' | head -c 200)
    printf "%s|%s|RUNTIME_FAIL|%s|%s|%s|exit=%d %s\n" "$name" "$g_stat" "$rf_lines" "$rf_md5" "$oflag" "$a_rc" "$detail" >> "$TSV"
    r_rfail=$((r_rfail + 1))
    continue
  fi

  np=$(normalize_output <<< "$php_out")
  na=$(normalize_output <<< "$aot_out")
  if [ "$np" = "$na" ]; then
    printf "%s|%s|PASS|%s|%s|%s|\n" "$name" "$g_stat" "$rf_lines" "$rf_md5" "$oflag" >> "$TSV"
    r_pass=$((r_pass + 1))
  else
    detail=$(diff <(printf "%s\n" "$np") <(printf "%s\n" "$na") | head -10 | tr '\n' '~' | head -c 400)
    printf "%s|%s|DIFF|%s|%s|%s|%s\n" "$name" "$g_stat" "$rf_lines" "$rf_md5" "$oflag" "$detail" >> "$TSV"
    r_diff=$((r_diff + 1))
  fi
done

SUMMARY="RFACE_DONE total=$total gen_same=$g_same gen_drift=$g_drift gen_norow=$g_norow notemp=$g_notemp pass=$r_pass diff=$r_diff runtime_fail=$r_rfail compile_fail=$r_cfail skip=$r_skip"
echo "$SUMMARY" | tee -a "$TSV"
