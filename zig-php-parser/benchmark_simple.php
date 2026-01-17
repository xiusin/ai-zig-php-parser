<?php
/**
 * 简化版性能测试 - 只测试已支持的功能
 */

$iterations = 100000;

// 1. 整数加法
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $a = 10;
    $b = 20;
    $c = $a + $b;
}
$time1 = (microtime(true) - $start) * 1000;
echo "Integer Addition: " . $time1 . " ms\n";

// 2. 整数乘法
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $a = 10;
    $b = 20;
    $c = $a * $b;
}
$time2 = (microtime(true) - $start) * 1000;
echo "Integer Multiplication: " . $time2 . " ms\n";

// 3. 字符串连接
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $str = "Hello" . " " . "World";
}
$time3 = (microtime(true) - $start) * 1000;
echo "String Concatenation: " . $time3 . " ms\n";

// 4. 字符串长度
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $str = "Hello World";
    $len = strlen($str);
}
$time4 = (microtime(true) - $start) * 1000;
echo "String Length: " . $time4 . " ms\n";

// 5. 数组创建
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $arr = [1, 2, 3, 4, 5];
}
$time5 = (microtime(true) - $start) * 1000;
echo "Array Creation: " . $time5 . " ms\n";

// 6. 数组访问
$arr = [1, 2, 3, 4, 5];
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $val = $arr[2];
}
$time6 = (microtime(true) - $start) * 1000;
echo "Array Access: " . $time6 . " ms\n";

// 7. 函数调用
function add($a, $b) {
    return $a + $b;
}

$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    add(10, 20);
}
$time7 = (microtime(true) - $start) * 1000;
echo "Function Call: " . $time7 . " ms\n";

// 8. 循环求和
$start = microtime(true);
for ($i = 0; $i < 1000; $i++) {
    $sum = 0;
    for ($j = 0; $j < 100; $j++) {
        $sum = $sum + $j;
    }
}
$time8 = (microtime(true) - $start) * 1000;
echo "Loop Sum (100x1000): " . $time8 . " ms\n";

// 9. 递归斐波那契
function fib($n) {
    if ($n <= 1) {
        return $n;
    }
    return fib($n - 1) + fib($n - 2);
}

$start = microtime(true);
for ($i = 0; $i < 100; $i++) {
    fib(15);
}
$time9 = (microtime(true) - $start) * 1000;
echo "Fibonacci(15) x100: " . $time9 . " ms\n";

// 10. 条件判断
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $a = 10;
    if ($a > 5) {
        $b = 1;
    } else {
        $b = 0;
    }
}
$time10 = (microtime(true) - $start) * 1000;
echo "If-Else: " . $time10 . " ms\n";

echo "\n=== Total Time: " . ($time1 + $time2 + $time3 + $time4 + $time5 + $time6 + $time7 + $time8 + $time9 + $time10) . " ms ===\n";
