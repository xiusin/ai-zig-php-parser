# 高级运行时优化设计文档

## 概述

本设计文档描述了Zig-PHP解释器高级运行时优化的技术架构和实现方案。基于现有的NaN Boxing值表示、引用计数GC、Shape系统和内存管理基础设施，实现字节码虚拟机、增量GC、分代GC、请求级Arena等核心优化。

## 现有架构分析

### 已实现的核心组件

1. **Value系统 (src/runtime/types.zig)**
   - NaN Boxing 64位值表示
   - 类型标签: null, bool, int, float, string, array, object, struct, closure等
   - 引用计数管理 (retain/release)

2. **GC系统 (src/runtime/gc.zig)**
   - Box<T> 泛型包装器，带引用计数和GC信息
   - 三色标记算法基础 (white/gray/black/purple)
   - 写屏障基础设施
   - MemoryManager 统一内存管理

3. **内存管理 (src/runtime/memory.zig)**
   - ArenaAllocator: 批量分配，一次释放
   - ObjectPool<T>: 固定大小对象复用
   - StringInterner: 字符串驻留池
   - GenerationalGC: 分代GC基础框架
   - LeakDetector: 内存泄漏检测

4. **对象模型 (src/runtime/types.zig)**
   - Shape/Hidden Classes: 属性布局优化
   - InlineCache: 属性访问缓存
   - PHPStruct: Go风格结构体
   - PHPClass/PHPObject: 类和对象系统

5. **VM (src/runtime/vm.zig)**
   - 树遍历解释器
   - CallFrame 调用栈
   - 环境变量管理
   - 内置函数注册

## 设计决策

### 决策1: 字节码VM架构

**选项A**: 栈式虚拟机 (Stack-based VM)
- 优点: 实现简单，指令紧凑
- 缺点: 频繁栈操作，性能略低

**选项B**: 寄存器式虚拟机 (Register-based VM)
- 优点: 减少栈操作，性能更高
- 缺点: 指令较长，实现复杂

**决策**: 采用**栈式虚拟机**
- 理由: 与现有Value系统兼容性好，实现复杂度可控，PHP语义映射自然

### 决策2: GC策略

**选项A**: 纯引用计数 + 周期检测
- 优点: 实时回收，延迟可预测
- 缺点: 循环引用处理开销

**选项B**: 分代GC + 增量标记
- 优点: 高吞吐量，低停顿
- 缺点: 实现复杂

**决策**: 采用**混合策略** - 引用计数为主 + 分代增量GC为辅
- 理由: 利用现有引用计数基础，增量GC处理循环引用和大对象

### 决策3: 内存分配策略

**选项A**: 统一分配器
- 优点: 简单一致
- 缺点: 无法针对不同场景优化

**选项B**: 分层分配器
- 优点: 针对性优化
- 缺点: 复杂度增加

**决策**: 采用**分层分配器**
- Request Arena: HTTP请求级别，请求结束一次释放
- Object Pool: 高频小对象复用
- General Heap: 长生命周期对象

## 技术设计

### 1. 字节码指令集设计

