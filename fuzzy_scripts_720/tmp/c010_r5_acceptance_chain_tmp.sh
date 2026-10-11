#!/usr/bin/env bash
# R-5 批（switch case 列表位严格化，旗标门控只改 AOT）验收链：十腿 → 主回归 → 影子。
#   腿序＝**先读本批直接判据（门 K 转拒 / 门 L 守卫 / 门 J 同支路），再读既有门，最后吃长时间影子**，
#   使「主判据是否成立」在 3 分钟内可见，避免整链跑完才发现方向错。
#   腿 1-3 为本批新增/相关：K=面 A 主验收，L=过度拒绝守卫，J=同支路（alt 语法）逐行等值；
#   D8=§8 独立缺陷面；E/F/G/H/H2/I=既有六腿（须逐行等值，门 I 另证旗标分叉未破）。
# 全部命令带 timeout（宪法 §三-6）；日志 append 到本脚本同名 .log；带 repo_build_residue 的门禁
#   与影子/主回归**串行**（记忆：规则「并发会互相污染残留计数」）。
set -u
cd "$(dirname "$0")/../.." || exit 1
LOG=fuzzy_scripts_720/tmp/c010_r5_acceptance_chain_tmp.log
{
  echo "== [1/3] gates start $(date '+%F %T')"
  timeout 300 bash fuzzy_scripts_720/tmp/c010_brace_switch_gate_tmp.sh >/dev/null 2>&1; echo "gateK_rc=$?"
  timeout 300 bash fuzzy_scripts_720/tmp/c010l_switch_armslot_gate_tmp.sh >/dev/null 2>&1; echo "gateL_rc=$?"
  timeout 300 bash fuzzy_scripts_720/tmp/c010_alt_syntax_gate_tmp.sh >/dev/null 2>&1; echo "gateJ_rc=$?"
  timeout 300 bash fuzzy_scripts_720/tmp/c010_indep_defects_gate_tmp.sh >/dev/null 2>&1; echo "gateD8_rc=$?"
  timeout 480 bash fuzzy_scripts_720/tmp/c010_keyword_case_gate_tmp.sh >/dev/null 2>&1; echo "gateE_rc=$?"
  timeout 300 bash fuzzy_scripts_720/tmp/c010_mechanism_gate_tmp.sh >/dev/null 2>&1; echo "gateF_rc=$?"
  timeout 300 bash fuzzy_scripts_720/tmp/c010_constant_case_gate_tmp.sh >/dev/null 2>&1; echo "gateG_rc=$?"
  timeout 900 bash fuzzy_scripts_720/tmp/c010_kw_full_table_gate_tmp.sh >/dev/null 2>&1; echo "gateH_rc=$?"
  timeout 300 bash fuzzy_scripts_720/tmp/c010_noface_tolerance_gate_tmp.sh >/dev/null 2>&1; echo "gateH2_rc=$?"
  timeout 480 bash fuzzy_scripts_720/tmp/c010_crossmode_gate_tmp.sh >/dev/null 2>&1; echo "gateI_rc=$?"
  echo "== [1/3] gates done $(date '+%F %T')"
  echo "== 十门新读数 =="
  tail -1 fuzzy_scripts_720/tmp/c010_brace_switch_tmp.tsv
  tail -1 fuzzy_scripts_720/tmp/c010l_switch_armslot_tmp.tsv
  tail -1 fuzzy_scripts_720/tmp/c010_alt_syntax_gate_tmp.tsv
  tail -1 fuzzy_scripts_720/tmp/c010_indep_defects_tmp.tsv
  tail -1 fuzzy_scripts_720/tmp/c010_keyword_case_tmp.tsv
  tail -1 fuzzy_scripts_720/tmp/c010_mechanism_tmp.tsv
  tail -1 fuzzy_scripts_720/tmp/c010_constant_case_tmp.tsv
  tail -1 fuzzy_scripts_720/tmp/c010_kw_full_table_tmp.tsv
  tail -1 fuzzy_scripts_720/tmp/c010_noface_tolerance_tmp.tsv
  tail -1 fuzzy_scripts_720/tmp/c010_crossmode_tmp.tsv
  echo "== [2/3] main regression start $(date '+%F %T')"
  timeout 1800 bash fuzzy_scripts_720/run_regression.sh >/dev/null 2>&1; echo "regression_rc=$?"
  echo "== [2/3] regression done $(date '+%F %T')"
  tail -6 fuzzy_scripts_720/regression_report.md
  echo "== [3/3] shadow start $(date '+%F %T')"
  timeout 3600 bash fuzzy_scripts_720/tmp/c010_shadow_main_md5_tmp.sh
  echo "== [3/3] shadow rc=$? $(date '+%F %T')"
  echo "== 影子读数 =="
  tail -1 fuzzy_scripts_720/tmp/c010_shadow_main_md5_tmp.tsv
  echo "== ALL DONE $(date '+%F %T')"
} >>"$LOG" 2>&1
echo DONE
