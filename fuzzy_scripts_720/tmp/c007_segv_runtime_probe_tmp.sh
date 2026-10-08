#!/bin/bash
# AOT-CODEGEN-007 §7.5 留口收口（轮次 #111）：T=45/50 两臂 SIGSEGV 的**运行时侧**归因。
#
# 起因（承 §7.5「仍未取证（留口，禁写成已证）」）：#105/#108 已把崩点钉到**生成码级**（阈值阶梯 + 双臂 diff），
#   但「崩在哪一次解引用、坏值具体是什么」当时未钉 ⇒ 原记「需运行时侧另一轮」。
#
# 通道（全程非门控）：
#   1) 冻结二进制 $BIN 编译（默认档 + --aot-enable-pass=inline --aot-inline-threshold=<T>）+ ZIGPHP_AOT_KEEP_TEMP=1
#      ⇒ 取生成码 main.zig，逐字节对账 §3.7 阶梯表登记的 md5/行数（不等即停 ⇒ 防代次漂移）。
#   2) **同一份生成码**在 /tmp 副本上用 -ODebug 重建 ⇒ Zig 段错误处理器给出带行号的栈追踪
#      ⇒ 崩点从「推测」变「实测到行」。
#   3) 再对副本插 print 探针（只读位模式与指针整数值，isArray() 才解引用）⇒ 「具体坏值」也取到。
#   ⚠ 零源码改动：探针只写 /tmp 副本；src/** 与冻结二进制一律不动（本轮不跑 `zig build`）。
#
# 自证（三条，缺一即读数作废）：
#   ① 生成码 md5/行数 == §3.7 登记值（34=f4c41d87…/46376，45=1c59a293…/47101，50=ed742689…/47849）。
#   ② 控制臂 T=34（= 冻结基线生成码）同法 -ODebug 重建后**必须跑到底**（exit=0）⇒ 证明「Debug 重建本身」不制造崩溃。
#   ③ Debug 未插桩臂的输出**截断点**必须与 §3.7 登记的 ReleaseFast 症状同处（45=Function Composition 段、
#      50=Partial Application 段）⇒ 证明 Debug 崩的就是 ReleaseFast 那个崩。
#      ⚠ exit 码**必然不同**（ReleaseFast=139 SIGSEGV；Debug=134，Zig 的 segfault 处理器捕获后 abort）
#        ⇒ 禁止拿 exit 码当同一性判据（本轮把它只作留档列）。
#
# 产物命名遵守 §三-8（aot_compile_ 前缀，不与 .php 同名）。用法：bash fuzzy_scripts_720/tmp/c007_segv_runtime_probe_tmp.sh [T ...]

set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

BIN="zig-out/bin/php-interpreter"
SRC="fuzzy_scripts_720/pass/f152_closure_arrow_higher_order.php"
NAME="f152_closure_arrow_higher_order"
PROBE_PY="fuzzy_scripts_720/tmp/c007_segv_probe_tmp.py"
WORK="/tmp/c007_p111_work"
TSV="fuzzy_scripts_720/tmp/c007_segv_runtime_probe_tmp.tsv"
TARGETS="${*:-45 50}"

# §3.7 阶梯表登记的生成码指纹（对账用；不等 ⇒ 代次漂移，本轮读数无效）
fp_md5() { case "$1" in 34) echo "f4c41d87a3bfbb78c7ff42fff27c3d66";; 45) echo "1c59a2935865215911c8925ff933d1ae";; 50) echo "ed742689d9e44b7088c1bcdcbe340a01";; esac; }
fp_lines() { case "$1" in 34) echo "46376";; 45) echo "47101";; 50) echo "47849";; esac; }
# §3.7 登记的 ReleaseFast 截断点（自证 ③）
fp_cut() { case "$1" in 34) echo "=== f152 Done ===";; 45) echo "--- Function Composition ---";; 50) echo "--- Partial Application ---";; esac; }

