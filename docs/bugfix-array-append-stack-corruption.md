# Bug修复：数组追加操作导致的栈损坏

## 问题描述

在执行包含数组追加操作（`$arr[] = $value`）的循环时，解释器进入无限循环。测试用例：

```php
<?php
$arr = array();
$i = 1;
while ($i <= 1) {
    echo "In loop\n";
    $arr[] = $i;  // ← 导致 $i 被损坏
    echo "After append\n";
    $i++;
}
echo "Done\n";
```

**预期输出**：
```
In loop
After append
Done
```

**实际行为**：无限循环，`$i` 的值在每次迭代后被重置为 0。

## 根本原因

### 栈不匹配问题

字节码生成器和VM执行器之间存在栈操作不匹配：

**字节码生成器** (`src/bytecode/generator.zig`):
```zig
// 对于 $arr[] = $value (无索引的数组追加)
try self.visitNode(assign_data.value);    // 推送值
try self.visitNode(access_data.target);   // 推送数组
// access_data.index 为 null，不推送索引
try self.emit(.array_set, 0, 0);
```

栈状态：`[值, 数组]` (只有2个元素)

**VM执行器** (`src/bytecode/vm.zig` - 修复前):
```zig
fn handleArraySet(...) {
    const value = vm.popFast();   // 弹出数组 (错误!)
    const index = vm.popFast();   // 弹出值 (错误!)
    const arr_val = vm.popFast(); // 弹出局部变量 $i (损坏!)
    // ...
}
```

第三次 `popFast()` 从局部变量空间读取数据，损坏了 `$i` 的值。

## 解决方案

### 1. 区分数组追加和索引设置

修改 `array_set` 指令使用 `operand1` 标记操作类型：
- `operand1 = 0`: 索引设置 `$arr[$idx] = $value` (需要3个栈值)
- `operand1 = 1`: 数组追加 `$arr[] = $value` (只需2个栈值)

### 2. 修改字节码生成器

**文件**: `src/bytecode/generator.zig`

```zig
.array_access => {
    const access_data = target_node.data.array_access;
    try self.visitNode(access_data.target);
    if (access_data.index) |idx| {
        try self.visitNode(idx);
        try self.emit(.array_set, 0, 0); // 索引设置
    } else {
        try self.emit(.array_set, 1, 0); // 数组追加 (operand1=1)
    }
    self.popStack();
    self.popStack();
    if (access_data.index != null) {
        self.popStack();
    }
},
```

### 3. 修改VM执行器

**文件**: `src/bytecode/vm.zig`

```zig
fn handleArraySet(vm: *BytecodeVM, _: *CallFrame, inst: Instruction) BytecodeVM.VMError!DispatchResult {
    const is_append = inst.operand1 == 1;
    
    if (is_append) {
        // 数组追加：栈顺序 [值, 数组]
        const arr_val = vm.popFast();
        const value = vm.popFast();
        
        if (arr_val == .array_val) {
            const arr = arr_val.array_val;
            arr.elements.append(vm.allocator, value) catch
                return BytecodeVM.VMError.OutOfMemory;
            vm.pushFast(.{ .array_val = arr });
        } else {
            vm.pushFast(.null_val);
        }
        return .continue_execution;
    }
    
    // 数组索引设置：栈顺序 [值, 数组, 索引]
    const index = vm.popFast();
    const arr_val = vm.popFast();
    const value = vm.popFast();
    // ... 原有的索引设置逻辑
}
```

## 验证

### 测试用例通过
```bash
$ ./zig-out/bin/php-interpreter test_while.php
In loop
After append
Done
```

### 测试套件通过
```bash
$ zig build test
167/167 tests passed
```

## 影响范围

- **修复的文件**: 
  - `src/bytecode/vm.zig` (handleArraySet)
  - `src/bytecode/generator.zig` (array_access 赋值生成)

- **影响的操作**:
  - 数组追加 `$arr[] = $value`
  - 数组索引设置 `$arr[$idx] = $value` (保持兼容)

- **测试覆盖**:
  - 所有现有测试保持通过
  - 修复了69个 INTERP_MISMATCH 测试失败

## 经验教训

1. **栈操作必须严格匹配**：字节码生成器推送的值数量必须与VM执行器弹出的数量完全一致
2. **使用操作数区分变体**：同一指令的不同变体应使用操作数字段标记
3. **调试技巧**：在栈操作前后添加调试输出可快速定位栈不匹配问题
4. **测试覆盖**：简单的循环+数组操作可以暴露复杂的栈管理问题

## 相关问题

此修复解决了测试报告中的以下问题：
- test_1000000.php - test_1000107.php (循环中的数组操作)
- 所有包含 `$arr[] = $value` 模式的测试用例

## 提交信息

```
fix(vm): 修复数组追加操作的栈损坏问题

- 区分数组追加 (operand1=1) 和索引设置 (operand1=0)
- 修复 handleArraySet 的栈弹出逻辑
- 修复字节码生成器的栈管理
- 修复了69个测试失败，所有167个测试通过
```
