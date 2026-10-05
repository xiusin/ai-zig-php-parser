#!/bin/bash
# AOT-CODEGEN-006 永久探针 main.zig 逐字节复现性巡检（只读，不改语料/基线）
cd /Users/wangjianjun/products/parser || exit 1
PASS_DIR=fuzzy_scripts_720/acceptance
TMP=/tmp/c006_permanent_probe_tmp
rm -rf "$TMP"; mkdir -p "$TMP"
probes="c006_tl_elseif_loop_tmp c006_tl_fncontext_loop_tmp c006_tl_ifarm_loop_tmp c006_tl_three_level_tmp"
mismatch=0; rows=0
for f in $probes; do
  src=""
  for cand in "$PASS_DIR/$f.php" "fuzzy_scripts_720/tmp/$f.php" "$PASS_DIR/${f%.php}.php"; do
    [ -f "$cand" ] && src="$cand" && break
  done
  [ -z "$src" ] && { echo "NOSRC|$f"; continue; }
  name=$(basename "$src" .php)
  total=0
  for run in 1 2 3; do
    out=$(ZIGPHP_AOT_KEEP_TEMP=1 timeout 300 ./zig-out/bin/aotc --compile "$src" 2>/dev/null | tail -1)
    [ -z "$out" ] && { echo "NOBIN|$f"; break; }
    d="$TMP/${name}_run${run}"
    if [ -d "$d" ] && [ -f "$d/main.zig" ]; then
      h=$(md5 -q "$d/main.zig"); l=$(wc -l < "$d/main.zig" | tr -d ' ')
      total="${total} ${l}/${h}"
      rm -rf "$d"
    else
      echo "NOTEMP|$f run=$run"; total="FAIL"
    fi
    rm -f "$PASS_DIR/aot_compile_${name}" "$out" 2>/dev/null
  done
  rows=$((rows+1))
  if [ "$total" = "FAIL" ]; then continue; fi
  u=$(echo "$total" | tr ' ' '\n' | grep -c . )
  d=$(echo "$total" | tr ' ' '\n' | sort -u | grep -c .)
  if [ "$d" != "1" ]; then
    echo "MISMATCH|$f$total"
    mismatch=$((mismatch+1))
  else
    echo "STABLE|$f$(echo "$total" | awk '{print $1}')"
  fi
done
echo "PERMANENT_PROBE_DONE rows=$rows mismatch=$mismatch"
