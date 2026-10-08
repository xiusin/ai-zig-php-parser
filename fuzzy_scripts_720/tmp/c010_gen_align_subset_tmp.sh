#!/usr/bin/env bash
# 方案② 代次对齐取证（N1）：用「当前二进制 zig-out/bin/php-interpreter（5beb1591…，10-07 22:28:25）」
# 对生成码 main.zig 逐形取 md5，与影子门已注册的 new 侧 md5（b416d3fb… 代次，10-07 20:46）逐字节对照。
#   选形依据（实测 grep，非推测）：暂存 ir_generator 改动面 = §8 #5 namespace + §8 #6 unset 名称匹配
#     ⇒ 语料 namespace 命中 1 形（f124）、unset( 命中 13 形、goto/iterable/__NAMESPACE__ 命中 0 形；
#     另加 3 枚无敏感语法的控制绿形，证明对照通道本身不产生假阳。
#   纪律：仓库根执行；全命令带 timeout；产物名 aot_compile_*；KEEP_TEMP 目录与产物抽取后即删；
#         编译失败判据取「产物不可执行」不取 rc（记忆规则 21）；.php 源零删除。
set -u
cd "$(dirname "$0")/../.." || exit 1
BIN=zig-out/bin/php-interpreter
REF=fuzzy_scripts_720/tmp/c010_shadow_main_md5_tmp.tsv
OUT=fuzzy_scripts_720/tmp/c010_gen_align_subset_tmp.tsv
: > "$OUT"
T=$(mktemp -d /tmp/c010align.XXXXXX)
START=$(date +%s)

for b in \
  f010_oop_singleton_registry_di f016_hash_bloom_consistent f037_adapter_unified_cache \
  f056_crdt_gcounter_lww_orset f080_db_transaction_mvcc_deadlock \
  f102_memory_gc_marksweep_refcount_gen f104_game_engine_ecs_collision_render \
  f110_os_sim_process_memory_filesystem f113_distributed_consistenthash_vectorclock_quorum \
  f119_logging_structured_levels_rotation f124_container_orchestrator_pod_service_autoscale \
  f160_virtual_fs_path_traversal f164_plugin_hook_system \
  f174_command_undo_redo_macro f177_graph_traversal_dfs_bfs f179_visitor_composite_ast
do
  src="fuzzy_scripts_720/pass/${b}.php"
  [ -f "$src" ] || { printf '%s\tcurrent\tMISSING_SRC\n' "$b" >>"$OUT"; continue; }
  log="$T/${b}.log"
  timeout 120 env ZIGPHP_AOT_KEEP_TEMP=1 "$BIN" --compile --no-debug-info \
    --output="$T/aot_compile_align_${b}" "$src" >"$log" 2>&1
  bin_path="$T/aot_compile_align_${b}"
  if [ -x "$bin_path" ]; then
    tdir=$(grep -o 'temp dir preserved: [^ ]*' "$log" | head -1 | sed 's/.*preserved: //')
    if [ -n "${tdir:-}" ] && [ -f "$tdir/main.zig" ]; then
      md5r=$(md5 -q "$tdir/main.zig")
    else
      md5r="NO_MAINDIR"
    fi
    [ -n "${tdir:-}" ] && rm -rf "$tdir"
  else
    md5r="NOT_EXECUTABLE"
  fi
  printf '%s\tcurrent\t%s\n' "$b" "$md5r" >>"$OUT"
  rm -f "$bin_path" "$log"
done
rm -rf "$T"
END=$(date +%s)

awk -F'\t' -v el=$((END-START)) '
  NR==FNR { if ($2=="new") ref[$1]=$3; next }
  { got[$1]=$3 }
  END {
    same=0; diff=0; noref=0
    for (b in got) {
      if (!(b in ref)) { noref++; printf "NOREF\t%s\t%s\n", b, got[b]; continue }
      if (ref[b]==got[b]) { same++; st="SAME" } else { diff++; st="GEN_DRIFT" }
      printf "%s\t%s\treg=%s\tcur=%s\n", st, b, ref[b], got[b]
    }
    printf "C010_ALIGN_DONE shapes=%d same=%d diff=%d noref=%d ELAPSED=%ds\n",
      length(got), same, diff, noref, el
  }' "$REF" "$OUT" | tee -a "$OUT"
