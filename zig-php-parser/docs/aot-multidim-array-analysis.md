# AOT 编译器多维数组问题分析

## 问题描述

多维数组赋值时出现 `incorrect alignment` 错误。

### 复现代码
```php
$matrix = [];
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        $matrix[$i][$j] = $i * 3 + $j;
    }
}
```

### 错误信息
```
thread panic: incorrect alignment
runtime_lib.zig:1591:16: in asArray
    return @ptrFromInt(nanbox_abi.decodePtr(self.val));
           ^
main.zig:289:23: in __main__
    try reg_19.asArray().setByValue(runtime.runtime_allocator, reg_53, reg_16);
```

## 根本原因

### 1. 生成的代码
```zig
// 获取 $matrix[$i]
reg_19 = reg_0.asArray().getByValue(reg_50) orelse runtime.Value.initNull();

// 设置 $matrix[$i][$j] = value
try reg_19.asArray().setByValue(runtime.runtime_allocator, reg_53, reg_16);
```

### 2. 问题分析

- `getByValue` 返回 `?Value`，如果 `$matrix[$i]` 不存在，返回 `null`
- `orelse runtime.Value.initNull()` 将 `reg_19` 设置为 `null` 值
- `null` 值的内部表示是 `QNAN | TAG_NIL`
- `asArray()` 调用 `decodePtr(QNAN | TAG_NIL)`，返回 `TAG_NIL & ADDR_MASK = 1`
- `@ptrFromInt(1)` 因为地址 1 不是 8 字节对齐而崩溃

### 3. PHP 语义

PHP 支持 **auto-vivification**：当访问不存在的数组元素时，自动创建一个空数组。

```php
$matrix = [];
$matrix[0][0] = 1;  // 自动创建 $matrix[0] = []，然后设置 $matrix[0][0] = 1
```

### 4. IR 结构问题

当前的 IR 结构不支持 auto-vivification：

```
%19 = array_get %0, %50      // 返回 Value（可能是 null）
array_set %19, %53, %16       // 对 Value 调用 asArray()
```

`array_set` 指令只知道内层数组（`%19`），不知道外层数组（`%0`）和键（`%50`），所以无法自动创建并写回。

## 解决方案

### 方案 A：修改 IR 生成器（推荐）

在 IR 生成器中检测嵌套的 `array_access` 赋值，生成特殊的 IR：

```
// 当前 IR（错误）
%19 = array_get %0, %50
array_set %19, %53, %16

// 修复后的 IR（正确）
array_set_nested %0, %50, %53, %16
```

新增 `array_set_nested` 指令，包含：
- 外层数组：`%0`
- 外层键：`%50`
- 内层键：`%53`
- 值：`%16`

代码生成：
```zig
// 获取或创建 $matrix[$i]
var inner = reg_0.asArray().getByValue(reg_50);
if (inner == null or inner.?.isNull()) {
    const new_arr = try PHPArray.init(allocator);
    inner = Value.initArray(new_arr);
    try reg_0.asArray().setByValue(allocator, reg_50, inner.?);
}
// 设置 $matrix[$i][$j] = value
try inner.?.asArray().setByValue(allocator, reg_53, reg_16);
```

**优点**：
- 完全支持 PHP 语义
- 性能最优
- 支持任意深度的嵌套

**缺点**：
- 需要修改 IR 生成器
- 需要添加新的 IR 指令
- 实现复杂度高

### 方案 B：运行时检查（临时方案）

在 `asArray()` 中添加 `null` 检查，返回错误：

```zig
pub fn asArray(self: Value) !*PHPArray {
    if (self.isNull()) {
        return error.CannotUseNullAsArray;
    }
    return @ptrFromInt(nanbox_abi.decodePtr(self.val));
}
```

**优点**：
- 实现简单
- 错误信息清晰

**缺点**：
- 不支持 PHP 的 auto-vivification
- 用户代码会崩溃

### 方案 C：解释器模式（不推荐）

在代码生成时，对所有 `array_set` 添加运行时检查：

```zig
if (reg_19.isNull()) {
    // 跳过或报错
} else {
    try reg_19.asArray().setByValue(...);
}
```

**优点**：
- 不会崩溃

