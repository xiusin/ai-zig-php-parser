# OOP 测试报告 - 内存泄露与功能问题总结

**测试日期**: 2026年1月10日
**更新日期**: 2026年1月10日 (negation 运算符修复)
**测试范围**: OOP 完整功能测试
**测试文件**: test_oop_comprehensive.php, test_oop_memory_leak_stress.php, 以及现有 OOP 测试套件

---

## 修复状态更新

### ✅ 已修复问题

#### 1. 否定运算符与 Trait 方法调用问题 (2026-01-10)

**问题描述**:
当类使用 Trait 时，对 Trait 方法使用否定运算符 (`!`) 会导致 `$this` 变成非对象：

```php
class UserProfile {
    use ValidatableTrait;
    
    public function testNegation() {
        // 这种调用失败：
        $result = !$this->validateLength($this->username, 3, 20);
        // 错误: Method call on non-object
    }
}
```

**根因分析**:
解析器中 `parseUnaryPostfix()` 函数没有处理 `->` 运算符。当解析 `!$this->method(...)` 时：
1. `parseUnary()` 看到 `!`，调用 `parseUnaryPostfix()`
2. `parseUnaryPostfix()` 只解析 `$this` 作为变量，然后只处理 `(` 和 `[`
3. `->` 运算符没有被处理，方法调用被错误地解析为属性访问

**修复方案**:
在 `src/compiler/parser.zig` 的 `parseUnaryPostfix()` 函数中添加 `->` 运算符处理：

```zig
} else if (tag == .arrow) {
    // Method call or property access: $obj->method(...) or $obj->property
    const op = self.curr;
    self.nextToken();

    // Parse method/property name
    const member_name_tok = ...;
    const member_id = try self.context.intern(...);

    if (self.curr.tag == .l_paren) {
        // Method call
        self.nextToken();
        var args = std.ArrayListUnmanaged(ast.Node.Index){};
        while (self.curr.tag != .r_paren and self.curr.tag != .eof) {
            try args.append(self.allocator, try self.parseExpression(0));
            if (self.curr.tag == .comma) self.nextToken();
        }
        _ = try self.eat(.r_paren);
        left = try self.createNode(.{ .tag = .method_call, ... });
    } else {
        // Property access
        left = try self.createNode(.{ .tag = .property_access, ... });
    }
}
```

**测试验证**:
- ✅ 直接方法调用 `$this->validateLength(...)` - 通过
- ✅ 否定方法调用 `!$this->validateLength(...)` - 现在通过
- ✅ 多次调用顺序 - 通过
- ✅ 带 Trait 的类 - 通过

### 1.1 测试通过情况

| 测试项目 | 状态 | 说明 |
|---------|------|------|
| 循环引用 (Circular References) | ✅ 通过 | 基本功能正常 |
| 自引用对象 (Self-Referencing) | ✅ 通过 | 链表遍历正常 |
| 接口实现 (Interfaces) | ✅ 通过 | 多接口正常 |
| 闭包 (Closures) | ⚠️ 部分通过 | 复杂闭包有问题 |
| 异常处理 (Exceptions) | ✅ 通过 | 基本异常正常 |
| 对象数组 (Object Arrays) | ✅ 通过 | 数组操作正常 |
| 静态属性/单例 (Static/Singleton) | ✅ 通过 | 基本功能正常 |
| 克隆 (Cloning) | ⚠️ 待测试 | 未验证深拷贝 |
| 反射 (Reflection) | ✅ 通过 | 基本功能正常 |
| 动态属性 (Dynamic Properties) | ⚠️ 待测试 | 未完全验证 |
| 观察者模式 (Observer Pattern) | ✅ 通过 | 基本功能正常 |
| 依赖注入 (Dependency Injection) | ✅ 通过 | 基本功能正常 |
| 对象池 (Object Pool) | ✅ 通过 | 基本功能正常 |
| 工厂模式 (Factory Pattern) | ✅ 通过 | 基本功能正常 |
| 魔术方法 (Magic Methods) | ❌ 失败 | __call 存在问题 |
| ArrayAccess | ✅ 通过 | 基本功能正常 |
| Iterator | ✅ 通过 | 基本功能正常 |
| Traits | ❌ 失败 | 内部方法调用问题 |
| 匿名类 (Anonymous Classes) | ❌ 失败 | $this 作用域问题 |

### 1.2 性能统计

```
Function calls: 124
Memory allocations: 111
GC collections: 0
Execution time: ~2.5ms
String intern pool size: 20
```

---

## 二、解析错误 (Parsing Errors)

### 2.1 解析错误列表

```
DEBUG: parseStatement failed with error: error.UnexpectedToken at token: .k_set (set)
DEBUG: parseStatement failed with error: error.InvalidExpression at token: .r_brace (})
DEBUG: parseStatement failed with error: error.UnexpectedToken at token: .k_class (class)
DEBUG: parseStatement failed with error: error.UnexpectedToken at token: .l_brace ({)
DEBUG: parseStatement failed with error: error.InvalidExpression at token: .r_brace (})
DEBUG: parseStatement failed with error: error.UnexpectedToken at token: .k_class (class)
DEBUG: parseStatement failed with error: error.InvalidExpression at token: .r_paren ())
```

