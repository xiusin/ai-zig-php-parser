# Design Document: Zig-PHP Performance Optimization

## Overview

本设计文档描述了将Zig-PHP解释器性能从当前的~500x慢于原生PHP优化到~10x以内的系统架构和实现方案。

### 当前架构问题分析

| 组件 | 当前实现 | 性能瓶颈 | 目标实现 |
|------|----------|----------|----------|
| Value表示 | Tagged Union (128-bit) | 每次操作需switch分发 | NaN-boxing (64-bit) |
| 执行模型 | Tree-walking AST | 每节点递归调用eval() | Bytecode VM + Dispatch Table |
| 内存分配 | 每值独立堆分配 | 频繁malloc/free | Arena + Object Pool |
| 函数调用 | HashMap查找 | O(n) hash计算 | Direct dispatch + IC |
| 数组 | ArrayHashMap | 无packed优化 | Packed Array + COW |
| 字符串 | 独立PHPString | 无SSO/interning | SSO + Rope + Interning |
| GC | 引用计数+周期检测 | 每操作RC更新 | 分代GC + 延迟RC |

### 性能目标

```
目标: 将整体性能从 0.002x 提升到 0.1x (50倍提升)

分解目标:
- Value操作: 10x 提升 (NaN-boxing)
- 执行循环: 5x 提升 (Bytecode + Dispatch Table)
- 内存分配: 3x 提升 (Arena + Pool)
- 函数调用: 5x 提升 (Direct dispatch)
- 数组操作: 10x 提升 (Packed + SIMD)
- 字符串操作: 5x 提升 (SSO + SIMD)
```

---

## Component Design

### 1. NaN-Boxing Value System

#### 1.1 设计原理

IEEE 754双精度浮点数中，NaN值的位模式为:
- 指数位全1 (bits 52-62)
- 尾数位非零 (bits 0-51)

这给我们提供了51位的payload空间来编码其他类型。

#### 1.2 位布局设计

```
64-bit Value Layout:

┌─────────────────────────────────────────────────────────────────┐
│ Float (normal):  [sign:1][exp:11][mantissa:52]                  │
│ NaN-boxed:       [1111111111111][tag:3][payload:48]             │
└─────────────────────────────────────────────────────────────────┘

Tag encoding (3 bits):
  000 = Pointer (heap object)
  001 = Integer (48-bit signed, covers PHP int range)
  010 = Boolean (payload bit 0)
  011 = Null
  100 = Undefined
  101 = Reserved
  110 = Reserved  
  111 = Reserved

Pointer types (distinguished by object header):
  - PHPString*
  - PHPArray*
  - PHPObject*
  - Closure*
  - Resource*
```

#### 1.3 数据结构

```zig
/// NaN-boxed Value - 64位紧凑表示
pub const Value = packed struct {
    bits: u64,

    // NaN-boxing常量
    const QNAN: u64 = 0x7FFC_0000_0000_0000;
    const SIGN_BIT: u64 = 0x8000_0000_0000_0000;
    const TAG_MASK: u64 = 0x0003_0000_0000_0000;
    const PAYLOAD_MASK: u64 = 0x0000_FFFF_FFFF_FFFF;
    
    // 类型标签
    const TAG_PTR: u64 = 0x0000_0000_0000_0000;
    const TAG_INT: u64 = 0x0001_0000_0000_0000;
    const TAG_BOOL: u64 = 0x0002_0000_0000_0000;
    const TAG_NULL: u64 = 0x0003_0000_0000_0000;

    // 特殊值
    pub const NULL: Value = .{ .bits = QNAN | SIGN_BIT | TAG_NULL };
    pub const TRUE: Value = .{ .bits = QNAN | SIGN_BIT | TAG_BOOL | 1 };
    pub const FALSE: Value = .{ .bits = QNAN | SIGN_BIT | TAG_BOOL | 0 };
    pub const UNDEFINED: Value = .{ .bits = QNAN | SIGN_BIT | 0x0004_0000_0000_0000 };

    /// 创建整数值 - O(1) 无分配
    pub inline fn initInt(val: i64) Value {
        // 48位有符号整数，范围 [-140737488355328, 140737488355327]
        const payload: u64 = @bitCast(@as(i48, @truncate(val)));
        return .{ .bits = QNAN | SIGN_BIT | TAG_INT | (payload & PAYLOAD_MASK) };
    }

    /// 创建浮点值 - O(1) 无分配
    pub inline fn initFloat(val: f64) Value {
        return .{ .bits = @bitCast(val) };
    }

    /// 创建指针值 - O(1)
    pub inline fn initPtr(ptr: *anyopaque) Value {
        return .{ .bits = QNAN | SIGN_BIT | TAG_PTR | @intFromPtr(ptr) };
    }

    /// 类型检查 - O(1) 位操作
    pub inline fn isFloat(self: Value) bool {
        return (self.bits & QNAN) != QNAN or self.bits == @as(u64, @bitCast(@as(f64, 0.0)));
    }

    pub inline fn isInt(self: Value) bool {
        return (self.bits & (QNAN | SIGN_BIT | TAG_MASK)) == (QNAN | SIGN_BIT | TAG_INT);
    }

    pub inline fn isNull(self: Value) bool {
        return self.bits == NULL.bits;
    }

    pub inline fn isBool(self: Value) bool {
        return (self.bits & (QNAN | SIGN_BIT | TAG_MASK)) == (QNAN | SIGN_BIT | TAG_BOOL);
    }

    pub inline fn isPtr(self: Value) bool {
        return (self.bits & (QNAN | SIGN_BIT | TAG_MASK)) == (QNAN | SIGN_BIT | TAG_PTR);
    }

    /// 值提取 - O(1)
    pub inline fn asInt(self: Value) i64 {
        const payload: u48 = @truncate(self.bits & PAYLOAD_MASK);
        return @as(i64, @as(i48, @bitCast(payload)));
    }

    pub inline fn asFloat(self: Value) f64 {
        return @bitCast(self.bits);
    }

    pub inline fn asBool(self: Value) bool {
        return (self.bits & 1) != 0;
    }

    pub inline fn asPtr(self: Value, comptime T: type) *T {
        return @ptrFromInt(self.bits & PAYLOAD_MASK);
    }
};
```

