<?php
// 随机测试脚本 #3 - 函数和作用域

echo "=== Random Test #3: Functions & Scope ===\n";

function calculate($a, $b, $callback) {
    $result = $a * $b;
    return $callback($result);
}

function createMultiplier($factor) {
    return function($x) use ($factor) {
        return $x * $factor;
    };
}

function recursiveSum($arr) {
    $sum = 0;
    foreach ($arr as $item) {
        if (is_array($item)) {
            $sum += recursiveSum($item);
        } else {
            $sum += $item;
        }
    }
    return $sum;
}

function fibonacci($n) {
    if ($n <= 1) return $n;
    return fibonacci($n - 1) + fibonacci($n - 2);
}

// 测试函数
$double = createMultiplier(2);
$triple = createMultiplier(3);

echo "calculate(5, 10, double): " . calculate(5, 10, $double) . "\n";
echo "calculate(5, 10, triple): " . calculate(5, 10, $triple) . "\n";

// 递归数组求和
$nested = [1, [2, [3, 4], 5], 6];
echo "recursiveSum([1, [2, [3, 4], 5], 6]): " . recursiveSum($nested) . "\n";

// 斐波那契 (小规模)
echo "fibonacci(10): " . fibonacci(10) . "\n";

// 可变参数函数
function sumAll(...$numbers) {
    $sum = 0;
    foreach ($numbers as $n) {
        $sum += $n;
    }
    return $sum;
}

echo "sumAll(1, 2, 3, 4, 5): " . sumAll(1, 2, 3, 4, 5) . "\n";

// 匿名函数
$funcs = [];
for ($i = 0; $i < 3; $i++) {
    $funcs[] = function() use ($i) {
        return $i * $i;
    };
}

foreach ($funcs as $f) {
    echo "closure: " . $f() . "\n";
}

// 引用参数
function increment(&$x) {
    $x++;
}

$val = 10;
increment($val);
echo "increment(10): $val\n";

// 默认参数
function greet($name = "World") {
    return "Hello, $name!";
}

echo greet() . "\n";
echo greet("PHP") . "\n";

echo "=== Test #3 Complete ===\n";
