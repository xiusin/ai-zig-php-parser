#!/bin/bash
# AOT-OPT-001 §5.2 R2 因果判别臂（任务 #98，只读、零源码改动、非门控）
#
# 动机：`cfg_cleanup` 本身有 CLI 开关 ⇒ R2「trampoline 删块 + then==else 折条件」可因果判别，不必改码。
#   通道实读：src/main.zig:165-168（名 "cfg-cleanup" / "cfg"）→ compiler.zig:673（applyPassOverrides）
#             → optimizer.zig:736（if (self.config.cfg_cleanup) 门）
# 唯一变量（相对已登记的 A 臂）：追加 --aot-disable-pass=cfg-cleanup
#   控制组 = fuzzy_scripts_720/tmp/c007_rf_face_tmp.tsv（同冻结二进制、同 optimizer 代次）
# 判据：
#   (1) 旗标是否生效：本臂 main.zig md5 对比 A 臂 md5 ⇒ 若逐形相同则读数作废（DISCRIM_NO_EFFECT）
#   (2) 输出面：AOT 运行输出 vs /opt/homebrew/bin/php 真值（官方 harness 同款归一化）⇒ PASS/DIFF/RUNTIME_FAIL/COMPILE_FAIL
# 产物：/tmp/opt001_cfgclean_work（收尾清空）、fuzzy_scripts_720/tmp/opt001_cfgclean_discriminant_tmp.tsv
# 铁律：禁止删除任何 .php 源；编译产物一律 aot_compile_* 命名并在收尾删除。
cd /Users/wangjianjun/products/parser || exit 1

SRC_DIR="fuzzy_scripts_720/pass"
TMP_DIR="fuzzy_scripts_720/tmp"
BIN="zig-out/bin/php-interpreter"
PHP_BIN="/opt/homebrew/bin/php"
WORK="/tmp/opt001_cfgclean_work"
TSV="$TMP_DIR/opt001_cfgclean_discriminant_tmp.tsv"
HDR="$TMP_DIR/opt001_cfgclean_discriminant_tmp_hdr.txt"
CONTROL="$TMP_DIR/c007_rf_face_tmp.tsv"

SHAPES="f016_hash_bloom_consistent f044_json_deepops_merge_diff f104_game_engine_ecs_collision_render f113_distributed_consistenthash_vectorclock_quorum f117_search_engine_inverted_tfidf_bm25 f124_container_orchestrator_pod_service_autoscale f134_event_sourcing_snapshot_cqrs_projection f161_json_xml_csv_parsing f177_graph_traversal_dfs_bfs f024_rbac_role_inheritance_policy f025_coding_hamming_rle_lzw_crc f051_validator_rule_chain_batch f061_graph_dijkstra_bellmanford_floyd f072_type_inference_hindley_milner f135_math_number_theory_crt_miller_rabin f152_closure_arrow_higher_order f160_virtual_fs_path_traversal f171_state_machine_dfa f176_specification_chain_rules"

CHAIN9="f016 f044 f104 f113 f117 f124 f134 f161 f177"

rm -rf "$WORK"
mkdir -p "$WORK"

{
  echo "# opt001 cfg-cleanup discriminant $(date '+%Y-%m-%d %H:%M:%S')"
  echo "bin_md5=$(md5 -q "$BIN")"
  echo "optimizer=$(md5 -q src/aot/optimizer.zig)/$(wc -l < src/aot/optimizer.zig | tr -d ' ')"
  echo "native_linker=$(md5 -q src/aot/native_linker.zig)/$(wc -l < src/aot/native_linker.zig | tr -d ' ')"
  echo "flags=--compile --no-debug-info --optimize=release-fast --aot-disable-pass=cfg-cleanup"
  echo "control=$CONTROL"
} > "$HDR"

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

> "$TSV"

total=0
d_same_gen=0
discrim_pass=0
still_diff=0
rfail=0
cfail=0
skip=0

