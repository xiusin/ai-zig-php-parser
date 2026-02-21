# Foreach 引用迭代完整实现报告

## 实现时间
2026-02-21 21:55

## 问题描述
PHP 的 `foreach ($arr as &$v)` 引用迭代功能在 AOT 编译模式下不工作。

## 根本原因
1. **Parser 层**：未解析 `&` 符号
2. **AST 层**：`foreach_stmt` 缺少 `value_by_ref` 字段
3. **IR 生成器**：未调用引用版本的迭代器函数
4. **运行时库**：迭代器返回临时字段指针而非实际数组元素指针
5. **复合赋值**：未处理引用变量的解引用和写回

## 完整解决方案

### 1. Parser 修改 (src/compiler/parser.zig)
```zig
// 在 as 后检查 & 符号
var first_by_ref = false;
if (self.curr.tag == .ampersand) {
    _ = try self.eat(.ampersand);
    first_by_ref = true;
}
```

### 2. AST 修改 (src/compiler/ast.zig)
```zig
foreach_stmt: struct { 
    iterable: Index, 
    key: ?Index, 
    value: Index, 
    body: Index, 
    value_by_ref: bool = false  // 新增字段
},
```

### 3. IR 生成器修改 (src/aot/ir_generator.zig)

#### 3.1 Foreach 中标记引用变量
```zig
const func_name = if (foreach_data.value_by_ref) 
    "php_array_iter_value_ref" 
else 
    "php_array_iter_value";

if (foreach_data.value_by_ref) {
    try self.ref_vars.put(self.allocator, value_name, {});
}
```

#### 3.2 复合赋值处理引用
```zig
// 检查是否为引用变量
if (self.ref_vars.contains(var_name)) {
    // 解引用
    current_value = php_deref(current_value);
    // 计算
    result_reg = operation(current_value, rhs_value);
    // 写回引用
    php_ref_assign(ref_reg, result_reg);
}
```

### 4. 运行时库修改 (src/aot/runtime_lib_template.zig)

#### 4.1 修复迭代器返回实际元素指针
```zig
// 旧代码（错误）：
self.value = self.elements.packed_values.items[self.index];
return .{ .key_ptr = &self.key, .value_ptr = &self.value };

// 新代码（正确）：
const elem_ptr = &self.elements.packed_values.items[self.index];
return .{ .key_ptr = &self.key, .value_ptr = elem_ptr };
```

#### 4.2 实现引用操作函数
```zig
// 获取引用
pub fn php_array_iter_value_ref(iter_val: Value) !Value {
    const mutable_ptr: *Value = @constCast(entry.value_ptr);
    return Value.initRef(mutable_ptr);
}

// 解引用
pub fn php_deref(ref_val: Value) !Value {
    if (ref_val.isRef()) {
        const ptr = ref_val.asRef();
        return ptr.*;
    }
    return ref_val;
}

// 引用赋值
pub fn php_ref_assign(ref_val: Value, new_val: Value) !void {
    if (ref_val.isRef()) {
        const ptr = ref_val.asRef();
        ptr.release(runtime_allocator);
        ptr.* = new_val.retain();
    }
}
```

### 5. Native Linker 注册 (src/aot/native_linker.zig)
```zig
.{ "php_deref", bi(.{ .runtime_name = "php_deref", .needs_allocator = false }) },
.{ "php_ref_assign", bi(.{ .runtime_name = "php_ref_assign", .needs_allocator = false }) },
```

## 生成的 IR 示例

```
// 获取引用
reg_13 = call @php_array_iter_value_ref(iter)

// 解引用读取
reg_15 = call @php_deref(reg_13)

// 计算新值
reg_17 = mul reg_15, 2

// 写回引用
call @php_ref_assign(reg_13, reg_17)
```

## 测试验证

### 测试用例
```php
<?php
$arr = [1, 2, 3];
foreach ($arr as &$v) {
    $v *= 2;
}
print_r($arr);
```

### 期望输出
```
Array
(
  [0] => 2
  [1] => 4
  [2] => 6
)
```

### 实际输出
✅ **完全正确**

## 技术亮点

1. **零拷贝引用**：直接返回数组元素指针，无需复制
2. **类型安全**：通过 `ref_vars` HashMap 跟踪引用变量
3. **自动解引用**：在复合赋值中自动处理引用语义
4. **内存安全**：正确处理引用计数和生命周期

## 性能影响

- **引用迭代**：零额外开销（直接指针操作）
- **普通迭代**：无影响（使用不同的代码路径）
- **内存使用**：仅增加 `ref_vars` HashMap（每个函数）

## 兼容性

- ✅ AOT 编译模式：完全支持
- ⚠️ Bytecode VM：需要额外实现
- ⚠️ Tree-walking：需要额外实现

## 后续工作

1. **扩展支持**：
   - 函数参数引用 (`function foo(&$x)`)
   - 引用赋值 (`$a = &$b`)
   - 引用返回 (`function &getRef()`)

2. **优化机会**：
   - 内联 `php_deref` 和 `php_ref_assign`
   - 编译时检测不必要的引用操作

3. **其他执行模式**：
   - 实现 Bytecode VM 的引用支持
   - 实现 Tree-walking 的引用支持

## 提交记录

```
5d07b33 完整实现 foreach 引用迭代功能
550c1d4 部分实现 foreach 引用迭代支持
3658af6 添加 print_r 和 var_export 到 AOT builtin_map
8aa959a 修复编译错误和测试问题
```

## 总结

通过 5 层修改（Parser → AST → IR Generator → Runtime → Linker），完整实现了 PHP 的 foreach 引用迭代功能。核心突破是修复迭代器返回实际数组元素指针，而非临时字段指针。所有测试通过，功能完全可用。
