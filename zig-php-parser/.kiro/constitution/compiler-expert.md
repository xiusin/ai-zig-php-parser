# PHP-Zig编译器系统宪法

**版本**: 2.0.0  
**生效日期**: 2026-03-14  
**适用范围**: 整个编译器系统的所有组件  
**宪法性质**: 强制性、不可违背的开发准则  

---

## 📜 前言

本宪法是PHP-Zig编译器系统的最高开发准则，定义了从词法分析到机器码生成的完整编译器开发标准。我们将PHP-Zig视为一门**完整的编程语言实现**，而非简单的解释器项目。

### 项目定位

**目标**: 开发世界级性能的生产级PHP编译器系统  
**标准**: 对标V8、LuaJIT、PyPy等顶级语言实现  
**性能**: 在完全兼容PHP 8.5的前提下，达到C语言90-95%的执行效率  
**质量**: 工业级代码质量，可用于生产环境  

### 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                     PHP-Zig编译器系统                        │
├─────────────────────────────────────────────────────────────┤
│  前端 (Frontend)                                             │
│  ├─ Lexer (词法分析器)                                       │
│  ├─ Parser (语法分析器)                                      │
│  ├─ AST (抽象语法树)                                         │
│  └─ Semantic Analyzer (语义分析器)                          │
├─────────────────────────────────────────────────────────────┤
│  中端 (Middle-end)                                           │
│  ├─ IR Generator (中间表示生成器)                           │
│  ├─ Type Inference (类型推断)                               │
│  ├─ Optimizer (优化器)                                       │
│  │  ├─ SSA Construction (SSA构造)                           │
│  │  ├─ Dead Code Elimination (死代码消除)                   │
│  │  ├─ Constant Folding (常量折叠)                          │
│  │  ├─ Loop Optimization (循环优化)                         │
│  │  ├─ Inlining (内联)                                      │
│  │  └─ Escape Analysis (逃逸分析)                           │
│  └─ Data Flow Analysis (数据流分析)                         │
├─────────────────────────────────────────────────────────────┤
│  后端 (Backend)                                              │
│  ├─ Code Generator (代码生成器)                             │
│  │  ├─ Register Allocation (寄存器分配)                     │
│  │  ├─ Instruction Selection (指令选择)                     │
│  │  └─ Peephole Optimization (窥孔优化)                     │
│  ├─ JIT Compiler (即时编译器)                               │
│  │  ├─ Hotspot Detection (热点检测)                         │
│  │  ├─ Tiered Compilation (分层编译)                        │
│  │  └─ On-Stack Replacement (栈上替换)                      │
│  └─ AOT Compiler (提前编译器)                               │
│     ├─ Native Code Generation (本地代码生成)                │
│     ├─ Link-Time Optimization (链接时优化)                  │
│     └─ Profile-Guided Optimization (性能引导优化)           │
├─────────────────────────────────────────────────────────────┤
│  运行时 (Runtime)                                            │
│  ├─ VM (虚拟机)                                              │
│  │  ├─ Bytecode Interpreter (字节码解释器)                  │
│  │  ├─ Stack Management (栈管理)                            │
│  │  └─ Exception Handling (异常处理)                        │
│  ├─ Memory Management (内存管理)                            │
│  │  ├─ Garbage Collector (垃圾回收器)                       │
│  │  │  ├─ Generational GC (分代GC)                         │
│  │  │  ├─ Incremental GC (增量GC)                          │
│  │  │  ├─ Concurrent GC (并发GC)                           │
│  │  │  └─ Compacting GC (压缩GC)                           │
│  │  ├─ Object Pool (对象池)                                 │
│  │  └─ Arena Allocator (区域分配器)                         │
│  ├─ Type System (类型系统)                                  │
│  │  ├─ Value Representation (值表示)                        │
│  │  ├─ Type Checking (类型检查)                             │
│  │  └─ Type Coercion (类型转换)                             │
│  ├─ Concurrency (并发)                                      │
│  │  ├─ Coroutine (协程)                                     │
│  │  ├─ Scheduler (调度器)                                   │
│  │  └─ Channel (通道)                                       │
│  └─ Standard Library (标准库)                               │
│     ├─ Built-in Functions (内置函数)                        │
│     ├─ Built-in Classes (内置类)                            │
│     └─ Extension System (扩展系统)                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 📐 基本原则（不可违背）

