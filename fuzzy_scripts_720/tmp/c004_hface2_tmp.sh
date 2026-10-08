#!/bin/bash
# REF-004 H 触发面定价（第二步）：逐枚语料脚本编译并跑调用点分类器，实测 `&null_val` 回落支的运行时可达面。
# 分类器：c004_hface_analyze_tmp.py（只读生成码，零源码改动）
cd /Users/wangjianjun/products/parser || exit 1
BIN="zig-out/bin/php-interpreter"
PASS_DIR="fuzzy_scripts_720/pass"
AN="fuzzy_scripts_720/tmp/c004_hface_analyze_tmp.py"
OUT="fuzzy_scripts_720/tmp/c004_hface2_tmp.tsv"
ERR="/tmp/c004_hface2.err"
start=$(date +%s)

{ echo "# started=$(date '+%F %T')"
  md5 -q "$BIN" | sed 's/^/# php_interpreter_md5=/'
  md5 -q src/aot/native_linker.zig | sed 's/^/# native_linker_md5=/'
  md5 -q "$AN" | sed 's/^/# analyzer_md5=/'
} > "$OUT"

for name in f042_array_functions_full f044_json_deepops_merge_diff \
            f057_workflow_engine_rollback f085_geo_rtree_knn_geocoder \
            f102_memory_gc_marksweep_refcount_gen f105_db_index_btree_hash_queryplan \
            f177_graph_traversal_dfs_bfs; do
  t0=$(date +%s)
  f="$PASS_DIR/$name.php"
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info "$f" 2>"$ERR" >/dev/null
  rc=$?
  d=$(awk '/preserved/ {print $NF; exit}' "$ERR")
  if [ $rc -ne 0 ] || [ -z "$d" ] || [ ! -f "$d/main.zig" ]; then
    printf "===== %s =====\nFAIL rc=%s\n" "$name" "$rc" >> "$OUT"
    [ -n "$d" ] && rm -rf "$d"
    rm -f "$PASS_DIR/aot_compile_${name}"
    continue
  fi
  printf "===== %s (compile %ss) =====\n" "$name" "$(( $(date +%s) - t0 ))" >> "$OUT"
  python3 "$AN" "$d/main.zig" >> "$OUT" 2>&1
  rm -rf "$d"
  rm -f "$PASS_DIR/aot_compile_${name}"
done
echo "ELAPSED=$(( $(date +%s) - start ))s" >> "$OUT"
echo "HFACE2_DONE" >> "$OUT"
