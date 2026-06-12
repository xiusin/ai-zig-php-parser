# Zig-PHP 性能测试框架

自动化的 Zig-PHP vs 原生 PHP 性能对比测试框架，支持批量测试、性能回归检测和多格式报告生成。

## 功能特性

- ✅ **自动化测试执行**: 自动运行 Zig-PHP 和原生 PHP 的对比测试
- ✅ **多次迭代支持**: 支持预热和多次测试迭代，确保结果准确
- ✅ **统计分析**: 计算平均值、中位数、标准差、P95、P99 等统计指标
- ✅ **批量测试**: 支持一次运行多个测试脚本
- ✅ **性能基线管理**: 保存和加载性能基线数据
- ✅ **回归检测**: 自动检测性能回归，支持自定义阈值
- ✅ **多格式报告**: 支持 JSON、CSV、Markdown、HTML 格式报告
- ✅ **CI 集成**: 提供 CI 运行器，支持持续集成环境

## 快速开始

### 1. 基本使用

```zig
const std = @import("std");
const framework = @import("framework.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 配置测试框架
    const config = framework.BenchmarkConfig{
        .warmup_iterations = 100,
        .test_iterations = 1000,
        .verbose = true,
    };
    
    const bench = try framework.BenchmarkFramework.init(allocator, config);
    defer bench.deinit();
    
    // 运行单个测试
    const result = try bench.runComparison("test.php");
    
    // 生成报告
    try bench.generateReport(result, "report.md", .markdown);
}
```

### 2. 批量测试

```zig
const test_scripts = [_][]const u8{
    "tests/test1.php",
    "tests/test2.php",
    "tests/test3.php",
};

const batch_result = try bench.runBatchTests(&test_scripts);
try bench.generateBatchReport(batch_result, "batch_report.md", .markdown);
```

### 3. 性能基线管理

```zig
// 保存基线
try bench.saveBaseline("test_name", stats);
try bench.saveBaselinesToFile("baseline.json");

// 加载基线
try bench.loadBaselines("baseline.json");

// 检测回归
const regression = try bench.detectRegression(
    "test_name",
    current_stats,
    5.0, // 5% 阈值
);

if (regression.has_regression) {
    std.debug.print("检测到性能回归！\n", .{});
}
```

## 配置选项

### BenchmarkConfig

| 选项 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `warmup_iterations` | `u32` | 100 | 预热迭代次数 |
| `test_iterations` | `u32` | 1000 | 测试迭代次数 |
| `timeout_ms` | `u64` | 30000 | 超时时间（毫秒） |
| `enable_memory_tracking` | `bool` | true | 是否启用内存监控 |
| `verbose` | `bool` | false | 是否启用详细日志 |
| `php_executable` | `[]const u8` | "php" | PHP 可执行文件路径 |
| `zigphp_executable` | `[]const u8` | "./zig-php" | Zig-PHP 可执行文件路径 |

## 报告格式

### 1. Markdown 报告

```markdown
# 性能测试报告: test.php

**测试时间**: 1234567890

## 对比结果

- **加速比**: 2.50x
- **内存节省**: 45.2%

## 详细统计

| 指标 | Zig-PHP | 原生 PHP | 改进 |
|------|---------|----------|------|
| 平均时间 (ns) | 100.00 | 250.00 | 60.0% |
| 中位数 (ns) | 95.00 | 240.00 | 60.4% |
| P95 (ns) | 120 | 300 | - |
```

### 2. JSON 报告

```json
{
  "test_name": "test.php",
  "timestamp": 1234567890,
  "speedup": 2.5,
  "memory_savings": 0.452,
  "zigphp": {
    "mean_ns": 100.00,
    "median_ns": 95.00,
    "std_dev_ns": 10.00,
    "min_ns": 80,
    "max_ns": 120,
    "p95_ns": 115,
    "p99_ns": 118,
    "iterations": 1000,
    "peak_memory_bytes": 1024
  },
  "php": {
    "mean_ns": 250.00,
    "median_ns": 240.00,
    "std_dev_ns": 25.00,
    "min_ns": 200,
    "max_ns": 300,
    "p95_ns": 290,
    "p99_ns": 295,
    "iterations": 1000,
    "peak_memory_bytes": 2048
  }
}
```

