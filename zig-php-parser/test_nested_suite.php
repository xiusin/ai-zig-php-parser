<?php
// Test 1: 三层嵌套
function test_3level() {
    $sum = 0;
    for ($i = 0; $i < 5; $i++) {
        for ($j = 0; $j < 5; $j++) {
            for ($k = 0; $k < 5; $k++) {
                $sum += $i * $j * $k;
            }
        }
    }
    return $sum;
}

// Test 2: 多个累加器
function test_multi_accumulator() {
    $sum = 0;
    $product = 1;
    for ($i = 1; $i < 4; $i++) {
        for ($j = 1; $j < 4; $j++) {
            $sum += $i + $j;
            $product *= $i;
        }
    }
    return $sum * 1000 + $product;  // 编码为单个值
}

// Test 3: 嵌套循环带条件
function test_with_condition() {
    $sum = 0;
    for ($i = 0; $i < 10; $i++) {
        for ($j = 0; $j < 10; $j++) {
            if ($i > $j) {
                $sum += $i - $j;
            }
        }
    }
    return $sum;
}

// Test 4: 不同步长
function test_different_step() {
    $sum = 0;
    for ($i = 0; $i < 10; $i += 2) {
        for ($j = 0; $j < 10; $j += 3) {
            $sum += $i * $j;
        }
    }
    return $sum;
}

// Test 5: 嵌套循环带多个操作
function test_multi_operations() {
    $sum = 0;
    $count = 0;
    for ($i = 0; $i < 5; $i++) {
        for ($j = 0; $j < 5; $j++) {
            $sum += $i * $j;
            $count += 1;
        }
    }
    return $sum * 100 + $count;  // 编码为单个值
}

$r1 = test_3level();
$r2 = test_multi_accumulator();
$r3 = test_with_condition();
$r4 = test_different_step();
$r5 = test_multi_operations();

$pass = 0;
if ($r1 == 1000) $pass += 1;
if ($r2 == 36216) $pass += 1;  // 36*1000 + 216
if ($r3 == 165) $pass += 1;
if ($r4 == 360) $pass += 1;
if ($r5 == 10025) $pass += 1;  // 100*100 + 25

return $pass;
