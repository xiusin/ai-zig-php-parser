<?php
// 简化测试套件：只测试核心功能

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

// 测试 4：混合运算
function test_mixed_ops() {
    $a = 10;
    $b = 20;
    $c = $a + $b;
    $d = $c * 2;
    $e = $d - $a;
    $f = $e / 5;
    return $f;
}

// 测试 5：比较操作
function test_comparisons() {
    $count = 0;
    for ($i = 0; $i < 100; $i++) {
        if ($i < 50) {
            $count++;
        }
        if ($i > 25) {
            $count++;
        }
        if ($i == 42) {
            $count += 10;
        }
    }
    return $count;
}

// 运行所有测试
echo "=== Type Inference Test Suite ===\n\n";

$r1 = test_simple_loop();
echo "Test 1 (Simple Loop): $r1\n";
if ($r1 != 499500) echo "  ERROR: Expected 499500\n";

$r2 = test_nested_loop();
echo "Test 2 (Nested Loop): $r2\n";
if ($r2 != 2025) echo "  ERROR: Expected 2025\n";

$r3 = test_conditional(1000);
echo "Test 3 (Conditional): $r3\n";
if ($r3 != -500) echo "  ERROR: Expected -500\n";

$r4 = test_mixed_ops();
echo "Test 4 (Mixed Ops): $r4\n";
if ($r4 != 10) echo "  ERROR: Expected 10\n";

$r5 = test_comparisons();
echo "Test 5 (Comparisons): $r5\n";
if ($r5 != 134) echo "  ERROR: Expected 134\n";

echo "\nAll tests completed!\n";
