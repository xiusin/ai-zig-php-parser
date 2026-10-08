#!/bin/bash
# AOT-OPT-001 §5.9：release-safe 中间档语料面 sweep（任务 #102，只读、非门控、零源码改动）
#
# 目的（两问，一次跑完）：
#   Q1 把 PERF-001 §7 里「release_safe 也落在引爆区」的**实测推论**换成实测（68 语料、输出面 + 生成码面）。
#   Q2 零插桩给 3 枚不可 CLI 关闭的字段定价：双臂逐字节等值 ⇒ 该 3 枚在本语料**惰性**；不等值 ⇒ 差集即其面。
#
# 实文链（已逐枚核对，锚点 = optimizer.zig 252234ef/6877、compiler.zig af4901da、main.zig 当代次）：
#   compiler.zig:240 fromString("release-safe") → :250 .release_safe => .basic
#   optimizer.zig:61 .basic => PassConfig.releaseSafe()
#   releaseSafe() :147-171 vs releaseSmall() :203-222（默认档）的差集 = 7 枚字段：
#     [CLI 可达 4 枚] function_inlining false:209→true:153（--aot-enable-pass=inline，main.zig:137）
#                     inline_threshold 5:210→15:154（--aot-inline-threshold，main.zig:317）
#                     licm false:213→true:157（--aot-enable-pass=licm，main.zig:149）
#                     max_iterations 1:219→3:163（--aot-max-iterations，main.zig:329）
#     [CLI 不可达 3 枚] copy_propagation false:220→true（releaseSafe 未列 ⇒ 取结构体默认 :77）
#                       gvn false（默认 :115）→true:166
#                       max_instructions_per_function 30000:221→50000（未列 ⇒ 默认 :106）
#   ⚠ PassOverrides（compiler.zig:197-212）无 copy_propagation/gvn/max_instructions 字段 ⇒ 这 3 枚确实不可达。
#   ⚠ optimizer.zig:6007 另有同名 LLVMPassConfig.releaseSafe()，与本 IR 管线无关，禁止误引。
#
# 臂：
#   A = --compile --no-debug-info --optimize=release-safe
#   B = --compile --no-debug-info --aot-enable-pass=inline --aot-inline-threshold=15
#                  --aot-enable-pass=licm  --aot-max-iterations=3      （默认档 + 4 枚可达字段）
# 每脚本双判据（与 c007_releasefast_face_tmp.sh 同口径，便于与 #94 的 release-fast 读数直接相减）：
#   (1) 生成码面：main.zig md5+行数 vs 冻结默认档基线 ⇒ GEN_SAME / GEN_DRIFT / NOROW / NOTEMP；
#                 另记 A-vs-B 逐字节等值 ⇒ AB_SAME / AB_DIFF
#   (2) 输出面  ：产物运行输出 vs /opt/homebrew/bin/php 真值（官方 harness 同款归一化）
#                 ⇒ PASS / DIFF / RUNTIME_FAIL / COMPILE_FAIL / SKIP
# 产物：/tmp/opt001_rs_work（临时，收尾删）、fuzzy_scripts_720/tmp/opt001_releasesafe_face_tmp.tsv、_hdr.txt
# 禁止删除任何 .php 源；本脚本自身为永久取证 harness。
cd /Users/wangjianjun/products/parser || exit 1

PASS_DIR="fuzzy_scripts_720/pass"
BASELINE="fuzzy_scripts_720/baseline_main_zig_md5.tsv"
BIN="zig-out/bin/php-interpreter"
PHP_BIN="/opt/homebrew/bin/php"
WORK="/tmp/opt001_rs_work"
TSV="fuzzy_scripts_720/tmp/opt001_releasesafe_face_tmp.tsv"
HDR="fuzzy_scripts_720/tmp/opt001_releasesafe_face_tmp_hdr.txt"
rm -rf "$WORK"
mkdir -p "$WORK"

START_TS=$(date +%s)