**缺点**：
- 不支持 auto-vivification
- 性能损失
- 不符合 PHP 语义

## 推荐实现步骤

### 1. 修改 IR 定义（src/aot/ir.zig）

添加新指令：
```zig
pub const Instruction = struct {
    pub const Op = union(enum) {
        // ... 现有指令
        
        /// 嵌套数组赋值（支持 auto-vivification）
        array_set_nested: struct {
            outer_array: Register,
            outer_key: Register,
            inner_key: Register,
            value: Register,
        },
    };
};
```

### 2. 修改 IR 生成器（src/aot/ir_generator.zig）

在 `generateAssignment` 中检测嵌套的 `array_access`：

```zig
fn generateAssignment(self: *Self, node: *const Node) !void {
    const assign_data = node.data.assignment;
    const value_reg = try self.generateExpression(assign_data.value);
    const target_node = self.getNode(assign_data.target) orelse return;
    
    switch (target_node.tag) {
        .array_access => {
            // 检查是否是嵌套的 array_access
            const inner_target = self.getNode(target_node.data.array_access.target);
            if (inner_target != null and inner_target.?.tag == .array_access) {
                // 嵌套数组赋值
                const outer_array_reg = try self.generateExpression(inner_target.?.data.array_access.target);
                const outer_key_reg = try self.generateExpression(inner_target.?.data.array_access.index.?);
                const inner_key_reg = try self.generateExpression(target_node.data.array_access.index.?);
                
                _ = try self.emit(.{ .array_set_nested = .{
                    .outer_array = outer_array_reg,
                    .outer_key = outer_key_reg,
                    .inner_key = inner_key_reg,
                    .value = value_reg,
                } }, null);
            } else {
                // 普通数组赋值
                // ... 现有逻辑
            }
        },
        // ... 其他情况
    }
}
```

### 3. 修改代码生成器（src/aot/native_linker.zig）

添加 `array_set_nested` 的代码生成：

```zig
.array_set_nested => |op| {
    try writer.print(
        \\    {{
        \\        const outer_arr = reg_{d}.asArray();
        \\        var inner = outer_arr.getByValue(reg_{d});
        \\        if (inner == null or inner.?.isNull()) {{
        \\            const new_arr = try runtime.PHPArray.init(runtime.runtime_allocator);
        \\            const new_val = runtime.Value.initArray(new_arr);
        \\            try outer_arr.setByValue(runtime.runtime_allocator, reg_{d}, new_val);
        \\            inner = new_val;
        \\        }}
        \\        try inner.?.asArray().setByValue(runtime.runtime_allocator, reg_{d}, reg_{d});
        \\    }}
        \\
    , .{ op.outer_array.id, op.outer_key.id, op.outer_key.id, op.inner_key.id, op.value.id });
},
```

### 4. 扩展支持（可选）

支持任意深度的嵌套：
- `$a[$i][$j][$k] = value`
- `$a[$i][$j][$k][$l] = value`

可以递归检测或使用栈结构。

## 影响范围

### 修复后支持的功能
- ✅ 多维数组赋值
- ✅ Auto-vivification
- ✅ 任意深度嵌套

### 不影响的功能
- ✅ 单维数组
- ✅ 数组读取
- ✅ 其他数据类型

## 工作量估计

- **方案 A**（推荐）：4-6 小时
  - IR 定义：30 分钟
  - IR 生成器：2-3 小时
  - 代码生成器：1 小时
  - 测试：1-2 小时

- **方案 B**（临时）：30 分钟
  - 修改 `asArray()`：10 分钟
  - 测试：20 分钟

## 总结

多维数组问题的根本原因是 **IR 结构不支持 PHP 的 auto-vivification 语义**。

当前的 `array_get` + `array_set` 模式无法处理嵌套数组赋值，因为 `array_set` 不知道如何创建并写回中间数组。

推荐实现方案 A：添加 `array_set_nested` 指令，在 IR 生成时检测嵌套赋值，生成支持 auto-vivification 的代码。

这是一个需要深度修改 IR 生成器的任务，但是是实现完整 PHP 语义的必要步骤。

---

**分析日期**: 2026-02-27  
**分析人**: xiusin  
**优先级**: P1（阻塞多维数组功能）
