#!/bin/bash
# CODEGEN-007 / PERF-001「release-fast 可达维扣除臂」（任务 #95，只读、非门控、零源码改动）
#
# 背景：release-fast 与默认档 releaseSmall 的 PassConfig 差 13 枚字段，但**只有 4 枚可由 CLI 扣除**
#   （src/main.zig:305-333 → compiler.zig:614 applyPassOverrides）：
#     --aot-disable-pass=inline / typespec / licm + --aot-max-iterations=1 + --aot-inline-threshold=5
#   不可达的 8 枚：copy_propagation / max_instructions_per_function / scalar_replacement / gvn /
#     advanced_sccp / slp_vectorization / polyhedral_optimization / loop_vectorization（改源码才能动 ⇒ 门控）。
#
# 本臂 = release-fast 之上扣掉全部可达差异 ⇒ 与默认档的**唯一**剩余差集为那 8 枚不可达字段。两判据：
#   (1) 生成码面 GEN_SAME / GEN_DRIFT（对比冻结默认档基线行）
#       ⇒ 若全语料 GEN_SAME，则 8 枚不可达字段在语料上**发射中性**，A 臂 67/67 漂移 100% 归因可达 4 维。
#   (2) 输出面 PASS / DIFF / RUNTIME_FAIL / COMPILE_FAIL（对 /opt/homebrew/bin/php 真值，官方 harness 同款归一化）
#       ⇒ 与 c007_rf_face_tmp.tsv 的 19 枚红形 join：转绿者 = 可达维造成；仍红者 = **不可归因下界**（须改 optimizer.zig 才能继续二分）。
# 已知标定：单形冒烟 f040 在本臂下 main.zig == 冻结基线（278560 B / 3c9aad34…），而 A 臂为 GEN_DRIFT（5595 行 / 4766decf…）。
# 产物：/tmp/c007_ko_work（临时，收尾删）；本脚本与同名 TSV/HDR 为永久取证资产，禁止删除任何 .php 源。
cd /Users/wangjianjun/products/parser || exit 1

PASS_DIR="fuzzy_scripts_720/pass"
BASELINE="fuzzy_scripts_720/baseline_main_zig_md5.tsv"
BIN="zig-out/bin/php-interpreter"
PHP_BIN="/opt/homebrew/bin/php"
WORK="/tmp/c007_ko_work"
TSV="fuzzy_scripts_720/tmp/c007_rf_knockout_tmp.tsv"
HDR="fuzzy_scripts_720/tmp/c007_rf_knockout_tmp_hdr.txt"
FLAGS=(--compile --no-debug-info --optimize=release-fast
       --aot-disable-pass=inline --aot-disable-pass=typespec --aot-disable-pass=licm
       --aot-max-iterations=1 --aot-inline-threshold=5)
rm -rf "$WORK"
mkdir -p "$WORK"

{
  echo "# c007 release-fast reachable-knockout arm $(date '+%Y-%m-%d %H:%M:%S')"
  echo "bin_md5=$(md5 -q "$BIN")"
  echo "native_linker=$(md5 -q src/aot/native_linker.zig)/$(wc -l < src/aot/native_linker.zig | tr -d ' ')"
  echo "ir_generator=$(md5 -q src/aot/ir_generator.zig)"
  echo "optimizer=$(md5 -q src/aot/optimizer.zig)"
  echo "flags=${FLAGS[*]}"
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
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" "${FLAGS[@]}" --output="$out_bin" "$f" >"$c_err" 2>&1
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
    ko_md5=""; ko_lines=""
  else
    ko_md5=$(md5 -q "$tdir/main.zig")
    ko_lines=$(wc -l < "$tdir/main.zig" | tr -d ' ')
    exp=$(awk -F'\t' -v n="$name" '$1==n {print $3}' "$BASELINE")
    exp_lines=$(awk -F'\t' -v n="$name" '$1==n {print $2}' "$BASELINE")
    if [ -z "$exp" ]; then
      g_stat="NOROW"; g_norow=$((g_norow + 1))
    elif [ "$ko_md5" = "$exp" ] && [ "$ko_lines" = "$exp_lines" ]; then
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
    printf "%s|%s|RUNTIME_FAIL|%s|%s|%s|exit=%d %s\n" "$name" "$g_stat" "$ko_lines" "$ko_md5" "$oflag" "$a_rc" "$detail" >> "$TSV"
    r_rfail=$((r_rfail + 1))
    continue
  fi

  np=$(normalize_output <<< "$php_out")
  na=$(normalize_output <<< "$aot_out")
  if [ "$np" = "$na" ]; then
    printf "%s|%s|PASS|%s|%s|%s|\n" "$name" "$g_stat" "$ko_lines" "$ko_md5" "$oflag" >> "$TSV"
    r_pass=$((r_pass + 1))
  else
    detail=$(diff <(printf "%s\n" "$np") <(printf "%s\n" "$na") | head -10 | tr '\n' '~' | head -c 400)
    printf "%s|%s|DIFF|%s|%s|%s|%s\n" "$name" "$g_stat" "$ko_lines" "$ko_md5" "$oflag" "$detail" >> "$TSV"
    r_diff=$((r_diff + 1))
  fi
done

SUMMARY="KNOCKOUT_DONE total=$total gen_same=$g_same gen_drift=$g_drift gen_norow=$g_norow notemp=$g_notemp pass=$r_pass diff=$r_diff runtime_fail=$r_rfail compile_fail=$r_cfail skip=$r_skip"
echo "$SUMMARY" | tee -a "$TSV"
