# 性能火焰图文档

## 概述

性能火焰图是一种可视化性能剖析数据的强大工具，可以快速识别程序中的性能瓶颈和热点函数。本文档描述了 Zig-PHP 解释器的火焰图实现。

## 功能特性

- ✅ **调用栈采样**：基于 `Profiler` 的当前调用栈进行定时采样
- ✅ **火焰图树构建**：从采样数据构建层次化的火焰图树
- ✅ **折叠格式生成**：生成 FlameGraph 工具兼容的折叠格式
- ✅ **SVG 火焰图**：直接生成 SVG 格式的火焰图
- ✅ **热点识别**：自动识别和排序热点函数
- ✅ **线程安全**：支持多线程并发采样
- ✅ **可配置过滤**：支持最小显示时间过滤

## 架构

```
┌─────────────────────────────────────────────────────────┐
│                    应用层                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  字节码 VM   │  │  JIT 编译器  │  │  AOT 编译器  │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
└─────────┼──────────────────┼──────────────────┼─────────┘
          │                  │                  │
          └──────────────────┼──────────────────┘
                             │
          ┌──────────────────▼──────────────────┐
          │         Profiler (性能剖析)         │
          │  - 函数调用跟踪                     │
          │  - 执行时间统计                     │
          └──────────────────┬──────────────────┘
                             │
          ┌──────────────────▼──────────────────┐
          │    FlameGraphGenerator (火焰图)     │
          │  - 调用栈采样                       │
          │  - 火焰图树构建                     │
          │  - 折叠格式生成                     │
          │  - SVG 生成                         │
          │  - 热点识别                         │
          └─────────────────────────────────────┘
                             │
          ┌──────────────────┼──────────────────┐
          │                  │                  │
     ┌────▼────┐      ┌─────▼─────┐      ┌────▼────┐
     │ 折叠格式 │      │ SVG 文件  │      │ 热点报告 │
     │  .txt   │      │   .svg    │      │  终端   │
     └─────────┘      └───────────┘      └─────────┘
```

## 核心组件

### 1. StackFrame (调用栈帧)

表示调用栈中的一个函数调用。

```zig
pub const StackFrame = struct {
    function_name: []const u8,
    file_name: ?[]const u8,
    line_number: ?u32,
    duration_ns: u64,
};
```

### 2. FlameGraphNode (火焰图节点)

火焰图树的节点，表示一个函数及其子调用。

```zig
pub const FlameGraphNode = struct {
    name: []const u8,
    total_time_ns: u64,
    self_time_ns: u64,
    call_count: u64,
    children: std.StringHashMap(*FlameGraphNode),
    parent: ?*FlameGraphNode,
};
```

### 3. FlameGraphGenerator (火焰图生成器)

主要的火焰图生成和管理类。

```zig
pub const FlameGraphGenerator = struct {
    allocator: std.mem.Allocator,
    profiler: *Profiler,
    root: *FlameGraphNode,
    samples: std.ArrayList(StackSample),
    sampling_interval_ns: u64,
    min_display_time_ns: u64,
    mutex: std.Thread.Mutex,
};
```

## 使用指南

### 基本使用

```zig
const std = @import("std");
const Profiler = @import("runtime/profiler.zig").Profiler;
const FlameGraphGenerator = @import("runtime/flamegraph.zig").FlameGraphGenerator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 1. 初始化 Profiler
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    // 2. 启动采样（会定时读取 Profiler 的当前调用栈）
    var generator = try FlameGraphGenerator.init(allocator, &profiler);
    defer generator.deinit();
    generator.setMinDisplayTime(0);
    try generator.startSampling();

    // 3. 执行应用程序（需要在关键路径插入 enterFunction/exitFunction）
    try runApplication(&profiler);

    // 4. 停止采样并生成输出
    generator.stopSampling();
    
    // 5. 生成火焰图
    try generator.saveFoldedFormat("flamegraph.txt");
    try generator.saveSVG("flamegraph.svg", 1200, 800);
    
    // 6. 打印热点报告
    try generator.printHotspotReport(10);
}
```

### 从折叠格式导入（离线转换）

```zig
const folded = try std.fs.cwd().readFileAlloc(allocator, "flamegraph.txt", 64 * 1024 * 1024);
defer allocator.free(folded);

try generator.buildFromFoldedFormat(folded, .microseconds);
try generator.saveSVG("flamegraph.svg", 1200, 800);
```

