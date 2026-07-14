# 第一部分：系统架构与设计原则

## 1. 系统架构总览

### 1.1 编译器管道 (Compiler Pipeline)

```
源代码 (Source Code)
    ↓
┌─────────────────────────────────────────┐
│ 前端 (Frontend)                          │
│ ┌─────────────────────────────────────┐ │
│ │ Lexer: 词法分析                      │ │
│ │ - Token化                            │ │
│ │ - 关键字识别                         │ │
│ │ - 字符串处理                         │ │
│ └─────────────────────────────────────┘ │
│           ↓                              │
│ ┌─────────────────────────────────────┐ │
│ │ Parser: 语法分析                     │ │
│ │ - 递归下降解析                       │ │
│ │ - AST构建                            │ │
│ │ - 错误恢复                           │ │
│ └─────────────────────────────────────┘ │
│           ↓                              │
│ ┌─────────────────────────────────────┐ │
│ │ Semantic Analysis: 语义分析          │ │
│ │ - 符号表构建                         │ │
│ │ - 类型检查                           │ │
│ │ - 作用域分析                         │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 中端 (Middle-end)                        │
│ ┌─────────────────────────────────────┐ │
│ │ IR Generation: IR生成                │ │
│ │ - SSA构造                            │ │
│ │ - 控制流图                           │ │
│ │ - 数据流图                           │ │
│ └─────────────────────────────────────┘ │
│           ↓                              │
│ ┌─────────────────────────────────────┐ │
│ │ Type Inference: 类型推断             │ │
│ │ - Hindley-Milner算法                 │ │
│ │ - 类型约束求解                       │ │
│ │ - 类型特化                           │ │
│ └─────────────────────────────────────┘ │
│           ↓                              │
│ ┌─────────────────────────────────────┐ │
│ │ Optimization: 优化                   │ │
│ │ - 死代码消除 (DCE)                   │ │
│ │ - 常量折叠 (Constant Folding)        │ │
│ │ - 公共子表达式消除 (CSE)             │ │
│ │ - 循环不变量外提 (LICM)              │ │
│ │ - 循环展开 (Loop Unrolling)          │ │
│ │ - 内联 (Inlining)                    │ │
│ │ - 逃逸分析 (Escape Analysis)         │ │
│ │ - 去虚化 (Devirtualization)          │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 后端 (Backend)                           │
│ ┌─────────────────────────────────────┐ │
│ │ Code Generation: 代码生成            │ │
│ │ - 指令选择                           │ │
│ │ - 寄存器分配                         │ │
│ │ - 指令调度                           │ │
│ │ - 窥孔优化                           │ │
│ └─────────────────────────────────────┘ │
│           ↓                              │
│ ┌─────────────────────────────────────┐ │
│ │ 执行模式选择                         │ │
│ │ ├─ Interpreter (解释器)              │ │
│ │ ├─ JIT (即时编译)                    │ │
│ │ └─ AOT (提前编译)                    │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
    ↓
机器码 / 字节码 (Machine Code / Bytecode)
```

### 1.2 执行模式架构

#### 1.2.1 解释器模式 (Interpreter Mode)

**特点**:
- 启动快速（无编译开销）
- 内存占用小
- 适合短脚本和开发调试

**架构**:
```
AST → Bytecode → Stack-based VM → 执行
```

**性能目标**:
- 函数调用: < 50ns
- 对象创建: < 200ns
- 数组操作: < 10ns/元素
- 字符串操作: < 5ns/字符

**关键技术**:
- 寄存器字节码（Register-based Bytecode）
- 直接线程解释（Direct Threaded Interpretation）
- 内联缓存（Inline Caching）
- 快速路径优化（Fast Path Optimization）

#### 1.2.2 JIT模式 (Just-In-Time Compilation)

**特点**:
- 运行时编译热点代码
- 平衡编译时间和执行速度
- 适合长时间运行的应用

**架构**:
```
Bytecode → Hotspot Detection → JIT Compilation → Native Code → 执行
```