### 2.2 问题分析

1. **`.k_set` 令牌意外** - 可能是属性 setter 语法不支持
2. **`class` 关键字解析问题** - 类声明解析可能存在问题
3. **表达式解析问题** - 某些复杂表达式无法正确解析

### 2.3 修复建议

1. 检查 `src/compiler/parser.zig` 中的类声明解析逻辑
2. 检查属性 setter/getter 的解析支持
3. 验证表达式解析器对复杂场景的处理

---

## 三、运行时错误 (Runtime Errors)

### 3.1 错误详情

#### 错误 1: UndefinedMethod - 闭包捕获对象
```
Runtime error: UndefinedMethod
位置: test_oop_comprehensive.php (Test 3: Closures Capturing Objects)
```

**问题描述**: 当闭包捕获对象并尝试调用对象方法时失败

#### 错误 2: TypeError - Trait 方法调用
```
Uncaught TypeError: Method call on non-object
位置: test_oop_traits.php:92
```

**问题描述**: `ReflectionClass::getProperties()` 返回 null 或非对象

```php
// 问题代码
$reflection = new ReflectionClass($this);
$properties = [];
foreach ($reflection->getProperties() as $property) {  // 92行
    $property->setAccessible(true);
    $properties[$property->getName()] = $property->getValue($this);
}
```

#### 错误 3: TypeError - Magic Methods __call
```
Uncaught TypeError: Value is not callable
位置: test_oop_magic_methods.php:82
```

**问题描述**: `__call` 方法返回的值无法被调用

```php
// 问题代码
echo $this->undefinedMethod("arg1", "arg2") . "\n";  // 82行
```

#### 错误 4: UndefinedVariableError - 匿名类中 $this
```
Uncaught UndefinedVariableError: Undefined variable: $this
位置: test_oop_anonymous_classes.php:66
```

**问题描述**: 匿名类内部闭包无法访问外部 `$this`

```php
// 问题代码
return new class($data) {
    public function process($input) {
        return function() use ($input) {
            return strtoupper($input . $this->suffix);  // $this 未定义
        };
    }
};
```

#### 错误 5: UndefinedFunction - memory_get_usage
```
Uncaught UndefinedFunctionError: Call to undefined function memory_get_usage()
位置: test_oop_memory_leak_stress.php:10
```

**问题描述**: `memory_get_usage()` 函数未实现

### 3.2 修复建议

1. **闭包问题**: 检查 `src/runtime/vm.zig` 中闭包捕获对象的实现
2. **Reflection 问题**: 完善 `src/reflection.zig` 中 `getProperties()` 方法
3. **Magic Methods**: 修复 `__call` 返回值的调用处理
4. **匿名类 $this**: 确保匿名类正确继承外部作用域的 `$this`
5. **内存函数**: 实现 `memory_get_usage()` 和相关函数

---

## 四、内存泄露问题 (Memory Leaks)

### 4.1 泄露统计

每次测试平均发现 **50-100+** 个内存泄露地址:

```
error(gpa): memory address 0x1051a0006 leaked:
error(gpa): memory address 0x1051a0007 leaked:
error(gpa): memory address 0x1051a0008 leaked:
... (更多类似条目)
```

### 4.2 泄露场景分析

#### 场景 1: 对象创建/销毁
```php
for ($i = 0; $i < 1000; $i++) {
    $obj = new RapidCreate($i);
    unset($obj);
}
```
**问题**: 对象销毁后内存未释放

#### 场景 2: 循环引用
```php
$nodeA->partner = $nodeB;
$nodeB->partner = $nodeA;
unset($nodeA);
unset($nodeB);
```
**问题**: 循环引用对象未正确检测和回收

#### 场景 3: 闭包捕获对象
```php
$closures[] = function() use ($target) {
    return $target->value;
};
```
**问题**: 闭包捕获的对象引用计数未正确管理

#### 场景 4: 静态注册表
```php
StaticRegistry::register("key{$i}", $obj);
StaticRegistry::clear();
```
**问题**: 静态属性中存储的对象未完全释放

### 4.3 内存泄露位置推测

根据泄露模式，最可能的泄露位置在:

1. **`src/runtime/types.zig`** - `Value` 联合类型的内存管理
2. **`src/runtime/gc.zig`** - 垃圾回收器实现
3. **`src/runtime/vm.zig`** - 虚拟机中的对象生命周期管理
4. **`src/runtime/object.zig`** - 对象创建和销毁逻辑

### 4.4 修复方案

