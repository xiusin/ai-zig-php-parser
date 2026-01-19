# AOT 编译器性能测试文档

## 概述

AOT 性能测试框架提供了完整的 AOT 编译器性能评估功能，包括编译时间、可执行文件大小、启动时间和执行时间的测量。

## 功能特性

### 1. 编译时间测量
- 测量 PHP 源代码编译为原生可执行文件的时间
- 支持多次迭代和预热
- 提供平均值、中位数、标准差等统计数据

### 2. 可执行文件大小测量
- 测量生成的可执行文件大小
- 支持段大小分析（文本段、数据段、BSS段）
- 与原生 PHP 脚本大小对比

### 3. 启动时间测量
- 测量可执行文件的启动时间
- 包括进程创建和初始化开销
- 高精度微秒级测量

### 4. 执行时间测量
- 测量 AOT 编译后的执行时间
- 与原生 PHP 执行时间对比
- 计算加速比

## 使用方法

### 基本用法

```zig
const std = @import("std");
const AOTBenchmark = @import("benchmark/aot_benchmark.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 初始化框架
    var framework = try AOTBenchmark.AOTBenchmarkFramework.init(allocator, .{
        .warmup_iterations = 10,
        .test_iterations = 100,
        .verbose = true,
    });
    defer framework.deinit();
    
    // 运行完整测试
    const result = try framework.runFullBenchmark("test.php");
    
    // 生成报告
    try framework.generateReport(result, "report.md", .markdown);
}
```

### 配置选项

```zig
pub const AOTBenchmarkConfig = struct {
    /// 预热迭代次数（默认：10）
    warmup_iterations: u32 = 10,
    
    /// 测试迭代次数（默认：100）
    test_iterations: u32 = 100,
    
    /// 超时时间（毫秒，默认：60000）
    timeout_ms: u64 = 60000,
    
    /// 是否启用详细日志（默认：false）
    verbose: bool = false,
    
    /// PHP 可执行文件路径（默认："php"）
    php_executable: []const u8 = "php",
    
    /// AOT 编译器路径（默认："./zig-php-aot"）
    aot_compiler: []const u8 = "./zig-php-aot",
    
    /// 临时目录（默认："/tmp/aot_benchmark"）
    temp_dir: []const u8 = "/tmp/aot_benchmark",
    
    /// 编译优化级别（默认："ReleaseFast"）
    optimize_level: []const u8 = "ReleaseFast",
};
```

## 测试结果

### 结果结构

```zig
pub const AOTBenchmarkResult = struct {
    /// 测试名称
    test_name: []const u8,
    
    /// 编译时间统计
    compile_time: CompileTimeStats,
    
    /// 可执行文件大小统计
    executable_size: ExecutableSizeStats,
    
    /// 启动时间统计
    startup_time: StartupTimeStats,
    
    /// 执行时间统计（AOT）
    aot_execution_time: ExecutionTimeStats,
    
    /// 执行时间统计（PHP）
    php_execution_time: ExecutionTimeStats,
    
    /// 加速比（PHP时间 / AOT时间）
    speedup: f64,
    
    /// 测试时间戳
    timestamp: i64,
};
```

### 统计数据

#### 编译时间统计
```zig
pub const CompileTimeStats = struct {
    mean_ms: f64,        // 平均编译时间（毫秒）
    median_ms: f64,      // 中位数编译时间（毫秒）
    std_dev_ms: f64,     // 标准差（毫秒）
    min_ms: u64,         // 最小编译时间（毫秒）
    max_ms: u64,         // 最大编译时间（毫秒）
    iterations: u32,     // 迭代次数
};
```

#### 可执行文件大小统计
```zig
pub const ExecutableSizeStats = struct {
    size_bytes: u64,         // 可执行文件大小（字节）
    text_size_bytes: u64,    // 文本段大小（字节）
    data_size_bytes: u64,    // 数据段大小（字节）
    bss_size_bytes: u64,     // BSS 段大小（字节）
};
```

#### 启动时间统计
```zig
pub const StartupTimeStats = struct {
    mean_us: f64,        // 平均启动时间（微秒）
    median_us: f64,      // 中位数启动时间（微秒）
    std_dev_us: f64,     // 标准差（微秒）
    min_us: u64,         // 最小启动时间（微秒）
    max_us: u64,         // 最大启动时间（微秒）
    iterations: u32,     // 迭代次数
};
```

#### 执行时间统计
```zig
pub const ExecutionTimeStats = struct {
    mean_ns: f64,        // 平均执行时间（纳秒）
    median_ns: f64,      // 中位数执行时间（纳秒）
    std_dev_ns: f64,     // 标准差（纳秒）
    min_ns: u64,         // 最小执行时间（纳秒）
    max_ns: u64,         // 最大执行时间（纳秒）
    p95_ns: u64,         // 第 95 百分位数（纳秒）
    p99_ns: u64,         // 第 99 百分位数（纳秒）
    iterations: u32,     // 迭代次数
};
```

