#!/usr/bin/env bash
# R-3 批（替代语法严格闭合，旗标门控只改 AOT）验收链：六门 → 主回归 → 影子。
# 顺序与 R-2 链（c010_acceptance_chain_tmp.sh）相反：先把分叉判定（门 I）与宽容面（门 H2）拿到，
# 再吃长时间影子。全部命令带 timeout（宪法 §三-6）；阶段标记便于中途读取部分结果。
set -u
cd "$(dirname "$0")/../.." || exit 1
LOG=fuzzy_scripts_720/tmp/c010_r3_acceptance_chain_tmp.log
{
  echo "== [1/3] gates start $(date '+%F %T')"
  timeout 480 bash fuzzy_scripts_720/tmp/c010_keyword_case_gate_tmp.sh >/dev/null 2>&1; echo "gateE_rc=$?"
  timeout 300 bash fuzzy_scripts_720/tmp/c010_mechanism_gate_tmp.sh >/dev/null 2>&1; echo "gateF_rc=$?"
  timeout 300 bash fuzzy_scripts_720/tmp/c010_constant_case_gate_tmp.sh >/dev/null 2>&1; echo "gateG_rc=$?"
  timeout 900 bash fuzzy_scripts_720/tmp/c010_kw_full_table_gate_tmp.sh >/dev/null 2>&1; echo "gateH_rc=$?"
  timeout 300 bash fuzzy_scripts_720/tmp/c010_noface_tolerance_gate_tmp.sh >/dev/null 2>&1; echo "gateH2_rc=$?"
  timeout 480 bash fuzzy_scripts_720/tmp/c010_crossmode_gate_tmp.sh >/dev/null 2>&1; echo "gateI_rc=$?"
  echo "== [1/3] gates done $(date '+%F %T')"
  echo "== 六门新读数 =="
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
