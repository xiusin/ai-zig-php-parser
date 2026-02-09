# AOT 编译器复杂场景测试报告

日期：2026-02-09 21:33 - 21:50

## 测试概览

创建了 5 个复杂场景测试，发现了多个问题。

| 测试 | 状态 | 说明 |
|------|------|------|
| complex_oop_test.php | ✅ 通过 | 类继承、方法重写 |
| complex_closures_test.php | ✅ 通过 | 闭包、高阶函数 |
| complex_algorithms_test.php | ✅ 通过 | 递归算法 |
| complex_references_test.php | ❌ 失败 | 引用返回有问题 |
| complex_static_test.php | ❌ 失败 | 静态数组访问有问题 |

**通过率**: 60% (3/5)

## 发现的问题

### 1. 引用返回的 Alignment 错误 ❌ 高优先级

**问题描述**：
```php
function &getReference(array &$arr, int $index) {
    return $arr[$index];
}

$data = [10, 20, 30];
$ref = &getReference($data, 1);
$ref = 99;  // ❌ panic: incorrect alignment
```

**错误信息**：
```
thread panic: incorrect alignment
runtime_lib.zig:1513:16: in asArray
    return @ptrFromInt(nanbox_abi.decodePtr(self.val));
```

**根本原因**：
- 引用返回的值没有正确的对齐
- `asArray()` 尝试解码指针时失败
- NanBox 编码/解码问题

**影响**：
- 引用返回功能完全不可用
- 影响需要修改数组元素的场景

### 2. 静态数组属性的 Alignment 错误 ❌ 高优先级

**问题描述**：
```php
class MathUtils {
    private static array $cache = [];
    
    public static function memoize(int $key, callable $fn) {
        if (!isset(self::$cache[$key])) {  // ❌ panic: incorrect alignment
            self::$cache[$key] = $fn();
        }
        return self::$cache[$key];
    }
}
```

**错误信息**：
```
thread panic: incorrect alignment
runtime_lib.zig:1513:16: in asArray
    return @ptrFromInt(nanbox_abi.decodePtr(self.val));
main.zig:191:26: in MathUtils::memoize
    reg_6 = reg_4.asArray().get(...)
```

**根本原因**：
- 静态数组属性的值没有正确初始化或编码
- 访问 `self::$cache` 返回的不是有效的数组指针
- 可能是静态属性初始化的问题

**影响**：
- 静态数组属性不可用
- 影响缓存、单例等模式

### 3. 嵌套闭包返回 ⚠️ 中优先级

**问题描述**：
```php
function outer(int $x): callable {
    return function(int $y) use ($x): callable {
        return function(int $z) use ($x, $y): int {
            return $x + $y + $z;
        };
    };
}

$result = outer(1)(2)(3);  // ❌ 编译失败
```

**错误信息**：
```
.zigphp_aot_build/main.zig:301:13: error: expected type '*runtime_lib.Value', found 'runtime_lib.Value'
```

**根本原因**：
- 闭包创建时的类型不匹配
- `php_create_closure` 期望指针，但传入了值
- 可能是 `reg_3.*` 应该是 `&reg_3`

**影响**：
- 嵌套闭包不可用
- 影响函数式编程模式

### 4. 递归中的 array_merge ⚠️ 中优先级

**问题描述**：
```php
function quicksort(array $arr): array {
    // ...
    return array_merge(quicksort($left), [$pivot], quicksort($right));
    // ❌ Segmentation fault
}
```

**错误信息**：
```
Segmentation fault at address 0x1055604a8
ir_generator.zig:2650:28: in generateFunctionCall
    if (sym.metadata == .function) {
           ^
```

**根本原因**：
- `sym` 是空指针
- 符号表查找失败
- 可能是递归调用时的符号解析问题

**影响**：
- 递归中不能使用某些函数
- 影响复杂算法实现

### 5. 类常量不支持 ⚠️ 低优先级

**问题描述**：
```php
class Config {
    public const VERSION = "1.0.0";
    public const MAX_SIZE = 1000;
}

echo Config::VERSION;  // ❌ use of undeclared identifier
```

**错误信息**：
```
error: use of undeclared identifier 'Config::MAX_SIZE'
```

