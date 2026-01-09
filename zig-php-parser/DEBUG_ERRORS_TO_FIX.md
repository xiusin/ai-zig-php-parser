# DEBUG错误修复清单

生成时间：2026-01-04
总错误数：58个（异常测试1个 + OOP测试57个）

---

## 一、异常测试错误（1个）

### 1.1 spaceship operator错误

**错误类型**: `error.InvalidExpression at token: .greater (>)`

**影响文件**:
- `examples/test_undefined_in_spaceship.php`

**错误原因**:
- 在解析`$undefined_var <=> 10`时，parser遇到未定义变量会抛出错误
- 错误恢复机制跳过了`.spaceship` token，导致遇到`.greater` token

**修复建议**:
1. 改进parser的错误恢复机制，确保在遇到未定义变量时能够正确恢复
2. 在`synchronize()`函数中添加对`.spaceship` token的处理
3. 或者在`parseExpression()`中添加对未定义变量的特殊处理

**优先级**: 中

---

## 二、OOP测试错误（57个）

### 2.1 throw语句错误（2个）

**错误类型**: `error.InvalidExpression at token: .k_throw (throw)`

**影响文件**:
- `examples/test_oop_type_hints.php`
- `examples/test_oop_iterators.php`

**错误原因**:
- parser.zig的`parseStatement()`函数中，`.k_throw`已经映射到`self.parseThrow()`
- 但`parseThrow()`函数可能未实现或实现不完整

**修复建议**:
1. 检查`parser.zig`中的`parseThrow()`函数实现
2. 确保throw语句能够正确解析表达式
3. 在VM中实现throw语句的执行逻辑

**优先级**: 高

**相关代码位置**:
- `src/compiler/parser.zig`: parseThrow函数
- `src/runtime/vm.zig`: evaluateThrowStatement函数

---

### 2.2 属性钩子错误（4个）

**错误类型**: `error.UnexpectedToken at token: .k_set (set)` / `error.UnexpectedToken at token: .k_get (get)`

**影响文件**:
- `examples/test_oop_iterators.php`
- `examples/test_oop_serialization.php`

**错误原因**:
- `set`和`get`是PHP 8.4的属性钩子（Property Hooks）特性
- parser.zig已经添加了对`.k_set`和`.k_get`的处理，但实现不完整
- 在类成员解析时，这些关键字应该被识别为属性钩子而不是普通方法

**修复建议**:
1. 完善`parseClassMember()`函数中的属性钩子解析逻辑
2. 在AST中添加属性钩子节点的支持
3. 在VM中实现属性钩子的执行逻辑

**优先级**: 中

**相关代码位置**:
- `src/compiler/parser.zig`: parseClassMember函数（第271行附近）
- `src/compiler/ast.zig`: 添加property_hook相关的数据结构

---

### 2.3 spaceship operator错误（1个）

**错误类型**: `error.InvalidExpression at token: .greater (>)`

**影响文件**:
- `examples/test_oop_multiple_interfaces.php`

**错误原因**:
- 与异常测试中的spaceship operator错误相同
- 在比较操作中，spaceship operator `<=>` 的解析出现问题

**修复建议**:
- 同2.1

**优先级**: 中

---

### 2.4 赋值符号错误（17个）

**错误类型**: `error.InvalidExpression at token: .equal (=)`

**影响文件**:
- `examples/test_oop_method_chaining.php` (14个)
- `examples/test_oop_composite_pattern.php` (3个)

**错误原因**:
- 在解析表达式时遇到赋值符号
- 可能是parser错误恢复机制导致的问题
- 也可能是对象字面量（object literal）解析不完整

**修复建议**:
1. 检查`parseExpression()`函数中对`.equal` token的处理
2. 改进对象字面量的解析逻辑（`parseArrayConstruct`函数）
3. 确保parser错误恢复机制能够正确处理赋值语句

**优先级**: 中

