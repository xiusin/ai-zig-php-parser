#!/bin/bash
# AOT-REF-002 R-1b 判据区分力实证：
#   同一批探针分别用「修复后模板（工作区 = b21cdfd）」与「修复前模板（b21cdfd^）」编译，
#   比较 pre/post 是否可分 ⇒ 判定探针能否作为 R-1b 的验收判据。
#   模板换回期间禁止任何其他 AOT 批次；结束必还原并用 md5 + git status 双重校验。
cd /Users/wangjianjun/products/parser || exit 1
TPL=src/aot/runtime_lib_template.zig
BIN=./zig-out/bin/php-interpreter
PHP=/opt/homebrew/bin/php
BACKUP=/tmp/rt_post_backup_$$.zig
PRE=/tmp/rt_pre_$$.zig
PROBES="
fuzzy_scripts_720/tmp/ref002_r1b_isolated_tmp.php
fuzzy_scripts_720/tmp/ref002_iso_e_byref_grow_then_write_tmp.php
fuzzy_scripts_720/tmp/ref002_iso_c_walk_ref_nogrow_tmp.php
fuzzy_scripts_720/tmp/ref_iter_slot_stale_probe_tmp.php
"

md5_before=$(md5 -q "$TPL")
cp "$TPL" "$BACKUP" || exit 1
git show b21cdfd^:"$TPL" > "$PRE" || exit 1
echo "MD5_BEFORE=$md5_before"
echo "PRE_MD5=$(md5 -q "$PRE")"

restore() {
  cp "$BACKUP" "$TPL"
  rm -f "$BACKUP" "$PRE"
  echo "RESTORED_MD5=$(md5 -q "$TPL")"
  git status --porcelain -- "$TPL" | sed 's/^/GITDIRTY|/'
  echo "RESTORE_DONE"
}
trap restore EXIT

run_set() {
  local tag=$1
  for p in $PROBES; do
    name=$(basename "$p" .php)
    out=/tmp/aot_compile_${tag}_${name}
    timeout 300 "$BIN" --compile --no-debug-info --output="$out" "$p" 2>/tmp/aotc_${tag}_${name}.err >/dev/null
    rc_c=$?
    if [ $rc_c -ne 0 ]; then
      echo "${tag}|COMPILE_FAIL|${name}|rc=${rc_c}"
      tail -2 /tmp/aotc_${tag}_${name}.err | sed "s/^/${tag}|  /"
      continue
    fi
    timeout 10 "$out" > /tmp/aot_${tag}_${name}.out 2>/tmp/aot_${tag}_${name}.err
    rc_r=$?
    timeout 10 "$PHP" "$p" > /tmp/php_${name}.out 2>/dev/null
    if cmp -s /tmp/aot_${tag}_${name}.out /tmp/php_${name}.out; then
      verdict=SAME_AS_PHP
    else
      verdict=DIFF_FROM_PHP
    fi
    echo "${tag}|${verdict}|${name}|rc=${rc_r}"
    sed 's/^/    /' /tmp/aot_${tag}_${name}.out | sed "s/^/${tag}  /"
    rm -f "$out"
  done
}

echo "=== POST（工作区模板 = b21cdfd 修复后） ==="
run_set post
cp "$PRE" "$TPL" || exit 1
echo "SWITCH_TO_PRE_MD5=$(md5 -q "$TPL")"
echo "=== PRE（b21cdfd^ 修复前） ==="
run_set pre
echo "SWAP_DONE"
