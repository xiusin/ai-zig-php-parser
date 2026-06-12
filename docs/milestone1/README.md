# Milestone 1：差异矩阵与性能基线自动化

## 交付物入口
- 功能点×执行模式差异矩阵（Excel）：[diff_matrix.xlsx](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/artifacts/diff_matrix.xlsx)
- 功能点×执行模式差异矩阵（CSV）：[diff_matrix.csv](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/artifacts/diff_matrix.csv)
- 端到端主链路调用链矩阵（Markdown）：[callchain_matrix.md](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/docs/milestone1/callchain_matrix.md)
- 执行模式差异说明：[mode_diff_matrix.md](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/docs/milestone1/mode_diff_matrix.md)
- 性能基线方法学与复现：[perf_baseline_methodology.md](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/docs/milestone1/perf_baseline_methodology.md)

## 一键生成
- 生成差异矩阵（CSV+XLSX）
  - `python3 tools/gen_diff_matrix.py --out-dir artifacts`
- 生成主链路调用链矩阵
  - `python3 tools/gen_callchain_matrix.py --out docs/milestone1/callchain_matrix.md`

## 一键跑基线（本地）
- `bash ci/scripts/repro.sh`

该脚本会创建 `.venv-m1/`，安装 `ci/requirements.txt`，并生成：\n- `.perf_reports/milestone1_baseline.json`（用例×模式的 wall time 与 perf stat）\n- `.perf_reports/pytest_benchmark.json`（pytest-benchmark 输出）