#### 方案 1: 完善引用计数
```zig
// 在类型系统中增加精确的引用计数管理
pub fn retain(self: *Value) void {
    switch (self) {
        .object_val => |obj| obj.ref_count += 1,
        .string_val => |str| str.ref_count += 1,
        .array_val => |arr| arr.ref_count += 1,
        else => {},
    }
}

pub fn release(self: *Value) void {
    switch (self) {
        .object_val => |obj| {
            obj.ref_count -= 1;
            if (obj.ref_count == 0) {
                self.dealloc();
            }
        },
        // ...
    }
}
```

#### 方案 2: 循环检测
```zig
// 实现标记-清除算法处理循环引用
pub fn collectCycles(self: *GC) void {
    var root_set = std.ArrayList(*Object).init(self.allocator);
    defer root_set.deinit();
    
    // 标记从根可达的所有对象
    self.mark(&root_set);
    
    // 清除不可达对象
    self.sweep(&root_set);
}
```

#### 方案 3: 完善析构函数调用
```zig
// 确保对象的 __destruct 被正确调用
pub fn destroyObject(self: *VM, obj: *Object) void {
    if (obj.class.destructor) |destructor| {
        self.callMethod(obj, destructor, &.{});
    }
    // 释放对象属性
    self.freeObjectProperties(obj);
    // 释放对象本身
    self.allocator.destroy(obj);
}
```

---

## 五、未支持的 PHP 功能

### 5.1 完整列表

| 功能 | 状态 | 优先级 |
|-----|------|-------|
| `memory_get_usage()` | ❌ 未实现 | 高 |
| `memory_get_peak_usage()` | ❌ 未实现 | 中 |
| `gc_collect_cycles()` | ❌ 未实现 | 高 |
| `ReflectionProperty::setAccessible()` | ❌ 未实现 | 高 |
| 箭头函数中的 `$this` | ❌ 未实现 | 高 |
| 属性访问器 (getter/setter) | ❌ 未实现 | 中 |
| 联合类型声明 | ⚠️ 部分支持 | 中 |
| 混合类型 (mixed) | ⚠️ 部分支持 | 中 |

### 5.2 实现建议

1. **内存函数**: 在 `src/builtins.zig` 中添加内存相关内置函数
2. **反射增强**: 完善 `src/reflection.zig` 中的 `ReflectionProperty` 实现
3. **$this 处理**: 在闭包/箭头函数解析时正确绑定 `$this`

---

## 六、测试文件清单

### 6.1 新增测试文件

1. **`test_oop_comprehensive.php`** - 综合 OOP 测试 (17个测试场景)
2. **`test_oop_memory_leak_stress.php`** - 内存泄露压力测试 (7个场景)

### 6.2 测试场景覆盖

```
test_oop_comprehensive.php:
├── 1. 循环引用
├── 2. 自引用对象
├── 3. 闭包捕获对象
├── 4. 异常处理
├── 5. 对象数组
├── 6. 静态属性/单例
├── 7. 对象克隆
├── 8. 反射操作
├── 9. 动态属性
├── 10. 观察者模式
├── 11. 依赖注入容器
├── 12. 对象池
├── 13. 工厂模式
├── 14. 魔术方法
├── 15. ArrayAccess
├── 16. Iterator
└── 17. Stringable

test_oop_memory_leak_stress.php:
├── 1. 快速创建/销毁
├── 2. 循环引用压力
├── 3. 闭包内存压力
├── 4. 异常链压力
├── 5. 对象数组压力
├── 6. 静态注册表压力
└── 7. 对象图压力
```

---

## 七、修复优先级

### 高优先级 (P0)

1. ✅ **内存泄露** - 修复 GPA 内存泄露 (影响所有测试)
2. ✅ **闭包 $this 绑定** - 匿名类中 $this 未定义
3. ✅ **Trait 反射** - `getProperties()` 返回 null

### 中优先级 (P1)

1. ⚠️ **Magic Methods** - `__call` 返回值处理
2. ⚠️ **内存函数** - 实现 `memory_get_usage()`
3. ⚠️ **解析错误** - 某些语法解析失败

### 低优先级 (P2)

1. 🔲 **性能优化** - 减少 GC collections
2. 🔲 **高级反射** - `setAccessible()` 实现
3. 🔲 **属性访问器** - getter/setter 语法

---

## 八、附录: 测试命令

```bash
# 运行综合测试
./zig-out/bin/php-interpreter examples/tests/oop/test_oop_comprehensive.php

# 运行内存泄露测试
./zig-out/bin/php-interpreter examples/tests/oop/test_oop_memory_leak_stress.php

# 运行现有 OOP 测试
./zig-out/bin/php-interpreter examples/tests/oop/test_oop_*.php

# 运行内存泄露检测脚本
bash test_oop_memory_leaks.sh
```

---

## 九、总结

本次测试发现了以下关键问题:

1. **严重**: 存在大量内存泄露 (50-100+ 地址/测试)
2. **严重**: 匿名类中 `$this` 作用域问题
3. **严重**: Trait 中反射方法返回 null
4. **中等**: 魔术方法 `__call` 返回值处理
5. **中等**: 缺少 `memory_get_usage()` 等函数

**建议**: 优先修复内存泄露问题，这是影响所有功能的基础性问题。
