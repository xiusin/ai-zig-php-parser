#!/bin/bash
# AOT-OPT-001 §5.3 取证轮（任务 #96，只读、零源码改动、非门控）
#
# 目标：把 f016（LICM 单枚红的 7 枚之一，输出 `{"ServerA":8}` → `{"ServerA":1}`）的两档生成码做逐字 diff，
#       定位「被 LICM 搬动的语句」落在哪一类 PHP 表达式上，据读数裁决 H1/H3/H4（OPT-001 §5.2）。
#
# 双臂（唯一变量 = `--aot-enable-pass=licm`，其余 flags 与冻结基线同档）：
#   基线臂 = --compile --no-debug-info                ⇒ main.zig 应等于冻结基线（f016: 46782 行 / c8dc9660f4fe42f63af5d7ed2e8cd43f）
#   LICM臂 = --compile --no-debug-info --aot-enable-pass=licm
# 产物：/tmp/opt001_f016_work/{main_base.zig,main_licm.zig,f016_licm_diff.txt}
# 铁律：禁止删除任何 .php 源；aot_compile_* 产物与 KEEP_TEMP 临时目录收尾必须清空。
cd /Users/wangjianjun/products/parser || exit 1

SRC="fuzzy_scripts_720/pass/f016_hash_bloom_consistent.php"
BIN="zig-out/bin/php-interpreter"
BASELINE="fuzzy_scripts_720/baseline_main_zig_md5.tsv"
WORK="/tmp/opt001_f016_work"
rm -rf "$WORK"; mkdir -p "$WORK"

run_arm() {
  local tag="$1"; shift
  local cerr="$WORK/${tag}.cerr"
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 900 "$BIN" --compile --no-debug-info "$@" \
    --output="$WORK/aot_compile_f016_${tag}" "$SRC" >"$cerr" 2>&1
  local rc=$?
  local tdir
  tdir=$(awk '/preserved/ {print $NF; exit}' "$cerr")
  if [ $rc -ne 0 ]; then
    echo "ARM=$tag COMPILE_FAIL rc=$rc $(grep -m1 'error:' "$cerr" | head -c 200)"
    [ -n "$tdir" ] && rm -rf "$tdir"
    return 1
  fi
  if [ -z "$tdir" ] || [ ! -f "$tdir/main.zig" ]; then
    echo "ARM=$tag NOTEMP"
    return 1
  fi
  cp "$tdir/main.zig" "$WORK/main_${tag}.zig"
  echo "ARM=$tag lines=$(wc -l < "$WORK/main_${tag}.zig" | tr -d ' ') md5=$(md5 -q "$WORK/main_${tag}.zig") oflag=$(grep -o -m1 -- '-O[A-Za-z]*' "$cerr")"
  rm -rf "$tdir"
  rm -f "$WORK/aot_compile_f016_${tag}"
}

echo "# opt001 f016 dual-arm $(date '+%Y-%m-%d %H:%M:%S') bin=$(md5 -q "$BIN") optimizer=$(md5 -q src/aot/optimizer.zig)"
echo "baseline_row=$(awk -F'\t' '$1=="f016_hash_bloom_consistent" {print $2" "$3}' "$BASELINE")"

run_arm base
run_arm licm --aot-enable-pass=licm

if [ -f "$WORK/main_base.zig" ] && [ -f "$WORK/main_licm.zig" ]; then
  diff "$WORK/main_base.zig" "$WORK/main_licm.zig" > "$WORK/f016_licm_diff.txt" 2>&1
  echo "diff_hunks=$(grep -c '^[0-9]' "$WORK/f016_licm_diff.txt") diff_lines=$(wc -l < "$WORK/f016_licm_diff.txt" | tr -d ' ')"
  # 口径说明：diff 常规格式用 '< ' / '> ' 前缀，'^-'/'^+' 只会数到 c 型 hunk 的 '---' 分隔行（恒不等于删行数）
  echo "removed_lines=$(grep -c '^< ' "$WORK/f016_licm_diff.txt") added_lines=$(grep -c '^> ' "$WORK/f016_licm_diff.txt")"
  echo "net_lines=$(( $(wc -l < "$WORK/main_licm.zig") - $(wc -l < "$WORK/main_base.zig") ))"
fi

echo "DUALARM_DONE"
