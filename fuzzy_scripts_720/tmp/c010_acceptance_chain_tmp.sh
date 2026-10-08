#!/usr/bin/env bash
# R-2 批验收链（影子 → 六门 → 主回归），串行执行避免临时目录与产物互扰。
# 全部命令带 timeout（宪法 §三-6）；日志落 c010_acceptance_chain_tmp.log。
set -u
cd "$(dirname "$0")/../.." || exit 1
LOG=fuzzy_scripts_720/tmp/c010_acceptance_chain_tmp.log
{
  echo "== [1/3] shadow start $(date '+%F %T')"
  timeout 3600 bash fuzzy_scripts_720/tmp/c010_shadow_main_md5_tmp.sh
  echo "== [1/3] shadow rc=$? $(date '+%F %T')"
  echo "== [2/3] gates start $(date '+%F %T')"
  timeout 480 bash fuzzy_scripts_720/tmp/c010_keyword_case_gate_tmp.sh >/dev/null 2>&1; echo "gateE_rc=$?"
  timeout 300 bash fuzzy_scripts_720/tmp/c010_mechanism_gate_tmp.sh >/dev/null 2>&1; echo "gateF_rc=$?"
  timeout 300 bash fuzzy_scripts_720/tmp/c010_constant_case_gate_tmp.sh >/dev/null 2>&1; echo "gateG_rc=$?"
  timeout 900 bash fuzzy_scripts_720/tmp/c010_kw_full_table_gate_tmp.sh >/dev/null 2>&1; echo "gateH_rc=$?"
  timeout 300 bash fuzzy_scripts_720/tmp/c010_noface_tolerance_gate_tmp.sh >/dev/null 2>&1; echo "gateH2_rc=$?"
  timeout 480 bash fuzzy_scripts_720/tmp/c010_crossmode_gate_tmp.sh >/dev/null 2>&1; echo "gateI_rc=$?"
  echo "== [2/3] gates done $(date '+%F %T')"
  echo "== [3/3] main regression start $(date '+%F %T')"
  timeout 1800 bash fuzzy_scripts_720/run_regression.sh >/dev/null 2>&1; echo "regression_rc=$?"
  echo "== [3/3] regression done $(date '+%F %T')"
  echo "== 六门新读数 =="
  tail -1 fuzzy_scripts_720/tmp/c010_keyword_case_tmp.tsv
  tail -1 fuzzy_scripts_720/tmp/c010_mechanism_tmp.tsv
  tail -1 fuzzy_scripts_720/tmp/c010_constant_case_tmp.tsv
  tail -1 fuzzy_scripts_720/tmp/c010_kw_full_table_tmp.tsv
  tail -1 fuzzy_scripts_720/tmp/c010_noface_tolerance_tmp.tsv
  tail -1 fuzzy_scripts_720/tmp/c010_crossmode_tmp.tsv
  echo "== 影子读数 =="
  tail -1 fuzzy_scripts_720/tmp/c010_shadow_main_md5_tmp.tsv
} >>"$LOG" 2>&1
echo DONE
