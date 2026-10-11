#!/usr/bin/env bash
# R-5 批跨代次逐行等值比对器（落地前置/后置同一口径）：
#   对每张门表，剔除 `#` 头行与末两行汇总（ELAPSED / *_DONE），只比**逐形读数行**，
#   输出每腿 `diff_rows`；同时单独回读 `*_DONE` 汇总行供人工核对。
#   头行的 compiler_md5/parser_md5 必然随代次变 ⇒ 不参与比对（记忆 §9.6 代次对齐口径）。
# 用法：bash fuzzy_scripts_720/tmp/c010_r5_rowdiff_tmp.sh [PRE_DIR]
#
# R-5 批腿后复测实测（工单 CODEGEN-010 §3.8.10/§3.8.11）：
#   c010_brace_switch_tmp.tsv  diff_rows=8  ← 预期变动面（门 K 的 4 枚 OVER_ACCEPT 转 BOTH_REJECT ⇒ 4×2）
#   c010l_switch_armslot_tmp.tsv diff_rows=24 ← 预期（本轮新建门，全表换判向）
#   其余九腿（J/D8/E/F/G/H/H2/I/影子）diff_rows=0，影子 old_rows=136 new_rows=136 ⇒ 发射中性实证
#   全链墙钟 56m24s = 十门 18m23s（Σ ELAPSED 1103s）+ 主回归 12m54s（774s）+ 影子 25m07s（1507s）
# ★ 纪律：长腿（主回归/影子）的等值必须在**腿完成后**复测本比对器；中途读数一律标注「禁引用」。
set -u
cd "$(dirname "$0")/../.." || exit 1
PRE="${1:-fuzzy_scripts_720/tmp/c010_r5_presnap}"
GATES="c010_brace_switch_tmp.tsv c010l_switch_armslot_tmp.tsv c010_alt_syntax_gate_tmp.tsv c010_indep_defects_tmp.tsv c010_keyword_case_tmp.tsv c010_mechanism_tmp.tsv c010_constant_case_tmp.tsv c010_kw_full_table_tmp.tsv c010_noface_tolerance_tmp.tsv c010_crossmode_tmp.tsv c010_shadow_main_md5_tmp.tsv"
for t in $GATES; do
  newp="fuzzy_scripts_720/tmp/$t"
  oldp="$PRE/$t"
  [ -f "$newp" ] || { echo "$t|MISSING_NEW"; continue; }
  [ -f "$oldp" ] || { echo "$t|MISSING_PRE"; continue; }
  grep -vE '^#|^ELAPSED=|_DONE ' "$oldp" > /tmp/r5_old.rows
  grep -vE '^#|^ELAPSED=|_DONE ' "$newp" > /tmp/r5_new.rows
  d=$(diff /tmp/r5_old.rows /tmp/r5_new.rows | grep -cE '^[<>]')
  oldn=$(wc -l < /tmp/r5_old.rows | tr -d ' ')
  newn=$(wc -l < /tmp/r5_new.rows | tr -d ' ')
  echo "$t|diff_rows=$d|old_rows=$oldn|new_rows=$newn"
done
rm -f /tmp/r5_old.rows /tmp/r5_new.rows
echo "== 汇总行（新） =="
for t in $GATES; do
  [ -f "fuzzy_scripts_720/tmp/$t" ] && { printf '%s :: ' "$t"; grep -hE '_DONE ' "fuzzy_scripts_720/tmp/$t" | tail -1; }
done