for name in $SHAPES; do
  f="$SRC_DIR/$name.php"
  total=$((total + 1))
  short=${name%%_*}
  if echo " $CHAIN9 " | grep -q " $short "; then grp="CHAIN"; else grp="NOHIT"; fi

  # 控制组 TSV 为竖线分隔（c007 系 harness 的落盘格式）；首轮误用 -F'\t' ⇒ ctrl 两列恒空
  ctrl_stat=$(awk -F'|' -v n="$name" '$1==n {print $3}' "$CONTROL")
  ctrl_md5=$(awk -F'|' -v n="$name" '$1==n {print $5}' "$CONTROL")

  if [ ! -f "$f" ]; then
    printf "%s|%s|SRC_MISSING|-|-\n" "$name" "$grp" >> "$TSV"
    skip=$((skip + 1))
    continue
  fi

  php_raw=$(timeout 10 "$PHP_BIN" "$f" 2>&1); php_rc=$?
  if [ $php_rc -ne 0 ]; then
    printf "%s|%s|PHP_EXIT|ctrl=%s|exit=%d\n" "$name" "$grp" "$ctrl_stat" "$php_rc" >> "$TSV"
    skip=$((skip + 1))
    continue
  fi
  php_norm=$(printf '%s\n' "$php_raw" | normalize_output)

  cerr="$WORK/${name}.cerr"
  out_bin="$WORK/aot_compile_${name}"
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info --optimize=release-fast \
    --aot-disable-pass=cfg-cleanup --output="$out_bin" "$f" >"$cerr" 2>&1
  c_rc=$?
  tdir=$(awk '/preserved/ {print $NF; exit}' "$cerr")
  oflag=$(grep -o -m1 -- '-O[A-Za-z]*' "$cerr")

  if [ $c_rc -ne 0 ]; then
    reason=$(grep -m1 "error:" "$cerr" | head -c 180 | tr '\n' ' ')
    printf "%s|%s|COMPILE_FAIL|ctrl=%s|%s\n" "$name" "$grp" "$ctrl_stat" "$reason" >> "$TSV"
    cfail=$((cfail + 1))
    [ -n "$tdir" ] && rm -rf "$tdir"
    rm -f "$out_bin"
    continue
  fi

  gen="NOTEMP"
  if [ -n "$tdir" ] && [ -f "$tdir/main.zig" ]; then
    now_md5=$(md5 -q "$tdir/main.zig")
    now_lines=$(wc -l < "$tdir/main.zig" | tr -d ' ')
    # 首轮缺陷：gen 列只留标签、未落本臂 md5 ⇒ 事后无法复核旗标是否生效；现补 md5+行数
    if [ "$now_md5" = "$ctrl_md5" ]; then
      gen="SAME_AS_RF"
      d_same_gen=$((d_same_gen + 1))
    else
      gen="DIFF_FROM_RF"
    fi
    gen="${gen}[${now_lines}/${now_md5}]"
    rm -rf "$tdir"
  fi

  aot_raw=$(timeout 10 "$out_bin" 2>&1); a_rc=$?
  rm -f "$out_bin"
  aot_norm=$(printf '%s\n' "$aot_raw" | normalize_output)

  if [ $a_rc -ne 0 ]; then
    # exit=124 是 `timeout 10` 的判停码（挂起或过慢），与段错误/异常退出必须分开计
    [ $a_rc -eq 124 ] && vlabel="TIMEOUT_10S" || vlabel="RUNTIME_FAIL"
    printf "%s|%s|%s|ctrl=%s|gen=%s|exit=%d %s\n" "$name" "$grp" "$vlabel" "$ctrl_stat" "$gen" "$a_rc" "$(printf '%s' "$aot_raw" | tail -2 | tr '\n' ' ' | head -c 160)" >> "$TSV"
    rfail=$((rfail + 1))
    continue
  fi
  if [ "$aot_norm" = "$php_norm" ]; then
    printf "%s|%s|PASS|ctrl=%s|gen=%s\n" "$name" "$grp" "$ctrl_stat" "$gen" >> "$TSV"
    discrim_pass=$((discrim_pass + 1))
  else
    printf "%s|%s|DIFF|ctrl=%s|gen=%s\n" "$name" "$grp" "$ctrl_stat" "$gen" >> "$TSV"
    still_diff=$((still_diff + 1))
  fi
done

{
  printf "CHAIN: PASS=%d DIFF=%d RUNTIME_FAIL=%d TIMEOUT_10S=%d COMPILE_FAIL=%d\n" \
    "$(grep -c '|CHAIN|PASS|' "$TSV" || true)" "$(grep -c '|CHAIN|DIFF|' "$TSV" || true)" \
    "$(grep -c '|CHAIN|RUNTIME_FAIL|' "$TSV" || true)" "$(grep -c '|CHAIN|TIMEOUT_10S|' "$TSV" || true)" \
    "$(grep -c '|CHAIN|COMPILE_FAIL|' "$TSV" || true)"
  printf "NOHIT: PASS=%d DIFF=%d RUNTIME_FAIL=%d TIMEOUT_10S=%d COMPILE_FAIL=%d\n" \
    "$(grep -c '|NOHIT|PASS|' "$TSV" || true)" "$(grep -c '|NOHIT|DIFF|' "$TSV" || true)" \
    "$(grep -c '|NOHIT|RUNTIME_FAIL|' "$TSV" || true)" "$(grep -c '|NOHIT|TIMEOUT_10S|' "$TSV" || true)" \
    "$(grep -c '|NOHIT|COMPILE_FAIL|' "$TSV" || true)"
} | tee -a "$TSV"

echo "gen_same_as_rf=$d_same_gen/$total (若 == total ⇒ 旗标未生效, 本读数作废)"
echo "DISCRIM_DONE total=$total pass=$discrim_pass diff=$still_diff runtime_fail=$rfail compile_fail=$cfail skip=$skip"
