#!/bin/bash
# 抽查：实时编译若干语料脚本，把 main.zig 的 md5 与已冻结基线 tsv 逐行比对
cd /Users/wangjianjun/products/parser || exit 1
BASELINE="fuzzy_scripts_720/baseline_main_zig_md5.tsv"
BIN="zig-out/bin/php-interpreter"
CASES="f031_builder_fluent_immutable f010_oop_singleton_registry_di f042_array_functions_full f067_json_parser_schema_path_diff f113_distributed_consistenthash_vectorclock_quorum"
ok=0
bad=0
for name in $CASES; do
  src="fuzzy_scripts_720/pass/${name}.php"
  exp=$(awk -F'\t' -v n="$name" '$1==n {print $3}' "$BASELINE")
  if [ ! -f "$src" ] || [ -z "$exp" ]; then
    echo "SKIP_MISSING|$name|src=$([ -f "$src" ] && echo y || echo n)|exp=${exp}"
    continue
  fi
  ZIGPHP_AOT_KEEP_TEMP=1 timeout 600 "$BIN" --compile --no-debug-info "$src" 2>/tmp/s7_spot.err >/dev/null
  d=$(awk '/preserved/ {print $NF; exit}' /tmp/s7_spot.err)
  if [ -z "$d" ] || [ ! -f "$d/main.zig" ]; then
    echo "NOTEMP|$name"
    bad=$((bad+1))
    continue
  fi
  got=$(md5 -q "$d/main.zig")
  lines=$(wc -l < "$d/main.zig" | tr -d ' ')
  exp_lines=$(awk -F'\t' -v n="$name" '$1==n {print $2}' "$BASELINE")
  if [ "$got" = "$exp" ] && [ "$lines" = "$exp_lines" ]; then
    echo "OK|$name|$lines|$got"
    ok=$((ok+1))
  else
    echo "DIFF|$name|live=$lines/$got|frozen=$exp_lines/$exp"
    bad=$((bad+1))
  fi
  rm -rf "$d"
  rm -f "fuzzy_scripts_720/pass/aot_compile_${name}"
done
echo "SPOT_DONE ok=$ok bad=$bad"
