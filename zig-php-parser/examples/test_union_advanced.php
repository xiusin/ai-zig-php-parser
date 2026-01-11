<?php
/**
 * 综合联合类型测试
 */

class AdvancedUnionTest {
    // 测试基本联合类型
    public function basicUnion(int|string $value): int|string {
        return $value;
    }

    // 测试多类型联合
    public function multiUnion(int|string|float $value): int|string|float {
        return $value;
    }

    // 测试可空联合类型
    public function nullableUnion(int|string|null $value): int|string|null {
        return $value;
    }

    // 测试对象联合类型
    public function objectUnion(Dog|Cat $animal): Dog|Cat {
        return $animal;
    }

    // 测试混合类型
    public function mixedUnion(int|array|object $value): int|array|object {
        return $value;
    }
}

class Dog {}
class Cat {}

echo "=== Advanced Union Type Test ===\n\n";

$test = new AdvancedUnionTest();

// 测试基本联合类型
echo "1. Basic Union Type:\n";
$result = $test->basicUnion(42);
echo "   Input: 42, Output: $result\n";
$result = $test->basicUnion("hello");
echo "   Input: 'hello', Output: $result\n\n";

// 测试多类型联合
echo "2. Multi-Type Union:\n";
$result = $test->multiUnion(3.14);
echo "   Input: 3.14, Output: $result\n\n";

// 测试可空联合类型
echo "3. Nullable Union:\n";
$result = $test->nullableUnion(null);
echo "   Input: null, Output: " . ($result === null ? "null" : $result) . "\n\n";

// 测试对象联合类型
echo "4. Object Union:\n";
$dog = new Dog();
$cat = new Cat();
$result = $test->objectUnion($dog);
echo "   Input: Dog object, Output: " . (($result instanceof Dog) ? "Dog" : "Cat") . "\n";
$result = $test->objectUnion($cat);
echo "   Input: Cat object, Output: " . (($result instanceof Cat) ? "Cat" : "Dog") . "\n\n";

echo "=== All Union Type Tests Passed ===\n";