## 报告格式

### Markdown 报告

```markdown
# AOT 性能测试报告: test.php

**测试时间**: 1705478400

## 总体结果

- **加速比**: 15.23x

## 编译时间

| 指标 | 值 |
|------|-----|
| 平均值 | 1234.56 ms |
| 中位数 | 1200.00 ms |
| 标准差 | 45.67 ms |

## 可执行文件大小

| 指标 | 值 |
|------|-----|
| 文件大小 | 524288 bytes (512.00 KB) |

## 启动时间

| 指标 | 值 |
|------|-----|
| 平均值 | 123.45 μs |
| 中位数 | 120.00 μs |

## 执行时间对比

| 指标 | AOT | PHP | 改进 |
|------|-----|-----|------|
| 平均值 (ns) | 1000000 | 15230000 | 93.4% |
| 中位数 (ns) | 980000 | 15000000 | 93.5% |
```

### JSON 报告

```json
{
  "test_name": "test.php",
  "timestamp": 1705478400,
  "speedup": 15.23,
  "compile_time": {
    "mean_ms": 1234.56,
    "median_ms": 1200.00,
    "std_dev_ms": 45.67
  },
  "executable_size": {
    "size_bytes": 524288
  },
  "startup_time": {
    "mean_us": 123.45,
    "median_us": 120.00
  },
  "aot_execution_time": {
    "mean_ns": 1000000,
    "median_ns": 980000
  },
  "php_execution_time": {
    "mean_ns": 15230000,
    "median_ns": 15000000
  }
}
```

### CSV 报告

```csv
metric,value,unit
compile_time_mean,1234.56,ms
compile_time_median,1200.00,ms
executable_size,524288,bytes
startup_time_mean,123.45,us
aot_execution_mean,1000000,ns
php_execution_mean,15230000,ns
speedup,15.23,x
```

## 性能目标

根据需求 6.6，AOT 编译器应达到以下性能目标：

### 编译时间
- **目标**: < 10s/文件
- **测量方法**: 多次编译取平均值
- **优化方向**: 并行编译、增量编译、缓存优化

### 可执行文件大小
- **目标**: 合理的文件大小（< 10MB for simple scripts）
- **测量方法**: 直接测量文件系统大小
- **优化方向**: 代码压缩、死代码消除、符号剥离

### 启动时间
- **目标**: < 原生 PHP 的 150%
- **测量方法**: 进程启动到第一条指令执行的时间
- **优化方向**: 减少初始化开销、延迟加载

### 执行时间
- **目标**: 达到原生 PHP 的 120%+
- **测量方法**: 完整程序执行时间
- **优化方向**: 代码优化、内联、SIMD

## 最佳实践

### 1. 测试脚本选择
- 选择代表性的工作负载
- 包含不同类型的操作（计算、I/O、字符串处理等）
- 避免过于简单或复杂的测试

### 2. 迭代次数设置
- 预热迭代：10-20 次
- 测试迭代：100-1000 次
- 根据测试时间调整

### 3. 环境控制
- 关闭不必要的后台进程
- 固定 CPU 频率
- 使用相同的硬件和操作系统

### 4. 结果分析
- 关注中位数而非平均值（更稳定）
- 检查标准差（评估稳定性）
- 分析百分位数（识别异常值）

## 示例测试脚本

### 简单数学运算
```php
<?php
function fibonacci($n) {
    if ($n <= 1) return $n;
    return fibonacci($n - 1) + fibonacci($n - 2);
}

echo fibonacci(20);
```

### 字符串操作
```php
<?php
$text = str_repeat("hello world ", 1000);
for ($i = 0; $i < 100; $i++) {
    $text = str_replace("world", "PHP", $text);
}
echo strlen($text);
```

### 数组操作
```php
<?php
$numbers = range(1, 1000);
$sum = array_reduce($numbers, function($carry, $item) {
    return $carry + $item;
}, 0);
echo $sum;
```

## 故障排除

### 编译失败
- 检查 AOT 编译器路径
- 验证 PHP 脚本语法
- 查看编译器错误输出

### 执行失败
- 检查可执行文件权限
- 验证依赖库
- 查看运行时错误

### 性能异常
- 检查系统负载
- 验证测试脚本
- 增加迭代次数

## 参考资料

- [需求文档](../requirements.md) - 需求 6.6
- [设计文档](../design.md) - AOT 编译器设计
- [JIT 性能测试](JIT_PERFORMANCE_TESTING.md) - JIT 性能测试文档

## 版本历史

- **v1.0** (2026-01-19): 初始版本
  - 编译时间测量
  - 可执行文件大小测量
  - 启动时间测量
  - 执行时间测量
  - 多格式报告生成
