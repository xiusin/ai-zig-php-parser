# OSR (On-Stack Replacement) 实现文档

## 概述

OSR (On-Stack Replacement) 是一种优化技术，允许在循环执行过程中从解释执行无缝切换到 JIT 编译的原生代码，无需等待函数返回。这对于长时间运行的循环特别有效，可以显著提升性能。

## 核心组件

### 1. FrameSnapshot（栈帧快照）

栈帧快照捕获解释器执行时的完整状态，包括：

- **程序计数器 (PC)**：当前字节码偏移
- **栈指针 (SP)**：操作数栈的当前位置
- **局部变量**：最多 256 个局部变量的值
- **操作数栈**：最多 256 个栈元素的值

```zig
pub const FrameSnapshot = struct {
    pc: u32,
    sp: u32,
    local_count: u16,
    locals: [256]i64,
    stack: [256]i64,
    stack_depth: u16,
};
```

### 2. OSREntry（OSR 入口点）

OSR 入口点表示一个可以从解释执行切换到 JIT 代码的位置：

```zig
pub const OSREntry = struct {
    bytecode_offset: u32,
    code_ptr: *const fn (*const FrameSnapshot) callconv(.c) i64,
    timestamp: i64,
    valid: bool,
};
```

### 3. OSRManager（OSR 管理器）

OSR 管理器负责管理所有 OSR 入口点的生命周期：

- **注册入口点**：将 JIT 编译的代码注册为 OSR 入口点
- **查找入口点**：根据函数 ID 和字节码偏移查找 OSR 入口点
- **失效入口点**：当代码需要重新编译时使入口点失效
- **统计信息**：跟踪 OSR 转换的成功率和失败率

```zig
pub const OSRManager = struct {
    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(u64, OSREntry),
    threshold: u32,
    stats: OSRStats,
};
```

### 4. StackCapture（栈状态捕获器）

栈状态捕获器负责从解释器栈帧中提取状态：

```zig
pub fn captureFrame(
    pc: u32,
    sp: u32,
    locals: []const i64,
    stack: []const i64,
) !FrameSnapshot
```

### 5. OSRTransition（OSR 转换器）

OSR 转换器执行实际的状态转换：

- **transitionToJIT**：从解释执行切换到 JIT 代码
- **fallbackToInterpreter**：从 JIT 代码回退到解释执行

## 工作流程

### 1. 热点检测

```
解释器执行循环
    ↓
循环迭代计数 >= 阈值？
    ↓ 是
触发 JIT 编译
```

### 2. JIT 编译

```
字节码
    ↓
IR 生成
    ↓
优化
    ↓
原生代码生成
    ↓
注册 OSR 入口点
```

### 3. OSR 转换

```
解释器执行到 OSR 点
    ↓
捕获栈帧状态
    ↓
查找 OSR 入口点
    ↓
验证快照完整性
    ↓
调用 JIT 代码
    ↓
继续执行
```

### 4. 回退机制

```
JIT 代码执行失败
    ↓
恢复栈帧状态
    ↓
回退到解释执行
    ↓
继续执行
```

## 使用示例

### 基本用法

```zig
const osr = @import("osr.zig");

// 1. 创建 OSR 管理器
const manager = try osr.OSRManager.init(allocator);
defer manager.deinit();

// 2. 捕获栈帧状态
const snapshot = try osr.StackCapture.captureFrame(
    pc,
    sp,
    locals,
    stack,
);

// 3. 注册 JIT 代码
try manager.registerEntry(function_id, bytecode_offset, jit_code_ptr);

// 4. 查找并执行 OSR 转换
if (manager.findEntry(function_id, bytecode_offset)) |entry| {
    const result = try osr.OSRTransition.transitionToJIT(
        entry,
        &snapshot,
        &manager.stats,
    );
}
```

### 与 JIT 编译器集成

```zig
// 在 JIT 编译器中
pub fn compileWithOSR(
    self: *JITCompiler,
    function_id: u32,
    bytecode: []const Instruction,
    osr_manager: *OSRManager,
) !void {
    // 1. 编译字节码
    const native_code = try self.compile(bytecode);
    
    // 2. 为每个循环头注册 OSR 入口点
    for (bytecode, 0..) |inst, offset| {
        if (inst.opcode == .loop_header) {
            try osr_manager.registerEntry(
                function_id,
                @intCast(offset),
                native_code.entry_point,
            );
        }
    }
}
```

