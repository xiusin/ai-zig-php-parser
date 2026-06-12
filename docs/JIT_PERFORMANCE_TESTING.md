# JIT 性能测试文档

## 概述

本文档描述了 Zig-PHP 项目中的 JIT 性能测试框架，该框架用于测量和分析 JIT 编译器的性能。

## 功能特性

### 1. 编译时间测量

JIT 性能测试框架能够精确测量 JIT 编译器编译每个函数所需的时间：

- **编译时间（纳秒）**：从开始编译到生成原生代码的总时间
- **代码大小（字节）**：生成的原生机器码大小
- **内存分配（字节）**：编译过程中分配的内存量

### 2. 执行时间测量

框架对比 JIT 编译执行和解释执行的性能差异：

- **平均执行时间**：多次迭代的平均值
- **中位数**：排除异常值的中位数时间
- **标准差**：执行时间的稳定性指标
- **百分位数（P95, P99）**：尾部延迟分析
- **加速比**：JIT 相对于解释执行的性能提升倍数

### 3. 内存使用测量

跟踪 JIT 编译和执行过程中的内存使用情况：

- **峰值内存使用**：执行过程中的最大内存占用
- **内存开销**：JIT 相对于解释执行的额外内存开销

## 使用方法

### 基本用法

```zig
const std = @import("std");
const JITBenchmark = @import("benchmark/jit_benchmark.zig").JITBenchmark;
const JITBenchmarkConfig = @import("benchmark/jit_benchmark.zig").JITBenchmarkConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 配置测试参数
    const config = JITBenchmarkConfig{
        .warmup_iterations = 10,      // 预热迭代次数
        .test_iterations = 100,       // 测试迭代次数
        .verbose = true,              // 启用详细日志
        .code_cache_size = 1024 * 1024, // 代码缓存大小
    };
    
    // 初始化测试框架
    const benchmark = try JITBenchmark.init(allocator, config);
    defer benchmark.deinit();
    
    // 创建测试函数
    const func = createTestFunction();
    
    // 运行完整测试
    const result = try benchmark.runFullTest("my_test", func);
    
    // 生成报告
    try benchmark.generateReport(result, "report.md", .markdown);
}
```

### 批量测试

```zig
const TestScenarioConfig = @import("benchmark/jit_benchmark.zig").TestScenarioConfig;
const TestScenario = @import("benchmark/jit_benchmark.zig").TestScenario;

// 定义多个测试场景
const scenarios = [_]TestScenarioConfig{
    .{
        .name = "简单函数",
        .scenario = .simple_function,
    },
    .{
        .name = "循环密集型",
        .scenario = .loop_intensive,
        .loop_count = 1000,
    },
    .{
        .name = "数学计算密集型",
        .scenario = .math_intensive,
    },
};

// 运行批量测试
const results = try benchmark.runBatchTests(&scenarios);
defer allocator.free(results);

// 分析结果
for (results) |result| {
    std.debug.print("测试: {s}\n", .{result.test_name});
    std.debug.print("  加速比: {d:.2}x\n", .{result.speedup});
    std.debug.print("  编译时间: {d} ns\n", .{result.compile_stats.compile_time_ns});
}
```

## 测试场景

框架提供了多种预定义的测试场景：

### 1. 简单函数 (simple_function)

测试基本的算术运算，适合验证 JIT 编译器的基础功能。

```php
// 等价的 PHP 代码
function simple() {
    return 1 + 2;
}
```

### 2. 循环密集型 (loop_intensive)

测试循环优化能力，可配置循环次数。

```php
// 等价的 PHP 代码
function loop_intensive($count) {
    $sum = 0;
    for ($i = 0; $i < $count; $i++) {
        $sum += $i;
    }
    return $sum;
}
```

### 3. 数学计算密集型 (math_intensive)

测试数学运算的优化，包括乘法、除法等。

```php
// 等价的 PHP 代码
function math_intensive() {
    return (10 * 20) + (30 * 40) - (100 / 5);
}
```

### 4. 条件分支密集型 (branch_intensive)

测试条件分支的优化和预测。

```php
// 等价的 PHP 代码
function branch_intensive($x) {
    if ($x < 30) {
        return 1;
    } else if ($x < 70) {
        return 2;
    } else {
        return 3;
    }
}
```

### 5. 函数调用密集型 (call_intensive)

测试函数调用的优化和内联。

## 报告格式

框架支持多种报告格式：

### 1. Markdown 格式

生成易读的 Markdown 报告，包含：
- 编译性能统计
- 执行性能对比
- 详细的统计表格
- 性能分析建议

### 2. JSON 格式

