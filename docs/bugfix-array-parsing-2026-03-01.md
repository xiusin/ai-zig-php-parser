# Array Parsing Bug Fix - 2026-03-01

## 问题描述

关联数组 `array('a' => 1, 'b' => 2, 'c' => 3)` 只创建 1 个元素，应该创建 3 个元素。

## 根本原因

### 1. Parser 层面
**文件**: `src/compiler/parser.zig`  
**函数**: `parseArrayConstruct()` (line 2468-2495)

```zig
// 错误代码
const first_expr = try self.parseExpression(0);  // ❌ 优先级 0
```

**问题**: `parseExpression(0)` 使用最低优先级，逗号运算符优先级为 0，导致：
- `'a' => 1, 'b' => 2, 'c' => 3` 被解析为单个逗号表达式
- 只有最后一个值 `'c' => 3` 被保留
- 循环只执行一次

### 2. Bytecode Generator 层面
**文件**: `src/bytecode/generator.zig`  
**函数**: `visitArrayInit()` (line 1290-1327)

```zig
// 错误的栈顺序
try self.visitNode(elem_node.data.array_pair.key);   // [array, key]
try self.visitNode(elem_node.data.array_pair.value); // [array, key, value] ❌
try self.emit(.array_set, 0, 0);
```

**问题**: VM 的 `array_set` 指令期望栈顺序（从栈底到栈顶）：
- 期望: `[value, array, key]`
- 实际: `[array, key, value]`

**参考**: `src/bytecode/vm.zig` line 5201-5203
```zig
const index = vm.popFast();   // 期望 key 在栈顶
const arr_val = vm.popFast(); // 期望 array 在中间
const value = vm.popFast();   // 期望 value 在栈底
```

## 解决方案

### 1. Parser 修复
**位置**: `src/compiler/parser.zig` line 2475, 2479

```zig
// 修复后
const first_expr = try self.parseExpression(1);  // ✅ 优先级 1
const value_expr = try self.parseExpression(1);  // ✅ 优先级 1
```

**效果**: 优先级 1 高于逗号运算符（优先级 0），在逗号处停止解析，正确分割数组元素。

### 2. Bytecode Generator 修复
**位置**: `src/bytecode/generator.zig` line 1306-1313

```zig
// 修复后
// 当前栈: [array]
try self.visitNode(elem_node.data.array_pair.value); // [array, value]
try self.emit(.swap, 0, 0);                           // [value, array]
try self.visitNode(elem_node.data.array_pair.key);   // [value, array, key] ✅
try self.emit(.array_set, 0, 0);                     // 消耗 3 个，推回 array
```

**效果**: 使用 `swap` 指令调整栈顺序，匹配 VM 期望的 `[value, array, key]`。

## 验证结果

### 测试用例
1. **索引数组**: `array(1, 2, 3)` → ✅ 输出 `3`
2. **短语法**: `[1, 2, 3]` → ✅ 输出 `3`
3. **关联数组**: `array('a' => 1, 'b' => 2, 'c' => 3)` → ✅ 输出 `3`
4. **混合数组**: `iflow_scripts/test_1000025.php` → ✅ 输出 `1,4,5`

### 字节码验证
```
[0] new_array
[1] push_int_1        // value
[2] swap              // 调整顺序
[3] push_const (0)    // key 'a'
[4] array_set         // 正确消耗 [value, array, key]
[5] push_const (1)    // value 2
[6] swap
[7] push_const (2)    // key 'b'
[8] array_set
...
```

## 关键要点

1. **表达式优先级**: 数组元素解析必须使用 `parseExpression(1)` 避免逗号运算符干扰
2. **栈顺序契约**: 字节码生成必须匹配 VM 指令的栈顺序期望
3. **swap 指令**: 用于调整栈顺序，成本低（单次栈操作）
4. **array_set 行为**: 消耗 3 个栈元素，推回修改后的数组（支持链式操作）

## 相关文件

- `src/compiler/parser.zig` - 语法解析
- `src/bytecode/generator.zig` - 字节码生成
- `src/bytecode/vm.zig` - 虚拟机执行
- `iflow_scripts/test_1000025.php` - 回归测试
