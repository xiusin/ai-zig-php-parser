# Task 2.7: 高级控制流实现计划

## 当前状态分析

### 已实现
1. **AST层面**：
   - ✅ `break_stmt` 节点定义（parser.zig:1144）
   - ✅ `continue_stmt` 节点定义（parser.zig:1154）
   - ✅ `switch_stmt` 节点定义（parser.zig:2106）
   - ✅ `case` 和 `default` 节点定义

2. **IR生成层面**：
   - ✅ `generateBreakStmt` 实现（ir_generator.zig:1374）
   - ✅ `generateContinueStmt` 实现（ir_generator.zig:1383）
   - ✅ `loop_stack` 机制（维护break/continue目标）
   - ❌ `generateSwitchStmt` **未实现**

3. **IR定义层面**：
   - ✅ `Terminator.switch_` 定义（ir.zig）
   - ✅ `SwitchCase` 结构定义

4. **代码生成层面**：
   - ✅ `generateTerminatorStateMachine` 中的switch处理（native_linker.zig:429）
   - ✅ break/continue 通过状态机的 `br` 终止指令实现

### 缺失部分
1. **IR生成**：
   - ❌ `generateSwitchStmt` 函数
   - ❌ 在 `generateStatement` 中添加 `.switch_stmt` 分支

2. **测试**：
   - ❌ break/continue 测试用例
   - ❌ switch/case 测试用例
   - ❌ 嵌套控制流测试用例

## 实现方案

### 阶段 1：实现 Switch 语句 IR 生成

#### 1.1 在 ir_generator.zig 中添加 generateSwitchStmt

```zig
/// Generate IR for switch statement
fn generateSwitchStmt(self: *Self, node: *const Node) !void {
    const switch_data = node.data.switch_stmt;
    
    // 生成switch表达式
    const value_reg = try self.generateExpression(switch_data.expression);
    
    // 创建基本块
    const merge_block = try self.createBlock("switch.merge");
    const default_block = if (switch_data.default) |_|
        try self.createBlock("switch.default")
    else
        merge_block;
    
    // 为每个case创建基本块
    var case_blocks = std.ArrayList(*BasicBlock).init(self.allocator);
    defer case_blocks.deinit();
    
    for (switch_data.cases, 0..) |_, i| {
        const label = try std.fmt.allocPrint(self.allocator, "switch.case.{d}", .{i});
        defer self.allocator.free(label);
        const block = try self.createBlock(label);
        try case_blocks.append(block);
    }
    
    // 构建switch cases数组
    var ir_cases = std.ArrayList(Terminator.SwitchCase).init(self.allocator);
    defer ir_cases.deinit();
    
    for (switch_data.cases, 0..) |case_idx, i| {
        const case_node = self.getNode(case_idx).?;
        const case_data = case_node.data.case;
        
        // 计算case值（必须是常量）
        const case_value_reg = try self.generateExpression(case_data.condition);
        // TODO: 从寄存器中提取常量值
        const case_value: i64 = 0; // 临时实现
        
        try ir_cases.append(.{
            .value = case_value,
            .block = case_blocks.items[i],
        });
    }
    
    // 生成switch终止指令
    const cases_slice = try self.allocator.dupe(Terminator.SwitchCase, ir_cases.items);
    self.setTerminator(.{ .switch_ = .{
        .value = value_reg,
        .cases = cases_slice,
        .default = default_block,
    } });
    
    // 生成每个case的代码
    for (switch_data.cases, 0..) |case_idx, i| {
        self.current_block = case_blocks.items[i];
        const case_node = self.getNode(case_idx).?;
        const case_data = case_node.data.case;
        
        for (case_data.body) |stmt_idx| {
            try self.generateStatement(stmt_idx);
            if (self.isBlockTerminated()) break;
        }
        
        // 如果没有break，fall through到下一个case或merge
        if (!self.isBlockTerminated()) {
            if (i + 1 < case_blocks.items.len) {
                self.setTerminator(.{ .br = case_blocks.items[i + 1] });
            } else if (switch_data.default != null) {
                self.setTerminator(.{ .br = default_block });
            } else {
                self.setTerminator(.{ .br = merge_block });
            }
        }
    }
    
    // 生成default块
    if (switch_data.default) |default_idx| {
        self.current_block = default_block;
        const default_node = self.getNode(default_idx).?;
        const default_data = default_node.data.default;
        
        for (default_data.body) |stmt_idx| {
            try self.generateStatement(stmt_idx);
            if (self.isBlockTerminated()) break;
        }
        
        if (!self.isBlockTerminated()) {
            self.setTerminator(.{ .br = merge_block });
        }
    }
    
    // 继续在merge块
    self.current_block = merge_block;
}
```

#### 1.2 在 generateStatement 中添加 switch 分支

在 `generateStatement` 函数的 switch 语句中添加：

```zig
.switch_stmt => try self.generateSwitchStmt(node),
```

### 阶段 2：创建测试用例

#### 2.1 创建 examples/test_control_flow_advanced.php

```php
<?php

// Test 1: Break in loop
echo "Test 1: Break\n";
for ($i = 0; $i < 10; $i = $i + 1) {
    if ($i == 5) {
        break;
    }
    echo $i;
    echo "\n";
}

// Test 2: Continue in loop
echo "Test 2: Continue\n";
for ($i = 0; $i < 5; $i = $i + 1) {
    if ($i == 2) {
        continue;
    }
    echo $i;
    echo "\n";
}

// Test 3: Switch statement
echo "Test 3: Switch\n";
$x = 2;
switch ($x) {
    case 1:
        echo "One\n";
        break;
    case 2:
        echo "Two\n";
        break;
    case 3:
        echo "Three\n";
        break;
    default:
        echo "Other\n";
}

// Test 4: Switch with fall-through
echo "Test 4: Switch fall-through\n";
$y = 1;
switch ($y) {
    case 1:
        echo "A\n";
    case 2:
        echo "B\n";
        break;
    default:
        echo "C\n";
}

// Test 5: Nested loops with break
echo "Test 5: Nested break\n";
for ($i = 0; $i < 3; $i = $i + 1) {
    for ($j = 0; $j < 3; $j = $j + 1) {
        if ($j == 1) {
            break;
        }
        echo $i;
        echo ",";
        echo $j;
        echo "\n";
    }
}
```

### 阶段 3：修复和测试

1. 编译测试文件
2. 验证输出
3. 修复发现的问题
4. 完善错误处理

## 技术难点

### 1. Switch 常量值提取

Switch case 的值必须是编译时常量。需要：
- 在IR生成时计算常量表达式
- 或者在代码生成时处理动态值（使用if-else链）

### 2. Fall-through 语义

PHP的switch默认支持fall-through，需要：
- 正确生成跳转到下一个case的代码
- 处理break语句终止fall-through

### 3. 嵌套循环的Break/Continue

需要确保：
- loop_stack 正确维护嵌套层次
- break/continue 跳转到正确的目标块

## 预期输出

### Test 1: Break
```
Test 1: Break
0
1
2
3
4
```

### Test 2: Continue
```
Test 2: Continue
0
1
3
4
```

### Test 3: Switch
```
Test 3: Switch
Two
```

### Test 4: Switch fall-through
```
Test 4: Switch fall-through
A
B
```

### Test 5: Nested break
```
Test 5: Nested break
0,0
1,0
2,0
```

## 下一步

1. 实现 `generateSwitchStmt`
2. 创建测试文件
3. 编译并测试
4. 生成完成报告