#### 1.4 性能对比

| 操作 | 当前实现 | NaN-boxing | 提升 |
|------|----------|------------|------|
| 类型检查 | switch (16 cases) | 位与操作 | ~10x |
| 整数创建 | 堆分配 + Box | 位操作 | ~100x |
| 整数加法 | switch + 解包 + 装包 | 直接位操作 | ~20x |
| 值复制 | 引用计数更新 | 64位复制 | ~50x |

---

### 2. Optimized Bytecode VM

#### 2.1 指令集设计

```zig
/// 紧凑指令格式 - 32位定长
pub const Instruction = packed struct {
    opcode: OpCode,      // 8 bits
    operand1: u8,        // 8 bits (register/local index)
    operand2: u16,       // 16 bits (constant index/jump offset)
};

/// 操作码 - 按频率排序以优化分支预测
pub const OpCode = enum(u8) {
    // 高频指令 (0x00-0x1F)
    load_local = 0x00,
    store_local = 0x01,
    load_const = 0x02,
    add_int = 0x03,
    sub_int = 0x04,
    mul_int = 0x05,
    lt_int = 0x06,
    jmp = 0x07,
    jz = 0x08,
    call = 0x09,
    ret = 0x0A,
    
    // 中频指令 (0x20-0x3F)
    add_float = 0x20,
    concat_str = 0x21,
    array_get = 0x22,
    array_set = 0x23,
    prop_get = 0x24,
    prop_set = 0x25,
    
    // 低频指令 (0x40+)
    new_array = 0x40,
    new_object = 0x41,
    // ...
};
```

#### 2.2 Dispatch Table实现

```zig
/// 分发函数类型
const DispatchFn = *const fn (*VM, Instruction) void;

/// 256项分发表 - 编译时初始化
const dispatch_table: [256]DispatchFn = comptime blk: {
    var table: [256]DispatchFn = undefined;
    for (&table) |*entry| {
        entry.* = &handleInvalid;
    }
    
    // 注册处理函数
    table[@intFromEnum(OpCode.load_local)] = &handleLoadLocal;
    table[@intFromEnum(OpCode.store_local)] = &handleStoreLocal;
    table[@intFromEnum(OpCode.add_int)] = &handleAddInt;
    // ... 其他指令
    
    break :blk table;
};

/// 主执行循环 - 使用计算跳转
pub fn run(self: *VM) Value {
    while (true) {
        const inst = self.fetch();
        
        // 预取下一条指令 (CPU流水线优化)
        @prefetch(self.code.ptr + self.ip + 1, .{
            .locality = 3,
            .cache = .data,
        });
        
        // 分发表调用
        dispatch_table[@intFromEnum(inst.opcode)](self, inst);
        
        if (self.should_return) {
            return self.return_value;
        }
    }
}

/// 整数加法 - 特化实现
fn handleAddInt(vm: *VM, inst: Instruction) void {
    const a = vm.stack[vm.sp - 2];
    const b = vm.stack[vm.sp - 1];
    
    // 快速路径: 两个都是整数
    if (a.isInt() and b.isInt()) {
        vm.stack[vm.sp - 2] = Value.initInt(a.asInt() +% b.asInt());
        vm.sp -= 1;
        return;
    }
    
    // 慢速路径: 类型转换
    vm.slowAddPath(a, b);
}
```

---

### 3. Memory Allocation Optimization

#### 3.1 Arena Allocator增强