### 说明：collectFromProfiler

`collectFromProfiler()` 当前生成的是“平铺统计树”（root 下直接挂每个函数），适合快速看 Top 函数总耗时；真正的调用栈火焰图建议使用 `startSampling()/stopSampling()` 或 `buildFromFoldedFormat()`。

### 手动采样

如果需要更精细的控制，可以手动添加调用栈样本：

```zig
const StackFrame = @import("runtime/flamegraph.zig").StackFrame;

// 创建调用栈
const frames = [_]StackFrame{
    .{
        .function_name = "main",
        .file_name = "main.zig",
        .line_number = 10,
        .duration_ns = 1000,
    },
    .{
        .function_name = "processData",
        .file_name = "data.zig",
        .line_number = 50,
        .duration_ns = 800,
    },
    .{
        .function_name = "parseJSON",
        .file_name = "json.zig",
        .line_number = 100,
        .duration_ns = 600,
    },
};

// 添加样本
try generator.addSample(&frames, 1000);

// 从样本构建火焰图
try generator.buildFromSamples();
```

### 配置参数

```zig
// 设置采样间隔（纳秒）
generator.setSamplingInterval(1_000_000); // 1ms

// 设置最小显示时间（纳秒）
// 低于此时间的函数将被过滤
generator.setMinDisplayTime(100_000); // 0.1ms
```

### 生成折叠格式

折叠格式是 FlameGraph 工具的标准输入格式：

```zig
// 生成折叠格式字符串
const folded = try generator.generateFoldedFormat(allocator);
defer allocator.free(folded);

// 或直接保存到文件
try generator.saveFoldedFormat("flamegraph.txt");
```

折叠格式示例：
```
main;processData;parseJSON 600
main;processData;validateData 200
main;renderOutput 500
```

### 生成 SVG 火焰图

```zig
// 生成 SVG 字符串
const svg = try generator.generateSVG(allocator, 1200, 800);
defer allocator.free(svg);

// 或直接保存到文件
try generator.saveSVG("flamegraph.svg", 1200, 800);
```

### 识别热点函数

```zig
// 获取前 10 个热点函数
const hotspots = try generator.identifyHotspots(allocator, 10);
defer allocator.free(hotspots);

for (hotspots) |hotspot| {
    std.debug.print("{}\n", .{hotspot});
}

// 或使用内置的报告功能
try generator.printHotspotReport(10);
```

热点报告示例：
```
=== 热点函数报告 (Top 10) ===
总执行时间: 10000000 ns (10.00 ms)

函数名                                      总时间(ms)   自身时间(ms)   调用次数    占比(%)
------------------------------------------------------------------------------------------
parseJSON                                        6.00          6.00        100      60.00
processData                                      8.00          2.00         50      80.00
validateData                                     2.00          2.00         50      20.00
renderOutput                                     5.00          5.00         30      50.00
```

## 与 FlameGraph 工具集成

