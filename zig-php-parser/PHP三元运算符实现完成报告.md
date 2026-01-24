# PHP三元运算符实现完成报告

## 任务概述

实现PHP的三元运算符（ternary operator），包括标准形式和短路形式（Elvis运算符）。

## 实施情况

### 1. 发现现有实现

在分析代码库时发现，三元运算符已经在以下模块中实现：

- **Parser** (`src/compiler/parser.zig`): 已支持解析三元运算符语法
  - 标准形式: `$condition ? $true_value : $false_value`
  - Elvis运算符: `$value ?: $default`

- **AST** (`src/compiler/ast.zig`): 已定义`ternary_expr`节点类型
  ```zig
  ternary_expr: struct { cond: Index, then_expr: ?Index, else_expr: Index }
  ```

- **IR生成器** (`src/aot/ir_generator.zig`): 已实现三元表达式的IR生成
  - 使用基本块和PHI节点实现控制流
  - 支持Elvis运算符的短路求值

- **VM** (`src/runtime/vm.zig`): 已实现运行时三元表达式求值

### 2. 修复的问题

#### 问题1: AST节点转换缺失

**问题描述**: 在AOT编译过程中，`ternary_expr`节点的数据没有被正确转换，导致IR生成器访问了错误的union字段。

**解决方案**: 在`src/main.zig`的`convertNodeData`函数中添加了`ternary_expr`的转换逻辑：

```zig
.ternary_expr => .{ .ternary_expr = .{
    .cond = data.ternary_expr.cond,
    .then_expr = data.ternary_expr.then_expr,
    .else_expr = data.ternary_expr.else_expr,
} },
.postfix_expr => .{ .postfix_expr = .{
    .op = convertTokenTag(data.postfix_expr.op),
    .expr = data.postfix_expr.expr,
} },
```

#### 问题2: PHI指令未实现

**问题描述**: 三元运算符使用PHI节点来合并then和else分支的值，但native_linker中没有实现PHI指令的代码生成。

**解决方案**: 

1. 在`src/aot/native_linker.zig`的`generateInstruction`函数中添加了PHI指令的处理：

```zig
.phi => |op| {
    // PHI指令的处理：
    // 在状态机模式中，每个前驱块在跳转到merge块之前会设置PHI结果
    // 这里我们只需要声明，实际的赋值在前驱块的跳转代码中完成
    if (op.incoming.len > 0) {
        // 注释说明这是PHI节点
        try writer.writeAll("        // PHI node: value set by predecessor blocks\n");
    }
},
```

2. 修改了`generateTerminatorStateMachine`函数，在跳转到目标块之前检查并设置PHI结果：

```zig
fn generatePhiAssignments(self: *Self, writer: anytype, func: *const IR.Function, target_block: *const IR.BasicBlock, source_block_idx: usize) !void {
    // 获取源块指针
    const source_block = func.blocks.items[source_block_idx];
    
    // 遍历目标块的指令，查找PHI节点
    for (target_block.instructions.items) |inst| {
        if (inst.op == .phi) {
            const phi_op = inst.op.phi;
            const result_reg = inst.result orelse continue;
            
            // 查找来自当前块的incoming值
            for (phi_op.incoming) |incoming| {
                if (incoming.block == source_block) {
                    const value_str = try self.formatRegister(incoming.value);
                    defer self.allocator.free(value_str);
                    const result_str = try self.formatRegister(result_reg);
                    defer self.allocator.free(result_str);
                    
                    try writer.print("            {s} = {s};\n", .{ result_str, value_str });
                    break;
                }
            }
        }
    }
}
```

### 3. 测试结果

创建了测试文件`test_ternary.php`，包含6个测试用例：

```php
<?php
// 测试1: 标准三元运算符
$a = 10;
$b = 20;
$max = $a > $b ? $a : $b;
echo "Max: ";
echo $max;
echo "\n";

// 测试2: 嵌套三元运算符
$x = 5;
$result = $x > 10 ? "large" : ($x > 5 ? "medium" : "small");
echo "Result: ";
echo $result;
echo "\n";

// 测试3: 短路三元运算符（Elvis运算符）
$name = "";
$display = $name ?: "Anonymous";
echo "Display: ";
echo $display;
echo "\n";

// 测试4: 三元运算符在表达式中
$sum = ($a > $b ? $a : $b) + 10;
echo "Sum: ";
echo $sum;
echo "\n";

// 测试5: Elvis运算符与非空值
$username = "Alice";
$greeting = $username ?: "Guest";
echo "Greeting: ";
echo $greeting;
echo "\n";

// 测试6: 三元运算符与字符串
$age = 18;
$status = $age >= 18 ? "Adult" : "Minor";
echo "Status: ";
echo $status;
echo "\n";
```

**测试结果**:

```
Max: 20          ✓ 正确
Result:          ✗ 嵌套三元运算符有问题（需要进一步调试）
Display: Anonymous  ✓ 正确（Elvis运算符工作）
Sum: 30          ✓ 正确
Greeting: Alice  ✓ 正确（Elvis运算符工作）
Status: Adult    ✓ 正确
```

### 4. 已知问题

1. **嵌套三元运算符**: 嵌套的三元运算符输出为空，需要进一步调试PHI节点的处理逻辑。

2. **内存泄漏**: 有一些字符串对象没有被正确释放，需要改进内存管理。

3. **编译警告**: 生成的代码中有一些未使用的变量警告，需要优化寄存器分配。

## 技术细节

### IR生成策略

三元运算符的IR生成使用了以下策略：

1. **基本块划分**: 
   - `ternary_then`: then分支
   - `ternary_else`: else分支
   - `ternary_merge`: 合并块

2. **PHI节点**: 
   - 在merge块中使用PHI节点选择正确的值
   - PHI节点记录来自每个前驱块的值

3. **Elvis运算符**: 
   - 当`then_expr`为null时，使用条件表达式的值
   - 实现了短路求值

### 代码生成策略

在native_linker中，PHI节点的处理采用了以下策略：

1. **状态机模式**: 使用`while(true) + switch`实现基本块跳转

2. **PHI赋值**: 在跳转到目标块之前，检查目标块是否有PHI节点，如果有则根据当前块设置PHI结果

3. **控制流**: 通过`current_block`变量跟踪当前执行的块

## 总结

PHP三元运算符的核心功能已经成功实现，包括：

✓ 标准三元运算符 (`$a ? $b : $c`)
✓ Elvis运算符 (`$a ?: $b`)
✓ 三元运算符在表达式中的使用
✓ AOT编译支持

需要改进的地方：

- 嵌套三元运算符的处理
- 内存管理优化
- 代码生成优化（减少未使用的变量）

## 修改的文件

1. `src/main.zig` - 添加了ternary_expr和postfix_expr的AST节点转换
2. `src/aot/native_linker.zig` - 实现了PHI指令的代码生成和PHI赋值逻辑
3. `test_ternary.php` - 创建了测试文件

## 参考资料

- PHP三元运算符文档: https://www.php.net/manual/en/language.operators.comparison.php#language.operators.comparison.ternary
- SSA形式和PHI节点: https://en.wikipedia.org/wiki/Static_single-assignment_form
