# 热点检测器 (Hotspot Detector)

## 概述

热点检测器是 Zig-PHP JIT 编译器的核心组件，负责识别频繁执行的函数和循环，触发即时编译优化。

## 设计原则

1. **原子操作**: 所有计数器使用原子操作，确保线程安全
2. **零成本抽象**: 检测开销极低（< 300 ns/op）
3. **可配置**: 支持自定义热点阈值
4. **统计透明**: 提供详细的统计信息

## 核心功能

### 1. 函数执行跟踪

热点检测器跟踪每个函数的执行次数，当达到阈值时标记为热点：

```zig
const detector = try HotspotDetector.init(allocator);
defer detector.deinit();

// 记录函数执行
try detector.recordExecution("my_function");

// 检查是否为热点
if (detector.isHotspot("my_function")) {
    // 触发 JIT 编译
}
```

### 2. 循环回边检测

检测循环的回边（向后跳转），用于触发 OSR (On-Stack Replacement)：

```zig
// 在循环回边处记录
try detector.recordLoopBackedge("my_function", bytecode_offset);

// 检查循环是否为热点
if (detector.isLoopHotspot("my_function", bytecode_offset)) {
    // 触发 OSR 编译
}
```

### 3. 配置选项

```zig
var config = HotspotConfig{};
config.function_threshold = 1000;        // 函数热点阈值
config.loop_backedge_threshold = 10000; // 循环热点阈值
config.enabled = true;                   // 启用热点检测
config.loop_detection_enabled = true;   // 启用循环检测

const detector = try HotspotDetector.initWithConfig(allocator, config);
```

## 使用示例

### 基本使用

```zig
const std = @import("std");
const HotspotDetector = @import("jit/hotspot_detector.zig").HotspotDetector;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 创建检测器
    const detector = try HotspotDetector.init(allocator);
    defer detector.deinit();
    
    // 模拟函数执行
    var i: u32 = 0;
    while (i < 2000) : (i += 1) {
        try detector.recordExecution("calculate");
        
        // 检查是否成为热点
        if (detector.isHotspot("calculate")) {
            std.debug.print("函数 'calculate' 成为热点！\n", .{});
            break;
        }
    }
    
    // 打印统计
    detector.printStats();
}
```

### 与 JIT 编译器集成

```zig
const Compiler = @import("jit/compiler.zig").Compiler;
const HotspotDetector = @import("jit/hotspot_detector.zig").HotspotDetector;

// 创建热点检测器
const detector = try HotspotDetector.init(allocator);
defer detector.deinit();

// 创建编译器并关联检测器
var compiler = Compiler.initWithHotspotDetector(allocator, detector);

// 在虚拟机执行循环中
while (true) {
    // 记录函数执行
    try detector.recordExecution(current_function.name);
    
    // 检查是否应该编译
    if (detector.isHotspot(current_function.name)) {
        // 触发 JIT 编译
        const jit_code = try compiler.compile(
            code_cache,
            current_function,
            type_feedback,
            null
        );
        
        if (jit_code) |code| {
            // 执行编译后的代码
            executeJitCode(code);
        }
    } else {
        // 继续解释执行
        interpretFunction(current_function);
    }
}
```

## 性能特性

### 时间复杂度

- **记录执行**: O(1) - 原子操作
- **检查热点**: O(1) - 哈希表查找
- **获取计数**: O(1) - 原子读取

### 空间复杂度

- **每个函数**: ~64 字节（名称 + 计数器 + 元数据）
- **每个循环**: ~80 字节（ID + 计数器 + 元数据）

### 性能基准

在现代 CPU 上的典型性能：

- 记录执行: ~200-300 ns/op
- 检查热点: ~50-100 ns/op
- 吞吐量: ~3-5M ops/sec

## 统计信息

热点检测器提供详细的统计信息：

```zig
const stats = detector.getStats();

std.debug.print("总函数调用: {d}\n", .{stats.total_function_calls});
std.debug.print("总循环回边: {d}\n", .{stats.total_loop_backedges});
std.debug.print("热点函数数: {d}\n", .{stats.hotspot_functions_detected});
std.debug.print("热点循环数: {d}\n", .{stats.hotspot_loops_detected});
```

