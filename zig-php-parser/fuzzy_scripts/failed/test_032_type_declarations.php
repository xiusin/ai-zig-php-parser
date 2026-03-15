<?php
// 测试32: 类型声明严格模式
// 标量类型
function acceptInt(int $x): int {
    return $x * 2;
}

function acceptFloat(float $x): float {
    return $x + 1.5;
}

function acceptString(string $x): string {
    return strtoupper($x);
}

function acceptBool(bool $x): bool {
    return !$x;
}

echo acceptInt(10) . "\n";
echo acceptFloat(3.14) . "\n";
echo acceptString("hello") . "\n";
echo (acceptBool(true) ? "true" : "false") . "\n";

// 可空类型
function nullable(?string $x): string {
    return $x ?? "null was passed";
}

echo nullable("value") . "\n";
echo nullable(null) . "\n";

// 联合类型 (PHP 8+)
function unionType(int|float $x): int|float {
    return $x * 2;
}

echo unionType(10) . "\n";
echo unionType(3.5) . "\n";

// 数组类型
function arrayType(array $arr): int {
    return count($arr);
}

echo arrayType([1, 2, 3]) . "\n";

// 可调用类型
function callType(callable $fn, $arg) {
    return $fn($arg);
}

echo callType('strlen', 'hello') . "\n";

// 对象类型
class MyClass {}
function objectType(object $obj): string {
    return get_class($obj);
}

echo objectType(new MyClass()) . "\n";
echo objectType(new stdClass()) . "\n";

// 返回类型void
function returnsVoid(): void {
    echo "No return\n";
}

returnsVoid();

// 返回类型static
class Base {
    public static function create(): static {
        return new static();
    }
}

class Derived extends Base {}

$base = Base::create();
$derived = Derived::create();
echo "Base type: " . get_class($base) . "\n";
echo "Derived type: " . get_class($derived) . "\n";

// 复杂参数类型
function complexTypes(
    string $name,
    int $age = 0,
    ?array $tags = null,
    callable $callback = null
): array {
    return [
        'name' => $name,
        'age' => $age,
        'tags' => $tags ?? [],
        'has_callback' => $callback !== null
    ];
}

$result = complexTypes("Test", 25, ['a', 'b'], 'strlen');
print_r($result);
?>