{
  echo "# opt001 release-safe 双臂面扫 $(date '+%Y-%m-%d %H:%M:%S')"
  echo "bin_md5=$(md5 -q "$BIN")"
  echo "optimizer=$(md5 -q src/aot/optimizer.zig)/$(wc -l < src/aot/optimizer.zig | tr -d ' ')"
  echo "compiler=$(md5 -q src/aot/compiler.zig)"
  echo "ir_generator=$(md5 -q src/aot/ir_generator.zig)"
  echo "native_linker=$(md5 -q src/aot/native_linker.zig)/$(wc -l < src/aot/native_linker.zig | tr -d ' ')"
  echo "armA=--compile --no-debug-info --optimize=release-safe"
  echo "armB=--compile --no-debug-info --aot-enable-pass=inline --aot-inline-threshold=15 --aot-enable-pass=licm --aot-max-iterations=3"
  echo "header_cols=shape|arm|gen_vs_baseline|verdict|lines|md5|Oflag|detail"
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

# run_arm <name> <phpfile> <arm> <php_normalized> ; 设 LAST_MD5/LAST_LINES/GLOBALS
LAST_MD5=""; LAST_LINES=""
run_arm() {
  local name="$1" f="$2" arm="$3" np="$4"
  local c_err="$WORK/${name}.${arm}.cerr"
  local out_bin="$WORK/aot_compile_${name}.${arm}"
  local g_stat rs_md5 rs_lines oflag tdir

  if [ "$arm" = "A" ]; then
    ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info --optimize=release-safe \
      --output="$out_bin" "$f" >"$c_err" 2>&1
  else
    ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info \
      --aot-enable-pass=inline --aot-inline-threshold=15 --aot-enable-pass=licm --aot-max-iterations=3 \
      --output="$out_bin" "$f" >"$c_err" 2>&1
  fi
  local c_rc=$?
  tdir=$(awk '/preserved/ {print $NF; exit}' "$c_err")
  oflag=$(grep -o -m1 -- '-O[A-Za-z]*' "$c_err")

  if [ $c_rc -ne 0 ] || [ ! -f "$out_bin" ]; then
    local reason
    reason=$(grep -m1 "error:" "$c_err" | head -c 200 | tr '\n' ' ')
    printf "%s|%s|COMPILE_FAIL|COMPILE_FAIL|||%s|%s\n" "$name" "$arm" "$oflag" "rc=$c_rc $reason" >> "$TSV"
    [ -n "$tdir" ] && rm -rf "$tdir"
    rm -f "$out_bin"
    LAST_MD5=""; LAST_LINES=""; CUR_GEN="COMPILE_FAIL"; CUR_VERD="COMPILE_FAIL"
    return
  fi

  if [ -z "$tdir" ] || [ ! -f "$tdir/main.zig" ]; then
    g_stat="NOTEMP"; rs_md5=""; rs_lines=""
  else
    rs_md5=$(md5 -q "$tdir/main.zig")
    rs_lines=$(wc -l < "$tdir/main.zig" | tr -d ' ')
    local exp exp_lines
    exp=$(awk -F'\t' -v n="$name" '$1==n {print $3}' "$BASELINE")
    exp_lines=$(awk -F'\t' -v n="$name" '$1==n {print $2}' "$BASELINE")
    if [ -z "$exp" ]; then
      g_stat="NOROW"
    elif [ "$rs_md5" = "$exp" ] && [ "$rs_lines" = "$exp_lines" ]; then
      g_stat="GEN_SAME"
    else
      g_stat="GEN_DRIFT"
    fi
  fi
  [ -n "$tdir" ] && rm -rf "$tdir"

  local aot_out a_rc
  aot_out=$(timeout 10 "$out_bin" 2>&1); a_rc=$?
  rm -f "$out_bin"

  LAST_MD5="$rs_md5"; LAST_LINES="$rs_lines"; CUR_GEN="$g_stat"
  if [ $a_rc -ne 0 ]; then
    local detail
    detail=$(echo "$aot_out" | tail -3 | tr '\n' ' ' | head -c 200)
    printf "%s|%s|%s|RUNTIME_FAIL|%s|%s|%s|exit=%d %s\n" \
      "$name" "$arm" "$g_stat" "$rs_lines" "$rs_md5" "$oflag" "$a_rc" "$detail" >> "$TSV"
    CUR_VERD="RUNTIME_FAIL"
    return
  fi
  local na
  na=$(normalize_output <<< "$aot_out")
  if [ "$np" = "$na" ]; then
    printf "%s|%s|%s|PASS|%s|%s|%s|\n" "$name" "$arm" "$g_stat" "$rs_lines" "$rs_md5" "$oflag" >> "$TSV"
    CUR_VERD="PASS"
  else
    local detail
    detail=$(diff <(printf "%s\n" "$np") <(printf "%s\n" "$na") | head -10 | tr '\n' '~' | head -c 400)
    printf "%s|%s|%s|DIFF|%s|%s|%s|%s\n" "$name" "$arm" "$g_stat" "$rs_lines" "$rs_md5" "$oflag" "$detail" >> "$TSV"
    CUR_VERD="DIFF"
  fi
}

CUR_GEN=""; CUR_VERD=""
ab_same=0; ab_diff=0; ab_na=0
cntA_pass=0; cntA_diff=0; cntA_rfail=0; cntA_cfail=0
cntB_pass=0; cntB_diff=0; cntB_rfail=0; cntB_cfail=0
gA_same=0; gA_drift=0; gB_same=0; gB_drift=0
total=0; skipped=0

for f in "$PASS_DIR"/*.php; do
  name=$(basename "$f" .php)
  total=$((total + 1))

  if should_exclude "$f"; then
    printf "%s|SKIP|EXCLUDED|SKIP||||harness-excluded\n" "$name" >> "$TSV"
    skipped=$((skipped + 1)); ab_na=$((ab_na + 1))
    continue
  fi
  php_out=$(timeout 10 "$PHP_BIN" "$f" 2>&1); php_rc=$?
  if [ $php_rc -ne 0 ]; then
    printf "%s|SKIP|EXCLUDED|SKIP||||php_exit=%d\n" "$name" "$php_rc" >> "$TSV"
    skipped=$((skipped + 1)); ab_na=$((ab_na + 1))
    continue
  fi
  np=$(normalize_output <<< "$php_out")

  run_arm "$name" "$f" "A" "$np"
  a_md5="$LAST_MD5"; a_gen="$CUR_GEN"; a_verd="$CUR_VERD"
  case "$a_gen" in GEN_SAME) gA_same=$((gA_same + 1));; GEN_DRIFT) gA_drift=$((gA_drift + 1));; esac
  case "$a_verd" in PASS) cntA_pass=$((cntA_pass + 1));; DIFF) cntA_diff=$((cntA_diff + 1));;
                   RUNTIME_FAIL) cntA_rfail=$((cntA_rfail + 1));; COMPILE_FAIL) cntA_cfail=$((cntA_cfail + 1));; esac

  run_arm "$name" "$f" "B" "$np"
  b_md5="$LAST_MD5"; b_gen="$CUR_GEN"; b_verd="$CUR_VERD"
  case "$b_gen" in GEN_SAME) gB_same=$((gB_same + 1));; GEN_DRIFT) gB_drift=$((gB_drift + 1));; esac
  case "$b_verd" in PASS) cntB_pass=$((cntB_pass + 1));; DIFF) cntB_diff=$((cntB_diff + 1));;
                   RUNTIME_FAIL) cntB_rfail=$((cntB_rfail + 1));; COMPILE_FAIL) cntB_cfail=$((cntB_cfail + 1));; esac

  if [ -z "$a_md5" ] || [ -z "$b_md5" ]; then
    ab_na=$((ab_na + 1))
    printf "%s|AB|(no_temp)|AB_NA||%s|%s|armA_md5=%s armB_md5=%s\n" "$name" "" "" "$a_md5" "$b_md5" >> "$TSV"
  elif [ "$a_md5" = "$b_md5" ]; then
    ab_same=$((ab_same + 1))
    printf "%s|AB|SAME|AB_SAME|%s|%s||\n" "$name" "$a_gen" "$a_md5" >> "$TSV"
  else
    ab_diff=$((ab_diff + 1))
    printf "%s|AB|%s_vs_%s|AB_DIFF|%s|%s||A=%s B=%s verdA=%s verdB=%s\n" \
      "$name" "$a_verd" "$b_verd" "$a_gen" "$a_md5" "$a_md5" "$b_md5" "$a_verd" "$b_verd" >> "$TSV"
  fi
done

ELAPSED=$(( $(date +%s) - START_TS ))
{
  echo "SUMMARY_A|armA|gen_same=$gA_same|gen_drift=$gA_drift|pass=$cntA_pass|diff=$cntA_diff|runtime_fail=$cntA_rfail|compile_fail=$cntA_cfail||"
  echo "SUMMARY_B|armB|gen_same=$gB_same|gen_drift=$gB_drift|pass=$cntB_pass|diff=$cntB_diff|runtime_fail=$cntB_rfail|compile_fail=$cntB_cfail||"
  echo "SUMMARY_AB|ab_same=$ab_same|ab_diff=$ab_diff|ab_na=$ab_na|total=$total|skip=$skipped|||"
  echo "ELAPSED=${ELAPSED}s"
} | tee -a "$TSV"