[ -x "$BIN" ] || { echo "FATAL: 冻结二进制缺失 $BIN"; exit 1; }
[ -f "$SRC" ] || { echo "FATAL: 探针源缺失 $SRC"; exit 1; }
[ -f "$PROBE_PY" ] || { echo "FATAL: 探针生成器缺失 $PROBE_PY"; exit 1; }

echo "PRECHECK_orphan_zig_build_exe=$(ps -A -o command= | grep -c '[z]ig build-exe')"

rm -rf "$WORK"; mkdir -p "$WORK"
START_TS=$(date +%s)
: > "$TSV"
{
  echo "# c007 §7.5 SIGSEGV runtime-side attribution $(date '+%Y-%m-%d %H:%M:%S')"
  echo "bin_md5=$(md5 -q "$BIN")"
  echo "arm=--compile --no-debug-info --aot-enable-pass=inline --aot-inline-threshold=<T> ; rebuild -ODebug on the /tmp copy"
  echo "header_cols=T|kind|field|value"
} >> "${TSV%.tsv}_hdr.txt"

row() { printf "%s|%s|%s|%s\n" "$1" "$2" "$3" "$4" >> "$TSV"; }

gen_arm() {   # $1 = T（34 = 控制臂，默认档无旗标）
  local t="$1" c_err="$WORK/t${t}.cerr" out_bin="$WORK/aot_compile_${NAME}.t${t}" tdir td_md5 td_lines dir
  if [ "$t" = "34" ]; then
    ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info --output="$out_bin" "$SRC" >"$c_err" 2>&1
  else
    ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info \
      --aot-enable-pass=inline --aot-inline-threshold="$t" --output="$out_bin" "$SRC" >"$c_err" 2>&1
  fi
  [ -f "$out_bin" ] || { row "$t" gen "COMPILE_FAIL" "$(grep -m1 'error:' "$c_err" | head -c 160)"; return 1; }
  rm -f "$out_bin"

  tdir=$(awk '/preserved/ {print $NF; exit}' "$c_err")
  if [ -z "$tdir" ] || [ ! -f "$tdir/main.zig" ]; then row "$t" gen "NOTEMP" "-"; return 1; fi
  td_md5=$(md5 -q "$tdir/main.zig"); td_lines=$(wc -l < "$tdir/main.zig" | tr -d ' ')

  if [ "$td_md5" = "$(fp_md5 "$t")" ] && [ "$td_lines" = "$(fp_lines "$t")" ]; then
    row "$t" gen "FP_MATCH" "md5=$td_md5 lines=$td_lines"
  else
    row "$t" gen "FP_MISMATCH" "got=$td_md5/$td_lines expect=$(fp_md5 "$t")/$(fp_lines "$t")"
    rm -rf "$tdir"; return 1
  fi

  # KEEP_TEMP 目录整份搬到 /tmp 副本（cp -R 保符号链接），随后删仓库根产物
  dir="$WORK/t${t}"; mkdir -p "$dir"
  cp -R "$tdir/." "$dir/" || { row "$t" copy "CP_FAIL" "$dir"; rm -rf "$tdir"; return 1; }
  rm -rf "$tdir"
  row "$t" copy "copied_to" "$dir main.zig_md5=$(md5 -q "$dir/main.zig") links=$(find "$dir" -maxdepth 1 -type l | wc -l | tr -d ' ')"
}

dbg_build() {   # $1 = 副本目录 $2 = 入口文件名 $3 = 输出二进制路径
  local dir="$1" root="$2" bin="$3" log="$3.build.log"
  # 与真实产物同一链接环境：只把 -OReleaseFast 换成 -ODebug，并去掉三枚「去追踪」旗标
  ( cd "$dir" && timeout 900 zig build-exe "$root" -femit-bin="$bin" \
      -ODebug -target aarch64-macos -L/opt/homebrew/lib -L/usr/local/lib -lpcre2-8 -lc ) >"$log" 2>&1
}

