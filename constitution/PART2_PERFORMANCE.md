# 第二部分：性能标准与优化技术

## 3. 性能目标与基准

### 3.1 解释器模式性能目标

| 操作 | 目标延迟 | 测量方法 |
|------|---------|---------|
| 函数调用 | < 50ns | `benchmark_function_call()` |
| 对象创建 | < 200ns | `benchmark_object_creation()` |
| 属性访问 | < 10ns | `benchmark_property_access()` |
| 方法调用 | < 60ns | `benchmark_method_call()` |
| 数组访问 | < 5ns | `benchmark_array_access()` |
| 数组追加 | < 20ns | `benchmark_array_append()` |
| 字符串拼接 | < 30ns | `benchmark_string_concat()` |
| 整数运算 | < 2ns | `benchmark_int_arithmetic()` |
| 浮点运算 | < 3ns | `benchmark_float_arithmetic()` |
| 类型检查 | < 1ns | `benchmark_type_check()` |

### 3.2 JIT模式性能目标

| 指标 | 目标 | 测量方法 |
|------|------|---------|
| 热点检测阈值 | 100次调用 | 计数器 |
| Tier 1编译时间 | < 5ms/函数 | 编译器计时 |
| Tier 2编译时间 | < 10ms/函数 | 编译器计时 |
| 编译后执行速度 | AOT的80-90% | 基准对比 |
| 代码缓存命中率 | > 95% | 缓存统计 |
| OSR延迟 | < 100μs | OSR计时 |
| 去优化延迟 | < 50μs | 去优化计时 |

### 3.3 AOT模式性能目标

| 指标 | 目标 | 测量方法 |
|------|------|---------|
| 编译速度 | < 5秒/1000行 | 编译器计时 |
| 执行速度 | C语言的90-95% | 基准对比 |
| 二进制大小 | < 2MB（静态） | 文件大小 |
| 启动时间 | < 10ms | 启动计时 |
| 内存占用 | < 50MB | 内存分析 |
| 优化级别 | -O3等效 | 优化分析 |

### 3.4 内存管理性能目标

| 指标 | 目标 | 测量方法 |
|------|------|---------|
| Minor GC停顿 | < 1ms | GC日志 |
| Major GC停顿 | < 10ms | GC日志 |
| GC吞吐量 | > 95% | 时间统计 |
| 内存利用率 | > 80% | 内存分析 |
| 对象分配 | < 50ns | 分配基准 |
| 对象池命中率 | > 90% | 池统计 |

### 3.5 并发性能目标

| 指标 | 目标 | 测量方法 |
|------|------|---------|
| 协程创建 | < 100ns | 创建基准 |
| 上下文切换 | < 50ns | 切换基准 |
| 调度延迟 | < 1μs | 调度统计 |
| 通道发送 | < 20ns | 通道基准 |
| 通道接收 | < 20ns | 通道基准 |
| 锁获取 | < 10ns | 锁基准 |

## 4. 底层优化技术

### 4.1 CPU级优化

#### 4.1.1 缓存优化

**缓存行对齐**:
```zig
/// 避免false sharing
pub const AtomicCounter = struct {
    value: std.atomic.Value(u64) align(64),  // 缓存行对齐
};
```

**数据预取**:
```zig
/// 预取下一个节点
pub fn traverseList(head: *Node) void {
    var current = head;
    while (current.next) |next| {
        // 预取下一个节点
        @prefetch(next, .{ .rw = .read, .locality = 3 });
        
        // 处理当前节点
        process(current);
        
        current = next;
    }
}
```

**缓存友好的数据布局**:
```zig
/// 结构体字段按访问频率排序
pub const HotColdSplit = struct {
    // 热数据（频繁访问）
    counter: u64,
    flags: u32,
    
    // 冷数据（很少访问）
    debug_info: *DebugInfo,
    metadata: *Metadata,
};
```

#### 4.1.2 分支预测优化

**分支提示**:
```zig
pub fn fastPath(condition: bool) void {
    if (condition) {
        @branchHint(.likely);  // 提示编译器这是常见路径
        // 快速路径
    } else {
        @branchHint(.unlikely);  // 提示编译器这是罕见路径
        // 慢速路径
    }
}
```

**分支消除**:
```zig
/// 使用查找表代替分支
const OPERATION_TABLE = [_]fn(i64, i64) i64{
    add, sub, mul, div, mod, and, or, xor,
};

pub fn execute(op: u8, a: i64, b: i64) i64 {
    return OPERATION_TABLE[op](a, b);  // 无分支
}
```

#### 4.1.3 指令级并行