```zig
/// 高性能Arena - 支持对齐和批量释放
pub const FastArena = struct {
    chunks: [MAX_CHUNKS]*Chunk,
    chunk_count: u8,
    current: *Chunk,
    
    const MAX_CHUNKS = 16;
    const CHUNK_SIZE = 256 * 1024; // 256KB
    
    const Chunk = struct {
        data: [CHUNK_SIZE]u8 align(64),
        offset: usize,
        
        pub inline fn alloc(self: *Chunk, size: usize, alignment: usize) ?[*]u8 {
            const aligned = std.mem.alignForward(usize, self.offset, alignment);
            if (aligned + size > CHUNK_SIZE) return null;
            self.offset = aligned + size;
            return @ptrCast(&self.data[aligned]);
        }
    };
    
    /// Bump allocation - O(1) 无锁
    pub inline fn alloc(self: *FastArena, comptime T: type) !*T {
        const ptr = self.current.alloc(@sizeOf(T), @alignOf(T)) orelse {
            try self.newChunk();
            return self.alloc(T);
        };
        return @ptrCast(@alignCast(ptr));
    }
    
    /// 批量重置 - O(1)
    pub fn reset(self: *FastArena) void {
        for (self.chunks[0..self.chunk_count]) |chunk| {
            chunk.offset = 0;
        }
        self.current = self.chunks[0];
    }
};
```

#### 3.2 Object Pool优化

```zig
/// 无锁对象池 - 使用freelist
pub fn FastPool(comptime T: type) type {
    return struct {
        const Self = @This();
        const SLAB_SIZE = 64;
        
        freelist: ?*Node,
        slabs: std.ArrayListUnmanaged(*[SLAB_SIZE]Node),
        
        const Node = struct {
            data: T,
            next: ?*Node,
        };
        
        /// 获取对象 - O(1) 摊销
        pub inline fn acquire(self: *Self) !*T {
            if (self.freelist) |node| {
                self.freelist = node.next;
                return &node.data;
            }
            return self.allocSlab();
        }
        
        /// 释放对象 - O(1)
        pub inline fn release(self: *Self, ptr: *T) void {
            const node: *Node = @fieldParentPtr("data", ptr);
            node.next = self.freelist;
            self.freelist = node;
        }
    };
}
```

#### 3.3 String Interning优化

```zig
/// 高性能字符串驻留池
pub const StringInterner = struct {
    /// 使用Swiss Table实现的哈希表
    table: SwissTable(InternedString),
    arena: *FastArena,
    
    const InternedString = struct {
        hash: u64,
        len: u32,
        data: [*]const u8,
    };
    
    /// 驻留字符串 - O(1) 平均
    pub fn intern(self: *StringInterner, str: []const u8) []const u8 {
        const hash = wyhash(str);
        
        // 快速路径: 已存在
        if (self.table.getByHash(hash, str)) |entry| {
            return entry.data[0..entry.len];
        }
        
        // 慢速路径: 插入新字符串
        const data = self.arena.dupeZ(u8, str);
        self.table.put(.{
            .hash = hash,
            .len = @intCast(str.len),
            .data = data.ptr,
        });
        return data;
    }
};
```

---

### 4. Packed Array Optimization

#### 4.1 数组类型判别

```zig
/// PHP数组的多态表示
pub const PHPArray = union(enum) {
    /// 紧凑数组: 连续整数键 [0, 1, 2, ...]
    packed: PackedArray,
    /// 混合数组: 整数和字符串键混合
    mixed: MixedArray,
    /// 空数组
    empty: void,
    
    pub fn get(self: *PHPArray, key: ArrayKey) ?Value {
        return switch (self.*) {
            .packed => |*p| p.get(key),
            .mixed => |*m| m.get(key),
            .empty => null,
        };
    }
};

/// 紧凑数组 - 连续内存布局
pub const PackedArray = struct {
    values: []Value,
    len: u32,
    capacity: u32,
    
    /// O(1) 索引访问
    pub inline fn get(self: *PackedArray, key: ArrayKey) ?Value {
        switch (key) {
            .integer => |i| {
                if (i >= 0 and i < self.len) {
                    return self.values[@intCast(i)];
                }
                return null;
            },
            .string => return null, // 触发转换为mixed
        }
    }
    
    /// SIMD加速的数值操作
    pub fn sum(self: *PackedArray) i64 {
        const vec_size = 4;
        var result: @Vector(vec_size, i64) = @splat(0);
        
        var i: usize = 0;
        while (i + vec_size <= self.len) : (i += vec_size) {
            const chunk = self.values[i..][0..vec_size];
            // 假设都是整数
            const ints: @Vector(vec_size, i64) = .{
                chunk[0].asInt(),
                chunk[1].asInt(),
                chunk[2].asInt(),
                chunk[3].asInt(),
            };
            result += ints;
        }
        
        // 处理剩余元素
        var scalar: i64 = @reduce(.Add, result);
        while (i < self.len) : (i += 1) {
            scalar += self.values[i].asInt();
        }
        return scalar;
    }
};
```

---

### 5. Inline Caching for Property/Method Access

#### 5.1 Shape System (Hidden Classes)

