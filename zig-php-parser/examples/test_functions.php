<?php
// Task 2.6: 函数定义和调用测试

// 测试1: 简单函数（无参数，无返回值）
function greet() {
    echo "Hello, World!\n";
}

// 测试2: 带参数的函数
function greetName($name) {
    echo "Hello, " . $name . "!\n";
}

// 测试3: 带返回值的函数
function add($a, $b) {
    return $a + $b;
}

// 测试4: 带多个参数和返回值
function multiply($x, $y) {
    $result = $x * $y;
    return $result;
}

// 测试5: 递归函数（阶乘）
function factorial($n) {
    if ($n <= 1) {
        return 1;
    }
    return $n * factorial($n - 1);
}

// 测试6: 递归函数（斐波那契）
function fibonacci($n) {
    if ($n <= 1) {
        return $n;
    }
    return fibonacci($n - 1) + fibonacci($n - 2);
}

// 执行测试
echo "=== Test 1: Simple function ===\n";
greet();

echo "\n=== Test 2: Function with parameter ===\n";
greetName("Alice");
greetName("Bob");

echo "\n=== Test 3: Function with return value ===\n";
$sum = add(10, 20);
echo "10 + 20 = " . $sum . "\n";

echo "\n=== Test 4: Function with multiple parameters ===\n";
$product = multiply(6, 7);
echo "6 * 7 = " . $product . "\n";

echo "\n=== Test 5: Recursive function (factorial) ===\n";
$fact5 = factorial(5);
echo "factorial(5) = " . $fact5 . "\n";

echo "\n=== Test 6: Recursive function (fibonacci) ===\n";
$fib10 = fibonacci(10);
echo "fibonacci(10) = " . $fib10 . "\n";

echo "\n=== All tests completed ===\n";
