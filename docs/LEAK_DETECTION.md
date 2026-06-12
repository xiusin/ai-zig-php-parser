# 内存泄漏检测系统

## 概述

Zig-PHP 内存泄漏检测系统提供完整的内存分配追踪和泄漏分析功能，帮助开发者快速定位和修复内存泄漏问题。

## 特性

### 1. 分配栈跟踪

系统自动捕获每次内存分配的调用栈，包括：
- 返回地址
- 函数名（如果可用）
- 文件名和行号（如果可用）
- 完整的调用链

### 2. 泄漏报告生成

生成详细的泄漏分析报告，包括：
- 统计信息（总分配、总释放、活跃分配等）
- 每个泄漏的详细信息（地址、大小、类型、存活时间、调用栈）
- 按类型汇总的泄漏统计
- 泄漏模式分析

### 3. 实时监控

实时追踪内存分配和释放：
- 当前内存使用量
- 峰值内存使用量
- 分配/释放速率
- 活跃分配数量

### 4. 修复建议

基于泄漏模式自动生成修复建议：
- 资源清理检查
- 错误处理审查
- 针对特定类型的建议
- 工具使用建议

## 架构

```
┌─────────────────────────────────────────────────────┐
│           Memory Leak Detection System              │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │
│  │  Allocation  │  │  Stack       │  │  Leak     │ │
│  │  Tracker     │  │  Tracer      │  │  Reporter │ │
│  └──────────────┘  └──────────────┘  └───────────┘ │
│         │                 │                 │        │
│         └─────────────────┴─────────────────┘        │
│                           │                          │
│                    ┌──────▼──────┐                   │
│                    │  Analyzer   │                   │
│                    └──────┬──────┘                   │
│                           │                          │
│                    ┌──────▼──────┐                   │
│                    │  Report     │                   │
│                    │  Generator  │                   │
│                    └─────────────┘                   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## 使用方法

### 基本使用

```zig
const std = @import("std");
const LeakDetector = @import("runtime/leak_detector.zig").LeakDetector;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 初始化泄漏检测器
    var detector = try LeakDetector.init(allocator);
    defer detector.deinit();
    
    // 记录分配
    const data = try allocator.alloc(u8, 1024);
    try detector.recordAllocation(@intFromPtr(data.ptr), 1024, "u8");
    
    // 使用数据...
    
    // 记录释放
    detector.recordFree(@intFromPtr(data.ptr));
    allocator.free(data);
    
    // 生成泄漏报告
    try detector.generateReport(std.io.getStdOut().writer());
}
```

### 集成到自定义 Allocator

```zig
const LeakDetector = @import("runtime/leak_detector.zig").LeakDetector;

pub const TrackedAllocator = struct {
    parent_allocator: std.mem.Allocator,
    leak_detector: *LeakDetector,
    
    pub fn init(parent: std.mem.Allocator, detector: *LeakDetector) TrackedAllocator {
        return .{
            .parent_allocator = parent,
            .leak_detector = detector,
        };
    }
    
    pub fn allocator(self: *TrackedAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }
    
    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *TrackedAllocator = @ptrCast(@alignCast(ctx));
        
        const result = self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);
        if (result) |ptr| {
            self.leak_detector.recordAllocation(
                @intFromPtr(ptr),
                len,
                "unknown",
            ) catch {};
        }
        
        return result;
    }
    
    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *TrackedAllocator = @ptrCast(@alignCast(ctx));
        
        self.leak_detector.recordFree(@intFromPtr(buf.ptr));
        self.parent_allocator.rawFree(buf, buf_align, ret_addr);
    }
    
    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *TrackedAllocator = @ptrCast(@alignCast(ctx));
        return self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);
    }
};
```

### 泄漏分析

```zig
const LeakAnalyzer = @import("runtime/leak_detector.zig").LeakAnalyzer;

pub fn analyzeLeaks(detector: *LeakDetector) !void {
    var analyzer = LeakAnalyzer.init(allocator, detector);
    
    // 分析泄漏模式
    var pattern = try analyzer.analyzeLeakPatterns();
    defer pattern.deinit(allocator);
    
    std.debug.print("Total leaks: {d}\n", .{pattern.total_leaks});
    std.debug.print("Total leaked bytes: {d}\n", .{pattern.total_leaked_bytes});
    std.debug.print("Most common type: {s}\n", .{pattern.most_common_type orelse "N/A"});
    std.debug.print("Largest leak: {d} bytes\n", .{pattern.largest_leak_size});
    std.debug.print("Average leak: {d} bytes\n", .{pattern.average_leak_size});
    
    // 生成修复建议
    try analyzer.generateFixSuggestions(std.io.getStdOut().writer());
}
```

## 报告格式

### 示例报告

```
=== Memory Leak Detection Report ===

Statistics:
  Total Allocations: 100
  Total Frees: 95
  Active Allocations: 5
  Total Allocated: 10240 bytes
  Total Freed: 9500 bytes
  Current Usage: 740 bytes
  Peak Usage: 10240 bytes