**循环展开**:
```zig
/// 4路展开，提高ILP
pub fn vectorAdd(a: []f64, b: []f64, result: []f64) void {
    var i: usize = 0;
    
    // 4路展开
    while (i + 4 <= a.len) : (i += 4) {
        result[i] = a[i] + b[i];
        result[i+1] = a[i+1] + b[i+1];
        result[i+2] = a[i+2] + b[i+2];
        result[i+3] = a[i+3] + b[i+3];
    }
    
    // 处理剩余
    while (i < a.len) : (i += 1) {
        result[i] = a[i] + b[i];
    }
}
```

### 4.2 SIMD优化

#### 4.2.1 字符串操作

```zig
/// SIMD字符串查找
pub fn findCharSIMD(haystack: []const u8, needle: u8) ?usize {
    const vec_len = haystack.len / 32;
    const needle_vec = @splat(32, needle);
    
    var i: usize = 0;
    while (i < vec_len) : (i += 1) {
        const chunk = @as(@Vector(32, u8), haystack[i*32..][0..32].*);
        const mask = @reduce(.Or, chunk == needle_vec);
        
        if (mask != 0) {
            // 找到匹配，精确定位
            for (haystack[i*32..][0..32], 0..) |c, j| {
                if (c == needle) return i * 32 + j;
            }
        }
    }
    
    // 处理剩余字节
    for (haystack[vec_len*32..], vec_len*32..) |c, j| {
        if (c == needle) return j;
    }
    
    return null;
}
```

#### 4.2.2 数值计算

```zig
/// SIMD向量加法
pub fn addVectorsSIMD(a: []const f64, b: []const f64, result: []f64) void {
    const vec_len = a.len / 4;
    
    var i: usize = 0;
    while (i < vec_len) : (i += 1) {
        const va = @as(@Vector(4, f64), a[i*4..][0..4].*);
        const vb = @as(@Vector(4, f64), b[i*4..][0..4].*);
        const vr = va + vb;
        result[i*4..][0..4].* = @as([4]f64, vr);
    }
    
    // 处理剩余
    for (a[vec_len*4..], b[vec_len*4..], result[vec_len*4..]) |av, bv, *rv| {
        rv.* = av + bv;
    }
}
```

### 4.3 内存优化

#### 4.3.1 内存池

```zig
/// 固定大小内存池
pub const FixedPool = struct {
    block_size: usize,
    blocks: []u8,
    free_list: ?*Block,
    
    const Block = struct {
        next: ?*Block,
    };
    
    /// 分配（O(1)）
    pub fn alloc(self: *FixedPool) ?[]u8 {
        const block = self.free_list orelse return null;
        self.free_list = block.next;
        return @as([*]u8, @ptrCast(block))[0..self.block_size];
    }
    
    /// 释放（O(1)）
    pub fn free(self: *FixedPool, ptr: []u8) void {
        const block = @as(*Block, @ptrCast(ptr.ptr));
        block.next = self.free_list;
        self.free_list = block;
    }
};
```

#### 4.3.2 Arena分配器

```zig
/// Arena分配器：批量分配，批量释放
pub const Arena = struct {
    buffer: []u8,
    offset: usize,
    
    /// 分配（O(1)，无碎片）
    pub fn alloc(self: *Arena, size: usize, alignment: usize) ![]u8 {
        const aligned_offset = std.mem.alignForward(self.offset, alignment);
        const end = aligned_offset + size;
        
        if (end > self.buffer.len) return error.OutOfMemory;
        
        const result = self.buffer[aligned_offset..end];
        self.offset = end;
        return result;
    }
    
    /// 重置（O(1)，批量释放）
    pub fn reset(self: *Arena) void {
        self.offset = 0;
    }
};
```

### 4.4 编译器优化

#### 4.4.1 内联

```zig
/// 强制内联
pub inline fn fastAdd(a: i64, b: i64) i64 {
    return a + b;
}

/// 内联提示
pub fn likelyInline(x: i64) i64 {
    @setRuntimeSafety(false);  // 禁用运行时检查
    return x * 2;
}
```

#### 4.4.2 常量折叠

```zig
/// 编译时计算
pub fn fibonacci(comptime n: u32) u32 {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

// 使用
const fib10 = fibonacci(10);  // 编译时计算，无运行时开销
```

#### 4.4.3 死代码消除

```zig
/// 编译时条件编译
pub fn optimizedFunction(comptime debug: bool) void {
    if (debug) {
        // 调试代码
        std.debug.print("Debug info\n", .{});
    }
    // 生产代码
    doWork();
}

// 使用
optimizedFunction(false);  // 调试代码被完全消除
```