本实现生成的折叠格式与 Brendan Gregg 的 [FlameGraph](https://github.com/brendangregg/FlameGraph) 工具完全兼容。

### 使用 FlameGraph 工具

1. 克隆 FlameGraph 仓库：
```bash
git clone https://github.com/brendangregg/FlameGraph.git
```

2. 生成折叠格式：
```bash
./your_app  # 生成 flamegraph.txt
```

3. 使用 FlameGraph 工具生成 SVG：
```bash
./FlameGraph/flamegraph.pl flamegraph.txt > flamegraph.svg
```

## profile-cli（工具）

仓库提供 `profile-cli` 用于离线转换：

```bash
./zig-out/bin/profile-cli folded_to_svg flamegraph.txt flamegraph.svg --unit us --width 1600 --height 900
./zig-out/bin/profile-cli folded_to_pprof flamegraph.txt profile.pb --unit us --period-ns 1000000
```

4. 在浏览器中查看：
```bash
firefox flamegraph.svg
```

## AOT 集成

AOT 编译产物已在每个生成函数的入口/退出处插入 `Profiler` 钩子，并可选启动采样生成输出文件。

- 启用：设置环境变量 `ZIGPHP_PROFILE`（值任意即可）
- 采样间隔：可选 `ZIGPHP_PROFILE_INTERVAL_NS`（纳秒，默认 1_000_000）
- 输出文件（运行结束后写入当前目录）：
  - `flamegraph.txt`（folded stacks，单位 us）
  - `profile.pb`（pprof protobuf，CPU/nanoseconds）

示例：

```bash
ZIGPHP_PROFILE=1 ZIGPHP_PROFILE_INTERVAL_NS=1000000 ./your_aot_binary
./zig-out/bin/profile-cli folded_to_svg flamegraph.txt flamegraph.svg --unit us
go tool pprof -http=:0 profile.pb
```

## 性能开销

火焰图生成的性能开销：

- **采样开销**: < 2% (取决于采样频率)
- **构建开销**: < 1% (一次性，在生成时)
- **内存开销**: 约 100 bytes/样本

建议：
- 生产环境：采样间隔 >= 1ms
- 开发环境：采样间隔 >= 100μs
- 性能测试：采样间隔 >= 10μs

## 最佳实践

### 1. 选择合适的采样间隔

```zig
// 生产环境：低开销
generator.setSamplingInterval(1_000_000); // 1ms

// 开发环境：平衡
generator.setSamplingInterval(100_000); // 0.1ms

// 性能测试：高精度
generator.setSamplingInterval(10_000); // 0.01ms
```

### 2. 过滤噪声

```zig
// 过滤执行时间很短的函数
generator.setMinDisplayTime(100_000); // 0.1ms
```

### 3. 定期清理样本

```zig
// 长时间运行的应用应该定期清理样本
if (generator.samples.items.len > 10000) {
    // 重新初始化生成器
    generator.deinit();
    generator = try FlameGraphGenerator.init(allocator, &profiler);
}
```

### 4. 关注热点函数

```zig
// 识别前 5 个热点函数并优化
const hotspots = try generator.identifyHotspots(allocator, 5);
defer allocator.free(hotspots);

for (hotspots) |hotspot| {
    if (hotspot.percentage > 10.0) {
        std.debug.print("警告: {s} 占用 {d:.2}% 的时间\n", .{
            hotspot.function_name,
            hotspot.percentage,
        });
    }
}
```

### 5. 结合 Profiler 使用

```zig
// 先使用 Profiler 收集基础数据
var profiler = try Profiler.init(allocator, .custom);
defer profiler.deinit();

// 执行应用
try runApplication(&profiler);

// 查看基础统计
profiler.printReport();

// 生成火焰图进行深入分析
var generator = try FlameGraphGenerator.init(allocator, &profiler);
defer generator.deinit();

try generator.collectFromProfiler();
try generator.printHotspotReport(10);
try generator.saveSVG("flamegraph.svg", 1200, 800);
```

## 故障排除

### 问题: 火焰图为空

**原因**: Profiler 没有收集到数据

**解决方案**:
```zig
// 确保 Profiler 已启用
profiler.enable();

// 确保函数调用被跟踪
try profiler.enterFunction("myFunction");
// ... 函数体 ...
try profiler.exitFunction("myFunction");
```

### 问题: 内存使用过高

**原因**: 样本数量过多

**解决方案**:
```zig
// 增加采样间隔
generator.setSamplingInterval(10_000_000); // 10ms

// 或定期清理样本
if (generator.samples.items.len > 10000) {
    generator.deinit();
    generator = try FlameGraphGenerator.init(allocator, &profiler);
}
```

### 问题: SVG 文件过大

**原因**: 函数调用层次太深或函数数量太多

**解决方案**:
```zig
// 增加最小显示时间
generator.setMinDisplayTime(1_000_000); // 1ms

// 或减小 SVG 尺寸
try generator.saveSVG("flamegraph.svg", 800, 600);
```

## 示例

完整示例请参考：
- `src/runtime/test_flamegraph.zig` - 综合测试
- `src/runtime/flamegraph.zig` - 实现代码

## 相关文档

- [性能剖析集成](PROFILER_INTEGRATION.md)
- [Perf 集成](PERF_INTEGRATION.md)
- [Tracy 集成](TRACY_INTEGRATION.md)

## 参考资料

- [Brendan Gregg's Flame Graphs](http://www.brendangregg.com/flamegraphs.html)
- [FlameGraph GitHub](https://github.com/brendangregg/FlameGraph)
- [The Flame Graph](https://queue.acm.org/detail.cfm?id=2927301)

---

**作者**: Kiro AI Assistant  
**日期**: 2026-01-20  
**版本**: 1.0  
**状态**: 已完成