```zig
/// 对象形状 - 描述属性布局
pub const Shape = struct {
    id: u32,
    parent: ?*Shape,
    property_map: PropertyMap,
    transition_map: TransitionMap,
    
    const PropertyMap = std.StringHashMapUnmanaged(PropertySlot);
    const TransitionMap = std.StringHashMapUnmanaged(*Shape);
    
    const PropertySlot = struct {
        offset: u16,      // 属性在对象中的偏移
        flags: Flags,
        
        const Flags = packed struct {
            writable: bool = true,
            enumerable: bool = true,
            configurable: bool = true,
        };
    };
    
    /// 添加属性转换 - 返回新Shape
    pub fn transition(self: *Shape, allocator: std.mem.Allocator, name: []const u8) !*Shape {
        // 检查是否已有转换
        if (self.transition_map.get(name)) |existing| {
            return existing;
        }
        
        // 创建新Shape
        const new_shape = try allocator.create(Shape);
        new_shape.* = .{
            .id = nextShapeId(),
            .parent = self,
            .property_map = try self.property_map.clone(allocator),
            .transition_map = .{},
        };
        
        // 添加新属性槽
        const offset: u16 = @intCast(new_shape.property_map.count());
        try new_shape.property_map.put(allocator, name, .{ .offset = offset, .flags = .{} });
        
        // 记录转换
        try self.transition_map.put(allocator, name, new_shape);
        
        return new_shape;
    }
};

/// 内联缓存条目
pub const InlineCache = struct {
    shape_id: u32,        // 缓存的Shape ID
    offset: u16,          // 属性偏移
    hits: u16,            // 命中计数
    
    const INVALID: InlineCache = .{ .shape_id = 0, .offset = 0, .hits = 0 };
    
    /// 尝试快速属性访问
    pub inline fn tryGet(self: *InlineCache, obj: *PHPObject) ?Value {
        if (obj.shape.id == self.shape_id) {
            self.hits +|= 1;
            return obj.slots[self.offset];
        }
        return null; // IC miss, 需要慢速路径
    }
    
    /// 更新缓存
    pub fn update(self: *InlineCache, shape: *Shape, name: []const u8) void {
        if (shape.property_map.get(name)) |slot| {
            self.shape_id = shape.id;
            self.offset = slot.offset;
            self.hits = 0;
        }
    }
};
```

#### 5.2 多态内联缓存 (PIC)

```zig
/// 多态内联缓存 - 支持多个Shape
pub const PolymorphicIC = struct {
    entries: [MAX_ENTRIES]Entry,
    count: u8,
    
    const MAX_ENTRIES = 4;
    
    const Entry = struct {
        shape_id: u32,
        offset: u16,
    };
    
    /// 查找或更新
    pub fn lookup(self: *PolymorphicIC, obj: *PHPObject, name: []const u8) ?u16 {
        const shape_id = obj.shape.id;
        
        // 线性搜索 (4项足够小，cache友好)
        for (self.entries[0..self.count]) |entry| {
            if (entry.shape_id == shape_id) {
                return entry.offset;
            }
        }
        
        // 未命中，尝试添加
        if (self.count < MAX_ENTRIES) {
            if (obj.shape.property_map.get(name)) |slot| {
                self.entries[self.count] = .{
                    .shape_id = shape_id,
                    .offset = slot.offset,
                };
                self.count += 1;
                return slot.offset;
            }
        }
        
        return null; // Megamorphic, 回退到HashMap
    }
};
```

---

### 6. Function Call Optimization

#### 6.1 Direct Dispatch Table

```zig
/// 内置函数直接分发表
pub const BuiltinDispatch = struct {
    /// 编译时生成的函数指针表
    const table = comptime blk: {
        var t: [BUILTIN_COUNT]BuiltinFn = undefined;
        
        // 字符串函数
        t[@intFromEnum(BuiltinId.strlen)] = &builtinStrlen;
        t[@intFromEnum(BuiltinId.substr)] = &builtinSubstr;
        t[@intFromEnum(BuiltinId.str_replace)] = &builtinStrReplace;
        
        // 数组函数
        t[@intFromEnum(BuiltinId.count)] = &builtinCount;
        t[@intFromEnum(BuiltinId.array_push)] = &builtinArrayPush;
        t[@intFromEnum(BuiltinId.in_array)] = &builtinInArray;
        
        // 数学函数
        t[@intFromEnum(BuiltinId.abs)] = &builtinAbs;
        t[@intFromEnum(BuiltinId.floor)] = &builtinFloor;
        t[@intFromEnum(BuiltinId.ceil)] = &builtinCeil;
        
        break :blk t;
    };
    
    /// 函数名到ID的完美哈希
    const name_to_id = comptime PerfectHash.build(&.{
        .{ "strlen", BuiltinId.strlen },
        .{ "substr", BuiltinId.substr },
        .{ "count", BuiltinId.count },
        // ...
    });
    
    /// O(1) 函数调用
    pub inline fn call(id: BuiltinId, args: []Value) Value {
        return table[@intFromEnum(id)](args);
    }
    
    /// 函数名解析 (编译时或首次调用时)
    pub fn resolve(name: []const u8) ?BuiltinId {
        return name_to_id.get(name);
    }
};

/// 特化的内置函数实现
fn builtinStrlen(args: []Value) Value {
    if (args.len != 1) return Value.initInt(0);
    
    const arg = args[0];
    if (arg.isPtr()) {
        const str = arg.asPtr(*PHPString);
        return Value.initInt(@intCast(str.len));
    }
    return Value.initInt(0);
}

fn builtinCount(args: []Value) Value {
    if (args.len != 1) return Value.initInt(0);
    
    const arg = args[0];
    if (arg.isPtr()) {
        const header = arg.asPtr(*ObjectHeader);
        if (header.type == .array) {
            const arr = @fieldParentPtr(PHPArray, "header", header);
            return Value.initInt(@intCast(arr.count()));
        }
    }
    return Value.initInt(0);
}
```