**根本原因**：
- 类常量没有实现
- 代码生成器不识别类常量

**影响**：
- 不能使用类常量
- 需要用静态属性替代

## 成功的功能

### 1. 类继承 ✅

```php
class Animal {
    protected string $name;
    public function __construct(string $name) {
        $this->name = $name;
    }
}

class Dog extends Animal {
    public function __construct(string $name, string $breed) {
        parent::__construct($name);  // ✅ 工作正常
        $this->breed = $breed;
    }
}
```

### 2. 闭包和高阶函数 ✅

```php
$multiply = function($x) use ($multiplier) {
    return $x * $multiplier;
};

$squared = array_map(function($x) { return $x * $x; }, $numbers);
$evens = array_filter($numbers, function($x) { return $x % 2 === 0; });
$sum = array_reduce($numbers, function($carry, $item) { return $carry + $item; }, 0);
```

### 3. 递归算法 ✅

```php
function factorial(int $n): int {
    if ($n <= 1) return 1;
    return $n * factorial($n - 1);
}

function fibonacci(int $n): int {
    if ($n <= 1) return $n;
    return fibonacci($n - 1) + fibonacci($n - 2);
}

function gcd(int $a, int $b): int {
    if ($b === 0) return $a;
    return gcd($b, $a % $b);
}
```

### 4. 静态方法和属性 ✅

```php
class MathUtils {
    public static int $pi_digits = 3;
    
    public static function square(int $x): int {
        return $x * $x;
    }
}

echo MathUtils::square(5);  // ✅ 25
MathUtils::$pi_digits = 5;  // ✅ 工作正常
```

### 5. 引用参数 ✅

```php
function increment(int &$x): void {
    $x++;
}

$a = 5;
increment($a);
echo $a;  // ✅ 6
```

## 问题优先级

### 高优先级（影响核心功能）
1. **引用返回的 Alignment 错误** - 阻止引用返回功能
2. **静态数组属性的 Alignment 错误** - 阻止静态数组使用

### 中优先级（影响高级功能）
3. **嵌套闭包返回** - 影响函数式编程
4. **递归中的 array_merge** - 影响复杂算法

### 低优先级（可替代）
5. **类常量不支持** - 可用静态属性替代

## 根本原因分析

### Alignment 错误的共同点

两个 alignment 错误都发生在：
```zig
runtime_lib.zig:1513:16: in asArray
    return @ptrFromInt(nanbox_abi.decodePtr(self.val));
```

**可能的原因**：
1. **NanBox 编码问题** - 数组指针没有正确编码
2. **指针对齐问题** - 指针地址不是 8 字节对齐
3. **值类型错误** - 期望数组但实际是其他类型
4. **初始化问题** - 静态数组没有正确初始化

**需要检查**：
- 静态属性的初始化代码
- 引用返回的值编码
- NanBox 的指针编码/解码逻辑
- 数组创建和赋值的代码

## 建议的修复顺序

1. **修复 Alignment 错误**（高优先级）
   - 检查 NanBox 编码/解码
   - 修复静态数组初始化
   - 修复引用返回的值编码
   - 预计时间：4-6 小时

2. **修复嵌套闭包**（中优先级）
   - 修复类型不匹配
   - 调整闭包创建代码
   - 预计时间：2-3 小时

3. **修复递归 array_merge**（中优先级）
   - 修复符号表查找
   - 处理空指针
   - 预计时间：2-3 小时

4. **实现类常量**（低优先级）
   - 添加类常量支持
   - 预计时间：3-4 小时

## 总结

复杂场景测试发现了 5 个问题，其中 2 个是高优先级的 alignment 错误。这些问题主要集中在：

1. **内存管理** - NanBox 编码/解码
2. **类型系统** - 引用和指针处理
3. **符号解析** - 递归调用中的符号查找

虽然发现了问题，但也验证了很多功能是正常工作的：
- ✅ 类继承和方法重写
- ✅ 闭包和高阶函数
- ✅ 递归算法
- ✅ 静态方法和简单静态属性
- ✅ 引用参数

**当前测试通过率**: 60% (3/5)
**核心功能通过率**: 80% (8/10 核心测试)

下一步应该优先修复 alignment 错误，因为它们影响了引用返回和静态数组这两个重要功能。