```
指令格式: [opcode:8][operand1:16][operand2:16] = 40位 (5字节)

栈操作指令 (0x00-0x0F):
  NOP         = 0x00  // 空操作
  PUSH_CONST  = 0x01  // 压入常量 [const_idx]
  PUSH_LOCAL  = 0x02  // 压入局部变量 [local_idx]
  PUSH_GLOBAL = 0x03  // 压入全局变量 [global_idx]
  POP         = 0x04  // 弹出栈顶
  DUP         = 0x05  // 复制栈顶
  SWAP        = 0x06  // 交换栈顶两元素

算术指令 - 类型特化 (0x10-0x2F):
  ADD_INT     = 0x10  // 整数加法
  ADD_FLOAT   = 0x11  // 浮点加法
  ADD_ANY     = 0x12  // 通用加法（含类型检查）
  SUB_INT     = 0x13
  SUB_FLOAT   = 0x14
  MUL_INT     = 0x15
  MUL_FLOAT   = 0x16
  DIV_INT     = 0x17
  DIV_FLOAT   = 0x18
  MOD_INT     = 0x19
  CONCAT      = 0x1A  // 字符串连接

比较指令 (0x20-0x2F):
  EQ          = 0x20  // ==
  NEQ         = 0x21  // !=
  LT          = 0x22  // <
  LE          = 0x23  // <=
  GT          = 0x24  // >
  GE          = 0x25  // >=
  IDENTICAL   = 0x26  // ===
  NOT_IDENT   = 0x27  // !==

控制流指令 (0x30-0x3F):
  JMP         = 0x30  // 无条件跳转 [offset]
  JZ          = 0x31  // 为零跳转
  JNZ         = 0x32  // 非零跳转
  CALL        = 0x33  // 函数调用 [func_idx][arg_count]
  RET         = 0x34  // 返回
  CALL_METHOD = 0x35  // 方法调用 [method_idx][arg_count]

对象操作 (0x40-0x4F):
  NEW_OBJ     = 0x40  // 创建对象 [class_idx]
  GET_PROP    = 0x41  // 获取属性 [prop_idx]
  SET_PROP    = 0x42  // 设置属性 [prop_idx]
  GET_PROP_IC = 0x43  // 内联缓存属性获取
  SET_PROP_IC = 0x44  // 内联缓存属性设置

数组操作 (0x50-0x5F):
  NEW_ARRAY   = 0x50  // 创建数组 [initial_size]
  GET_ELEM    = 0x51  // 获取元素
  SET_ELEM    = 0x52  // 设置元素
  ARRAY_PUSH  = 0x53  // 数组追加
  ARRAY_LEN   = 0x54  // 数组长度

类型守卫 (0x60-0x6F):
  GUARD_INT   = 0x60  // 整数类型守卫 [deopt_offset]
  GUARD_FLOAT = 0x61  // 浮点类型守卫
  GUARD_STR   = 0x62  // 字符串类型守卫
  GUARD_ARRAY = 0x63  // 数组类型守卫
  GUARD_OBJ   = 0x64  // 对象类型守卫
```

### 2. 字节码编译器架构

```
AST -> BytecodeCompiler -> CompiledFunction
                |
                v
        ConstantPool (常量表)
        LocalTable (局部变量表)
        LabelResolver (标签解析)
```

**CompiledFunction结构**:
```zig
pub const CompiledFunction = struct {
    name: []const u8,
    bytecode: []const Instruction,
    constants: []const Value,
    local_count: u16,
    max_stack: u16,
    arg_count: u16,
    is_variadic: bool,
    source_map: ?[]const SourceMapping,  // 调试信息
};
```

### 3. 增量GC设计

**三色标记增量化**:
```
状态机:
  IDLE -> MARKING -> SWEEPING -> IDLE

MARKING阶段:
  - 每次执行N条字节码后，执行一个标记步骤
  - 从灰色列表取出对象，标记其子对象为灰色
  - 写屏障: 当黑色对象引用白色对象时，将白色对象加入灰色列表

SWEEPING阶段:
  - 增量扫描堆，回收白色对象
  - 每次扫描M个对象后让出控制权
```

**写屏障实现**:
```zig
pub fn writeBarrier(self: *IncrementalGC, source: *GCObject, target: *GCObject) void {
    if (self.state == .marking) {
        if (source.color == .black and target.color == .white) {
            target.color = .gray;
            self.gray_list.append(target);
        }
    }
}
```

### 4. 分代GC设计

**内存布局**:
```
+------------------+
|    Nursery       |  <- 年轻代 (256KB-1MB)
|  (Bump Alloc)    |     快速指针碰撞分配
+------------------+
|   Survivor 0     |  <- 存活区0
+------------------+
|   Survivor 1     |  <- 存活区1
+------------------+
|    Old Gen       |  <- 老年代
|  (Free List)     |     标记-清除-压缩
+------------------+
```

**晋升策略**:
- 对象在Nursery分配
- 经过2次Minor GC仍存活 -> 晋升到Old Gen
- 大对象(>8KB)直接分配到Old Gen

### 5. 请求级Arena设计