#### 6.2 CallFrame Pool

```zig
/// 调用帧池 - 避免函数调用时的堆分配
pub const CallFramePool = struct {
    frames: [MAX_DEPTH]CallFrame,
    depth: u16,
    
    const MAX_DEPTH = 1024;
    
    pub const CallFrame = struct {
        function: *Function,
        ip: u32,
        bp: u32,              // base pointer (局部变量起始)
        return_addr: u32,
        locals: [MAX_LOCALS]Value,
        
        const MAX_LOCALS = 64;
    };
    
    /// 压入新帧 - O(1)
    pub inline fn push(self: *CallFramePool, func: *Function) !*CallFrame {
        if (self.depth >= MAX_DEPTH) {
            return error.StackOverflow;
        }
        const frame = &self.frames[self.depth];
        frame.function = func;
        frame.ip = 0;
        frame.bp = if (self.depth > 0) 
            self.frames[self.depth - 1].bp + self.frames[self.depth - 1].function.local_count
        else 0;
        self.depth += 1;
        return frame;
    }
    
    /// 弹出帧 - O(1)
    pub inline fn pop(self: *CallFramePool) void {
        if (self.depth > 0) {
            self.depth -= 1;
        }
    }
    
    /// 获取当前帧
    pub inline fn current(self: *CallFramePool) *CallFrame {
        return &self.frames[self.depth - 1];
    }
};
```

---

### 7. String Optimization

#### 7.1 Small String Optimization (SSO)

```zig
/// SSO字符串 - 短字符串内联存储
pub const SSOString = extern struct {
    data: Data,
    
    const SSO_CAPACITY = 23;
    
    const Data = extern union {
        /// 短字符串: 内联存储
        small: extern struct {
            chars: [SSO_CAPACITY]u8,
            len: u8,  // 最高位为0表示短字符串
        },
        /// 长字符串: 堆分配
        large: extern struct {
            ptr: [*]u8,
            len: usize,
            capacity: usize,
        },
    };
    
    /// 创建字符串
    pub fn init(allocator: std.mem.Allocator, str: []const u8) !SSOString {
        if (str.len <= SSO_CAPACITY) {
            var result = SSOString{ .data = undefined };
            @memcpy(result.data.small.chars[0..str.len], str);
            result.data.small.len = @intCast(str.len);
            return result;
        }
        
        // 长字符串
        const ptr = try allocator.alloc(u8, str.len);
        @memcpy(ptr, str);
        return .{ .data = .{ .large = .{
            .ptr = ptr.ptr,
            .len = str.len,
            .capacity = str.len,
        }}};
    }
    
    /// 获取字符串切片
    pub inline fn slice(self: *const SSOString) []const u8 {
        if (self.isSmall()) {
            return self.data.small.chars[0..self.data.small.len];
        }
        return self.data.large.ptr[0..self.data.large.len];
    }
    
    /// 检查是否为短字符串
    pub inline fn isSmall(self: *const SSOString) bool {
        return (self.data.small.len & 0x80) == 0;
    }
    
    /// 长度
    pub inline fn len(self: *const SSOString) usize {
        if (self.isSmall()) {
            return self.data.small.len;
        }
        return self.data.large.len;
    }
};
```

#### 7.2 SIMD String Operations

