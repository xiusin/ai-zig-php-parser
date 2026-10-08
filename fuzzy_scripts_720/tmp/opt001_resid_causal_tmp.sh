#!/bin/bash
# AOT-OPT-001 §5.6 残红五形因果判别臂（任务 #99 第二阶段，只读、零源码改动、非门控）
#
# 前置读数（同代次，fuzzy_scripts_720/tmp/opt001_resid_hoist_tmp.tsv，四臂 IR-only）：
#   C4（pre-header 指令操作数定义在该循环内 = 陈旧提升）在 5 形 × 4 臂 **全 0**
#   C4bh（pre-header 读指令 + 循环内非 store 改写）在 5 形 × 4 臂 **全 0**
#   ⇒ 「提升本身取了陈旧值」两条探针均否证；残红机制只可能仍落在 cfg_cleanup 删臂/折条件链上。
#   C1 与档位内红绿**逐臂同向**：f117 base0/licm4/li5-3/li5nc-0、f161 0/2/2/0、
#     f051 0/0/1/0、f135 0/0/2/0、f061 0/0/0/0（f061 是唯一 C1 恒 0 却仍红的形）。
#
# 本臂做**输出面**因果判别：唯一变量 = --aot-disable-pass=cfg-cleanup（LICM 与迭代数保持不变）。
#   若关 cfg_cleanup 即转绿 ⇒ 该形的红由 R2（删臂+折条件）因果承载，与「提升」无关。
#   若仍红 ⇒ 签名在场但非承重（#98 的「C1 是下界探针」口径在默认档同样成立）。
# 臂集：li5 = --aot-enable-pass=licm --aot-max-iterations=5；li5nc = 上式 + 关 cfg_cleanup
#       licm / licmnc 仅对组 I 两形（f117 f161，3 轮即红）追加，用于分离「轮数」与「链」。
# 生效性自证：同形两臂 main.zig 的 md5/行数必须不同，否则该形读数作废（NO_EFFECT）。
# 真值：/opt/homebrew/bin/php；归一化 = 官方 harness 同款 normalize_output。
# 铁律：禁止删除任何 .php 源；编译产物一律 aot_compile_* 命名并即时删除；全部命令带 timeout。
cd /Users/wangjianjun/products/parser || exit 1

BIN="zig-out/bin/php-interpreter"
PHP_BIN="/opt/homebrew/bin/php"
SRC_DIR="fuzzy_scripts_720/pass"
TMP_DIR="fuzzy_scripts_720/tmp"
WORK="/tmp/opt001_resid_causal_work"
TSV="$TMP_DIR/opt001_resid_causal_tmp.tsv"

SHAPES="f117_search_engine_inverted_tfidf_bm25 f161_json_xml_csv_parsing f051_validator_rule_chain_batch f061_graph_dijkstra_bellmanford_floyd f135_math_number_theory_crt_miller_rabin"
GROUP1="f117 f161"

rm -rf "$WORK"; mkdir -p "$WORK"
{
  echo "# opt001 §5.6 residual causal discriminant $(date '+%Y-%m-%d %H:%M:%S')"
  echo "bin_md5=$(md5 -q "$BIN")"
  echo "optimizer=$(md5 -q src/aot/optimizer.zig)/$(wc -l < src/aot/optimizer.zig | tr -d ' ')"
  echo "native_linker=$(md5 -q src/aot/native_linker.zig)/$(wc -l < src/aot/native_linker.zig | tr -d ' ')"
  echo "level=default(无 --optimize) 唯一变量=--aot-disable-pass=cfg-cleanup"
} > "$TSV"

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

