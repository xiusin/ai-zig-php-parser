<?php
// 测试各种边界情况

// 情况1：空函数（单块，应该优化）
function empty_func() {
    // 什么都不做
}

// 情况2：只有一条语句的函数（单块，应该优化）
function single_statement($x) {
    return $x;
}

// 情况3：多条语句但无分支（单块，应该优化）
function linear_computation($a, $b, $c) {
    $sum = $a + $b;
    $result = $sum + $c;
    return $result;
}

// 情况4：有循环的函数（多块，应该使用状态机）
function sum_to_n($n) {
    $sum = 0;
    $i = 1;
    while ($i <= $n) {
        $sum = $sum + $i;
        $i = $i + 1;
    }
    return $sum;
}

// 测试所有函数
echo "Testing empty_func: ";
empty_func();
echo "OK\n";

echo "Testing single_statement: ";
$r1 = single_statement(42);
echo $r1;
echo "\n";

echo "Testing linear_computation: ";
$r2 = linear_computation(10, 20, 30);
echo $r2;
echo "\n";

echo "Testing sum_to_n: ";
$r3 = sum_to_n(10);
echo $r3;
echo "\n";