**性能目标**:
- 热点检测: < 100次调用
- 编译时间: < 10ms/函数
- 执行速度: AOT的80-90%
- 内存占用: < 200MB

**关键技术**:
- 分层编译（Tiered Compilation）
  - Tier 0: 解释执行
  - Tier 1: 快速JIT（无优化）
  - Tier 2: 优化JIT（全优化）
- 栈上替换（On-Stack Replacement, OSR）
- 去优化（Deoptimization）
- 类型反馈（Type Feedback）
- 推测优化（Speculative Optimization）

#### 1.2.3 AOT模式 (Ahead-Of-Time Compilation)

**特点**:
- 编译时生成本地代码
- 最高执行性能
- 适合生产部署

**架构**:
```
AST → IR → Optimization → Native Code Generation → 链接 → 可执行文件
```

**性能目标**:
- 编译时间: < 5秒/1000行
- 执行速度: C语言的90-95%
- 二进制大小: < 2MB（静态链接）
- 启动时间: < 10ms

**关键技术**:
- 静态单赋值形式（SSA）
- 全程序优化（Whole Program Optimization）
- 链接时优化（Link-Time Optimization, LTO）
- 性能引导优化（Profile-Guided Optimization, PGO）
- 跨过程优化（Interprocedural Optimization, IPO）

### 1.3 内存管理架构

#### 1.3.1 垃圾回收器 (Garbage Collector)

**多代GC架构**:
```
┌─────────────────────────────────────────┐
│ Young Generation (年轻代)                │
│ ┌─────────┬─────────┬─────────────────┐ │
│ │ Eden    │ S0      │ S1              │ │
│ │ (新对象)│ (存活0) │ (存活1)         │ │
│ └─────────┴─────────┴─────────────────┘ │
│           ↓ Minor GC                     │
├─────────────────────────────────────────┤
│ Old Generation (老年代)                  │
│ ┌─────────────────────────────────────┐ │
│ │ 长期存活对象                         │ │
│ └─────────────────────────────────────┘ │
│           ↓ Major GC                     │
├─────────────────────────────────────────┤
│ Permanent Generation (永久代)            │
│ ┌─────────────────────────────────────┐ │
│ │ 类元数据、常量池                     │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

**GC算法组合**:
1. **Minor GC**: 复制算法（Copying）
   - 快速（< 1ms）
   - 高频率
   - Eden → Survivor

2. **Major GC**: 标记-压缩（Mark-Compact）
   - 较慢（< 10ms）
   - 低频率
   - 整理内存碎片

3. **Concurrent GC**: 并发标记清除
   - 与应用并发执行
   - 减少停顿时间
   - 三色标记算法

4. **Incremental GC**: 增量回收
   - 分步执行
   - 避免长时间停顿
   - 写屏障（Write Barrier）

**性能目标**:
- Minor GC停顿: < 1ms
- Major GC停顿: < 10ms
- GC吞吐量: > 95%（应用时间/总时间）
- 内存利用率: > 80%

#### 1.3.2 对象池 (Object Pool)

**用途**: 高频对象复用，减少GC压力

**实现**:
```zig
pub const ObjectPool = struct {
    /// 对象类型
    T: type,
    /// 空闲对象列表（无锁栈）
    free_list: std.atomic.Stack(T),
    /// 对象总数
    total_count: std.atomic.Value(usize),
    /// 最大容量
    max_capacity: usize,
    
    /// 获取对象（O(1)）
    pub fn acquire(self: *ObjectPool) !*T {
        // 尝试从空闲列表获取
        if (self.free_list.pop()) |node| {
            return &node.data;
        }
        // 空闲列表为空，创建新对象
        if (self.total_count.load(.monotonic) < self.max_capacity) {
            _ = self.total_count.fetchAdd(1, .monotonic);
            return try self.allocator.create(T);
        }
        return error.PoolExhausted;
    }
    
    /// 归还对象（O(1)）
    pub fn release(self: *ObjectPool, obj: *T) void {
        obj.reset();  // 重置对象状态
        self.free_list.push(&obj.node);
    }
};
```

**适用对象**:
- PHPString（字符串）
- PHPArray（数组）
- PHPObject（对象）
- Closure（闭包）
- Frame（栈帧）

### 1.4 并发架构

#### 1.4.1 协程系统 (Coroutine System)

**架构**:
```
┌─────────────────────────────────────────┐
│ 用户代码                                 │
│ ┌─────────┐  ┌─────────┐  ┌─────────┐  │
│ │Coroutine│  │Coroutine│  │Coroutine│  │
│ │   1     │  │   2     │  │   3     │  │
│ └────┬────┘  └────┬────┘  └────┬────┘  │
│      │            │            │        │
└──────┼────────────┼────────────┼────────┘
       │            │            │
