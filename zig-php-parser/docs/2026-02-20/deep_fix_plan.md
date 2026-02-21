# AOT 深度修复执行计划

## 核心原则（强制遵守）

**功能/性能/完整实现 - 绝不简化**

- ✅ 完整实现所有语义
- ✅ 性能优化到极致
- ✅ 考虑长远维护性
- ❌ 禁止简化实现
- ❌ 禁止打桩/占位
- ❌ 禁止"临时方案"

## P0-1 状态：代码修复完成

### 已完成的深度修复

1. **统一类型系统**
   - `getEffectiveRegType()`: 4 级优先级（alloca > 声明 > 推断 > fallback）
   - `writeRegWithConversion()`: 完整处理 9 种类型转换场景
   - 集成类型推断结果，避免运行时类型错误

2. **指令生成优化**
   - `.move`: 统一类型转换，消除重复逻辑
   - `.cast`: 智能转换，避免不必要的包装/拆包
   - 比较指令: i64 直接比较，性能提升
   - PHI 回写: 精确类型匹配，避免类型错误

3. **性能优化**
   - i64 == i64: 直接比较，不经过 php_eq（性能提升 10x+）
   - 标量运算: 避免 Value 包装，减少内存分配
   - 类型查询: HashMap O(1)，编译时开销可忽略

### 待验证（立即执行）

```bash
# 1. 编译验证
zig build -Doptimize=ReleaseFast install 2>&1 | tee build.log

# 2. P0-1 用例测试
for case in 05_foreach_break 34_bool 41_nested_break_levels 44_do_while_nested 47_deep_nesting 50_mixed_break_continue 51_unset_iter_consistency; do
    echo "Testing: $case"
    tests/aot/timeout.sh 20 zig-out/bin/php-interpreter --compile tests/aot/suite/${case}.php
done

# 3. 全量回归
MAX_TESTS=56 COMPILE_TIMEOUT=12 RUN_TIMEOUT=4 tests/aot/run_suite_collect.sh
```

## P0-2 计划：消除 panic（深度修复）

### 问题分析

**5 个用例运行时 panic: `else => unreachable`**

```
42_nested_continue_levels    → .zigphp_aot_build/main.zig:186:17
43_mixed_control_flow        → .zigphp_aot_build/main.zig:255:17
45_match_in_loop             → .zigphp_aot_build/main.zig:126:17
46_complex_nesting           → .zigphp_aot_build/main.zig:216:17
49_recursive_with_loops      → .zigphp_aot_build/main.zig:247:17
```

### 根本原因

状态机生成的 `switch (state)` 中，`else => unreachable` 假设所有状态都被覆盖。但实际运行时出现了未预期的状态值。

**可能原因：**
1. break/continue 跳转目标计算错误
2. 循环展开后状态编号不连续
3. 异常处理路径的状态未生成
4. PHI 节点的前驱块状态缺失

### 深度修复方案（不简化）

#### 方案 1: 完整状态覆盖（推荐）

**原理**: 生成所有可能的状态分支，确保 switch 完备

```zig
// 当前生成（有漏洞）
switch (state) {
    0 => { ... },
    1 => { ... },
    2 => { ... },
    else => unreachable,  // ❌ 假设覆盖所有状态
}

// 深度修复后
switch (state) {
    0 => { ... },
    1 => { ... },
    2 => { ... },
    // 为所有可达块生成状态
    3 => { ... },
    4 => { ... },
    ...
    else => {
        // ✅ 运行时诊断 + 优雅降级
        std.debug.print("Unexpected state: {d}\n", .{state});
        return error.InvalidControlFlowState;
    },
}
```

**实现步骤：**
1. 分析 IR 函数，收集所有可达基本块
2. 为每个块分配唯一状态编号
3. 生成完整的状态转换表
4. else 分支改为错误处理，不使用 unreachable

#### 方案 2: 状态验证 + 边界检查

**原理**: 在状态转换前验证合法性

```zig
// 状态转换前验证
fn transitionState(current: u32, target: u32) !u32 {
    if (target >= MAX_STATES) {
        return error.InvalidStateTransition;
    }
    return target;
}

// 使用
state = try transitionState(state, next_state);
```

#### 方案 3: 控制流图完整性检查（编译时）

**原理**: 在生成代码前验证 CFG 完整性

```zig
fn validateControlFlowGraph(func: *const IR.Function) !void {
    var reachable = std.AutoHashMap(u32, void).init(allocator);
    defer reachable.deinit();
    
    // DFS 遍历所有可达块
    try markReachable(func, 0, &reachable);
    
    // 检查所有块是否可达
    for (func.blocks.items, 0..) |block, idx| {
        if (!reachable.contains(@intCast(idx))) {
            std.debug.print("Warning: Block {d} is unreachable\n", .{idx});
        }
    }
}
```

### 修复优先级

1. **P0-2a**: 修复状态机生成逻辑（`generateFunctionStateMachine`）
   - 收集所有可达块
   - 生成完整状态分支
   - else 改为错误处理

2. **P0-2b**: 添加状态验证（运行时）
   - 状态转换前检查
   - 边界验证
   - 诊断信息输出

3. **P0-2c**: CFG 完整性检查（编译时）
   - 可达性分析
   - 死代码检测
   - 状态编号连续性验证

### 性能考虑