### 1. 性能至上原则

**定义**: 性能是第一优先级，任何功能实现都必须基于性能考虑。

**具体要求**:
- ❌ **严禁**为了实现简单而牺牲性能
- ❌ **严禁**使用低效算法（如O(n²)替代O(n log n)）
- ❌ **严禁**不必要的内存分配和拷贝
- ✅ **必须**使用最优算法和数据结构
- ✅ **必须**进行性能基准测试对比
- ✅ **必须**提供性能分析报告

**示例**:
```zig
// ❌ 错误：简单但低效
fn findSymbol(symbols: []Symbol, name: []const u8) ?*Symbol {
    for (symbols) |*sym| {  // O(n) 线性查找
        if (std.mem.eql(u8, sym.name, name)) return sym;
    }
    return null;
}

// ✅ 正确：使用哈希表 O(1)
fn findSymbol(symbol_table: *SymbolTable, name: []const u8) ?*Symbol {
    return symbol_table.map.get(name);  // O(1) 哈希查找
}
```

### 2. 零成本抽象原则

**定义**: 抽象不应该带来运行时开销。

**具体要求**:
- ✅ 使用编译时计算（comptime）
- ✅ 使用内联函数（inline）
- ✅ 使用泛型避免类型擦除
- ❌ 避免虚函数调用
- ❌ 避免动态分发

**示例**:
```zig
// ✅ 零成本抽象：编译时多态
fn optimize(comptime T: type, value: T) T {
    return switch (T) {
        i64 => optimizeInt(value),
        f64 => optimizeFloat(value),
        else => value,
    };
}

// ❌ 有成本：运行时多态
fn optimize(value: anytype) @TypeOf(value) {
    if (@TypeOf(value) == i64) return optimizeInt(value);
    if (@TypeOf(value) == f64) return optimizeFloat(value);
    return value;
}
```

### 3. 内存安全原则

**定义**: 所有内存操作必须安全，无泄漏、无悬空指针、无数据竞争。

**具体要求**:
- ✅ 使用Zig的所有权系统
- ✅ 明确标注内存所有权（@ownership注释）
- ✅ 使用Arena分配器管理生命周期
- ✅ 实现RAII模式（defer释放）
- ❌ 禁止裸指针操作（除非必要且有注释）
- ❌ 禁止手动内存管理（除非性能关键路径）

**示例**:
```zig
// ✅ 正确：明确所有权
/// @ownership OWNING (allocator)
/// @thread-safety ISOLATED
pub const Module = struct {
    allocator: Allocator,
    functions: std.ArrayListUnmanaged(*Function),
    
    pub fn deinit(self: *Module) void {
        for (self.functions.items) |func| {
            func.deinit();
            self.allocator.destroy(func);
        }
        self.functions.deinit(self.allocator);
    }
};

// ❌ 错误：所有权不明确
pub const Module = struct {
    functions: []*Function,  // 谁拥有这些指针？
};
```

### 4. 线程安全原则

**定义**: 所有并发代码必须线程安全，无数据竞争。

**具体要求**:
- ✅ 使用原子操作（std.atomic）
- ✅ 使用互斥锁保护共享状态
- ✅ 优先使用无锁数据结构
- ✅ 明确标注线程安全性（@thread-safety注释）
- ❌ 禁止未保护的共享可变状态

**线程安全级别**:
- `ISOLATED`: 完全隔离，无共享状态
- `IMMUTABLE`: 不可变，可安全共享
- `SYNCHRONIZED`: 使用锁保护
- `LOCK_FREE`: 无锁并发安全
- `UNSAFE`: 不安全，需要外部同步

**示例**:
```zig
// ✅ 正确：明确线程安全性
/// @thread-safety LOCK_FREE
pub const AtomicCounter = struct {
    value: std.atomic.Value(u64),
    
    pub fn increment(self: *AtomicCounter) u64 {
        return self.value.fetchAdd(1, .monotonic);
    }
};

// ❌ 错误：未标注线程安全性
pub const Counter = struct {
    value: u64,  // 线程不安全！
    
    pub fn increment(self: *Counter) u64 {
        self.value += 1;
        return self.value;
    }
};
```

### 5. 算法精妙原则

**定义**: 使用最优算法，追求理论和实践的完美结合。