┌──────┼────────────┼────────────┼────────┐
│      ↓            ↓            ↓        │
│ ┌─────────────────────────────────────┐ │
│ │ Scheduler (调度器)                   │ │
│ │ - Work Stealing (工作窃取)           │ │
│ │ - Priority Queue (优先级队列)        │ │
│ │ - Load Balancing (负载均衡)          │ │
│ └─────────────────────────────────────┘ │
│      ↓            ↓            ↓        │
│ ┌────────┐  ┌────────┐  ┌────────┐    │
│ │Worker 1│  │Worker 2│  │Worker 3│    │
│ │(Thread)│  │(Thread)│  │(Thread)│    │
│ └────────┘  └────────┘  └────────┘    │
└─────────────────────────────────────────┘
       │            │            │
       └────────────┴────────────┘
                    ↓
              OS Threads (系统线程)
```

**调度策略**:
1. **工作窃取** (Work Stealing)
   - 每个Worker有本地队列
   - 空闲Worker从其他Worker窃取任务
   - 减少锁竞争

2. **优先级调度**
   - 高优先级协程优先执行
   - 防止饥饿

3. **抢占式调度**
   - 定时器中断
   - 防止协程长时间占用CPU

**性能目标**:
- 协程创建: < 100ns
- 上下文切换: < 50ns
- 调度延迟: < 1μs
- 支持协程数: > 100万

#### 1.4.2 通道系统 (Channel System)

**无锁通道实现**:
```zig
/// 无锁MPMC通道（多生产者多消费者）
pub const Channel = struct {
    /// 环形缓冲区
    buffer: []T,
    /// 容量（2的幂）
    capacity: usize,
    /// 头指针（原子）
    head: std.atomic.Value(usize),
    /// 尾指针（原子）
    tail: std.atomic.Value(usize),
    
    /// 发送（O(1)，无锁）
    pub fn send(self: *Channel, value: T) !void {
        while (true) {
            const tail = self.tail.load(.acquire);
            const head = self.head.load(.acquire);
            
            // 检查是否已满
            if (tail - head >= self.capacity) {
                return error.ChannelFull;
            }
            
            // CAS更新尾指针
            if (self.tail.cmpxchgWeak(
                tail, tail + 1, .release, .acquire
            )) |_| {
                continue;  // CAS失败，重试
            }
            
            // 写入数据
            self.buffer[tail & (self.capacity - 1)] = value;
            return;
        }
    }
    
    /// 接收（O(1)，无锁）
    pub fn receive(self: *Channel) !T {
        while (true) {
            const head = self.head.load(.acquire);
            const tail = self.tail.load(.acquire);
            
            // 检查是否为空
            if (head >= tail) {
                return error.ChannelEmpty;
            }
            
            // CAS更新头指针
            if (self.head.cmpxchgWeak(
                head, head + 1, .release, .acquire
            )) |_| {
                continue;  // CAS失败，重试
            }
            
            // 读取数据
            return self.buffer[head & (self.capacity - 1)];
        }
    }
};
```

### 1.5 类型系统架构

#### 1.5.1 值表示 (Value Representation)

**NaN-Boxing优化**:
```
64位值表示：
┌────────────────────────────────────────────────────────────┐
│ 类型标记 (16位) │ 数据 (48位)                              │
├────────────────────────────────────────────────────────────┤
│ 0x0000          │ 整数 (i48)                               │
│ 0x0001          │ 指针 (对象/数组/字符串)                  │
│ 0x0002          │ 布尔 (true/false)                        │
│ 0x0003          │ null                                     │
│ 0x0004          │ undefined                                │
│ 0xFFFF          │ 浮点数 (f64, NaN区域)                   │
└────────────────────────────────────────────────────────────┘
```

**优势**:
- 单个64位表示所有类型
- 无需额外类型标记字段
- 类型检查只需位操作（< 1ns）
- 缓存友好（紧凑布局）

**实现**:
```zig
pub const Value = packed struct {
    bits: u64,
    
    // 类型检查（内联，零成本）
    pub inline fn isInt(self: Value) bool {
        return (self.bits >> 48) == 0x0000;
    }
    
    pub inline fn isFloat(self: Value) bool {
        return (self.bits >> 48) == 0xFFFF;
    }
    
    pub inline fn isPointer(self: Value) bool {
        return (self.bits >> 48) == 0x0001;
    }
    
    // 类型转换（内联，零成本）
    pub inline fn asInt(self: Value) i48 {
        return @truncate(@as(i64, @bitCast(self.bits)));
    }
    
    pub inline fn asFloat(self: Value) f64 {
        return @bitCast(self.bits);
    }
    
    pub inline fn asPointer(self: Value) *anyopaque {
        const ptr_bits = self.bits & 0x0000_FFFF_FFFF_FFFF;
        return @ptrFromInt(ptr_bits);
    }
};
```

## 2. 核心设计原则

### 2.1 性能至上原则

**定义**: 性能是第一优先级，任何设计决策都必须基于性能考虑。

**量化标准**:
- 每个函数必须有时间复杂度注释
- 性能关键路径必须有基准测试
- 性能回归 > 5% 必须拒绝
- 优化必须有性能分析报告

**示例**:
```zig
/// 符号表查找
/// 
/// 算法: Robin Hood哈希表
/// 时间复杂度: O(1) 平均, O(n) 最坏
/// 空间复杂度: O(n)
/// 缓存友好: 是（线性探测）
/// 
/// 性能基准:
/// - 查找: 15ns (命中), 20ns (未命中)
/// - 插入: 25ns
/// - 删除: 30ns
pub fn lookup(self: *SymbolTable, name: []const u8) ?*Symbol {
    var hash = self.hash(name);
    var dist: usize = 0;
    
    while (true) : (dist += 1) {
        const idx = (hash + dist) & self.mask;
        const entry = &self.entries[idx];
        
        if (entry.isEmpty()) return null;
        if (entry.distance < dist) return null;  // Robin Hood优化
        if (std.mem.eql(u8, entry.name, name)) return entry.symbol;
    }
}
```

### 2.2 零成本抽象原则

**定义**: 抽象层不应该带来运行时开销。

**实现技术**:
1. **编译时计算** (comptime)
2. **内联函数** (inline)
3. **泛型特化** (Generic Specialization)
4. **常量传播** (Constant Propagation)

**示例**:
```zig
/// 零成本的类型安全容器
pub fn ArrayList(comptime T: type) type {
    return struct {
        items: []T,
        capacity: usize,
        allocator: Allocator,
        
        /// 内联访问（零成本）
        pub inline fn get(self: *@This(), index: usize) T {
            return self.items[index];  // 直接数组访问
        }
        
        /// 编译时大小检查
        pub fn append(self: *@This(), item: T) !void {
            comptime {
                // 编译时验证T的大小合理
                if (@sizeOf(T) > 1024) {
                    @compileError("Type too large for ArrayList");
                }
            }
            // 运行时逻辑
            if (self.items.len >= self.capacity) {
                try self.grow();
            }
            self.items[self.items.len] = item;
            self.items.len += 1;
        }
    };
}
```

### 2.3 内存安全原则

**定义**: 所有内存操作必须安全，无泄漏、无悬空指针、无数据竞争。

**所有权系统**:
```zig
/// 所有权标记
/// @ownership OWNING - 拥有内存，负责释放
/// @ownership NON-OWNING - 不拥有内存，只是引用
/// @ownership SHARED - 共享所有权（引用计数）
```

**RAII模式**:
```zig
pub const Module = struct {
    allocator: Allocator,
    functions: std.ArrayListUnmanaged(*Function),
    
    /// @ownership OWNING (allocator)
    pub fn init(allocator: Allocator) !*Module {
        const module = try allocator.create(Module);
        module.* = .{
            .allocator = allocator,
            .functions = .{},
        };
        return module;
    }
    
    /// 自动清理（RAII）
    pub fn deinit(self: *Module) void {
        // 释放所有函数
        for (self.functions.items) |func| {
            func.deinit();
            self.allocator.destroy(func);
        }
        self.functions.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

// 使用示例
const module = try Module.init(allocator);
defer module.deinit();  // 自动清理
```

### 2.4 线程安全原则

**定义**: 所有并发代码必须线程安全，无数据竞争。

**线程安全级别**:
```zig
/// @thread-safety ISOLATED - 完全隔离，无共享状态
/// @thread-safety IMMUTABLE - 不可变，可安全共享
/// @thread-safety SYNCHRONIZED - 使用锁保护
/// @thread-safety LOCK_FREE - 无锁并发安全
/// @thread-safety UNSAFE - 不安全，需要外部同步
```

**无锁数据结构示例**:
```zig
/// 无锁栈
/// @thread-safety LOCK_FREE
pub const LockFreeStack = struct {
    head: std.atomic.Value(?*Node),
    
    pub const Node = struct {
        next: ?*Node,
        data: T,
    };
    
    /// 压栈（O(1)，无锁）
    pub fn push(self: *LockFreeStack, node: *Node) void {
        while (true) {
            const old_head = self.head.load(.acquire);
            node.next = old_head;
            
            // CAS操作
            if (self.head.cmpxchgWeak(
                old_head, node, .release, .acquire
            )) |_| {
                continue;  // CAS失败，重试
            }
            return;  // 成功
        }
    }
    
    /// 弹栈（O(1)，无锁）
    pub fn pop(self: *LockFreeStack) ?*Node {
        while (true) {
            const old_head = self.head.load(.acquire);
            if (old_head == null) return null;
            
            const new_head = old_head.?.next;
            
            // CAS操作
            if (self.head.cmpxchgWeak(
                old_head, new_head, .release, .acquire
            )) |_| {
                continue;  // CAS失败，重试
            }
            return old_head;  // 成功
        }
    }
};
```

### 2.5 算法精妙原则

**定义**: 使用最优算法，追求理论和实践的完美结合。

**算法选择标准**:
1. **时间复杂度**: 选择最优渐进复杂度
2. **空间复杂度**: 在时间复杂度相同时，选择空间更优的
3. **缓存友好**: 优先选择顺序访问的算法
4. **分支预测**: 减少分支，提高预测准确率
5. **SIMD友好**: 可向量化的算法

**常用优化技术**:

#### 2.5.1 SIMD优化

```zig
/// SIMD优化的字符串比较
/// 时间复杂度: O(n/16) with SIMD
pub fn compareStringSIMD(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    
    const vec_len = a.len / 16;
    var i: usize = 0;
    
    // SIMD比较：一次比较16字节
    while (i < vec_len) : (i += 1) {
        const va = @as(@Vector(16, u8), a[i*16..][0..16].*);
        const vb = @as(@Vector(16, u8), b[i*16..][0..16].*);
        if (@reduce(.Or, va != vb)) return false;
    }
    
    // 处理剩余字节
    return std.mem.eql(u8, a[vec_len*16..], b[vec_len*16..]);
}
```

#### 2.5.2 循环展开

```zig
/// 循环展开优化的数组求和
pub fn sumArray(arr: []const i64) i64 {
    var sum: i64 = 0;
    var i: usize = 0;
    
    // 展开4次
    while (i + 4 <= arr.len) : (i += 4) {
        sum += arr[i];
        sum += arr[i + 1];
        sum += arr[i + 2];
        sum += arr[i + 3];
    }
    
    // 处理剩余元素
    while (i < arr.len) : (i += 1) {
        sum += arr[i];
    }
    
    return sum;
}
```

#### 2.5.3 分支消除

```zig
/// 分支消除：使用位操作代替条件判断
pub fn abs(x: i64) i64 {
    // 传统方法（有分支）
    // return if (x < 0) -x else x;
    
    // 无分支方法
    const mask = x >> 63;  // 负数: -1, 非负数: 0
    return (x + mask) ^ mask;
}
```

## 3. AOT 编译器超越 PHP 解释器的增强特性

> **设计哲学**：AOT 编译器并非仅仅模拟 PHP 解释器——在编译期即可确定的场景下，AOT 拥有比解释器更强的表达能力和更宽松的语法约束。这些增强特性必须在宪法中明确记录，以确保开发者知晓并持续维护。

### 3.1 array_walk / array_walk_recursive 首参数接受数组字面量

**PHP 解释器限制**：

```php
<?php
// PHP 解释器：Fatal Error - Cannot pass parameter by reference
array_walk([1, 2, 3], function($v) { echo $v; });
```

PHP 解释器要求 `array_walk` 和 `array_walk_recursive` 的第一个参数 `&$array` 必须是变量（by-reference 语义），不允许传递数组字面量 `[]`。

**AOT 增强行为**：

```php
<?php
// AOT 编译器：合法，正常执行
array_walk([1, 2, 3], function($v) { echo $v; });

// 带键的字面量
array_walk(['a'=>1, 'b'=>2], function($v, $k) { echo "$k=$v"; });

// array_walk_recursive 同样支持
array_walk_recursive([1, [2, 3]], function($v) { echo $v; });
```

**技术原理**：

AOT 编译器在编译期将数组字面量分配到栈/堆上的具名临时变量，然后将其地址传递给 `php_array_walk`，从而满足 by-reference 语义。这与 PHP 解释器在 VM 层面强制检查参数来源不同——AOT 编译器在 IR 层面已将字面量"物化"为可取地址的存储位置。

**实现依据**：

- `ir_generator.zig`：`array_walk` / `array_walk_recursive` 的参数补全逻辑（2 参数时自动补 null userdata）
- `native_linker.zig`：`byref_funcs` 列表中包含 `array_walk`，但 AOT 代码生成时数组字面量已被物化为 alloca，取地址后作为指针参数传递
- `runtime_lib_template.zig`：`php_array_walk` 接受 `Value` 类型的数组参数，运行时通过 `asArray()` 获取数组指针并直接修改元素

**维护约束**：

1. 此增强特性是 AOT 模式独有的语法放宽，**不得**在解释器/字节码/JIT 模式中强制模拟
2. 当 `array_walk` 首参数为字面量时，回调中对 `$value` 的引用修改**不会**传播到原字面量（因字面量是临时对象），此行为与 PHP 解释器语义一致——PHP 解释器根本不允许此场景，AOT 允许但引用写回作用于临时副本
3. 所有 `array_walk` 相关的回归测试必须覆盖字面量参数场景

### 3.2 超越特性发现与记录流程

> **目标**：确保 AOT 编译器相对于 PHP 解释器的语法增强和语义超越被系统性发现、验证和记录，避免增强特性因未文档化而丢失或被误删。

#### 3.2.1 发现时机

开发者应在以下场景主动审视是否产生了超越特性：

| 时机 | 说明 | 示例 |
|------|------|------|
| AOT 编译成功但 PHP 解释器报错 | AOT 语法更宽松，接受了 PHP 拒绝的语法 | `array_walk([1,2,3], ...)` |
| AOT 运行结果与 PHP 不同且更优 | AOT 编译期优化产生了更精确的行为 | 编译期常量折叠消除了运行时类型检查 |
| 编译期物化绕过运行时限制 | AOT 将字面量/表达式物化为可寻址存储 | by-ref 参数接受字面量 |
| AOT 独有内建函数/语法糖 | AOT 提供了 PHP 不存在的便捷接口 | 未来可能新增的编译期元数据函数 |

#### 3.2.2 验证流程

发现潜在超越特性后，**必须**按以下流程验证后方可记录：

```
发现潜在超越特性
    ↓
1. PHP 解释器对比验证
   ├─ PHP 报错/拒绝 → 确认为超越特性（进入步骤 2）
   └─ PHP 行为一致 → 非超越特性，仅是 AOT 兼容性提升
    ↓
2. AOT 编译 + 运行验证
   ├─ 编译成功 + 运行结果正确 → 确认可记录（进入步骤 3）
   └─ 编译失败或运行异常 → AOT bug，非增强特性
    ↓
3. 边界条件验证
   ├─ 字面量参数 → 临时对象生命周期是否安全？
   ├─ 嵌套表达式 → 是否影响表达式求值顺序？
   ├─ 引用语义 → by-ref 写回是否影响调用者？
   └─ 错误路径 → 增强场景的错误处理是否完整？
    ↓
4. 记录到宪法
```

#### 3.2.3 记录规范

每条超越特性**必须**包含以下要素，新增于本节（§3）中作为子章节：

```markdown
### 3.N {特性名称}

**PHP 解释器限制**：
- PHP 解释器对该场景的处理方式（报错信息/拒绝原因）

**AOT 增强行为**：
- AOT 编译器接受该语法/产生该行为的具体表现

**技术原理**：
- AOT 为何能实现此增强（编译期物化/类型特化/死代码消除等）

**实现依据**：
- 涉及的源文件和函数列表

**维护约束**：
1. 适用范围限制（AOT-only / 全模式）
2. 语义边界说明（与 PHP 行为的差异及合理性）
3. 回归测试要求
```

#### 3.2.4 代码标记规范 `@enhancement`

所有超越特性的实现代码**必须**添加 `@enhancement` 注释标记，便于 `grep` 扫描和回归检查。

**标记格式**：

```zig
// 函数级标记（doc-comment 形式，置于函数声明上方）
/// @enhancement AOT超越PHP: {简述超越行为}(PHP解释器{报错/行为})
pub fn php_array_walk(...) !Value { ... }

// 行内标记（置于关键逻辑行末尾）
const byref_funcs = [_][]const u8{
    "array_push", "array_pop", ..., "array_walk", // @enhancement AOT超越PHP: array_walk首参数允许字面量
};
```

**标记要素**（每条标记必须包含）：

| 要素 | 说明 | 示例 |
|------|------|------|
| `@enhancement` | 固定标记词 | `@enhancement` |
| `AOT超越PHP` | 固定前缀，标识类别 | `AOT超越PHP` |
| 简述 | 一句话描述超越行为 | `首参数允许数组字面量` |
| PHP行为 | PHP 解释器的拒绝/差异行为 | `PHP报Fatal Error by-ref` |

**扫描命令**：

```bash
# 扫描所有超越特性标记
grep -rn "@enhancement" src/

# 统计超越特性数量
grep -rc "@enhancement" src/ | grep -v ':0$'

# 按文件列出
grep -rl "@enhancement" src/
```

**新增超越特性时的标记检查清单**：

- [ ] 运行时函数（`runtime_lib_template.zig`）的 `pub fn` 上方已添加 doc-comment 形式标记
- [ ] IR 生成器（`ir_generator.zig`）的处理逻辑处已添加行内标记
- [ ] 链接器（`native_linker.zig`）的相关注册/列表处已添加行内标记
- [ ] 标记中的简述与宪法 §3 对应章节一致

#### 3.2.5 审查检查项

代码审查时，审查者应额外关注：

- [ ] 本次变更是否引入了新的 AOT 超越行为？
- [ ] 已有的超越特性是否被本次变更破坏？
- [ ] 超越特性的测试脚本是否已添加到 `fuzzy_scripts/pass/` 目录？
- [ ] 宪法 §3 是否已同步更新？
- [ ] 实现代码是否已添加 `@enhancement AOT超越PHP` 标记？

#### 3.2.6 反模式：以下不属于超越特性

- AOT 尚未支持但 PHP 已支持的特性（那是 AOT 的缺陷，不是增强）
- AOT 和 PHP 行为一致的特性（那是兼容性，不是超越）
- AOT 因 bug 导致的错误行为（那是 bug，不是增强）
- 解释器/JIT 模式的差异（除非差异使 AOT 在语义上更强）

## 4. AOT 已知限制与测试容差标准

> **设计哲学**：AOT 编译器将 PHP 源码编译为本地可执行文件，部分运行时输出天然无法与 PHP 解释器逐字节对齐。这些差异源于 AOT 架构本身的限制而非缺陷，在测试对比中必须作为已知容差予以排除，避免将架构限制误判为 BUG。

### 4.1 容差规则总表

| 编号 | 容差类别 | 根因 | 典型示例 | 处理方式 |
|------|---------|------|---------|---------|
| T1 | 栈追踪文件路径/行号不一致 | AOT 编译产物为本地可执行文件，不含 PHP 源码行号映射表 | AOT: `Error in /tmp/aot_bin` vs PHP: `in /path/to/script.php:138` | 规范化时去除文件路径和行号 |
| T2 | 栈追踪调用链深度差异 | AOT 仅输出 `#0 {main}`，PHP 有完整调用链 | AOT: `#0 {main}` vs PHP: `#0 f() #1 g() #2 {main}` | 规范化时跳过所有 `#N` 开头的栈帧行 |
| T3 | 浮点数末位精度微差 | AOT 与 PHP 解释器浮点格式化路径不同，末位舍入可能不同 | `2.7182818284591` vs `2.718281828459` | 规范化时截断到小数点后 12 位 |
| T4 | 输出缩进不一致 | AOT 与 PHP 解释器在数组/对象打印时的缩进策略不同 | `  [0] => 1` vs `    [0] => 1` | 一律忽略 |

### 4.2 容差判定原则

1. **仅限格式差异**：容差仅适用于输出格式（路径、行号、精度位数、缩进）的差异，**不适用于**语义差异（如值本身不同、逻辑分支不同）
2. **根因必须可追溯**：每条容差规则必须能追溯到 AOT 架构限制的具体原因，禁止将未定位的差异随意归入容差
3. **规范化优先**：测试脚本必须通过 `normalize_output()` 函数在对比前消除已知容差差异，而非人工判断
4. **新增容差必须记录**：发现新的 AOT 架构限制导致的输出差异时，必须在本节新增容差条目并更新规范化函数

### 4.3 规范化函数实现要求

所有 AOT 批量测试脚本（`batch_test_aot.sh`、`full_scan_aot.sh` 等）中的 `normalize_output()` 函数**必须**覆盖以下规范化规则：

```python
# 1. 跳过栈追踪行（#N 开头）— 对应 T1、T2
if re.match(r"^#\d+", line):
    continue

# 2. 跳过 "thrown in" 行 — 对应 T1
if "thrown in" in line:
    continue

# 3. 去除文件路径和行号 — 对应 T1
line = re.sub(r"\s*in [^\s]+\.php:\d+", "", line)
line = re.sub(r"\s*in [^\s]+\.php on line \d+", "", line)

# 4. 截断浮点数到小数点后 12 位 — 对应 T3
line = re.sub(r"(\d+\.\d{13,})", truncate_float, line)
```

### 4.4 容差与 BUG 的边界

```
输出差异
    ↓
是否为格式差异（路径/行号/精度/缩进）？
    ├─ 是 → 检查是否在容差总表 §4.1 中
    │       ├─ 是 → 容差，不计入失败
    │       └─ 否 → 新增容差条目（需分析根因）
    └─ 否 → 语义差异 → AOT BUG，必须修复
```