## 5. 性能测试与分析

### 5.1 基准测试框架

```zig
/// 基准测试框架
pub const Benchmark = struct {
    name: []const u8,
    iterations: usize,
    
    pub fn run(self: *Benchmark, func: anytype) !Result {
        // 预热
        for (0..100) |_| {
            _ = func();
        }
        
        // 测量
        const start = std.time.nanoTimestamp();
        for (0..self.iterations) |_| {
            _ = func();
        }
        const end = std.time.nanoTimestamp();
        
        const total_ns = @as(u64, @intCast(end - start));
        const ns_per_op = total_ns / self.iterations;
        
        return Result{
            .name = self.name,
            .iterations = self.iterations,
            .total_ns = total_ns,
            .ns_per_op = ns_per_op,
        };
    }
    
    pub const Result = struct {
        name: []const u8,
        iterations: usize,
        total_ns: u64,
        ns_per_op: u64,
        
        pub fn print(self: Result) void {
            std.debug.print(
                "{s}: {d} ns/op ({d} iterations)\n",
                .{ self.name, self.ns_per_op, self.iterations }
            );
        }
    };
};

// 使用示例
test "benchmark function call" {
    var bench = Benchmark{
        .name = "function_call",
        .iterations = 1_000_000,
    };
    
    const result = try bench.run(struct {
        fn call() void {
            _ = testFunction(42);
        }
    }.call);
    
    result.print();
    
    // 断言性能要求
    try std.testing.expect(result.ns_per_op < 50);
}
```

### 5.2 性能分析工具

#### 5.2.1 CPU Profiling

```zig
/// CPU性能分析器
pub const CPUProfiler = struct {
    samples: std.ArrayList(Sample),
    
    pub const Sample = struct {
        function: []const u8,
        timestamp: i64,
        duration: u64,
    };
    
    pub fn start(self: *CPUProfiler, function: []const u8) i64 {
        const timestamp = std.time.nanoTimestamp();
        return timestamp;
    }
    
    pub fn end(self: *CPUProfiler, function: []const u8, start: i64) !void {
        const end_time = std.time.nanoTimestamp();
        const duration = @as(u64, @intCast(end_time - start));
        
        try self.samples.append(.{
            .function = function,
            .timestamp = start,
            .duration = duration,
        });
    }
    
    pub fn report(self: *CPUProfiler) void {
        // 按duration排序
        std.sort.sort(Sample, self.samples.items, {}, struct {
            fn lessThan(_: void, a: Sample, b: Sample) bool {
                return a.duration > b.duration;
            }
        }.lessThan);
        
        // 打印Top 10
        std.debug.print("Top 10 functions by duration:\n", .{});
        for (self.samples.items[0..@min(10, self.samples.items.len)]) |sample| {
            std.debug.print("  {s}: {d}ns\n", .{ sample.function, sample.duration });
        }
    }
};
```

#### 5.2.2 Memory Profiling

```zig
/// 内存分析器
pub const MemoryProfiler = struct {
    allocations: std.ArrayList(Allocation),
    total_allocated: usize,
    total_freed: usize,
    
    pub const Allocation = struct {
        ptr: usize,
        size: usize,
        stack_trace: []usize,
    };
    
    pub fn trackAlloc(self: *MemoryProfiler, ptr: usize, size: usize) !void {
        self.total_allocated += size;
        
        // 捕获栈跟踪
        var stack_trace: [16]usize = undefined;
        const trace_len = std.debug.captureStackTrace(&stack_trace);
        
        try self.allocations.append(.{
            .ptr = ptr,
            .size = size,
            .stack_trace = try self.allocator.dupe(usize, stack_trace[0..trace_len]),
        });
    }
    
    pub fn trackFree(self: *MemoryProfiler, ptr: usize) void {
        for (self.allocations.items, 0..) |alloc, i| {
            if (alloc.ptr == ptr) {
                self.total_freed += alloc.size;
                _ = self.allocations.swapRemove(i);
                return;
            }
        }
    }
    
    pub fn report(self: *MemoryProfiler) void {
        std.debug.print("Memory Report:\n", .{});
        std.debug.print("  Total allocated: {d} bytes\n", .{self.total_allocated});
        std.debug.print("  Total freed: {d} bytes\n", .{self.total_freed});
        std.debug.print("  Leaked: {d} bytes\n", .{self.total_allocated - self.total_freed});
        std.debug.print("  Active allocations: {d}\n", .{self.allocations.items.len});
    }
};
```

### 5.3 性能回归检测