```zig
pub const RequestArena = struct {
    arena: ArenaAllocator,
    request_id: u64,
    start_time: i64,
    
    // 需要特殊处理的跨请求对象
    escape_list: std.ArrayList(*anyopaque),
    
    pub fn beginRequest(self: *RequestArena) void {
        self.arena.reset();
        self.request_id = generateRequestId();
        self.start_time = std.time.timestamp();
    }
    
    pub fn endRequest(self: *RequestArena) void {
        // 处理逃逸对象
        for (self.escape_list.items) |obj| {
            promoteToGlobalHeap(obj);
        }
        self.escape_list.clearRetainingCapacity();
        
        // 一次性释放所有请求内存
        self.arena.freeAll();
    }
    
    pub fn markEscape(self: *RequestArena, obj: *anyopaque) void {
        self.escape_list.append(obj);
    }
};
```

### 6. 类型特化优化

**类型反馈收集**:
```zig
pub const TypeFeedback = struct {
    call_site_id: u32,
    observed_types: [4]TypeTag,  // 最多记录4种类型
    type_count: u8,
    call_count: u32,
    
    pub fn recordType(self: *TypeFeedback, tag: TypeTag) void {
        self.call_count += 1;
        for (self.observed_types[0..self.type_count]) |t| {
            if (t == tag) return;
        }
        if (self.type_count < 4) {
            self.observed_types[self.type_count] = tag;
            self.type_count += 1;
        }
    }
    
    pub fn isMonomorphic(self: *TypeFeedback) bool {
        return self.type_count == 1 and self.call_count > 100;
    }
};
```

**特化代码生成**:
- 单态(Monomorphic): 生成类型特化指令
- 多态(Polymorphic): 使用内联缓存
- 超多态(Megamorphic): 回退到通用路径

## 组件交互

```
                    +------------------+
                    |   PHP Source     |
                    +--------+---------+
                             |
                    +--------v---------+
                    |     Lexer        |
                    +--------+---------+
                             |
                    +--------v---------+
                    |     Parser       |
                    +--------+---------+
                             |
                    +--------v---------+
                    |       AST        |
                    +--------+---------+
                             |
              +--------------+--------------+
              |                             |
    +---------v----------+       +----------v---------+
    | BytecodeCompiler   |       | TreeWalker (现有)  |
    +---------+----------+       +--------------------+
              |
    +---------v----------+
    |  CompiledFunction  |
    +---------+----------+
              |
    +---------v----------+
    |   BytecodeVM       |<-----> TypeFeedback
    +---------+----------+
              |
    +---------v----------+
    |  MemoryManager     |
    |  +---------------+ |
    |  | RequestArena  | |
    |  +---------------+ |
    |  | ObjectPool    | |
    |  +---------------+ |
    |  | GenerationalGC| |
    |  +---------------+ |
    +--------------------+
```

## 性能目标

| 指标 | 当前 | 目标 | 提升 |
|------|------|------|------|
| 函数调用 | ~500ns | ~50ns | 10x |
| 属性访问 | ~200ns | ~20ns | 10x |
| 数组操作 | ~100ns | ~30ns | 3x |
| GC停顿 | ~10ms | <1ms | 10x |
| 内存占用 | 100% | 40% | 60%↓ |

## 风险与缓解

1. **字节码兼容性风险**
   - 缓解: 保留树遍历解释器作为回退路径

2. **GC正确性风险**
   - 缓解: 完善的单元测试和压力测试

3. **性能回退风险**
   - 缓解: 类型守卫失败时平滑去优化

4. **内存泄漏风险**
   - 缓解: LeakDetector在开发模式下始终启用

---

## 7. 增强型分代GC详细设计

### 7.1 内存区域布局