⚠ Detected 5 memory leak(s):

Leak #1:
  Address: 0x7f8a4c000000
  Size: 256 bytes
  Type: String
  Allocated at: 1642512345678 ms
  Lifetime: 12345 ms
  Stack trace:
    #0: allocString at string.zig:42
    #1: parseExpression at parser.zig:156
    #2: compile at compiler.zig:89
    #3: main at main.zig:23

Leak #2:
  Address: 0x7f8a4c000100
  Size: 128 bytes
  Type: Array
  Allocated at: 1642512345789 ms
  Lifetime: 12234 ms
  Stack trace:
    #0: allocArray at array.zig:67
    #1: createArrayLiteral at parser.zig:234
    #2: compile at compiler.zig:89
    #3: main at main.zig:23

...

Summary by Type:
  String: 3 leak(s), 512 bytes
  Array: 1 leak(s), 128 bytes
  Object: 1 leak(s), 100 bytes
```

## 性能考虑

### 开销

内存泄漏检测会带来一定的性能开销：

- **内存开销**：每个分配记录约 200-300 字节
- **时间开销**：每次分配/释放约 1-2 微秒
- **栈跟踪开销**：捕获栈跟踪约 5-10 微秒

### 优化建议

1. **仅在 Debug 模式启用**
   ```zig
   const leak_detection_enabled = builtin.mode == .Debug;
   ```

2. **选择性启用**
   ```zig
   detector.disable(); // 禁用检测
   // 执行性能关键代码
   detector.enable(); // 重新启用
   ```

3. **限制栈深度**
   ```zig
   const MAX_STACK_DEPTH = 16; // 减少栈跟踪深度
   ```

4. **定期清理**
   ```zig
   // 定期清理已释放的记录
   if (detector.getStats().total_frees > 10000) {
       // 触发清理
   }
   ```

## 最佳实践

### 1. 使用 defer 确保资源释放

```zig
pub fn processData(allocator: std.mem.Allocator) !void {
    const data = try allocator.alloc(u8, 1024);
    defer allocator.free(data);
    
    // 使用 data...
    // 即使发生错误，data 也会被释放
}
```

### 2. 使用 errdefer 处理错误路径

```zig
pub fn createObject(allocator: std.mem.Allocator) !*Object {
    const obj = try allocator.create(Object);
    errdefer allocator.destroy(obj);
    
    obj.data = try allocator.alloc(u8, 100);
    errdefer allocator.free(obj.data);
    
    // 如果后续操作失败，obj 和 obj.data 都会被清理
    try obj.init();
    
    return obj;
}
```

### 3. 实现 deinit 方法

```zig
pub const MyStruct = struct {
    allocator: std.mem.Allocator,
    data: []u8,
    
    pub fn init(allocator: std.mem.Allocator, size: usize) !MyStruct {
        return .{
            .allocator = allocator,
            .data = try allocator.alloc(u8, size),
        };
    }
    
    pub fn deinit(self: *MyStruct) void {
        self.allocator.free(self.data);
    }
};
```

### 4. 使用资源守卫

```zig
const ResourceGuard = @import("runtime/memory_safety.zig").ResourceGuard;

pub fn processFile(path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    var guard = ResourceGuard(@TypeOf(file), @TypeOf(file).close).init(file);
    defer guard.deinit();
    
    // 使用 file...
    // guard 会自动关闭文件
}
```

## 与其他工具集成

### Valgrind

```bash
# 使用 Valgrind 进行更深入的内存分析
valgrind --leak-check=full --show-leak-kinds=all ./zig-php
```

### AddressSanitizer

```bash
# 使用 ASan 进行运行时内存错误检测
zig build -Dasan=true
./zig-out/bin/zig-php
```

### ThreadSanitizer

```bash
# 使用 TSan 进行数据竞争检测
zig build -Dtsan=true
./zig-out/bin/zig-php
```

## 故障排除

### 常见问题

#### 1. 误报泄漏

**问题**：报告显示泄漏，但实际上内存已正确释放。

**解决方案**：
- 确保在释放内存时调用 `recordFree()`
- 检查地址是否匹配
- 验证 allocator 是否正确传递

#### 2. 栈跟踪不完整

**问题**：栈跟踪只显示地址，没有符号信息。

**解决方案**：
- 在 Debug 模式下编译
- 确保调试符号未被剥离
- 使用 `-g` 编译选项

#### 3. 性能下降

**问题**：启用泄漏检测后性能显著下降。

**解决方案**：
- 仅在测试环境启用
- 减少栈跟踪深度
- 使用选择性启用/禁用

## 参考

- [内存安全模块](./MEMORY_SAFETY.md)
- [性能监控系统](./PERFORMANCE_MONITORING.md)
- [调试信息生成](./DEBUG_INFO.md)

## 验证需求

本文档验证以下需求：
- **需求 10.5**：内存泄漏检测 - 提供分配栈跟踪和泄漏报告生成