```zig
/// SIMD加速的字符串操作
pub const SimdString = struct {
    const Vec = @Vector(16, u8);
    
    /// SIMD strlen - 16字节并行处理
    pub fn strlen(str: [*]const u8) usize {
        var ptr = str;
        
        // 对齐到16字节边界
        while (@intFromPtr(ptr) & 15 != 0) {
            if (ptr[0] == 0) return @intFromPtr(ptr) - @intFromPtr(str);
            ptr += 1;
        }
        
        // SIMD主循环
        const zero: Vec = @splat(0);
        while (true) {
            const chunk: Vec = @as(*const Vec, @ptrCast(@alignCast(ptr))).*;
            const cmp = chunk == zero;
            const mask = @as(u16, @bitCast(cmp));
            
            if (mask != 0) {
                const offset = @ctz(mask);
                return @intFromPtr(ptr) - @intFromPtr(str) + offset;
            }
            ptr += 16;
        }
    }
    
    /// SIMD memcmp
    pub fn memcmp(a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;
        
        var i: usize = 0;
        while (i + 16 <= a.len) : (i += 16) {
            const va: Vec = a[i..][0..16].*;
            const vb: Vec = b[i..][0..16].*;
            if (@reduce(.Or, va != vb)) return false;
        }
        
        // 处理剩余字节
        return std.mem.eql(u8, a[i..], b[i..]);
    }
    
    /// SIMD strstr (简化版)
    pub fn strstr(haystack: []const u8, needle: []const u8) ?usize {
        if (needle.len == 0) return 0;
        if (needle.len > haystack.len) return null;
        
        const first = needle[0];
        const first_vec: Vec = @splat(first);
        
        var i: usize = 0;
        while (i + 16 <= haystack.len - needle.len + 1) : (i += 16) {
            const chunk: Vec = haystack[i..][0..16].*;
            const cmp = chunk == first_vec;
            var mask = @as(u16, @bitCast(cmp));
            
            while (mask != 0) {
                const offset = @ctz(mask);
                const pos = i + offset;
                if (std.mem.eql(u8, haystack[pos..][0..needle.len], needle)) {
                    return pos;
                }
                mask &= mask - 1; // 清除最低位
            }
        }
        
        // 处理剩余部分
        return std.mem.indexOf(u8, haystack[i..], needle);
    }
};
```

---

### 8. Bytecode Compiler Optimization

#### 8.1 Constant Folding

```zig
/// 编译时常量折叠
pub const ConstantFolder = struct {
    /// 折叠二元表达式
    pub fn foldBinary(op: BinaryOp, left: Value, right: Value) ?Value {
        // 只折叠常量
        if (!left.isConstant() or !right.isConstant()) return null;
        
        return switch (op) {
            .add => blk: {
                if (left.isInt() and right.isInt()) {
                    break :blk Value.initInt(left.asInt() +% right.asInt());
                }
                if (left.isFloat() or right.isFloat()) {
                    break :blk Value.initFloat(left.toFloat() + right.toFloat());
                }
                break :blk null;
            },
            .sub => blk: {
                if (left.isInt() and right.isInt()) {
                    break :blk Value.initInt(left.asInt() -% right.asInt());
                }
                break :blk null;
            },
            .mul => blk: {
                if (left.isInt() and right.isInt()) {
                    break :blk Value.initInt(left.asInt() *% right.asInt());
                }
                break :blk null;
            },
            .concat => blk: {
                // 字符串连接折叠
                if (left.isString() and right.isString()) {
                    // 在编译时连接字符串常量
                    break :blk null; // 需要allocator，延迟处理
                }
                break :blk null;
            },
            else => null,
        };
    }
    
    /// 折叠一元表达式
    pub fn foldUnary(op: UnaryOp, operand: Value) ?Value {
        if (!operand.isConstant()) return null;
        
        return switch (op) {
            .neg => blk: {
                if (operand.isInt()) {
                    break :blk Value.initInt(-operand.asInt());
                }
                if (operand.isFloat()) {
                    break :blk Value.initFloat(-operand.asFloat());
                }
                break :blk null;
            },
            .not => Value.initBool(!operand.toBool()),
            else => null,
        };
    }
};
```

#### 8.2 Register Allocation

```zig
/// 简单寄存器分配器 - 用于栈顶缓存
pub const RegisterAllocator = struct {
    /// 虚拟寄存器到物理寄存器的映射
    reg_map: [MAX_REGS]?VarId,
    /// 寄存器使用计数 (LRU)
    use_count: [MAX_REGS]u32,
    next_use: u32,
    
    const MAX_REGS = 8;
    const VarId = u16;
    
    /// 分配寄存器给变量
    pub fn allocate(self: *RegisterAllocator, var_id: VarId) u8 {
        // 检查是否已分配
        for (self.reg_map, 0..) |mapped, i| {
            if (mapped == var_id) {
                self.use_count[i] = self.next_use;
                self.next_use += 1;
                return @intCast(i);
            }
        }
        
        // 找空闲寄存器
        for (self.reg_map, 0..) |mapped, i| {
            if (mapped == null) {
                self.reg_map[i] = var_id;
                self.use_count[i] = self.next_use;
                self.next_use += 1;
                return @intCast(i);
            }
        }
        
        // LRU驱逐
        var min_use: u32 = std.math.maxInt(u32);
        var victim: u8 = 0;
        for (self.use_count, 0..) |use, i| {
            if (use < min_use) {
                min_use = use;
                victim = @intCast(i);
            }
        }
        
        self.reg_map[victim] = var_id;
        self.use_count[victim] = self.next_use;
        self.next_use += 1;
        return victim;
    }
    
    /// 释放寄存器
    pub fn release(self: *RegisterAllocator, reg: u8) void {
        self.reg_map[reg] = null;
    }
};
```

