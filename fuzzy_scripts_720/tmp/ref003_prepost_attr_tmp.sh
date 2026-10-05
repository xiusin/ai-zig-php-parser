#!/bin/bash
# AOT-REF-003 归因实证：同一批崩溃/语义探针分别用「修复后模板（工作区 = b21cdfd）」与
# 「修复前模板（b21cdfd^）」编译运行 ⇒ 判定 SIGSEGV 与 break 丢失是否早于 REF-002 R-1a/R-1b 就存在。
# 结束必还原模板并用 md5 + git status 双重校验。
cd /Users/wangjianjun/products/parser || exit 1
TPL=src/aot/runtime_lib_template.zig
BIN=./zig-out/bin/php-interpreter
BACKUP=/tmp/rt_post_backup_$$.zig
PRE=/tmp/rt_pre_$$.zig
PROBES="
fuzzy_scripts_720/tmp/ref003_crash_min_tmp.php
fuzzy_scripts_720/tmp/ref003_crash_v1_keyonly_tmp.php
fuzzy_scripts_720/tmp/ref003_crash_attr_tmp.php
fuzzy_scripts_720/tmp/ref003_liveset_bisect_tmp.php
"

md5_before=$(md5 -q "$TPL")
cp "$TPL" "$BACKUP" || exit 1
git show b21cdfd^:"$TPL" > "$PRE" || exit 1
echo "MD5_BEFORE=$md5_before PRE_MD5=$(md5 -q "$PRE")"

restore() {
  cp "$BACKUP" "$TPL"
  rm -f "$BACKUP" "$PRE"
  echo "RESTORED_MD5=$(md5 -q "$TPL")"
  git status --porcelain -- "$TPL" | sed 's/^/GITDIRTY|/'
  echo "RESTORE_DONE"
}
trap restore EXIT

for p in $PROBES; do
  name=$(basename "$p" .php)
  out=/tmp/aot_compile_pre_${name}
  timeout 300 "$BIN" --compile --no-debug-info --output="$out" "$p" 2>/tmp/aotc_pre_${name}.err >/dev/null
  rc_c=$?
  if [ $rc_c -ne 0 ]; then
    echo "pre|COMPILE_FAIL|${name}|rc=${rc_c}"
    continue
  fi
  timeout 10 "$out" > /tmp/aot_pre_${name}.out 2>/dev/null
  rc_r=$?
  echo "pre|${name}|run_rc=${rc_r}"
  sed 's/^/  pre  /' /tmp/aot_pre_${name}.out
  rm -f "$out"
done
echo "ATTR_PRE_DONE"