```
┌─────────────────────────────────────────────────────────────────┐
│                    Enhanced Generational GC                      │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    Nursery (Eden)                        │    │
│  │  Size: 2MB (可配置)                                      │    │
│  │  分配方式: Bump Pointer (O(1) 分配)                      │    │
│  │  ┌─────┬─────┬─────┬─────┬─────────────────────────┐    │    │
│  │  │Obj1 │Obj2 │Obj3 │Obj4 │      Free Space        │    │    │
│  │  └─────┴─────┴─────┴─────┴─────────────────────────┘    │    │
│  │                          ↑ allocation_ptr                │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              ↓ Minor GC                          │
│  ┌──────────────────────┐  ┌──────────────────────┐             │
│  │   Survivor Space 0   │  │   Survivor Space 1   │             │
│  │   Size: 256KB        │  │   Size: 256KB        │             │
│  │   (From Space)       │  │   (To Space)         │             │
│  │   ┌───┬───┬───┐      │  │   ┌───────────────┐  │             │
│  │   │S1 │S2 │S3 │      │  │   │   Empty       │  │             │
│  │   └───┴───┴───┘      │  │   └───────────────┘  │             │
│  └──────────────────────┘  └──────────────────────┘             │
│                              ↓ Promotion (age >= threshold)      │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    Old Generation                        │    │
│  │  Size: 动态增长 (初始8MB)                                │    │
│  │  分配方式: Free List + Segregated Fits                   │    │
│  │  ┌────────┬────────┬────────┬────────┬────────────┐     │    │
│  │  │ Block1 │ Block2 │  Free  │ Block3 │   Free     │     │    │
│  │  └────────┴────────┴────────┴────────┴────────────┘     │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Large Object Space (LOS)                    │    │
│  │  阈值: >8KB 直接分配                                     │    │
│  │  管理: 独立的大对象链表                                  │    │
│  │  回收: 与Old Gen同步进行                                 │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Card Table 跨代引用追踪

```zig
pub const CardTable = struct {
    /// 每个Card覆盖512字节的堆内存
    const CARD_SIZE: usize = 512;
    const CARD_SHIFT: u5 = 9; // log2(512)
    
    /// Card状态
    const CARD_CLEAN: u8 = 0;
    const CARD_DIRTY: u8 = 1;
    
    cards: []u8,
    heap_start: usize,
    heap_size: usize,
    
    pub fn init(allocator: std.mem.Allocator, heap_start: usize, heap_size: usize) !CardTable {
        const card_count = (heap_size + CARD_SIZE - 1) / CARD_SIZE;
        const cards = try allocator.alloc(u8, card_count);
        @memset(cards, CARD_CLEAN);
        return CardTable{
            .cards = cards,
            .heap_start = heap_start,
            .heap_size = heap_size,
        };
    }
    
    /// 写屏障: 当老年代对象引用年轻代对象时调用
    pub fn markCard(self: *CardTable, addr: usize) void {
        const offset = addr - self.heap_start;
        const card_index = offset >> CARD_SHIFT;
        if (card_index < self.cards.len) {
            self.cards[card_index] = CARD_DIRTY;
        }
    }
    
    /// 获取所有脏Card对应的地址范围
    pub fn getDirtyRanges(self: *CardTable, allocator: std.mem.Allocator) ![]AddressRange {
        var ranges = std.ArrayList(AddressRange).init(allocator);
        for (self.cards, 0..) |card, i| {
            if (card == CARD_DIRTY) {
                const start = self.heap_start + (i << CARD_SHIFT);
                try ranges.append(.{ .start = start, .end = start + CARD_SIZE });
            }
        }
        return ranges.toOwnedSlice();
    }
    
    /// Minor GC后清理Card Table
    pub fn clearDirtyCards(self: *CardTable) void {
        @memset(self.cards, CARD_CLEAN);
    }
    
    const AddressRange = struct { start: usize, end: usize };
};
```

### 7.3 GC触发策略

```zig
pub const GCTriggerPolicy = struct {
    /// 触发阈值配置
    nursery_threshold: f32 = 0.9,      // Nursery使用90%触发Minor GC
    old_gen_threshold: f32 = 0.7,      // Old Gen使用70%触发Major GC
    allocation_rate_threshold: usize = 10 * 1024 * 1024, // 10MB/s触发并发标记
    
    /// 自适应调整参数
    last_gc_time_ns: i64 = 0,
    last_allocation_bytes: usize = 0,
    gc_overhead_ratio: f32 = 0.0,
    
    pub fn shouldTriggerMinorGC(self: *GCTriggerPolicy, nursery: *Nursery) bool {
        const usage = @as(f32, @floatFromInt(nursery.used)) / 
                      @as(f32, @floatFromInt(nursery.size));
        return usage >= self.nursery_threshold;
    }
    
    pub fn shouldTriggerMajorGC(self: *GCTriggerPolicy, old_gen: *OldGeneration) bool {
        const usage = @as(f32, @floatFromInt(old_gen.used)) / 
                      @as(f32, @floatFromInt(old_gen.capacity));
        return usage >= self.old_gen_threshold;
    }
    
    pub fn shouldTriggerConcurrentMark(self: *GCTriggerPolicy, stats: *GCStats) bool {
        const current_time = std.time.nanoTimestamp();
        const elapsed_ns = current_time - self.last_gc_time_ns;
        if (elapsed_ns <= 0) return false;
        
        const allocation_rate = (stats.total_allocated - self.last_allocation_bytes) * 
                                1_000_000_000 / @as(usize, @intCast(elapsed_ns));
        return allocation_rate >= self.allocation_rate_threshold;
    }
    
    /// 根据GC开销自适应调整阈值
    pub fn adaptThresholds(self: *GCTriggerPolicy, gc_time_ns: i64, total_time_ns: i64) void {
        self.gc_overhead_ratio = @as(f32, @floatFromInt(gc_time_ns)) / 
                                  @as(f32, @floatFromInt(total_time_ns));
        
        // 如果GC开销过高，提高阈值减少GC频率
        if (self.gc_overhead_ratio > 0.1) {
            self.nursery_threshold = @min(0.95, self.nursery_threshold + 0.02);
            self.old_gen_threshold = @min(0.85, self.old_gen_threshold + 0.02);
        }
        // 如果GC开销很低，降低阈值更积极回收
        else if (self.gc_overhead_ratio < 0.02) {
            self.nursery_threshold = @max(0.7, self.nursery_threshold - 0.02);
            self.old_gen_threshold = @max(0.5, self.old_gen_threshold - 0.02);
        }
    }
};
```

---

## 8. 高级逃逸分析详细设计

### 8.1 逃逸状态定义

```zig
pub const EscapeState = enum(u8) {
    /// 不逃逸: 对象仅在当前函数内使用，可以栈分配
    NoEscape = 0,
    
    /// 参数逃逸: 对象通过参数传递但不被存储，调用者可决定分配位置
    ArgEscape = 1,
    
    /// 全局逃逸: 对象被存储到堆、全局变量或通过返回值逃逸，必须堆分配
    GlobalEscape = 2,
    
    /// 未知: 分析未完成或无法确定
    Unknown = 3,
};