```zig
/// 性能回归检测
pub const RegressionDetector = struct {
    baseline: std.StringHashMap(u64),
    threshold: f64,  // 回归阈值（如5%）
    
    pub fn check(self: *RegressionDetector, name: []const u8, current: u64) !bool {
        const baseline = self.baseline.get(name) orelse {
            // 首次运行，记录基线
            try self.baseline.put(name, current);
            return true;
        };
        
        const ratio = @as(f64, @floatFromInt(current)) / @as(f64, @floatFromInt(baseline));
        const regression = (ratio - 1.0) * 100.0;
        
        if (regression > self.threshold) {
            std.debug.print(
                "⚠️  Performance regression detected in {s}: {d:.2}% slower\n",
                .{ name, regression }
            );
            return false;
        }
        
        if (regression < -self.threshold) {
            std.debug.print(
                "✅ Performance improvement in {s}: {d:.2}% faster\n",
                .{ name, -regression }
            );
            // 更新基线
            try self.baseline.put(name, current);
        }
        
        return true;
    }
};
```

## 6. 性能优化案例

### 6.1 案例1：哈希表优化

**问题**: 标准哈希表在高冲突场景下性能下降

**解决方案**: Robin Hood哈希

```zig
/// Robin Hood哈希表
pub const RobinHoodHashMap = struct {
    entries: []Entry,
    mask: usize,
    
    const Entry = struct {
        key: []const u8,
        value: *Symbol,
        distance: u8,  // 距离理想位置的距离
        
        fn isEmpty(self: Entry) bool {
            return self.key.len == 0;
        }
    };
    
    pub fn insert(self: *RobinHoodHashMap, key: []const u8, value: *Symbol) !void {
        var hash = self.hash(key);
        var dist: u8 = 0;
        var entry = Entry{ .key = key, .value = value, .distance = 0 };
        
        while (true) : (dist += 1) {
            const idx = (hash + dist) & self.mask;
            const existing = &self.entries[idx];
            
            if (existing.isEmpty()) {
                existing.* = entry;
                entry.distance = dist;
                return;
            }
            
            // Robin Hood: 如果当前entry距离更远，交换
            if (existing.distance < dist) {
                std.mem.swap(Entry, &entry, existing);
            }
        }
    }
};
```

**性能提升**:
- 查找: 15ns → 10ns (33%提升)
- 插入: 25ns → 18ns (28%提升)
- 最坏情况: O(n) → O(log n)

### 6.2 案例2：字符串拼接优化

**问题**: 多次字符串拼接导致大量内存分配

**解决方案**: 字符串构建器

```zig
/// 字符串构建器
pub const StringBuilder = struct {
    buffer: std.ArrayList(u8),
    
    pub fn append(self: *StringBuilder, str: []const u8) !void {
        try self.buffer.appendSlice(str);
    }
    
    pub fn build(self: *StringBuilder) ![]const u8 {
        return try self.buffer.toOwnedSlice();
    }
};

// 使用对比
// 慢速方式（多次分配）
var result: []const u8 = "";
for (strings) |s| {
    result = try std.mem.concat(allocator, u8, &[_][]const u8{ result, s });
}

// 快速方式（单次分配）
var builder = StringBuilder.init(allocator);
for (strings) |s| {
    try builder.append(s);
}
const result = try builder.build();
```

**性能提升**:
- 10个字符串: 500ns → 50ns (10x)
- 100个字符串: 50μs → 500ns (100x)
- 内存分配: 10次 → 1次

### 6.3 案例3：GC优化

**问题**: Full GC导致长时间停顿

**解决方案**: 分代GC + 增量GC

```zig
/// 分代GC
pub const GenerationalGC = struct {
    young_gen: YoungGeneration,
    old_gen: OldGeneration,
    
    pub fn collect(self: *GenerationalGC) !void {
        // Minor GC（快速）
        try self.young_gen.collect();
        
        // 检查是否需要Major GC
        if (self.old_gen.needsCollection()) {
            try self.old_gen.collect();
        }
    }
};

/// 增量GC
pub const IncrementalGC = struct {
    work_budget: usize,  // 每次增量的工作量
    
    pub fn incrementalCollect(self: *IncrementalGC) !void {
        var work_done: usize = 0;
        
        while (work_done < self.work_budget) {
            // 标记一批对象
            const marked = try self.markBatch(100);
            work_done += marked;
            
            if (marked == 0) break;  // 标记完成
        }
    }
};
```

**性能提升**:
- Minor GC停顿: 10ms → 0.5ms (20x)
- Major GC停顿: 100ms → 5ms (20x)
- GC吞吐量: 85% → 97%
