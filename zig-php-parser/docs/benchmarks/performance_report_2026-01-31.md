# 性能对比报告

## 测试环境

- **日期**: 2026-01-31
- **平台**: Darwin arm64
- **PHP 版本**: PHP 8.4.8 (cli) (built: Jun  3 2025 16:29:26) (NTS)
- **Zig 版本**: 0.15.2

## 测试说明

本报告对比 PHP 原生执行与 Zig-PHP AOT 编译执行的性能差异。

## 基准测试结果

详细结果请参见 `tests/benchmarks/baseline_results.json`

## 回归检测

回归阈值: 10%