**相关代码位置**:
- `src/compiler/parser.zig`: parseExpression函数（第1114行附近）
- `src/compiler/parser.zig`: parseArrayConstruct函数（第2063行附近）

---

### 2.5 右大括号错误（32个）

**错误类型**: `error.InvalidExpression at token: .r_brace (})`

**影响文件**:
- `examples/test_oop_type_hints.php`
- `examples/test_oop_iterators.php`
- `examples/test_oop_closures.php`
- `examples/test_oop_serialization.php`
- `examples/test_oop_method_chaining.php`
- `examples/test_oop_multiple_interfaces.php`
- `examples/test_oop_composite_pattern.php`

**错误原因**:
- 这是parser错误恢复机制的副作用
- 当解析某个语句失败后，synchronize()函数跳过tokens直到遇到statement边界
- `.r_brace`是statement边界之一，但parser没有正确处理它

**修复建议**:
1. 改进`synchronize()`函数的逻辑
2. 确保在遇到`.r_brace`时能够正确恢复解析状态
3. 添加更多statement边界检查点

**优先级**: 低（这是错误恢复的副作用，不影响正常代码）

**相关代码位置**:
- `src/compiler/parser.zig`: synchronize函数（第126行附近）
- `src/compiler/parser.zig`: recoverFromError函数（第131行附近）

---

### 2.6 分号错误（5个）

**错误类型**: `error.InvalidExpression at token: .semicolon (;)`

**影响文件**:
- `examples/test_oop_iterators.php`

**错误原因**:
- 与右大括号错误类似，这是parser错误恢复机制的副作用
- `.semicolon`也是statement边界之一

**修复建议**:
- 同2.5

**优先级**: 低

---

### 2.7 左大括号错误（1个）

**错误类型**: `error.UnexpectedToken at token: .l_brace ({)`

**影响文件**:
- `examples/test_oop_iterators.php`

**错误原因**:
- 可能是对象字面量或闭包解析不完整
- parser期望一个表达式，但遇到了左大括号

**修复建议**:
1. 检查对象字面量的解析逻辑
2. 检查闭包的解析逻辑
3. 确保parser能够正确识别这些语法结构

**优先级**: 中

---

## 三、错误统计

### 按错误类型统计：

| 错误类型 | 数量 | 优先级 |
|---------|------|--------|
| `.k_throw` | 2 | 高 |
| `.k_set` / `.k_get` | 4 | 中 |
| `.greater` (spaceship) | 2 | 中 |
| `.equal` | 17 | 中 |
| `.r_brace` | 32 | 低 |
| `.semicolon` | 5 | 低 |
| `.l_brace` | 1 | 中 |

### 按影响文件统计：

| 文件 | 错误数 | 主要错误类型 |
|------|--------|-------------|
| test_oop_method_chaining.php | 19 | `.equal`, `.r_brace` |
| test_oop_iterators.php | 14 | `.k_throw`, `.r_brace`, `.semicolon` |
| test_oop_serialization.php | 10 | `.k_set`, `.k_get`, `.r_brace` |
| test_oop_multiple_interfaces.php | 4 | `.greater`, `.r_brace` |
| test_oop_composite_pattern.php | 3 | `.equal`, `.r_brace` |
| test_oop_type_hints.php | 3 | `.k_throw`, `.r_brace` |
| test_oop_closures.php | 2 | `.r_brace` |
| test_oop_namespaces.php | 2 | `.r_brace` |
| test_undefined_in_spaceship.php | 1 | `.greater` |

---

## 四、修复优先级

### 高优先级（必须修复）：
1. throw语句实现（2个错误）

### 中优先级（建议修复）：
1. 属性钩子实现（4个错误）
2. spaceship operator修复（2个错误）
3. 赋值符号/对象字面量修复（18个错误）
4. 左大括号修复（1个错误）

### 低优先级（可选修复）：
1. parser错误恢复机制改进（37个错误）

---

## 五、修复步骤建议

### 第一步：修复高优先级错误
1. 实现`parseThrow()`函数
2. 在VM中实现`evaluateThrowStatement()`函数
3. 测试throw语句功能