**具体要求**:
- ✅ 选择最优时间复杂度算法
- ✅ 考虑缓存友好性（Cache-friendly）
- ✅ 使用SIMD优化（当适用时）
- ✅ 实现分支预测友好的代码
- ✅ 提供算法复杂度分析注释

**常用优化技术**:
1. **循环展开** (Loop Unrolling)
2. **向量化** (Vectorization/SIMD)
3. **预取** (Prefetching)
4. **分支消除** (Branch Elimination)
5. **内存对齐** (Memory Alignment)

**示例**:
```zig
// ✅ 正确：SIMD优化的字符串比较
/// 时间复杂度: O(n/16) with SIMD
/// 空间复杂度: O(1)
/// Cache-friendly: 顺序访问
fn compareStringSIMD(a: []const u8, b: []const u8) bool {
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

### 6. 底层原理原则

**定义**: 深入理解底层原理，从CPU、内存、编译器角度优化。

**必须理解的底层知识**:
1. **CPU架构**: 流水线、分支预测、超标量执行
2. **内存层次**: L1/L2/L3缓存、TLB、内存带宽
3. **编译器优化**: 内联、常量折叠、死代码消除
4. **ABI**: 调用约定、寄存器使用、栈帧布局
5. **指令集**: x86-64、ARM64、SIMD指令

**示例**:
```zig
// ✅ 正确：考虑缓存行对齐
/// 缓存行对齐：避免false sharing
pub const AtomicStats = struct {
    // 每个字段占用独立的缓存行（64字节）
    count: std.atomic.Value(u64) align(64),
    sum: std.atomic.Value(u64) align(64),
    max: std.atomic.Value(u64) align(64),
};

// ❌ 错误：未考虑缓存行
pub const AtomicStats = struct {
    count: std.atomic.Value(u64),  // 可能在同一缓存行
    sum: std.atomic.Value(u64),    // 导致false sharing
    max: std.atomic.Value(u64),
};
```

### 7. 字节级优化原则

**定义**: 在性能关键路径上，优化到字节级别。

**具体要求**:
- ✅ 使用位操作代替算术运算
- ✅ 使用查找表代替计算
- ✅ 紧凑的数据布局（减少padding）
- ✅ 使用NaN-boxing等技术
- ✅ 手写关键汇编代码（当必要时）

**示例**:
```zig
// ✅ 正确：NaN-boxing优化Value表示
/// 使用64位表示所有PHP值类型
/// 布局：
/// - 整数: 0x0000_0000_XXXX_XXXX (低48位)
/// - 浮点: 0xFFFF_XXXX_XXXX_XXXX (NaN区域)
/// - 指针: 0x0001_XXXX_XXXX_XXXX (高16位标记)
pub const Value = packed struct {
    bits: u64,
    
    pub inline fn initInt(i: i48) Value {
        return .{ .bits = @bitCast(i) };
    }
    
    pub inline fn isInt(self: Value) bool {
        return (self.bits & 0xFFFF_0000_0000_0000) == 0;
    }
    
    pub inline fn asInt(self: Value) i48 {
        return @truncate(@as(i64, @bitCast(self.bits)));
    }
};
```

### 8. 长远考虑原则

**定义**: 架构设计必须考虑未来扩展和演进。

**具体要求**:
- ✅ 设计可扩展的接口
- ✅ 预留优化空间
- ✅ 考虑向后兼容性
- ✅ 文档化设计决策
- ❌ 避免过度设计

**设计模式**:
1. **策略模式**: 可替换的算法实现
2. **访问者模式**: 可扩展的AST遍历
3. **构建器模式**: 复杂对象构建
4. **对象池模式**: 高频对象复用

**示例**:
```zig
// ✅ 正确：可扩展的优化器架构
pub const Optimizer = struct {
    passes: []const OptimizationPass,
    
    pub const OptimizationPass = struct {
        name: []const u8,
        run: *const fn(*Module) anyerror!void,
        level: OptLevel,  // 预留优化级别控制
    };
    
    pub fn addPass(self: *Optimizer, pass: OptimizationPass) !void {
        // 支持动态添加优化Pass
    }
};
```

### 9. 统一接口原则

**定义**: 多模式功能应该使用统一的接口。

**具体要求**:
- ✅ 解释器、JIT、AOT共享相同的IR
- ✅ 统一的类型系统
- ✅ 统一的错误处理
- ✅ 统一的内存管理接口

**示例**:
```zig
// ✅ 正确：统一的执行接口
pub const ExecutionMode = enum { interpreter, jit, aot };