---

### 9. Generational GC Design

#### 9.1 分代堆布局

```zig
/// 分代垃圾回收器
pub const GenerationalGC = struct {
    /// 年轻代 (Nursery) - Bump allocation
    nursery: Nursery,
    /// 老年代 - Mark-Sweep
    old_gen: OldGeneration,
    /// 记忆集 - 跨代引用
    remembered_set: RememberedSet,
    /// 统计信息
    stats: GCStats,
    
    const Nursery = struct {
        start: [*]u8,
        end: [*]u8,
        cursor: [*]u8,
        
        const SIZE = 2 * 1024 * 1024; // 2MB
        
        /// Bump allocation - O(1)
        pub inline fn alloc(self: *Nursery, size: usize) ?*anyopaque {
            const aligned_size = std.mem.alignForward(usize, size, 8);
            if (@intFromPtr(self.cursor) + aligned_size > @intFromPtr(self.end)) {
                return null; // 触发Minor GC
            }
            const ptr = self.cursor;
            self.cursor += aligned_size;
            return @ptrCast(ptr);
        }
        
        /// 重置 (Minor GC后)
        pub fn reset(self: *Nursery) void {
            self.cursor = self.start;
        }
    };
    
    const OldGeneration = struct {
        allocator: std.mem.Allocator,
        objects: std.ArrayListUnmanaged(*ObjectHeader),
        
        pub fn alloc(self: *OldGeneration, size: usize) !*anyopaque {
            return try self.allocator.alignedAlloc(u8, 8, size);
        }
    };
    
    const RememberedSet = struct {
        /// 使用位图记录包含跨代引用的老年代对象
        bitmap: std.DynamicBitSetUnmanaged,
        
        pub fn add(self: *RememberedSet, obj_index: usize) void {
            self.bitmap.set(obj_index);
        }
        
        pub fn clear(self: *RememberedSet) void {
            self.bitmap.setRangeValue(.{ .start = 0, .end = self.bitmap.capacity() }, false);
        }
    };
    
    /// 写屏障 - 在指针写入时调用
    pub inline fn writeBarrier(self: *GenerationalGC, obj: *ObjectHeader, new_ref: *ObjectHeader) void {
        // 只有老年代对象引用年轻代对象时才记录
        if (obj.generation == .old and new_ref.generation == .young) {
            self.remembered_set.add(obj.index);
        }
    }
    
    /// Minor GC - 只收集年轻代
    pub fn minorGC(self: *GenerationalGC) void {
        const start_time = std.time.nanoTimestamp();
        
        // 1. 标记根集
        self.markRoots();
        
        // 2. 标记记忆集中的对象
        var iter = self.remembered_set.bitmap.iterator(.{});
        while (iter.next()) |idx| {
            self.markFromOldGen(idx);
        }
        
        // 3. 复制存活对象到老年代
        self.evacuateNursery();
        
        // 4. 重置年轻代
        self.nursery.reset();
        self.remembered_set.clear();
        
        const elapsed = std.time.nanoTimestamp() - start_time;
        self.stats.minor_gc_time_ns += @intCast(elapsed);
        self.stats.minor_gc_count += 1;
    }
};
```

#### 9.2 增量标记

```zig
/// 增量标记器 - 避免长停顿
pub const IncrementalMarker = struct {
    gray_stack: std.ArrayListUnmanaged(*ObjectHeader),
    state: State,
    work_done: usize,
    
    const State = enum { idle, marking, sweeping };
    const WORK_QUANTUM = 1000; // 每次增量工作量
    
    /// 执行增量标记步骤
    pub fn step(self: *IncrementalMarker) bool {
        var work: usize = 0;
        
        while (work < WORK_QUANTUM and self.gray_stack.items.len > 0) {
            const obj = self.gray_stack.pop();
            self.scanObject(obj);
            work += 1;
        }
        
        self.work_done += work;
        return self.gray_stack.items.len == 0; // 返回是否完成
    }
    
    fn scanObject(self: *IncrementalMarker, obj: *ObjectHeader) void {
        obj.mark = .black;
        
        // 扫描对象的引用
        switch (obj.type) {
            .array => {
                const arr = @fieldParentPtr(PHPArray, "header", obj);
                for (arr.values()) |val| {
                    if (val.isPtr()) {
                        const ref = val.asPtr(*ObjectHeader);
                        if (ref.mark == .white) {
                            ref.mark = .gray;
                            self.gray_stack.append(ref) catch {};
                        }
                    }
                }
            },
            .object => {
                // 类似处理对象属性
            },
            else => {},
        }
    }
};
```

---

## Correctness Properties

### 不变量 (Invariants)

1. **Value表示不变量**
   - NaN-boxed Value的类型标签必须与实际存储的数据类型一致
   - 指针类型的Value必须指向有效的堆对象
   - 整数值必须在48位有符号范围内

2. **内存安全不变量**
   - 所有堆分配的对象必须有对应的释放路径
   - 引用计数必须准确反映实际引用数
   - Arena分配的对象不能在Arena重置后访问