### 3. CSV 报告

```csv
test_name,implementation,mean_ns,median_ns,std_dev_ns,min_ns,max_ns,p95_ns,p99_ns,iterations,peak_memory_bytes
"test.php","Zig-PHP",100.00,95.00,10.00,80,120,115,118,1000,1024
"test.php","PHP",250.00,240.00,25.00,200,300,290,295,1000,2048
```

### 4. HTML 报告

生成完整的 HTML 页面，包含样式和表格。

## CI 集成

### 使用 CI 运行器

```bash
# 基本用法
zig build run-ci

# 自定义配置
zig build run-ci -- \
  --baseline performance_baseline.json \
  --test-dir tests/benchmarks \
  --threshold 5.0 \
  --output-dir benchmark_results \
  --no-fail-on-regression
```

### GitHub Actions 示例

```yaml
name: Performance Tests

on: [push, pull_request]

jobs:
  benchmark:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v2
      
      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.11.0
      
      - name: Build Zig-PHP
        run: zig build
      
      - name: Run Performance Tests
        run: zig build run-ci
      
      - name: Upload Reports
        uses: actions/upload-artifact@v2
        with:
          name: benchmark-reports
          path: benchmark_results/
```

## 性能回归检测

框架会自动检测以下指标的回归：

- **平均值 (mean)**: 平均执行时间
- **中位数 (median)**: 中位执行时间
- **P95**: 第 95 百分位数

如果任一指标的变化超过阈值（默认 5%），则认为存在性能回归。

### 回归检测流程

1. 加载性能基线数据
2. 运行当前测试
3. 对比当前结果与基线
4. 计算变化百分比
5. 判断是否超过阈值
6. 生成回归报告

## 最佳实践

### 1. 测试脚本编写

- 确保测试脚本可独立运行
- 避免外部依赖（数据库、网络等）
- 使用确定性的输入数据
- 测试时间应在 1-10 秒之间

### 2. 迭代次数选择

- **预热迭代**: 100-200 次，用于 JIT 预热
- **测试迭代**: 1000-10000 次，根据测试时长调整
- 快速测试（< 1ms）: 10000 次
- 中等测试（1-10ms）: 1000 次
- 慢速测试（> 10ms）: 100 次

### 3. 回归阈值设置

- **严格模式**: 2-3%，用于关键性能路径
- **标准模式**: 5%，用于一般测试
- **宽松模式**: 10%，用于不稳定的测试

### 4. CI 集成建议

- 在每次 PR 时运行性能测试
- 保存基线数据到版本控制
- 定期更新基线（每周或每月）
- 使用相同的硬件环境进行测试

## 故障排除

### 问题 1: 测试超时

**原因**: 测试脚本执行时间过长

**解决方案**:
- 增加 `timeout_ms` 配置
- 减少测试迭代次数
- 优化测试脚本

### 问题 2: 内存不足

**原因**: 测试脚本内存占用过大

**解决方案**:
- 减少测试迭代次数
- 优化测试脚本的内存使用
- 增加系统内存

### 问题 3: 结果不稳定

**原因**: 系统负载波动、JIT 未预热

**解决方案**:
- 增加预热迭代次数
- 增加测试迭代次数
- 在空闲系统上运行测试
- 使用更宽松的回归阈值

## 示例

完整的使用示例请参考：

- `example_usage.zig`: 基本使用示例
- `ci_runner.zig`: CI 集成示例

## 性能指标说明

### 统计指标

- **mean (平均值)**: 所有样本的算术平均值
- **median (中位数)**: 排序后位于中间的值，更能反映典型性能
- **std_dev (标准差)**: 衡量数据的离散程度
- **min/max**: 最小/最大值，用于识别异常值
- **P95/P99**: 第 95/99 百分位数，用于评估尾延迟

### 对比指标

- **speedup (加速比)**: PHP时间 / Zig-PHP时间，> 1 表示更快
- **memory_savings (内存节省)**: (PHP内存 - Zig-PHP内存) / PHP内存

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！

## 相关文档

- [需求文档](../../.kiro/specs/zig-php-performance-optimization/requirements.md)
- [设计文档](../../.kiro/specs/zig-php-performance-optimization/design.md)
- [任务列表](../../.kiro/specs/zig-php-performance-optimization/tasks.md)
