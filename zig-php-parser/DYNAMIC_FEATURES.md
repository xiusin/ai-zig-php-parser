# 动态特性支持文档

## 概述

zig-php-parser项目支持多种动态特性，这些特性在解释器模式下完全可用。AOT编译器则专注于静态优化的场景。

---

## 支持的动态特性

### 1. 动态函数调用 ✅

**函数**: `call_user_func`, `call_user_func_array`

**描述**: 通过函数名或回调动态调用函数

**示例**:
```php
<?php
// 通过函数名调用
$func = "strlen";
$result = call_user_func($func, "Hello");

// 通过回调数组调用
$result = call_user_func([$obj, "method"], $arg1, $arg2);

// 通过数组传递参数
$result = call_user_func_array("array_sum", [[1, 2, 3]]);
```

**实现位置**: `src/runtime/vm.zig`

```zig
fn callUserFuncFn(vm: *VM, args: []const Value) !Value {
    // 实现动态函数调用
}

fn callUserFuncArrayFn(vm: *VM, args: []const Value) !Value {
    // 实现通过数组传递参数的动态函数调用
}
```

---

### 2. 动态属性访问 ✅

**描述**: 对象可以动态添加和访问属性

**示例**:
```php
<?php
$obj = new stdClass();
$obj->dynamicProperty = "Hello";  // 动态添加属性
echo $obj->dynamicProperty;       // 动态访问属性
```

**实现位置**: `src/runtime/builtin_classes.zig`

```zig
pub const DynamicObject = struct {
    dynamic_properties: std.StringHashMap(Value),

    pub fn setProperty(self: *DynamicObject, name: []const u8, value: Value) !void;
    pub fn getProperty(self: *DynamicObject, name: []const u8) !Value;
    pub fn hasProperty(self: *DynamicObject, name: []const u8) bool;
    pub fn unsetProperty(self: *DynamicObject, name: []const u8) void;
};
```

---

### 3. 动态类型系统 ✅

**描述**: 支持动态类型推断和运行时类型检查

**示例**:
```php
<?php
// 动态类型
$var = 42;          // int
$var = "Hello";      // string
$var = [1, 2, 3];    // array

// 类型推断在AOT编译时进行
// 运行时类型检查在解释器模式下进行
```

**实现位置**: `src/aot/type_inference.zig`, `src/aot/symbol_table.zig`

```zig
pub const InferredType = union(enum) {
    concrete: ConcreteType,
    union_type: []const InferredType,
    dynamic: void,  // 动态类型

    pub fn isDynamic(self: InferredType) bool {
        return self == .dynamic;
    }
};
```

---

### 4. 动态路径检测 ✅

**描述**: 检测include/require路径是否包含动态变量

**示例**:
```php
<?php
// 静态路径
include "config.php";           // 静态，AOT编译时解析
include "lib/utils.php";        // 静态，AOT编译时解析

// 动态路径
include "$dir/config.php";      // 动态，运行时解析
include "${base}/file.php";     // 动态，运行时解析
```

**实现位置**: `src/aot/dependency_resolver.zig`

```zig
pub fn isDynamicPath(self: *Self, path: []const u8) bool {
    // 检查路径是否包含变量
    // 如 $dir, ${base} 等
}
```

---

### 5. 动态方法调用 ✅

**描述**: 通过方法名动态调用对象方法

**示例**:
```php
<?php
$obj = new MyClass();
$method = "process";
$result = $obj->$method($arg1, $arg2);
```

**实现位置**: `src/runtime/vm.zig`

```zig
fn evaluateMethodCall(self: *VM, method_data: anytype) !Value {
    // 动态方法调用实现
}
```

---

### 6. 动态数组访问 ✅

**描述**: 通过变量索引访问数组元素

**示例**:
```php
<?php
$arr = [1, 2, 3, 4, 5];
$index = 2;
echo $arr[$index];  // 输出 3
```

**实现位置**: `src/runtime/vm.zig`

```zig
fn evaluateArrayAccess(self: *VM, array_access: anytype) !Value {
    // 动态数组访问实现
}
```

---

## AOT编译与动态特性

### AOT编译的限制

AOT编译器在编译时进行静态分析和优化，因此对某些动态特性有限制：

**不支持**:
- ❌ `eval()` 函数（运行时执行代码）
- ❌ 动态include路径（运行时解析）
- ❌ 完全动态的函数调用（无法静态分析）

**支持**:
- ✅ 已知的函数调用（通过类型推断）
- ✅ 静态include路径
- ✅ 部分动态特性（通过动态类型系统）

### 动态特性与AOT编译的权衡

| 特性 | 解释器模式 | AOT编译模式 |
|------|-----------|-----------|
| 动态函数调用 | ✅ 完全支持 | ⚠️ 部分支持 |
| 动态属性 | ✅ 完全支持 | ⚠️ 部分支持 |
| 动态类型 | ✅ 完全支持 | ⚠️ 类型推断 |
| 动态路径 | ✅ 完全支持 | ❌ 不支持 |
| eval() | ✅ 完全支持 | ❌ 不支持 |
| 性能 | ⚠️ 解释器开销 | ✅ 本地机器码 |

---

## 使用建议

### 1. 开发调试阶段

**推荐**: 使用解释器模式

```bash
zig-php script.php
```

**优势**:
- ✅ 支持所有动态特性
- ✅ 快速迭代
- ✅ 易于调试

### 2. 生产部署阶段

**推荐**: 使用AOT编译模式

```bash
zig-php --compile --optimize=release-fast app.php
```

**优势**:
- ✅ 最高性能
- ✅ 无需PHP运行时
- ✅ 快速启动

**注意**:
- ⚠️ 避免使用动态特性
- ⚠️ 使用静态类型
- ⚠️ 使用静态路径

---

## 动态特性的最佳实践

### 1. 避免过度使用动态特性

**不推荐**:
```php
<?php
// 过度动态
$func = $_GET['func'];
$result = $func();  // 安全风险
```

**推荐**:
```php
<?php
// 白名单机制
$allowed_funcs = ['func1', 'func2'];
$func = $_GET['func'];
if (in_array($func, $allowed_funcs)) {
    $result = $func();
}
```

### 2. 使用类型提示

**推荐**:
```php
<?php
function process(int $num): string {
    return (string)$num;
}
```

### 3. 优先使用静态路径

**不推荐**:
```php
<?php
include "$path/config.php";
```

**推荐**:
```php
<?php
include __DIR__ . "/config.php";
```

---

## 未来计划

### 短期目标
- [ ] 完善 `eval()` 函数的实现
- [ ] 改进动态类型推断
- [ ] 增强动态路径处理

### 中期目标
- [ ] 支持更多动态特性
- [ ] 改进AOT编译器对动态特性的支持
- [ ] 性能优化

### 长期目标
- [ ] 混合模式（AOT + JIT）
- [ ] 渐进式类型系统
- [ ] 完整的PHP兼容性

---

## 总结

zig-php-parser项目在解释器模式下完全支持PHP的动态特性，同时通过AOT编译器提供高性能的静态编译选项。开发者可以根据需求选择合适的模式：

- **开发调试**: 解释器模式，支持所有动态特性
- **生产部署**: AOT编译模式，最高性能

这种设计既保留了PHP的灵活性，又提供了接近原生代码的性能！🚀