3. **GC不变量**
   - 三色标记: 黑色对象不能直接引用白色对象
   - 写屏障: 老年代到年轻代的引用必须记录在记忆集中
   - 根集完整性: 所有活跃的栈帧和全局变量必须作为GC根

4. **Shape不变量**
   - 对象的Shape必须与其实际属性布局一致
   - Shape转换必须是确定性的 (相同属性序列产生相同Shape)
   - 内联缓存的Shape ID必须与目标对象匹配

### 前置条件 (Preconditions)

```zig
/// 函数调用前置条件
fn callFunction(vm: *VM, func: *Function, args: []Value) !Value {
    // P1: 参数数量匹配
    std.debug.assert(args.len >= func.min_params);
    std.debug.assert(args.len <= func.max_params);
    
    // P2: 栈空间充足
    std.debug.assert(vm.stack_depth + func.max_stack < MAX_STACK);
    
    // P3: 函数已编译
    std.debug.assert(func.bytecode != null);
    
    // ...
}

/// 数组访问前置条件
fn arrayGet(arr: *PHPArray, key: ArrayKey) ?Value {
    // P1: 数组未被释放
    std.debug.assert(arr.header.ref_count > 0);
    
    // P2: 键类型有效
    std.debug.assert(key == .integer or key == .string);
    
    // ...
}
```

### 后置条件 (Postconditions)

```zig
/// GC后置条件
fn minorGC(gc: *GenerationalGC) void {
    // ... GC实现 ...
    
    // Q1: 年轻代已清空
    std.debug.assert(gc.nursery.cursor == gc.nursery.start);
    
    // Q2: 记忆集已清空
    std.debug.assert(gc.remembered_set.count() == 0);
    
    // Q3: 所有存活对象已晋升或复制
    // (通过测试验证)
}
```

---

## Error Handling Strategy

```zig
/// 统一错误类型
pub const VMError = error{
    // 运行时错误
    StackOverflow,
    OutOfMemory,
    DivisionByZero,
    TypeMismatch,
    UndefinedVariable,
    UndefinedFunction,
    UndefinedProperty,
    NullReference,
    
    // 编译错误
    SyntaxError,
    SemanticError,
    
    // 系统错误
    IoError,
    AllocationFailed,
};

/// 错误处理模式
pub fn safeEval(vm: *VM, node: NodeIndex) VMError!Value {
    return vm.eval(node) catch |err| {
        // 记录错误上下文
        vm.error_context = .{
            .file = vm.current_file,
            .line = vm.current_line,
            .message = errorMessage(err),
        };
        
        // 尝试恢复或传播
        if (vm.exception_handler) |handler| {
            return handler.handle(err);
        }
        return err;
    };
}
```

---

## Testing Strategy

### 单元测试

```zig
test "NaN-boxing: integer round-trip" {
    const cases = [_]i64{ 0, 1, -1, 42, -42, 
        std.math.maxInt(i48), std.math.minInt(i48) };
    
    for (cases) |val| {
        const v = Value.initInt(val);
        try std.testing.expect(v.isInt());
        try std.testing.expectEqual(val, v.asInt());
    }
}

test "NaN-boxing: float preservation" {
    const cases = [_]f64{ 0.0, 1.0, -1.0, 3.14159, 
        std.math.inf(f64), -std.math.inf(f64) };
    
    for (cases) |val| {
        const v = Value.initFloat(val);
        try std.testing.expect(v.isFloat());
        try std.testing.expectEqual(val, v.asFloat());
    }
}
```

### 基准测试

```zig
test "benchmark: integer addition" {
    const iterations = 1_000_000;
    var timer = try std.time.Timer.start();
    
    var sum = Value.initInt(0);
    for (0..iterations) |i| {
        sum = Value.initInt(sum.asInt() +% @as(i64, @intCast(i)));
    }
    
    const elapsed_ns = timer.read();
    const ns_per_op = elapsed_ns / iterations;
    
    std.debug.print("\nInteger add: {} ns/op\n", .{ns_per_op});
    try std.testing.expect(ns_per_op < 10); // 目标: <10ns/op
}
```

---

## Implementation Priority

| 优先级 | 组件 | 预期提升 | 复杂度 | 依赖 |
|--------|------|----------|--------|------|
| P0 | NaN-boxing Value | 10x | 中 | 无 |
| P0 | Dispatch Table | 5x | 低 | 无 |
| P1 | Packed Array | 5x | 中 | NaN-boxing |
| P1 | String SSO | 3x | 低 | 无 |
| P1 | Object Pool | 2x | 低 | 无 |
| P2 | Inline Cache | 3x | 高 | Shape System |
| P2 | SIMD String | 2x | 中 | 无 |
| P2 | Constant Folding | 1.5x | 低 | 无 |
| P3 | Generational GC | 2x | 高 | NaN-boxing |
| P3 | Register Allocation | 1.5x | 中 | Bytecode VM |
