#!/usr/bin/env bash
# 任务 #114（2026-10-07）永久 harness：f004 语料 SKIP 的覆盖回收 + readonly 强制归属实测
# 通道 = 单文件 $argv[1] 选形 ⇒ 一次编译、三形运行（fatal 形进程被杀，逐形编译在此族不可行）
# 坑（固化，勿删）：
#   1) 编译必须用官方回归同档命令（--compile --output），产物名 aot_compile_* 且不得落在源目录
#   2) 三形共用一次编译 ⇒ PHP 侧与 AOT 侧都要逐形跑，禁止只跑 valid 就宣布等值
#   3) fatal 形两侧 exit=255 ⇒ 等值判据只能取「stdout 归一化后逐字节」，禁拿 exit 码当同一性判据
#   4) 错误消息里的声明类 vs 实例类差异属消息文本面，不被 §七-5（栈行号豁免）覆盖，必须单列
set -u
cd "$(dirname "$0")/../.." || exit 1
P="fuzzy_scripts_720/tmp"
BIN="zig-out/bin/php-interpreter"
PROBE="$P/f004_ro_unser_tmp.php"
OUT="$P/f004_ro_unser_tmp.tsv"
PHP="/opt/homebrew/bin/php"
T=$(mktemp -d /tmp/f004_ro_unser.XXXXXX)
trap 'rm -rf "$T"' EXIT

START=$(date +%s)
{ echo "# compiler_md5=$(md5 -q "$BIN")"
  echo "# native_linker_md5=$(md5 -q src/aot/native_linker.zig)"
  echo "# runtime_lib_template_md5=$(md5 -q src/aot/runtime_lib_template.zig)"
  echo "# probe_md5=$(md5 -q "$PROBE")"
  echo "# columns: shape|php|aot|verdict|msg_class_diff"
} > "$OUT"

timeout 120 "$BIN" --compile --output="$T/aot_compile_f004_ro_unser_tmp" "$PROBE" >"$T/compile.log" 2>&1
CRC=$?
echo "COMPILE rc=$CRC" >> "$OUT"
if [ "$CRC" -ne 0 ]; then
  tail -8 "$T/compile.log" >> "$OUT"
  echo "ROUNSER_DONE compile_failed shapes=0" >> "$OUT"
  cat "$OUT"
  exit 1
fi

norm() { sed -E -e 's/[[:space:]]*$//' -e 's|/[^[:space:]:]*\.php:[0-9]+|FILE:LINE|g' -e 's| in [^ ]*\.php on line [0-9]+| in FILE:LINE|g' -e '/^Stack trace:/,$d' -e '/^$/d'; }

COUNT=0
for s in valid ro_ok fatal priv_read priv_write prot_read type_inherit type_self dyn_ro class_const val_self val_dyn; do
  COUNT=$((COUNT + 1))
  timeout 10 "$PHP" "$PROBE" "$s" >"$T/$s.php.out" 2>&1; prc=$?
  timeout 10 "$T/aot_compile_f004_ro_unser_tmp" "$s" >"$T/$s.aot.out" 2>&1; arc=$?
  php_n=$(norm < "$T/$s.php.out" | tr '\n' '|')
  aot_n=$(norm < "$T/$s.aot.out" | tr '\n' '|')
  if [ "$php_n" = "$aot_n" ]; then v=SAME; else v=DIFF; fi
  ph_class=$(grep -oE '(Cannot modify readonly property|Cannot assign [a-z]+ to property) [^ ]+' "$T/$s.php.out" | head -1 | sed -E 's/^.*property //')
  ao_class=$(grep -oE '(Cannot modify readonly property|Cannot assign [a-z]+ to property) [^ ]+' "$T/$s.aot.out" | head -1 | sed -E 's/^.*property //')
  if [ -z "$ph_class$ao_class" ]; then md=NA; elif [ "$ph_class" = "$ao_class" ]; then md=EQUAL; else md="php=$ph_class|aot=$ao_class"; fi
  echo "$s|php_rc=$prc|aot_rc=$arc|$v|msg_class_diff=$md|$php_n||aot=$aot_n" >> "$OUT"
done

echo "ELAPSED=$(($(date +%s) - START))s" >> "$OUT"
SAME_N=$(grep -c '|SAME|' "$OUT")
DIFF_N=$(grep -c '|DIFF|' "$OUT")
echo "ROUNSER_DONE shapes=$COUNT same=$SAME_N diff=$DIFF_N" >> "$OUT"
cat "$OUT"
