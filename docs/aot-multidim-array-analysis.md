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

## 解决方案（已实现）

### 修改 IR 生成器

在 IR 生成器中检测嵌套的 `array_access` 赋值，生成特殊的 IR：

```
// 修复后的 IR
array_set_nested %0, %50, %53, %16
```

新增 `array_set_nested` 指令，包含：
- 外层数组：`%0`
- 外层键：`%50`
- 内层键：`%53`
- 值：`%16`

代码生成：
```zig
{
    const outer_arr = reg_0.asArray();
    var inner = outer_arr.getByValue(reg_50);
    if (inner == null or inner.?.isNull()) {
        const new_arr = try PHPArray.init(allocator);
        inner = Value.initArray(new_arr);
        try outer_arr.setByValue(allocator, reg_50, inner.?);
    }
    try inner.?.asArray().setByValue(allocator, reg_53, reg_16);
}
```

## 实现细节

### 1. IR 定义（src/aot/ir.zig）

添加新指令：
```zig
pub const ArraySetNestedOp = struct {
    outer_array: Register,
    outer_key: Register,
    inner_key: Register,
    value: Register,
};

pub const Op = union(enum) {
    // ... 现有指令
    array_set_nested: ArraySetNestedOp,
};
```

### 2. IR 生成器（src/aot/ir_generator.zig）

在 `generateAssignment` 中检测嵌套的 `array_access`：

```zig
.array_access => {
    const target_expr = self.getNode(target_node.data.array_access.target);
    const is_nested = target_expr != null and target_expr.?.tag == .array_access;
    
    if (is_nested and target_node.data.array_access.index != null and target_expr.?.data.array_access.index != null) {
        // 嵌套数组赋值
        const outer_array_reg = try self.generateExpression(target_expr.?.data.array_access.target);
        const outer_key_reg = try self.generateExpression(target_expr.?.data.array_access.index.?);
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
}
```

### 3. 代码生成器（src/aot/native_linker.zig）

添加 `array_set_nested` 的代码生成（两处）。

### 4. 优化器（src/aot/optimizer.zig）

添加 `array_set_nested` 的支持：
- 寄存器重命名
- 使用寄存器标记
- 副作用标记

### 5. 逃逸分析（src/aot/escape_analysis.zig）

添加 `array_set_nested` 的逃逸分析。

## 测试结果

### ✅ 二维数组（完全支持）

```php
// 数字键
$matrix = [];
$matrix[0][0] = 1;
$matrix[0][1] = 2;

// 字符串键
$data = [];
$data["user"]["name"] = "Alice";
$data["user"]["age"] = 30;

// 混合键
$mixed = [];
$mixed[0]["key"] = "value0";
$mixed["str"][0] = "str0";
```

**测试**: ✅ 所有二维数组测试通过

### ⚠️ 三维及以上数组（部分支持）

```php
// 三维数组
$cube = [];
$cube[0][0][0] = 100;  // ❌ 崩溃
```

**限制**: 当前实现只支持 **恰好两层** 的嵌套赋值。

**原因**: `$cube[0][0][0]` 需要三次 auto-vivification：
1. `$cube[0]` 不存在 → 需要创建
2. `$cube[0][0]` 不存在 → 需要创建（当前实现支持）
3. `$cube[0][0][0] = 100` → 设置（当前实现支持）

但步骤 1 没有处理，因为 `outer_array` 本身可能是 `array_get` 的结果（返回 `null`）。

**解决方案**: 需要递归处理所有嵌套层级，或者要求用户显式初始化：

```php
// 方案 A: 显式初始化
$cube = [];
$cube[0] = [];
$cube[0][0] = [];
$cube[0][0][0] = 100;  // ✅ 正常

// 方案 B: 逐层赋值
$cube = [];
$cube[0][0] = [];  // 先创建二维数组
$cube[0][0][0] = 100;  // ✅ 正常
```

## 影响范围

### 修复后支持的功能
- ✅ 二维数组赋值（任意键类型）
- ✅ Auto-vivification（二维）
- ⚠️ 三维及以上数组（需要显式初始化）

### 不影响的功能
- ✅ 单维数组
- ✅ 数组读取（任意维度）
- ✅ 其他数据类型

## 后续改进

### 支持任意深度嵌套

需要修改 IR 生成器，递归检测所有嵌套层级：

```zig
// 伪代码
fn generateNestedArrayAssignment(target: Node, value: Register) !void {
    var keys = ArrayList(Register).init(allocator);
    var current = target;
    
    // 收集所有键
    while (current.tag == .array_access) {
        keys.insert(0, try self.generateExpression(current.data.array_access.index.?));
        current = self.getNode(current.data.array_access.target).?;
    }
    
    // 生成递归的 auto-vivification 代码
    const base_array = try self.generateExpression(current);
    for (keys.items, 0..) |key, i| {
        if (i < keys.items.len - 1) {
            // 中间层：确保是数组
            _ = try self.emit(.{ .ensure_array = .{ .array = base_array, .key = key } }, null);
        } else {
            // 最后一层：设置值
            _ = try self.emit(.{ .array_set = .{ .array = base_array, .key = key, .value = value } }, null);
        }
    }
}
```

这需要添加新的 `ensure_array` 指令，并修改代码生成器。

**工作量**: 2-3 小时

## 总结

多维数组问题已通过添加 `array_set_nested` 指令得到修复，完全支持二维数组的 auto-vivification。

三维及以上数组需要显式初始化或逐层赋值，这是当前实现的限制。

如果需要完整支持任意深度嵌套，需要进一步修改 IR 生成器，添加递归的 auto-vivification 逻辑。

---

**修复日期**: 2026-02-27  
**修复人**: xiusin  
**优先级**: P1（已修复二维数组，三维数组为 P2）
**Commit**: 待提交

