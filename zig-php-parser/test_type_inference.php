<?php
// 测试套件：类型推断和代码生成

// 测试 1：简单整数循环
function test_simple_loop() {
    $sum = 0;
    for ($i = 0; $i < 1000; $i++) {
        $sum += $i;
    }
    return $sum;
}

// 测试 2：嵌套循环
function test_nested_loop() {
    $sum = 0;
    for ($i = 0; $i < 10; $i++) {
        for ($j = 0; $j < 10; $j++) {
            $sum += $i * $j;
        }
    }
    return $sum;
}

// 测试 3：条件分支
function test_conditional($n) {
    $sum = 0;
    for ($i = 0; $i < $n; $i++) {
        if ($i % 2 == 0) {
            $sum += $i;
        } else {
            $sum -= $i;
        }
    }
    return $sum;
}

// 测试 4：数组操作
function test_array() {
    $arr = [];
    for ($i = 0; $i < 100; $i++) {
        $arr[] = $i * 2;
    }
    $sum = 0;
    foreach ($arr as $val) {
        $sum += $val;
    }
    return $sum;
}

// 测试 5：字符串拼接
function test_string_concat() {
    $str = "";
    for ($i = 0; $i < 100; $i++) {
        $str .= "x";
    }
    return strlen($str);
}

// 测试 6：混合类型
function test_mixed_types($n) {
    $result = 0;
    for ($i = 0; $i < $n; $i++) {
        if ($i % 3 == 0) {
            $result += $i;  // 整数
        } else if ($i % 3 == 1) {
            $result += 1.5;  // 浮点数
        } else {
            $result += 1;  // 整数
        }
    }
    return $result;
}

// 测试 7：函数调用
function helper($x) {
    return $x * 2;
}

function test_function_call() {
    $sum = 0;
    for ($i = 0; $i < 100; $i++) {
        $sum += helper($i);
    }
    return $sum;
}

// 测试 8：递归
function factorial($n) {
    if ($n <= 1) {
        return 1;
    }
    return $n * factorial($n - 1);
}

// 运行所有测试
echo "=== Type Inference Test Suite ===\n\n";

$start = microtime(true);
$r1 = test_simple_loop();
$t1 = (microtime(true) - $start) * 1000;
echo "Test 1 (Simple Loop): $r1 in {$t1}ms\n";

$start = microtime(true);
$r2 = test_nested_loop();
$t2 = (microtime(true) - $start) * 1000;
echo "Test 2 (Nested Loop): $r2 in {$t2}ms\n";

$start = microtime(true);
$r3 = test_conditional(1000);
$t3 = (microtime(true) - $start) * 1000;
echo "Test 3 (Conditional): $r3 in {$t3}ms\n";

$start = microtime(true);
$r4 = test_array();
$t4 = (microtime(true) - $start) * 1000;
echo "Test 4 (Array): $r4 in {$t4}ms\n";

$start = microtime(true);
$r5 = test_string_concat();
$t5 = (microtime(true) - $start) * 1000;
echo "Test 5 (String): $r5 in {$t5}ms\n";

$start = microtime(true);
$r6 = test_mixed_types(1000);
$t6 = (microtime(true) - $start) * 1000;
echo "Test 6 (Mixed Types): $r6 in {$t6}ms\n";

$start = microtime(true);
$r7 = test_function_call();
$t7 = (microtime(true) - $start) * 1000;
echo "Test 7 (Function Call): $r7 in {$t7}ms\n";

$start = microtime(true);
$r8 = factorial(10);
$t8 = (microtime(true) - $start) * 1000;
echo "Test 8 (Recursion): $r8 in {$t8}ms\n";

$total = $t1 + $t2 + $t3 + $t4 + $t5 + $t6 + $t7 + $t8;
echo "\nTotal Time: {$total}ms\n";