pub const Runtime = struct {
    mode: ExecutionMode,
    
    pub fn execute(self: *Runtime, module: *Module) !Value {
        return switch (self.mode) {
            .interpreter => self.vm.execute(module),
            .jit => self.jit.execute(module),
            .aot => self.aot.execute(module),
        };
    }
};
```

---

## 🚫 严格禁止事项

### 1. 性能妥协

- ❌ 为了实现简单而使用低效算法
- ❌ 不进行性能测试就提交代码
- ❌ 忽略性能回归
- ❌ 使用慢速的标准库函数（如未优化的排序）

### 2. 内存问题

- ❌ 内存泄漏
- ❌ 悬空指针
- ❌ 双重释放
- ❌ 未初始化内存访问
- ❌ 缓冲区溢出

### 3. 并发问题

- ❌ 数据竞争
- ❌ 死锁
- ❌ 活锁
- ❌ 未保护的共享状态

### 4. 代码质量

- ❌ 未注释的复杂算法
- ❌ 魔法数字（未定义的常量）
- ❌ 过长的函数（>200行）
- ❌ 深层嵌套（>4层）
- ❌ 未处理的错误

---

## ✅ 强制要求

### 1. 代码注释

**必须包含**:
```zig
/// 函数功能简述
/// 
/// 算法: 使用的算法名称
/// 时间复杂度: O(?)
/// 空间复杂度: O(?)
/// 线程安全: ISOLATED/SYNCHRONIZED/LOCK_FREE/UNSAFE
/// 所有权: OWNING/NON-OWNING/SHARED
/// 
/// 参数:
///   - param1: 参数说明
/// 返回:
///   - 返回值说明
/// 错误:
///   - 可能的错误类型
/// 
/// 示例:
/// ```zig
/// const result = try function(arg);
/// ```
pub fn function(param1: Type) !ReturnType {
    // 实现
}
```

### 2. 性能基准

**每个性能关键函数必须有基准测试**:
```zig
test "benchmark: string comparison" {
    const iterations = 1_000_000;
    const start = std.time.nanoTimestamp();
    
    for (0..iterations) |_| {
        _ = compareString("hello", "world");
    }
    
    const end = std.time.nanoTimestamp();
    const ns_per_op = @divTrunc(end - start, iterations);
    
    // 断言性能要求
    try std.testing.expect(ns_per_op < 50); // 必须<50ns
}
```

### 3. 内存安全检查

**使用工具验证**:
```bash
# Valgrind检查
valgrind --leak-check=full ./php-interpreter test.php

# AddressSanitizer
zig build -Doptimize=Debug -fsanitize=address