run_dbg() {   # $1 = 二进制 $2 = T $3 = kind
  local bin="$1" t="$2" kind="$3" outf rc last fl
  outf="$WORK/${kind}.t${t}.out"
  timeout 20 "$bin" >"$outf" 2>&1; rc=$?
  row "$t" "$kind" "exit" "$rc"
  last=$(grep -v '^PROBE' "$outf" | grep -vE '^\s' | tail -1)
  row "$t" "$kind" "last_line" "$(printf '%s' "$last" | head -c 120)"
  if grep -qF -- "$(fp_cut "$t")" "$outf"; then
    row "$t" "$kind" "CUT_MATCH" "$(fp_cut "$t")"
  else
    row "$t" "$kind" "CUT_MISMATCH" "expected=$(fp_cut "$t")"
  fi
  row "$t" "$kind" "fault_msg" "$(grep -m1 -iE 'Segmentation fault|panic|error:' "$outf" | head -c 140)"
  row "$t" "$kind" "trace" "$(grep -E 'main\.zig:[0-9]+:[0-9]+:|runtime_lib\.zig:[0-9]+:[0-9]+:' "$outf" \
        | sed -E 's|.*/([^/]+\.[0-9a-z]*):|\1:|; s| 0x[0-9a-f]+ in | in |' | tr '\n' '~' | head -c 400)"
  # 栈追踪里第一个 main.zig 帧 = PHP 级崩点语句（runtime_lib 帧不算，它是运行时内部）
  fl=$(grep -m1 -oE 'main\.zig:[0-9]+:[0-9]+:' "$outf" | cut -d: -f2)
  [ -n "$fl" ] && row "$t" "$kind" "fault_main_line" "$fl"
  return $rc
}

for t in $TARGETS 34; do
  gen_arm "$t" || { echo "ARM_t${t}_ABORT"; continue; }

  if ! dbg_build "$WORK/t${t}" main.zig "$WORK/aot_compile_${NAME}.t${t}_dbg"; then
    row "$t" dbg "BUILD_FAIL" "$(tail -3 "$WORK/aot_compile_${NAME}.t${t}_dbg.build.log" | tr '\n' ' ' | head -c 300)"
    continue
  fi
  run_dbg "$WORK/aot_compile_${NAME}.t${t}_dbg" "$t" "dbg"
  [ "$t" = "34" ] && continue

  fl=$(awk -F'|' -v t="$t" '$1==t && $2=="dbg" && $3=="fault_main_line"{print $4; exit}' "$TSV")
  [ -n "$fl" ] || { row "$t" probe "NO_FAULT_LINE" "-"; continue; }

  python3 "$PROBE_PY" --main "$WORK/t${t}/main.zig" --line "$fl" --out "$WORK/t${t}/main_probe.zig" \
    > "$WORK/probe_gen.t${t}.txt" 2>&1
  row "$t" probe "GEN" "$(head -1 "$WORK/probe_gen.t${t}.txt" | head -c 300)"
  if dbg_build "$WORK/t${t}" main_probe.zig "$WORK/aot_compile_${NAME}.t${t}_prb"; then
    timeout 20 "$WORK/aot_compile_${NAME}.t${t}_prb" > "$WORK/probe.t${t}.out" 2>&1
    row "$t" probe "exit" "$?"
    row "$t" probe "PROBE_COUNT" "$(grep -c '^PROBE' "$WORK/probe.t${t}.out")"
    grep '^PROBE' "$WORK/probe.t${t}.out" > "$WORK/probe.t${t}.lines"
    while IFS= read -r l; do row "$t" probe "PROBE" "$(printf '%s' "$l" | head -c 300)"; done < "$WORK/probe.t${t}.lines"
  else
    row "$t" probe "BUILD_FAIL" "$(tail -5 "$WORK/aot_compile_${NAME}.t${t}_prb.build.log" | tr '\n' ' ' | head -c 400)"
  fi
done

echo "=== TSV ==="
cat "$TSV"
echo "SEGV_PROBE_DONE targets=\"$TARGETS +34\" ELAPSED=$(( $(date +%s) - START_TS ))s"
