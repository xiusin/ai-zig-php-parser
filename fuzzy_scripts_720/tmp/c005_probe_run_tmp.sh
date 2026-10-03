#!/bin/bash
# AOT-CODEGEN-005 探针门：同族/隔离探针 AOT 输出 vs PHP 真值逐字节比对（数量由列表计算）
cd /Users/wangjianjun/products/parser || exit 1
PHP=/opt/homebrew/bin/php
BIN=./zig-out/bin/php-interpreter
PROBES="
ref002_iso_a_break_foreach_tmp
ref002_iso_b_foreach_snapshot_tmp
ref002_iso_f_break_after_nested_for_tmp
ref002_iso_g_flag_and_break_tmp
ref002_iso_h_no_break_tmp
ref002_iso_i_no_nested_for_tmp
ref002_iso_j_func_context_tmp
c005_k_seq_if_for_tmp
c005_l_while_sibling_break_tmp
c005_m_for_sibling_break_tmp
c005_n_while_nested_for_break_tmp
c005_o_for_nested_for_break_tmp
c005_p_while_nested_foreach_tmp
c005_q_while_nested_while_tmp
c005_r_while_else_nested_for_tmp
c005_s_dowhile_nested_for_tmp
c005_rc4_min_y1_tmp
"
same=0
diff=0
for f in $PROBES; do
  src="fuzzy_scripts_720/tmp/$f.php"
  out="/tmp/aot_compile_$f"
  timeout 300 "$BIN" --compile --no-debug-info --output="$out" "$src" 2>/tmp/aotc_$f.err
  rc_c=$?
  if [ $rc_c -ne 0 ]; then
    echo "COMPILE_FAIL|$f|rc=$rc_c"
    diff=$((diff+1))
    continue
  fi
  timeout 10 "$out" > /tmp/aot_$f.out 2>/tmp/aot_$f.err
  rc_r=$?
  timeout 10 "$PHP" "$src" > /tmp/php_$f.out 2>/tmp/php_$f.err
  if cmp -s /tmp/aot_$f.out /tmp/php_$f.out; then
    echo "IDENTICAL|$f|rc=$rc_r"
    same=$((same+1))
  else
    echo "DIFFERS|$f|rc=$rc_r"
    echo "  PHP: $(tr '\n' '|' < /tmp/php_$f.out)"
    echo "  AOT: $(tr '\n' '|' < /tmp/aot_$f.out)"
    diff=$((diff+1))
  fi
  rm -f "$out"
done
echo "PROBE_DONE total=$(echo $PROBES | wc -w | tr -d ' ') same=$same differs=$diff"
