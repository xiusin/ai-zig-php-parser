<?php
// 核心嵌套循环压力测试（纯整数操作）

// 测试1：3层嵌套 for
$sum = 0;
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        for ($k = 0; $k < 3; $k++) {
            $sum += $i + $j + $k;
        }
    }
}
if ($sum == 81) {
    echo "T1: PASS\n";
} else {
    echo "T1: FAIL ($sum != 81)\n";
}

// 测试2：2层嵌套乘法
$prod_sum = 0;
for ($i = 0; $i < 10; $i++) {
    for ($j = 0; $j < 10; $j++) {
        $prod_sum += $i * $j;
    }
}
if ($prod_sum == 2025) {
    echo "T2: PASS\n";
} else {
    echo "T2: FAIL ($prod_sum != 2025)\n";
}

// 测试3：3层嵌套乘法
$triple = 0;
for ($i = 0; $i < 5; $i++) {
    for ($j = 0; $j < 5; $j++) {
        for ($k = 0; $k < 5; $k++) {
            $triple += $i * $j * $k;
        }
    }
}
if ($triple == 1000) {
    echo "T3: PASS\n";
} else {
    echo "T3: FAIL ($triple != 1000)\n";
}