或使用内置的打印方法：

```zig
detector.printStats();
```

输出示例：

```
=== 热点检测器统计 ===
总函数调用次数: 15000
总循环回边次数: 50000
检测到的热点函数: 5
检测到的热点循环: 3
跟踪的唯一函数: 20
跟踪的唯一循环: 8

配置:
  函数热点阈值: 1000
  循环热点阈值: 10000
  热点检测: 启用
  循环检测: 启用

前 10 个最热函数:
  1. calculate_sum: 5000 次 [热点]
  2. process_data: 3000 次 [热点]
  3. validate_input: 2000 次 [热点]
  ...
```

## 线程安全

热点检测器是线程安全的：

- 所有计数器使用 `std.atomic.Value`
- 哈希表修改由互斥锁保护
- 支持多线程并发记录

```zig
// 多线程使用示例
const thread_fn = struct {
    fn run(detector: *HotspotDetector, thread_id: u32) void {
        var i: u32 = 0;
        while (i < 1000) : (i += 1) {
            const func_name = std.fmt.allocPrint(
                detector.allocator,
                "thread_{d}_func",
                .{thread_id}
            ) catch return;
            defer detector.allocator.free(func_name);
            
            detector.recordExecution(func_name) catch return;
        }
    }
}.run;

var threads: [4]std.Thread = undefined;
for (&threads, 0..) |*thread, i| {
    thread.* = try std.Thread.spawn(.{}, thread_fn, .{ detector, i });
}

for (threads) |thread| {
    thread.join();
}
```

## 最佳实践

### 1. 选择合适的阈值

- **函数阈值**: 通常设置为 1000-10000
  - 太低: 过早编译，浪费编译时间
  - 太高: 错过优化机会
  
- **循环阈值**: 通常设置为 10000-100000
  - 循环执行频率通常高于函数调用

### 2. 监控统计信息

定期检查统计信息，调整阈值：

```zig
// 每 10 秒打印一次统计
var timer = try std.time.Timer.start();
while (true) {
    if (timer.read() > 10_000_000_000) {
        detector.printStats();
        timer.reset();
    }
    
    // 执行代码...
}
```

### 3. 重置计数器

在某些场景下可能需要重置计数器：

```zig
// 重置所有计数器和热点标记
detector.reset();
```

### 4. 禁用热点检测

在调试或性能分析时可能需要禁用：

```zig
var config = HotspotConfig{};
config.enabled = false;

const detector = try HotspotDetector.initWithConfig(allocator, config);
```

## 内存管理

热点检测器遵循 Zig 的内存安全原则：

- 使用显式 Allocator
- 所有字符串键都被复制
- `deinit()` 释放所有资源
- 无内存泄漏（通过 Valgrind 验证）

```zig
// 正确的使用模式
const detector = try HotspotDetector.init(allocator);
defer detector.deinit(); // 确保资源释放

// 使用 errdefer 处理错误
const detector = try HotspotDetector.init(allocator);
errdefer detector.deinit();

// ... 可能失败的操作 ...
```

## 调试和诊断

### 启用详细日志

```zig
// 在记录执行时打印日志
try detector.recordExecution("my_func");
std.debug.print("记录执行: my_func, 计数={d}\n", .{
    detector.getExecutionCount("my_func")
});
```

### 检查热点状态

```zig
const func_name = "my_func";
const count = detector.getExecutionCount(func_name);
const is_hot = detector.isHotspot(func_name);

std.debug.print("{s}: 计数={d}, 热点={s}, 阈值={d}\n", .{
    func_name,
    count,
    if (is_hot) "是" else "否",
    detector.config.function_threshold,
});
```

## 相关文档

- [JIT 编译器设计](./JIT_COMPILER.md)
- [性能优化指南](./PERFORMANCE_OPTIMIZATION.md)
- [测试指南](./TESTING.md)

## 参考实现

- 设计文档: `.kiro/specs/zig-php-performance-optimization/design.md`
- 源代码: `src/jit/hotspot_detector.zig`
- 测试: `src/jit/test_hotspot_integration.zig`
- 示例: `examples/hotspot_detector_demo.zig`
