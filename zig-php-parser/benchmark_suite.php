<?php
/**
 * Zig-PHP vs Native PHP 性能基准测试套件
 * 测试各种常见操作的性能差异
 */

function benchmark($name, $iterations, $callback) {
    $start = microtime(true);
    for ($i = 0; $i < $iterations; $i++) {
        $callback();
    }
    $end = microtime(true);
    $time = ($end - $start) * 1000; // 转换为毫秒
    $ops_per_sec = $iterations / ($end - $start);
    
    printf("%-40s: %8.2f ms (%10.0f ops/sec)\n", $name, $time, $ops_per_sec);
    return $time;
}

echo "=== Zig-PHP Performance Benchmark Suite ===\n";
echo "Iterations: 100,000 per test\n\n";

$iterations = 100000;

// 1. 基础算术运算
benchmark("Integer Addition", $iterations, function() {
    $a = 10;
    $b = 20;
    $c = $a + $b;
});

benchmark("Integer Multiplication", $iterations, function() {
    $a = 10;
    $b = 20;
    $c = $a * $b;
});

benchmark("Float Operations", $iterations, function() {
    $a = 3.14;
    $b = 2.71;
    $c = $a * $b + $a / $b;
});

// 2. 字符串操作
benchmark("String Concatenation", $iterations, function() {
    $str = "Hello" . " " . "World";
});

benchmark("String Length", $iterations, function() {
    $str = "Hello World";
    $len = strlen($str);
});

// 3. 数组操作
benchmark("Array Creation", $iterations, function() {
    $arr = [1, 2, 3, 4, 5];
});

benchmark("Array Push", $iterations, function() {
    static $arr = [];
    $arr[] = 42;
});

benchmark("Array Access", $iterations, function() {
    static $arr = [1, 2, 3, 4, 5];
    $val = $arr[2];
});

benchmark("Array Count", $iterations, function() {
    static $arr = [1, 2, 3, 4, 5];
    $c = count($arr);
});

// 4. 函数调用
function simple_function($a, $b) {
    return $a + $b;
}

benchmark("Function Call (2 args)", $iterations, function() {
    simple_function(10, 20);
});

function recursive_factorial($n) {
    if ($n <= 1) return 1;
    return $n * recursive_factorial($n - 1);
}

benchmark("Recursive Call (factorial 10)", $iterations / 100, function() {
    recursive_factorial(10);
});

// 5. 循环
benchmark("For Loop (100 iterations)", $iterations / 100, function() {
    $sum = 0;
    for ($i = 0; $i < 100; $i++) {
        $sum += $i;
    }
});

benchmark("While Loop (100 iterations)", $iterations / 100, function() {
    $sum = 0;
    $i = 0;
    while ($i < 100) {
        $sum += $i;
        $i++;
    }
});

// 6. 变量操作
benchmark("Variable Assignment", $iterations, function() {
    $a = 42;
});

benchmark("Variable Copy", $iterations, function() {
    $a = 42;
    $b = $a;
});

// 7. 条件判断
benchmark("If-Else", $iterations, function() {
    $a = 10;
    if ($a > 5) {
        $b = 1;
    } else {
        $b = 0;
    }
});

// 8. 类型检查
benchmark("is_int()", $iterations, function() {
    $a = 42;
    is_int($a);
});

benchmark("is_string()", $iterations, function() {
    $a = "hello";
    is_string($a);
});

// 9. 综合测试：斐波那契数列
function fibonacci($n) {
    if ($n <= 1) return $n;
    return fibonacci($n - 1) + fibonacci($n - 2);
}

benchmark("Fibonacci(15)", $iterations / 1000, function() {
    fibonacci(15);
});

// 10. 综合测试：数组求和
benchmark("Array Sum (100 elements)", $iterations / 100, function() {
    $arr = range(1, 100);
    $sum = 0;
    foreach ($arr as $val) {
        $sum += $val;
    }
});

echo "\n=== Benchmark Complete ===\n";
