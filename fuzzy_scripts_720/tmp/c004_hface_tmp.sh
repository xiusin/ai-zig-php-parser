#!/bin/bash
# REF-004 H 路线触发面定价：绿色语料内 `&null_val` 回落支的发射面普查（只读生成码，零源码改动）。
# 判据一：回落支逐枚归属到「所在函数入口」⇒ 区分具名方法 vs 闭包/动态载体。
# 判据二：同脚本内 make_ref 的发射数量与样例 ⇒ 装填侧是否已在具名路径生效。
cd /Users/wangjianjun/products/parser || exit 1
BIN="zig-out/bin/php-interpreter"
PASS_DIR="fuzzy_scripts_720/pass"
OUT="fuzzy_scripts_720/tmp/c004_hface_tmp.tsv"
ERR="/tmp/c004_hface.err"

{ md5 -q "$BIN" | sed 's/^/# php_interpreter_md5=/'
  md5 -q src/aot/native_linker.zig | sed 's/^/# native_linker_md5=/'
  md5 -q src/aot/runtime_lib_template.zig | sed 's/^/# runtime_lib_template_md5=/'
  echo "# columns: name|lines|fallback_sites|make_ref_sites"
} > "$OUT"

for name in f042_array_functions_full f044_json_deepops_merge_diff \
            f057_workflow_engine_rollback f085_geo_rtree_knn_geocoder \
            f102_memory_gc_marksweep_refcount_gen f105_db_index_btree_hash_queryplan \
            f177_graph_traversal_dfs_bfs; do
  f="$PASS_DIR/$name.php"
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info "$f" 2>"$ERR" >/dev/null
  rc=$?
  d=$(awk '/preserved/ {print $NF; exit}' "$ERR")
  if [ $rc -ne 0 ] || [ -z "$d" ] || [ ! -f "$d/main.zig" ]; then
    printf "%-40s|COMPILE_OR_TEMP_FAIL rc=%s\n" "$name" "$rc" >> "$OUT"
    [ -n "$d" ] && rm -rf "$d"
    rm -f "$PASS_DIR/aot_compile_${name}"
    continue
  fi
  lines=$(wc -l < "$d/main.zig" | tr -d ' ')
  fb=$(grep -c 'else &null_val' "$d/main.zig")
  mkr=$(grep -c 'make_ref(' "$d/main.zig")
  printf "%-40s|lines=%-8s fallback=%-4s make_ref=%-4s\n" "$name" "$lines" "$fb" "$mkr" >> "$OUT"

  # 回落支归属：最近一个 fn 头 + 该回落行原文（判据一）
  awk '/^[a-zA-Z_ ]*fn /{ fn=$0 } /else &null_val/{ print "  FB @" NR " in [" fn "] : " $0 }' "$d/main.zig" >> "$OUT"

  # 装填侧样例：make_ref 发射点前 3 条（判据二）
  grep -n 'make_ref(' "$d/main.zig" | head -3 | sed 's|^|  MK |' >> "$OUT"

  rm -rf "$d"
  rm -f "$PASS_DIR/aot_compile_${name}"
done
echo "HFACE_DONE" >> "$OUT"