### 第二步：修复中优先级错误
1. 完善属性钩子解析和执行
2. 修复spaceship operator的parser错误恢复
3. 改进对象字面量解析
4. 测试这些功能

### 第三步：优化parser错误恢复（可选）
1. 改进`synchronize()`函数
2. 改进`recoverFromError()`函数
3. 添加更多statement边界检查点
4. 测试错误恢复机制

---

## 六、测试验证

修复后，运行以下命令验证：

```bash
# 运行所有测试
./run_all_memory_tests.sh

# 检查DEBUG错误数量
cat exception_debug_errors.log | wc -l
cat oop_debug_errors.log | wc -l

# 确保无内存泄露
grep -i "memory leak" memory_leak_test_results.log
grep -i "memory leak" oop_memory_leak_test_results.log
```

---

## 七、注意事项

1. **内存泄露**: 修复任何功能时，必须确保不会引入内存泄露
2. **向后兼容**: 修复parser错误恢复时，不要破坏现有的正常代码解析
3. **测试覆盖**: 每次修复后，都要运行完整的测试套件
4. **性能影响**: parser错误恢复的改进不应影响正常代码的解析性能

---

## 八、相关文档

- PHP 8.4 Property Hooks: https://wiki.php.net/rfc/property-hooks
- PHP spaceship operator: https://www.php.net/manual/en/language.operators.comparison.php#language.operators.comparison.spaceship
- PHP throw statement: https://www.php.net/manual/en/language.exceptions.php

---

## 九、OOP高级测试新发现的解析器限制（2026-01-09）

### 9.1 类常量不支持

**错误类型**: `error.UnexpectedToken at token: .k_const (const)`

**影响代码**:
```php
class Config {
    const VERSION = "1.0.0";  // 不支持
}
```

**原因**: parser未实现类常量的解析逻辑

**优先级**: 低

---

### 9.2 instanceof操作符不支持

**错误类型**: `Undefined variable: $Rectangle`

**影响代码**:
```php
$shape instanceof Rectangle;  // 不支持
$obj instanceof Shape;        // 不支持
```

**原因**: parser未实现`instanceof`关键字的解析

**优先级**: 中

---

### 9.3 静态属性自增/自减不支持

**错误类型**: `TypeError: Increment/decrement only supports variables and properties`

**影响代码**:
```php
self::$instanceCount++;  // 不支持
self::$count = self::$count + 1;  // 支持
```

**原因**: VM未实现静态属性的`++/--`操作

**优先级**: 低

---

### 9.4 预定义常量不支持

**错误类型**: `Undefined variable: $PHP_EOL`

**影响代码**:
```php
echo "Hello" . PHP_EOL;  // 不支持
```

**原因**: 未实现`PHP_EOL`等预定义常量

**优先级**: 低

---

### 9.5 当前支持和不支持的OOP功能对比

| 功能 | 状态 | 说明 |
|------|------|------|
| 类定义 | ✅ 支持 | `class ClassName { }` |
| 构造函数 | ✅ 支持 | `public function __construct()` |
| 访问修饰符 | ✅ 支持 | `private`, `protected`, `public` |
| 静态成员变量 | ✅ 支持 | `private static $var` |
| 静态方法 | ✅ 支持 | `public static function method()` |
| 接口定义 | ✅ 支持 | `interface Shape { }` |
| 接口实现 | ✅ 支持 | `class Rect implements Shape` |
| 多态 | ✅ 支持 | `function foo(Shape $shape)` |
| self::访问静态成员 | ✅ 支持 | `self::$count + 1` |
| **类常量** | ❌ 不支持 | `const VERSION = "1.0"` |
| **instanceof** | ❌ 不支持 | `$obj instanceof Class` |
| **静态属性++** | ❌ 不支持 | `self::$count++` |
| **预定义常量** | ❌ 不支持 | `PHP_EOL`, `PHP_VERSION` |