run_arm() {
  # $1=shape $2=arm $3=extra-flags
  local name="$1" arm="$2" flags="$3"
  local f="$SRC_DIR/$name.php" out="$WORK/aot_compile_${name}_${arm}" cerr="$WORK/${name}_${arm}.cerr"
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 $BIN --compile --no-debug-info $flags --output="$out" "$f" >"$cerr" 2>&1
  local c_rc=$?
  local tdir gen="NOTEMP"
  tdir=$(awk '/preserved/ {print $NF; exit}' "$cerr")
  if [ $c_rc -ne 0 ]; then
    local reason=$(grep -m1 "error:" "$cerr" | head -c 160 | tr '\n' ' ')
    printf "%s|%s|COMPILE_FAIL|%s\n" "$name" "$arm" "$reason" >> "$TSV"
    echo "  [$name $arm] COMPILE_FAIL $reason"
    [ -n "$tdir" ] && rm -rf "$tdir"; rm -f "$out" "$cerr"
    return
  fi
  if [ -n "$tdir" ] && [ -f "$tdir/main.zig" ]; then
    gen="[$(wc -l < "$tdir/main.zig" | tr -d ' ')/$(md5 -q "$tdir/main.zig")]"
    rm -rf "$tdir"
  fi
  local aot_raw a_rc
  aot_raw=$(timeout 10 "$out" 2>&1); a_rc=$?
  rm -f "$out" "$cerr"
  local aot_norm=$(printf '%s\n' "$aot_raw" | normalize_output)
  if [ $a_rc -ne 0 ]; then
    local vlabel="RUNTIME_FAIL"; [ $a_rc -eq 124 ] && vlabel="TIMEOUT_10S"
    printf "%s|%s|%s|gen=%s|exit=%d\n" "$name" "$arm" "$vlabel" "$gen" "$a_rc" >> "$TSV"
    echo "  [$name $arm] $vlabel exit=$a_rc"
    return
  fi
  if [ "$aot_norm" = "$php_norm" ]; then
    printf "%s|%s|PASS|gen=%s\n" "$name" "$arm" "$gen" >> "$TSV"
    echo "  [$name $arm] PASS gen=$gen"
  else
    local d=$(diff <(printf '%s\n' "$php_norm") <(printf '%s\n' "$aot_norm") | head -8 | tr '\n' '~' | head -c 400)
    printf "%s|%s|DIFF|gen=%s|d=%s\n" "$name" "$arm" "$gen" "$d" >> "$TSV"
    echo "  [$name $arm] DIFF gen=$gen"
    echo "      d=$d"
  fi
}

for name in $SHAPES; do
  f="$SRC_DIR/$name.php"
  if [ ! -f "$f" ]; then printf "%s|-|SRC_MISSING\n" "$name" >> "$TSV"; continue; fi
  php_raw=$(timeout 10 "$PHP_BIN" "$f" 2>&1); php_rc=$?
  if [ $php_rc -ne 0 ]; then printf "%s|-|PHP_EXIT|exit=%d\n" "$name" "$php_rc" >> "$TSV"; continue; fi
  php_norm=$(printf '%s\n' "$php_raw" | normalize_output)
  short=${name%%_*}
  if echo " $GROUP1 " | grep -q " $short "; then
    run_arm "$name" licm     "--aot-enable-pass=licm"
    run_arm "$name" licmnc   "--aot-enable-pass=licm --aot-disable-pass=cfg-cleanup"
  fi
  run_arm "$name" li5        "--aot-enable-pass=licm --aot-max-iterations=5"
  run_arm "$name" li5nc      "--aot-enable-pass=licm --aot-max-iterations=5 --aot-disable-pass=cfg-cleanup"
done

{
  for arm in licm licmnc li5 li5nc; do
    printf "%s: PASS=%d DIFF=%d RUNTIME_FAIL=%d TIMEOUT_10S=%d COMPILE_FAIL=%d\n" "$arm" \
      "$(grep -c "|$arm|PASS|" "$TSV" || true)" "$(grep -c "|$arm|DIFF|" "$TSV" || true)" \
      "$(grep -c "|$arm|RUNTIME_FAIL|" "$TSV" || true)" "$(grep -c "|$arm|TIMEOUT_10S|" "$TSV" || true)" \
      "$(grep -c "|$arm|COMPILE_FAIL|" "$TSV" || true)"
  done
} | tee -a "$TSV"
echo "RESID_CAUSAL_DONE"