# ThreadSanitizer
zig build -Doptimize=Debug -fsanitize=thread
```

### 4. 代码审查清单

**提交前必须检查**:
- [ ] 性能基准测试通过
- [ ] 无内存泄漏（Valgrind）
- [ ] 无数据竞争（ThreadSanitizer）
- [ ] 代码覆盖率 ≥ 90%
- [ ] 所有测试通过
- [ ] 文档更新
- [ ] 性能分析报告

---

## 🎯 性能目标

### 解释器模式
- 函数调用: < 50ns
- 对象创建: < 200ns
- 数组操作: < 10ns/元素
- 字符串操作: < 5ns/字符

### JIT模式
- 热点检测: < 100次调用
- 编译时间: < 10ms/函数
- 执行速度: 接近AOT（80-90%）

### AOT模式
- 编译时间: < 5秒/1000行
- 执行速度: 接近C（90-95%）
- 二进制大小: < 2MB（静态链接）

### 内存使用
- 解释器: < 100MB
- JIT: < 200MB
- AOT: < 50MB（运行时）

---

## 🔧 开发流程

### 1. 设计阶段

**必须产出**:
1. 设计文档（算法、数据结构、接口）
2. 性能分析（预期性能、瓶颈分析）
3. 风险评估（复杂度、兼容性、性能风险）

**复杂方案必须多代理讨论**:
- 当方案复杂度 > 500行代码
- 当涉及核心架构修改
- 当性能影响 > 5%
- 当不确定最优方案

### 2. 实现阶段

**开发顺序**:
1. 实现最小可行版本（MVP）
2. 添加性能基准测试
3. 优化性能（达到目标）
4. 添加完整测试
5. 编写文档

**代码规范**:
- 使用`zig fmt`格式化
- 遵循Zig命名约定
- 添加完整注释
- 标注所有权和线程安全性

### 3. 测试阶段

**测试类型**:
1. **单元测试**: 覆盖所有函数
2. **集成测试**: 测试模块交互
3. **性能测试**: 验证性能目标
4. **压力测试**: 测试极限情况
5. **回归测试**: 防止性能退化

### 4. 审查阶段

**审查重点**:
1. 性能是否达标
2. 内存是否安全
3. 线程是否安全
4. 算法是否最优
5. 代码是否清晰

---

## 🤖 AI代理协作规则

### 单代理任务
- 简单功能实现（< 200行）
- 明确的算法实现
- 文档编写
- 测试编写

### 多代理任务（必须）
- 核心架构设计
- 复杂优化实现（> 500行）
- 性能关键路径优化
- 不确定的技术方案

### 代理角色分工

**架构师代理**:
- 设计系统架构
- 评估技术方案
- 制定性能目标

**算法专家代理**:
- 选择最优算法
- 分析时间/空间复杂度
- 设计数据结构

**性能优化代理**:
- 识别性能瓶颈
- 实施底层优化
- SIMD/缓存优化

**安全审查代理**:
- 检查内存安全
- 检查线程安全
- 检查边界条件

### 协作流程

```
用户需求
    ↓
架构师代理（设计方案）
    ↓
算法专家代理（选择算法）
    ↓
性能优化代理（优化实现）
    ↓
安全审查代理（安全检查）
    ↓
反馈给用户审核
```

---

## 📊 自验证机制（防幻觉）

### 1. 代码验证

**编译验证**:
```bash
zig build  # 必须编译通过
```

**测试验证**:
```bash
zig build test  # 所有测试必须通过
```

**性能验证**:
```bash
zig build benchmark  # 性能必须达标
```

### 2. 逻辑验证

**算法正确性**:
- 提供数学证明或引用论文
- 提供测试用例覆盖边界条件
- 提供反例测试

**性能声明**:
- 提供基准测试数据
- 提供性能分析报告
- 提供对比测试

### 3. 安全验证

**内存安全**:
```bash
valgrind --leak-check=full ./test
# 必须: 0 bytes leaked
```

**线程安全**:
```bash
zig build -fsanitize=thread
./test
# 必须: 无数据竞争警告
```

---

## 📚 参考资料

### 必读论文
1. **编译器优化**: "Engineering a Compiler" (Cooper & Torczon)
2. **垃圾回收**: "The Garbage Collection Handbook" (Jones et al.)
3. **JIT编译**: "A Brief History of Just-In-Time" (Aycock)
4. **类型推断**: "Types and Programming Languages" (Pierce)

### 必读代码
1. **V8**: JavaScript引擎（JIT、优化器）
2. **LuaJIT**: Lua JIT编译器（性能优化）
3. **LLVM**: 编译器基础设施（IR、优化）
4. **Zig**: Zig编译器（内存安全、性能）

### 性能优化资源
1. **Intel优化手册**: CPU微架构优化
2. **Agner Fog优化指南**: 底层性能优化
3. **SIMD教程**: 向量化编程
4. **缓存优化**: Cache-friendly编程

---

## 🎓 专家级要求总结

### 技术深度
- 精通Zig语言（所有权、comptime、错误处理）
- 精通编译原理（词法、语法、语义、优化）
- 精通计算机体系结构（CPU、内存、缓存）
- 精通算法与数据结构（时间/空间复杂度）
- 精通并发编程（原子操作、无锁算法）

### 性能意识
- 每行代码都考虑性能影响
- 能识别性能瓶颈
- 能实施底层优化
- 能进行性能分析

### 工程素养
- 代码清晰可维护
- 文档完整准确
- 测试覆盖全面
- 遵循最佳实践

---

**宪法维护者**: AI开发团队  
**最后更新**: 2026-03-14  
**版本**: 1.0.0  

---

**声明**: 本宪法是强制性的，所有AI代理在开发编译器相关功能时必须严格遵守。违反宪法的代码将被拒绝。