生成机器可读的 JSON 报告，适合：
- 自动化分析
- CI/CD 集成
- 性能趋势追踪

### 3. CSV 格式

生成表格数据，适合：
- 数据分析
- 图表生成
- Excel 导入

### 4. HTML 格式

生成可视化的 HTML 报告，适合：
- 团队分享
- 演示展示
- 归档保存

## 性能指标解读

### 编译时间

- **< 100ms**：优秀，适合生产环境
- **100-500ms**：良好，可接受
- **> 500ms**：需要优化

### 加速比

- **> 10x**：优秀，JIT 带来显著性能提升
- **5-10x**：良好，JIT 有明显效果
- **2-5x**：一般，JIT 有一定效果
- **< 2x**：较差，需要优化 JIT 编译器

### 内存开销

- **< 10%**：优秀，内存开销可忽略
- **10-30%**：良好，可接受的开销
- **30-50%**：一般，需要关注
- **> 50%**：较差，需要优化内存使用

## 最佳实践

### 1. 预热

始终进行足够的预热迭代（建议 10-100 次），以确保：
- JIT 编译器已完成优化
- CPU 缓存已预热
- 操作系统调度稳定

### 2. 迭代次数

根据测试场景选择合适的迭代次数：
- **快速测试**：100-1000 次
- **标准测试**：1000-10000 次
- **精确测试**：10000+ 次

### 3. 环境控制

确保测试环境稳定：
- 关闭不必要的后台程序
- 固定 CPU 频率（禁用动态调频）
- 使用独立的测试机器

### 4. 结果分析

关注多个指标：
- 不仅看平均值，还要看中位数和百分位数
- 注意标准差，评估性能稳定性
- 对比多次测试结果，确保可重现性

## 集成到 CI/CD

### GitHub Actions 示例

```yaml
name: JIT Performance Tests

on: [push, pull_request]

jobs:
  jit-benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: '0.11.0'
      
      - name: Run JIT benchmarks
        run: |
          zig build jit-benchmark
          
      - name: Upload reports
        uses: actions/upload-artifact@v2
        with:
          name: jit-benchmark-reports
          path: |
            *.md
            *.json
            *.csv
```

## 故障排查

### 编译失败

如果 JIT 编译失败：
1. 检查错误消息
2. 验证字节码是否有效
3. 确认目标架构支持
4. 检查代码缓存是否已满

### 性能异常

如果性能结果异常：
1. 增加预热迭代次数
2. 检查系统负载
3. 验证测试代码是否正确
4. 对比多次运行结果

### 内存问题

如果内存使用过高：
1. 检查内存泄漏
2. 调整代码缓存大小
3. 优化测试函数
4. 使用内存分析工具

## 参考资料

- [需求文档](../specs/zig-php-performance-optimization/requirements.md) - 需求 6.5
- [设计文档](../specs/zig-php-performance-optimization/design.md) - JIT 编译器设计
- [任务列表](../specs/zig-php-performance-optimization/tasks.md) - 任务 39

## 示例输出

### 控制台输出

```
================================================================================
JIT 性能测试套件
================================================================================

=== JIT 性能测试: 简单函数 ===

[编译阶段]
编译时间: 1234567 ns
代码大小: 128 bytes
内存分配: 512 bytes

[JIT 执行阶段]
JIT 执行预热中... (10 次迭代)
JIT 执行测试中... (100 次迭代)
  完成 10/100
  完成 20/100
  ...
平均执行时间: 45.23 ns
中位数: 44.50 ns
标准差: 3.21 ns

[解释执行阶段]
解释执行预热中... (10 次迭代)
解释执行测试中... (100 次迭代)
  完成 10/100
  完成 20/100
  ...
平均执行时间: 523.45 ns
中位数: 520.30 ns
标准差: 15.67 ns

[性能对比]
加速比: 11.57x
内存开销: 5.2%

================================================================================
测试汇总
================================================================================

总测试数: 5
成功测试: 5
平均加速比: 9.34x
平均内存开销: 8.1%

生成详细报告...
  ✓ jit_benchmark_0_简单函数.md
  ✓ jit_benchmark_0_简单函数.json
  ...

测试完成！
```

## 未来改进

计划中的功能增强：

1. **更多测试场景**
   - 字符串操作密集型
   - 数组操作密集型
   - 对象操作密集型

2. **高级分析**
   - 性能火焰图生成
   - 热点代码识别
   - 优化建议生成

3. **对比分析**
   - 与原生 PHP 对比
   - 历史性能趋势
   - 跨版本对比

4. **自动化优化**
   - 自动调整编译参数
   - 智能场景选择
   - 性能回归自动检测