### 在解释器中使用

```zig
// 在字节码虚拟机中
pub fn execute(
    self: *BytecodeVM,
    bytecode: []const Instruction,
    osr_manager: *OSRManager,
) !Value {
    var pc: u32 = 0;
    
    while (pc < bytecode.len) {
        const inst = bytecode[pc];
        
        // 检查是否有 OSR 入口点
        if (osr_manager.findEntry(self.function_id, pc)) |entry| {
            // 捕获当前状态
            const snapshot = try StackCapture.captureFrame(
                pc,
                @intCast(self.stack.items.len),
                self.locals,
                self.stack.items,
            );
            
            // 执行 OSR 转换
            const result = osr.OSRTransition.transitionToJIT(
                entry,
                &snapshot,
                &osr_manager.stats,
            ) catch {
                // 转换失败，继续解释执行
                continue;
            };
            
            return Value{ .int_val = result };
        }
        
        // 正常解释执行
        try self.executeInstruction(inst);
        pc += 1;
    }
}
```

## 性能考虑

### 1. 快照开销

- 快照捕获是轻量级操作（O(n)，n 为局部变量和栈深度）
- 使用固定大小数组避免动态分配
- 只在 OSR 点执行捕获

### 2. 缓存效率

- 使用哈希表快速查找 OSR 入口点（O(1)）
- 缓存键使用位运算组合函数 ID 和偏移（避免字符串操作）
- 失效机制避免使用过期的 JIT 代码

### 3. 转换成本

- 验证快照完整性的开销很小
- 函数调用约定匹配避免额外的栈操作
- 统计信息使用原子操作（为未来并发做准备）

## 正确性保证

### 属性 13：OSR 语义保持

**对于任意热循环，从解释执行切换到 JIT 代码后，循环的执行结果应该保持不变**

验证方法：
1. 对相同输入执行解释执行和 JIT 执行
2. 比较两者的结果
3. 确保结果完全相同

### 属性 13.1：栈状态捕获完整性

**对于任意栈帧状态，捕获后的快照应该包含所有必要信息**

验证方法：
1. 捕获栈帧状态
2. 验证所有字段（PC、SP、局部变量、栈）
3. 确保没有信息丢失

### 属性 13.2：OSR 转换幂等性

**对于任意有效的 OSR 入口点，多次转换应该产生相同结果**

验证方法：
1. 对相同快照执行多次 OSR 转换
2. 比较所有结果
3. 确保结果完全相同

### 属性 13.3：OSR 回退安全性

**对于任意无效的 OSR 转换，系统应该能够安全回退到解释执行**

验证方法：
1. 创建无效的 OSR 场景
2. 尝试转换
3. 验证回退机制正常工作

### 属性 13.4：OSR 入口点缓存一致性

**对于任意 OSR 入口点，注册后应该能够正确查找和失效**

验证方法：
1. 注册 OSR 入口点
2. 验证可以查找到
3. 使其失效
4. 验证无法查找到

### 属性 13.5：OSR 状态转换原子性

**对于任意 OSR 转换，要么完全成功，要么完全失败，不存在中间状态**

验证方法：
1. 执行 OSR 转换
2. 检查统计信息
3. 确保只有一个计数器增加

## 测试

### 单元测试

```bash
zig test src/jit/osr.zig
```

### 属性测试

```bash
zig test src/jit/test_osr_properties.zig
```

所有属性测试运行 100 次迭代，确保在各种随机输入下的正确性。

## 未来改进

1. **并发支持**：使用原子操作支持多线程 JIT 编译
2. **更智能的失效策略**：基于代码修改的细粒度失效
3. **性能剖析**：集成性能计数器跟踪 OSR 的收益
4. **自适应阈值**：根据函数特征动态调整 OSR 阈值
5. **多层 OSR**：支持从 JIT 代码到更优化的 JIT 代码的转换

## 参考文献

1. Lameed & Hendren, "Flexible On-Stack Replacement in LLVM", VEE 2013
2. D'Elia & Demetrescu, "On-Stack Replacement, Distilled", PLDI 2018
3. HotSpot JVM OSR Implementation
4. V8 TurboFan Deoptimization
5. GraalVM Truffle OSR Support

## 作者

Kiro AI Assistant

## 版本

1.0 - 2026-01-18
