<?php
// Test 110: First-class callable syntax
class FirstClassCallable {
    public function add(int $a, int $b): int {
        return $a + $b;
    }

    public function multiply(int $a, int $b): int {
        return $a * $b;
    }
}

echo "=== First-class callable ===\n";
$obj = new FirstClassCallable();
$add = $obj->add(...);
$multiply = $obj->multiply(...);

echo "add(5, 3): " . $add(5, 3) . "\n";
echo "multiply(5, 3): " . $multiply(5, 3) . "\n";

echo "\n=== Static first-class callable ===\n";
class StaticCallable {
    public static function subtract(int $a, int $b): int {
        return $a - $b;
    }
}

$subtract = StaticCallable::subtract(...);
echo "subtract(10, 3): " . $subtract(10, 3) . "\n";

echo "\n=== Callable in array ===\n";
$callbacks = [
    'add' => $obj->add(...),
    'multiply' => $obj->multiply(...),
];

echo "callbacks['add'](100, 200): " . $callbacks['add'](100, 200) . "\n";
echo "callbacks['multiply'](100, 200): " . $callbacks['multiply'](100, 200) . "\n";

echo "\n=== Arrow with callable ===\n";
$numbers = [1, 2, 3, 4, 5];
$doubled = array_map(fn($x) => $x * 2, $numbers);
echo "Doubled: " . implode(',', $doubled) . "\n";