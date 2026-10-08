#!/usr/bin/env bash
# AOT-REF-004 §7.2 永久 harness（禁删）：uasort / uksort / array_map / array_filter 引用形参实测面
#
# 口径：
#   1) 一次编译（冻结二进制 ./zig-out/bin/php-interpreter，默认 --compile --no-debug-info）
#   2) 逐形运行 15 形（崩溃形杀进程 ⇒ 必须逐次运行，禁止串行管道）
#   3) 同形跑系统 PHP 真值（/opt/homebrew/bin/php），stdout 与 stderr 分离取数
#   4) ⚠ 判据：三枚排序派发器均走 quickSort（runtime_lib_template.zig :22521/:22545/:22566）
#      ⇒ 不稳定 ⇒ 「输出 == 真值」不可直接判等值，必须与同输入 *_zero* 控制形比对
#
# 用法：bash fuzzy_scripts_720/tmp/c004_uasort_face_tmp.sh
# 产物：fuzzy_scripts_720/tmp/c004_uasort_face_tmp.tsv（编译产物写 /tmp 并在末尾按显式路径删除）
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
P=fuzzy_scripts_720/tmp/t004_uasort_uksort_ref_tmp.php
BIN=/tmp/aot_compile_t004_uasort_uksort_ref_tmp
TSV=fuzzy_scripts_720/tmp/c004_uasort_face_tmp.tsv
SHAPES="ctrl_usort usort_read uasort_read uasort_write uksort_read map_write filter_write usort_read3 uasort_read3 uksort_read3 usort_zero3 uasort_zero3 uksort_zero3 uasort_zero uksort_zero usort_reflog usort_byvalog uasort_reflog uasort_byvalog uksort_reflog uksort_byvalog"

T0=$(date +%s)
{
  echo "# REF-004 §7.2 uasort/uksort/map/filter 引用形参实测面"
  echo "# generated=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "# php_interpreter_md5=$(md5 -q ./zig-out/bin/php-interpreter)"
  echo "# native_linker_md5=$(md5 -q src/aot/native_linker.zig)"
  echo "# runtime_lib_template_md5=$(md5 -q src/aot/runtime_lib_template.zig)"
  echo "# probe_md5=$(md5 -q "$P")"
  echo "# columns: shape|side|rc|stdout_sha|warn_lines|first_err"
} > "$TSV"

timeout 600 ./zig-out/bin/php-interpreter --compile --no-debug-info --output="$BIN" "$P" >/tmp/c004_compile.log 2>&1
crc=$?
echo "# compile rc=$crc bin=$BIN size=$(stat -f%z "$BIN" 2>/dev/null || echo 0)" >> "$TSV"

for s in $SHAPES; do
  # PHP 真值
  po=$(timeout 10 /opt/homebrew/bin/php "$P" "$s" 2>/tmp/c004_php_err.log); prc=$?
  pw=$(grep -c 'Warning' /tmp/c004_php_err.log); pw=${pw:-0}
  pe=$(grep -m1 -E 'Warning|Error|Fatal' /tmp/c004_php_err.log 2>/dev/null | cut -c1-90 | tr '\t' ' ')
  printf "%-14s|php|%s|%s|%s|%s\n" "$s" "$prc" "$(echo "$po" | tr '\n' '~')" "$pw" "$pe" >> "$TSV"
  # AOT 实测
  ao=$(timeout 10 "$BIN" "$s" 2>/tmp/c004_aot_err.log); arc=$?
  aw=$(grep -c 'Warning' /tmp/c004_aot_err.log); aw=${aw:-0}
  ae=$(grep -m1 -E 'Warning|Error|Fatal' /tmp/c004_aot_err.log 2>/dev/null | cut -c1-90 | tr '\t' ' ')
  printf "%-14s|aot|%s|%s|%s|%s\n" "$s" "$arc" "$(echo "$ao" | tr '\n' '~')" "$aw" "$ae" >> "$TSV"
done

echo "ELAPSED=$(($(date +%s) - T0))s" | tee -a "$TSV"
rm -f "$BIN" /tmp/c004_compile.log /tmp/c004_php_err.log /tmp/c004_aot_err.log
echo "C004_FACE_DONE shapes=$(echo $SHAPES | wc -w | tr -d ' ')"
