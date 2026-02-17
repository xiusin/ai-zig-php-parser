<?php
// 嵌套循环验证（函数封装版本）

function test_3layer() {
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        for ($j = 0; $j < 3; $j++) {
            for ($k = 0; $k < 3; $k++) {
                $sum += $i + $j + $k;
            }
        }
    }
    return $sum;
}

function test_2layer_mul() {
    $sum = 0;
    for ($i = 0; $i < 10; $i++) {
        for ($j = 0; $j < 10; $j++) {
            $sum += $i * $j;
        }
    }
    return $sum;
}

function test_3layer_mul() {
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

$r1 = test_3layer();
$r2 = test_2layer_mul();
$r3 = test_3layer_mul();

echo "T1: ";
if ($r1 == 81) { echo "PASS\n"; } else { echo "FAIL\n"; }
echo "T2: ";
if ($r2 == 2025) { echo "PASS\n"; } else { echo "FAIL\n"; }
echo "T3: ";
if ($r3 == 1000) { echo "PASS\n"; } else { echo "FAIL\n"; }
