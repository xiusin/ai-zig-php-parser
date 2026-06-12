<?php
// 类型系统边界测试

// 混合类型参数
function mixedTest(mixed $value): string {
    return match(true) {
        is_int($value) => "int: $value",
        is_float($value) => "float: $value",
        is_string($value) => "string: $value",
        is_bool($value) => "bool: " . ($value ? 'true' : 'false'),
        is_array($value) => "array: " . count($value) . " items",
        is_object($value) => "object: " . get_class($value),
        is_null($value) => "null",
        is_resource($value) => "resource",
        default => "unknown"
    };
}

echo mixedTest(42) . "\n";
echo mixedTest(3.14) . "\n";
echo mixedTest("hello") . "\n";
echo mixedTest(true) . "\n";
echo mixedTest([1, 2, 3]) . "\n";
echo mixedTest(new stdClass()) . "\n";
echo mixedTest(null) . "\n";

// 可空类型
function nullableTest(?int $value): ?string {
    if ($value === null) return null;
    return "Value is $value";
}

echo "Nullable int: " . var_export(nullableTest(10), true) . "\n";
echo "Nullable null: " . var_export(nullableTest(null), true) . "\n";

// 严格类型
declare(strict_types=1);
function strictInt(int $val): int {
    return $val;
}

echo "Strict int: " . strictInt(42) . "\n";
// strictInt("42"); // 严格模式下会报错

// 类型转换函数
function coerceFloat(float $f): string {
    return "Float: $f";
}

echo "Coerce float: " . coerceFloat(10) . "\n";
echo "Coerce string: " . coerceFloat("3.14") . "\n";

// 返回类型声明
function returnsInt(): int {
    return 42;
}

function returnsString(): string {
    return "hello";
}

function returnsArray(): array {
    return [1, 2, 3];
}

function returnsVoid(): void {
    echo "void return\n";
}

function returnsNull(): ?string {
    return null;
}

echo "Int: " . returnsInt() . "\n";
echo "String: " . returnsString() . "\n";
echo "Array: " . count(returnsArray()) . "\n";
returnsVoid();
echo "Null return: " . var_export(returnsNull(), true) . "\n";

// never类型
function throwException(): never {
    throw new Exception('Never returns');
}

function infiniteLoop(): never {
    while (true) {}
}

// 测试never类型
try {
    throwException();
} catch (Exception $e) {
    echo "Caught never: " . $e->getMessage() . "\n";
}

// 可变参数类型
function typedVariadic(int ...$nums): int {
    return array_sum($nums);
}

echo "Variadic sum: " . typedVariadic(1, 2, 3, 4, 5) . "\n";

// 引用参数类型
function modifyRef(string &$str): void {
    $str = strtoupper($str);
}

$refStr = "hello";
modifyRef($refStr);
echo "Modified ref: $refStr\n";

// 可调用类型
function executeCallable(callable $callback, mixed ...$args): mixed {
    return $callback(...$args);
}

echo "Callable result: " . executeCallable('strlen', 'hello') . "\n";

// 对象类型
function objectParam(object $obj): string {
    return get_class($obj);
}

echo "Object class: " . objectParam(new ArrayObject()) . "\n";

// self和parent类型
class ParentClass {
    public function getSelf(): self {
        return $this;
    }
}

class ChildClass extends ParentClass {
    public function getParent(): parent {
        return new ParentClass();
    }
}

$child = new ChildClass();
echo "Self type: " . get_class($child->getSelf()) . "\n";
echo "Parent type: " . get_class($child->getParent()) . "\n";

echo "Type system tests completed\n";
