# Task 2.5: 控制流实现完成报告

## 任务概述
实现AOT编译器的控制流支持，包括if/else、while循环和for循环。

## 实现方案

### 1. 状态机模式
采用状态机模式生成控制流代码，每个基本块对应一个状态：

```zig
var current_block: u32 = 0;
while (true) {
    switch (current_block) {
        0 => { // entry block
            // 指令...
            current_block = next_block;
        },
        1 => { // then block
            // 指令...
            current_block = merge_block;
        },
        // ...
    }
}
```

### 2. 寄存器声明提升
将所有寄存器声明提升到函数顶部，解决跨基本块的作用域问题：

```zig
// Register declarations
var reg_0: runtime.Value = undefined;
var reg_1: runtime.Value = undefined;
// ...
```

### 3. 终止指令处理
实现三种终止指令：
- **ret**: 函数返回
- **br**: 无条件跳转 → `current_block = target_idx;`
- **cond_br**: 条件跳转 → `if (cond.toBool()) { current_block = then_idx; } else { current_block = else_idx; }`

## 代码修改

### src/aot/native_linker.zig

1. **generateFunction()** - 修改函数生成逻辑
   - 收集所有寄存器并在函数顶部声明
   - 调用`generateControlFlow()`生成状态机

2. **generateControlFlow()** - 新增控制流生成方法
   - 单块优化：直接生成线性代码
   - 多块：生成状态机结构

3. **generateTerminatorStateMachine()** - 新增终止指令生成
   - 处理ret/br/cond_br/switch/throw/unreachable

4. **findBlockIndex()** - 新增辅助方法
   - 查找基本块在函数中的索引

5. **generateInstruction()** - 修改指令生成
   - 将所有`const`改为赋值语句
   - 调整缩进为8空格（状态机内部）
   - alloca指令不生成代码（声明已提升）

## 测试结果

### 测试文件: examples/test_control_flow.php

```php
<?php
// Test if/else
$x = 10;
if ($x > 5) {
    echo "x is greater than 5\n";
} else {
    echo "x is less than or equal to 5\n";
}

// Test while loop
$i = 0;
while ($i < 3) {
    echo "Loop iteration: " . $i . "\n";
    $i = $i + 1;
}

// Test for loop
for ($j = 0; $j < 3; $j = $j + 1) {
    echo "For loop: " . $j . "\n";
}

echo "Control flow test complete\n";
?>
```

### 执行结果

```
$ ./zig-out/bin/php-interpreter --compile examples/test_control_flow.php && ./test_control_flow
Success: Compiled to test_control_flow
x is greater than 5
Loop iteration: 0
Loop iteration: 1
Loop iteration: 2
For loop: 0
For loop: 1
For loop: 2
Control flow test complete
```

✅ **所有控制流功能正常工作！**

## 生成的代码示例

```zig
fn @"__main__"() !void {
    _ = runtime; // Avoid unused warning

    // Register declarations
    var reg_0: runtime.Value = undefined;
    var reg_1: runtime.Value = undefined;
    // ... (所有寄存器)

    // Control flow state machine
    var current_block: u32 = 0;
    while (true) {
        switch (current_block) {
            0 => { // entry
                reg_0 = runtime.Value.initInt(10);
                reg_1 = reg_0;
                reg_2 = reg_1;
                reg_3 = runtime.Value.initInt(5);
                reg_4 = try runtime.php_gt(reg_2, reg_3);
                if (reg_4.toBool()) {
                    current_block = 1;
                } else {
                    current_block = 2;
                }
            },
            1 => { // if_then_0
                reg_5 = runtime.Value.initString(...);
                try runtime.php_echo(reg_5);
                current_block = 3;
            },
            // ... 更多基本块
        }
    }
}
```

## 技术亮点

1. **状态机模式**：简洁高效，易于理解和调试
2. **寄存器提升**：解决作用域问题，避免重复声明
3. **单块优化**：简单函数直接生成线性代码，无状态机开销
4. **完整支持**：if/else、while、for、嵌套控制流全部支持

## 已知问题

1. **内存泄漏**：cleanup代码在return之前未执行（需要在每个return点插入cleanup）
2. **未使用寄存器**：某些中间结果寄存器未使用（可优化）

## 下一步

- Task 2.6: 实现函数定义和调用
- Task 2.7: 性能优化
- 修复内存泄漏问题

## 提交信息

```
feat(aot): 实现控制流支持（if/else, while, for）

- 采用状态机模式生成控制流代码
- 将寄存器声明提升到函数顶部
- 实现ret/br/cond_br终止指令
- 支持if/else、while循环、for循环
- 测试通过：所有控制流功能正常工作

Task 2.5 完成
```