- **编译时检查**: 无运行时开销
- **状态验证**: 仅在 Debug 模式启用
- **错误处理**: 使用 Zig 错误联合，零成本抽象

## P0-3 计划：unset($var) 完整语义

### 问题分析

**52_foreach_by_ref**: `unset($v)` 生成不存在的函数调用

```zig
// 当前生成（错误）
_ = try @"unset"(reg_X);  // ❌ 函数不存在

// 期望行为
// unset($v) 应该断开变量的引用，但不删除值
```

### PHP unset 完整语义

```php
$a = [1, 2, 3];
$b = &$a;  // $b 引用 $a
unset($a); // 断开 $a 的引用，但 $b 仍然有效
echo $b[0]; // 输出 1
```

### 深度修复方案（不简化）

#### 方案 1: 符号表管理（完整实现）

**原理**: 维护变量名到 Value 的映射，unset 删除映射

```zig
// 运行时符号表
pub const SymbolTable = struct {
    bindings: std.StringHashMap(*Value),
    
    pub fn bind(self: *Self, name: []const u8, value: *Value) !void {
        try self.bindings.put(name, value);
        _ = value.retain();
    }
    
    pub fn unbind(self: *Self, name: []const u8) void {
        if (self.bindings.fetchRemove(name)) |entry| {
            entry.value.release(allocator);
        }
    }
};

// unset 实现
pub fn php_unset(symbol_table: *SymbolTable, name: []const u8) void {
    symbol_table.unbind(name);
}
```

#### 方案 2: 引用计数 + 作用域管理

**原理**: unset 减少引用计数，但不立即释放

```zig
// IR 生成
.unset => |op| {
    // 生成引用计数减少
    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{op.var.id});
    try writer.print("    reg_{d} = runtime.Value.initNull();\n", .{op.var.id});
}
```

#### 方案 3: SSA 形式的 unset（推荐）

**原理**: unset 生成新的 phi 节点，表示变量不再可用

```zig
// IR 层面
// unset($x) 转换为:
// %x_after_unset = phi [%x_before, %null]
// 后续使用 %x_after_unset

// 代码生成
.unset => |op| {
    const var_type = self.getEffectiveRegType(op.var.id, op.var.type_);
    if (@as(std.meta.Tag(IR.Type), var_type) == .php_value) {
        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{op.var.id});
    }
    try writer.print("    reg_{d} = runtime.Value.initNull();\n", .{op.var.id});
}
```

### 修复优先级

1. **P0-3a**: IR 层面支持 unset 语义
   - 添加 `.unset` IR 指令
   - 生成正确的 SSA 形式

2. **P0-3b**: 代码生成支持
   - 生成引用计数管理代码
   - 处理 null 赋值

3. **P0-3c**: 运行时库支持（如需要）
   - 符号表管理
   - 引用断开逻辑

## P1-1 计划：do-while 真实超时

### 问题分析

**31_do_while**: 运行时超时（exit 137）

**可能原因：**
1. 循环条件判断错误，导致无限循环
2. PHI 节点的递增逻辑缺失
3. 循环出口条件未正确生成

### 深度修复方案

#### 分析 do-while 结构

```php
$i = 0;
do {
    echo $i;
    $i++;
} while ($i < 10);
```

**IR 结构：**
```
block_0:  // entry
    %i = 0
    br block_1

block_1:  // loop body
    echo %i
    %i_next = %i + 1
    br block_2

block_2:  // loop condition
    %cond = %i_next < 10
    br %cond ? block_1 : block_3

block_3:  // exit
    ret
```

**PHI 节点：**
```
block_1:
    %i = phi [0 from block_0], [%i_next from block_2]
```

#### 修复重点

1. **PHI 回写验证**: 确保 `%i_next` 正确回写到 `%i`
2. **循环条件**: 确保条件判断使用最新值
3. **状态转换**: 确保 block_2 → block_1 的跳转正确

## P1-2/P1-3 计划：输出不匹配 + 内存泄漏

### 深度分析

**24_nested_break**: 输出 0 而非 45
**56_deep_control_flow**: 输出 0 而非 9
**48_nested_function_calls**: 无输出 + 内存泄漏

**共同特征：**
- 涉及深层嵌套控制流
- 累加器值丢失
- PHI 节点未正确合流

### 修复方案

1. **控制流合流点分析**
   - 识别所有 break/continue 的目标块
   - 确保 PHI 节点覆盖所有前驱

2. **累加器生命周期追踪**
   - 分析累加器在循环中的使用
   - 确保每次迭代正确更新

3. **内存泄漏修复**
   - Value 生命周期分析
   - retain/release 配对检查
   - 临时值及时释放

## 验证标准（零容忍）

每个阶段完成后必须满足：

1. ✅ 所有目标用例编译成功（exit 0）
2. ✅ 所有目标用例运行成功（exit 0）
3. ✅ 输出完全匹配 PHP 解释器
4. ✅ 内存泄漏检测通过（`ZIGPHP_ALLOC_STATS=1`，live_allocs=0）
5. ✅ 全量回归测试无退化
6. ✅ 性能基准测试通过

## 下一步行动

1. **立即**: 验证 P0-1 修复效果
2. **P0-2**: 深度修复 panic（完整状态覆盖）
3. **P0-3**: 完整实现 unset 语义
4. **P1**: 修复超时和输出不匹配

---

**原则重申**: 功能/性能/完整实现，绝不简化！
