# 性能基线方法学与可重复实验

## 目标
- 用同一组 PHP 用例，采集不同执行模式的**可重复**性能数据，作为后续 Milestone2/3 的回归基线。
- 输出包含：wall time、（Linux 下）`perf stat` 指标、工具链与环境指纹。

## 指标口径
- wall time：以子进程运行解释器/产物的真实耗时（秒）记录在 JSON 中。
- `perf stat`（仅 Linux 且存在 `perf` 时启用）：\n  `cycles, instructions, branches, branch-misses, cache-misses`\n- pytest-benchmark：提供一个冒烟基准用于 CI 快速回归（默认仅跑 `tree` + 1 个用例）。输出 `pytest_benchmark.json`。

## 工具与实现位置
- 运行封装： [perf_harness.py](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/ci/perf_harness.py)\n- 基线用例（用例×模式）： [test_perf_baseline.py](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/ci/tests/test_perf_baseline.py)\n- pytest-benchmark 冒烟： [test_pytest_benchmark_smoke.py](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/ci/tests/test_pytest_benchmark_smoke.py)\n- 一键入口： [run_perf_baseline.py](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/ci/scripts/run_perf_baseline.py)\n- 可重复实验脚本： [repro.sh](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/ci/scripts/repro.sh)

## 一键复现（本地）
```bash
bash ci/scripts/repro.sh
```

产物：\n- `.perf_reports/milestone1_baseline.json`\n- `.perf_reports/pytest_benchmark.json`

## 运行矩阵控制
- 用例集合：环境变量 `ZIGPHP_CASES`（逗号分隔，路径相对仓库根目录）\n- 执行模式：环境变量 `ZIGPHP_MODES`（例如 `tree,bytecode,fast`）\n- 是否包含 AOT：环境变量 `ZIGPHP_INCLUDE_AOT=1`（会额外记录 compile/run）

## 统计与显著性（Milestone1 预留）
- Milestone1 的目标是建立**自动化采集与落盘**，显著性检验与多轮采样会在后续里程碑逐步加严。\n- 当前建议在后续把每个（case,mode）运行 N 次并做：median/IQR、Mann-Whitney U test，并记录 perf counter 的置信区间。