pub const EscapeInfo = struct {
    state: EscapeState,
    /// 逃逸路径（用于调试和优化报告）
    escape_path: ?[]const EscapePoint = null,
    /// 是否可以执行标量替换
    can_scalar_replace: bool = false,
    /// 标量替换后的字段列表
    scalar_fields: ?[]const ScalarField = null,
    
    pub const EscapePoint = struct {
        location: SourceLocation,
        reason: EscapeReason,
    };
    
    pub const EscapeReason = enum {
        returned,           // 通过return返回
        stored_to_heap,     // 存储到堆对象
        stored_to_global,   // 存储到全局变量
        passed_to_unknown,  // 传递给未分析的函数
        captured_by_closure,// 被闭包捕获
        thrown_as_exception,// 作为异常抛出
    };
    
    pub const ScalarField = struct {
        name: []const u8,
        type_tag: Value.Tag,
        local_slot: u16,  // 替换后的局部变量槽位
    };
};
```

### 8.2 数据流图构建

```zig
pub const DataFlowGraph = struct {
    nodes: std.ArrayList(DFGNode),
    edges: std.ArrayList(DFGEdge),
    allocator: std.mem.Allocator,
    
    pub const DFGNode = struct {
        id: u32,
        kind: NodeKind,
        value: ?Value = null,
        escape_state: EscapeState = .Unknown,
        
        pub const NodeKind = enum {
            allocation,      // new Object(), []
            parameter,       // 函数参数
            local_var,       // 局部变量
            field_load,      // $obj->field
            field_store,     // $obj->field = $val
            array_load,      // $arr[$key]
            array_store,     // $arr[$key] = $val
            call_arg,        // 函数调用参数
            call_result,     // 函数调用返回值
            return_value,    // return语句
            phi,             // SSA phi节点
        };
    };
    
    pub const DFGEdge = struct {
        from: u32,
        to: u32,
        kind: EdgeKind,
        
        pub const EdgeKind = enum {
            def_use,         // 定义-使用关系
            points_to,       // 指向关系
            field_of,        // 字段关系
            element_of,      // 数组元素关系
        };
    };
    
    pub fn init(allocator: std.mem.Allocator) DataFlowGraph {
        return DataFlowGraph{
            .nodes = std.ArrayList(DFGNode).init(allocator),
            .edges = std.ArrayList(DFGEdge).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn addNode(self: *DataFlowGraph, kind: DFGNode.NodeKind) !u32 {
        const id = @as(u32, @intCast(self.nodes.items.len));
        try self.nodes.append(.{ .id = id, .kind = kind });
        return id;
    }
    
    pub fn addEdge(self: *DataFlowGraph, from: u32, to: u32, kind: DFGEdge.EdgeKind) !void {
        try self.edges.append(.{ .from = from, .to = to, .kind = kind });
    }
};
```

### 8.3 逃逸分析算法

```zig
pub const EscapeAnalyzer = struct {
    dfg: DataFlowGraph,
    worklist: std.ArrayList(u32),
    allocator: std.mem.Allocator,
    
    pub fn analyze(self: *EscapeAnalyzer, function: *CompiledFunction) !void {
        // Phase 1: 构建数据流图
        try self.buildDFG(function);
        
        // Phase 2: 初始化逃逸状态
        for (self.dfg.nodes.items) |*node| {
            node.escape_state = switch (node.kind) {
                .parameter => .ArgEscape,  // 参数初始为ArgEscape
                .allocation => .NoEscape,  // 分配初始为NoEscape
                .return_value => .GlobalEscape, // 返回值为GlobalEscape
                else => .Unknown,
            };
        }
        
        // Phase 3: 迭代传播逃逸状态
        try self.propagateEscapeStates();
        
        // Phase 4: 标量替换分析
        try self.analyzeScalarReplacement();
    }
    
    fn propagateEscapeStates(self: *EscapeAnalyzer) !void {
        // 将所有节点加入工作列表
        for (self.dfg.nodes.items, 0..) |_, i| {
            try self.worklist.append(@intCast(i));
        }
        
        // 迭代直到不动点
        while (self.worklist.items.len > 0) {
            const node_id = self.worklist.pop();
            const node = &self.dfg.nodes.items[node_id];
            
            // 计算新的逃逸状态
            var new_state = node.escape_state;
            
            // 检查所有出边
            for (self.dfg.edges.items) |edge| {
                if (edge.from == node_id) {
                    const target = &self.dfg.nodes.items[edge.to];
                    // 逃逸状态向上传播
                    new_state = @max(new_state, target.escape_state);
                }
            }
            
            // 如果状态改变，更新并将相关节点加入工作列表
            if (new_state != node.escape_state) {
                node.escape_state = new_state;
                // 将所有指向此节点的节点加入工作列表
                for (self.dfg.edges.items) |edge| {
                    if (edge.to == node_id) {
                        try self.worklist.append(edge.from);
                    }
                }
            }
        }
    }
    
    fn analyzeScalarReplacement(self: *EscapeAnalyzer) !void {
        for (self.dfg.nodes.items) |*node| {
            if (node.kind == .allocation and node.escape_state == .NoEscape) {
                // 检查是否所有字段访问都是独立的
                var can_replace = true;
                var fields = std.ArrayList(EscapeInfo.ScalarField).init(self.allocator);
                
                for (self.dfg.edges.items) |edge| {
                    if (edge.from == node.id and edge.kind == .field_of) {
                        const field_node = &self.dfg.nodes.items[edge.to];
                        if (field_node.kind == .field_load or field_node.kind == .field_store) {
                            // 可以替换为标量
                            try fields.append(.{
                                .name = "field", // 实际实现需要从AST获取
                                .type_tag = .integer, // 实际实现需要类型推断
                                .local_slot = @intCast(fields.items.len),
                            });
                        } else {
                            can_replace = false;
                            break;
                        }
                    }
                }
                
                if (can_replace and fields.items.len > 0) {
                    // 标记为可标量替换
                    // 实际实现需要存储到EscapeInfo
                }
            }
        }
    }
};
```

---

## 9. 复杂类型指针传参优化详细设计

### 9.1 类型大小分类

```zig
pub const TypeSizeCategory = enum {
    /// 小型值类型: <=64字节，值传递
    SmallValue,
    /// 中型类型: 64-256字节，根据使用模式决定
    MediumValue,
    /// 大型类型: >256字节，指针传递
    LargeValue,
    /// 动态大小: 运行时确定
    DynamicSize,
};

pub const PassingConvention = enum {
    /// 值传递: 复制整个值
    ByValue,
    /// 常量指针传递: 不可修改
    ByConstPointer,
    /// 可变指针传递: 可修改
    ByMutablePointer,
    /// Copy-on-Write: 延迟复制
    ByCOW,
};

pub const TypePassingInfo = struct {
    category: TypeSizeCategory,
    convention: PassingConvention,
    estimated_size: ?usize,
    requires_runtime_check: bool,
    
    /// 根据类型信息推断传递方式
    pub fn infer(type_tag: Value.Tag, size_hint: ?usize) TypePassingInfo {
        return switch (type_tag) {
            // 基本类型始终值传递
            .null, .boolean, .integer, .float => .{
                .category = .SmallValue,
                .convention = .ByValue,
                .estimated_size = 8,
                .requires_runtime_check = false,
            },
            
            // 字符串默认指针传递
            .string => .{
                .category = .DynamicSize,
                .convention = .ByCOW,
                .estimated_size = null,
                .requires_runtime_check = false, // 字符串总是指针
            },
            
            // 数组根据大小决定
            .array => blk: {
                if (size_hint) |size| {
                    if (size <= 16) {
                        break :blk .{
                            .category = .SmallValue,
                            .convention = .ByValue,
                            .estimated_size = size * 8,
                            .requires_runtime_check = false,
                        };
                    }
                }
                break :blk .{
                    .category = .DynamicSize,
                    .convention = .ByCOW,
                    .estimated_size = null,
                    .requires_runtime_check = true,
                };
            },
            
            // 对象和结构体根据大小决定
            .object, .struct_instance => blk: {
                if (size_hint) |size| {
                    if (size <= 64) {
                        break :blk .{
                            .category = .SmallValue,
                            .convention = .ByValue,
                            .estimated_size = size,
                            .requires_runtime_check = false,
                        };
                    } else if (size <= 256) {
                        break :blk .{
                            .category = .MediumValue,
                            .convention = .ByConstPointer,
                            .estimated_size = size,
                            .requires_runtime_check = false,
                        };
                    }
                }
                break :blk .{
                    .category = .LargeValue,
                    .convention = .ByConstPointer,
                    .estimated_size = size_hint,
                    .requires_runtime_check = size_hint == null,
                };
            },
            
            else => .{
                .category = .SmallValue,
                .convention = .ByValue,
                .estimated_size = 8,
                .requires_runtime_check = false,
            },
        };
    }
};
```

### 9.2 Copy-on-Write实现

```zig
pub const COWWrapper = struct {
    /// 引用计数
    ref_count: u32,
    /// 是否为共享状态
    is_shared: bool,
    /// 实际数据指针
    data: *anyopaque,
    /// 数据大小
    size: usize,
    /// 复制函数
    copy_fn: *const fn (*anyopaque, std.mem.Allocator) anyerror!*anyopaque,
    
    pub fn init(data: *anyopaque, size: usize, copy_fn: anytype) COWWrapper {
        return COWWrapper{
            .ref_count = 1,
            .is_shared = false,
            .data = data,
            .size = size,
            .copy_fn = copy_fn,
        };
    }
    
    /// 获取只读访问
    pub fn getReadOnly(self: *COWWrapper) *anyopaque {
        return self.data;
    }
    
    /// 获取可写访问（必要时复制）
    pub fn getWritable(self: *COWWrapper, allocator: std.mem.Allocator) !*anyopaque {
        if (self.ref_count > 1 or self.is_shared) {
            // 需要复制
            const new_data = try self.copy_fn(self.data, allocator);
            self.ref_count -= 1;
            self.data = new_data;
            self.ref_count = 1;
            self.is_shared = false;
        }
        return self.data;
    }
    
    /// 增加引用
    pub fn retain(self: *COWWrapper) void {
        self.ref_count += 1;
        if (self.ref_count > 1) {
            self.is_shared = true;
        }
    }
    
    /// 减少引用
    pub fn release(self: *COWWrapper, allocator: std.mem.Allocator, free_fn: *const fn (*anyopaque, std.mem.Allocator) void) void {
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            free_fn(self.data, allocator);
        }
    }
};
```

### 9.3 参数传递优化器

```zig
pub const ParameterPassingOptimizer = struct {
    allocator: std.mem.Allocator,
    type_cache: std.AutoHashMap(u64, TypePassingInfo),
    
    pub fn init(allocator: std.mem.Allocator) ParameterPassingOptimizer {
        return ParameterPassingOptimizer{
            .allocator = allocator,
            .type_cache = std.AutoHashMap(u64, TypePassingInfo).init(allocator),
        };
    }
    
    /// 优化函数参数传递
    pub fn optimizeFunction(self: *ParameterPassingOptimizer, func: *CompiledFunction) !void {
        for (func.parameters) |*param| {
            const passing_info = self.analyzeParameter(param);
            param.passing_convention = passing_info.convention;
            
            if (passing_info.requires_runtime_check) {
                // 生成运行时大小检查代码
                try self.generateRuntimeCheck(func, param);
            }
        }
    }
    
    fn analyzeParameter(self: *ParameterPassingOptimizer, param: *const Parameter) TypePassingInfo {
        // 检查缓存
        const cache_key = hashParameter(param);
        if (self.type_cache.get(cache_key)) |cached| {
            return cached;
        }
        
        // 推断传递方式
        const type_tag = param.type_hint orelse .mixed;
        const size_hint = param.size_hint;
        const info = TypePassingInfo.infer(type_tag, size_hint);
        
        // 考虑readonly修饰符
        var final_info = info;
        if (param.is_readonly) {
            final_info.convention = .ByConstPointer;
        }
        
        // 缓存结果
        self.type_cache.put(cache_key, final_info) catch {};
        
        return final_info;
    }
    
    fn generateRuntimeCheck(self: *ParameterPassingOptimizer, func: *CompiledFunction, param: *const Parameter) !void {
        // 生成类似以下的运行时检查:
        // if (sizeof(param) > 64) {
        //     use_pointer_passing();
        // } else {
        //     use_value_passing();
        // }
        _ = self;
        _ = func;
        _ = param;
    }
    
    fn hashParameter(param: *const Parameter) u64 {
        var hash: u64 = 0;
        if (param.type_hint) |t| {
            hash = @intFromEnum(t);
        }
        if (param.size_hint) |s| {
            hash = hash *% 31 +% s;
        }
        return hash;
    }
};
```

### 9.4 字符串和数组的特殊处理

```zig
/// 字符串传递优化
pub const StringPassingStrategy = struct {
    /// 短字符串阈值（内联存储）
    const SHORT_STRING_THRESHOLD: usize = 23;
    
    pub fn shouldInline(str: *PHPString) bool {
        return str.length <= SHORT_STRING_THRESHOLD;
    }
    
    pub fn pass(str: *PHPString, is_readonly: bool) PassingConvention {
        if (shouldInline(str)) {
            return .ByValue;
        }
        return if (is_readonly) .ByConstPointer else .ByCOW;
    }
};

/// 数组传递优化
pub const ArrayPassingStrategy = struct {
    /// 小数组阈值（元素数）
    const SMALL_ARRAY_THRESHOLD: usize = 16;
    
    pub fn shouldCopyOnPass(arr: *PHPArray) bool {
        return arr.count() <= SMALL_ARRAY_THRESHOLD;
    }
    
    pub fn pass(arr: *PHPArray, is_readonly: bool) PassingConvention {
        if (shouldCopyOnPass(arr)) {
            return .ByValue;
        }
        return if (is_readonly) .ByConstPointer else .ByCOW;
    }
    
    /// 估算数组内存大小
    pub fn estimateSize(arr: *PHPArray) usize {
        var size: usize = @sizeOf(PHPArray);
        var iter = arr.elements.iterator();
        while (iter.next()) |entry| {
            size += @sizeOf(ArrayKey) + @sizeOf(Value);
            // 递归计算嵌套数组大小
            if (entry.value_ptr.getTag() == .array) {
                size += estimateSize(entry.value_ptr.getAsArray().data);
            }
        }
        return size;
    }
};
