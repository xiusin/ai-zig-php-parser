<?php
// Test 1: 三层嵌套
$sum1 = 0;
for ($i = 0; $i < 5; $i++) {
    for ($j = 0; $j < 5; $j++) {
        for ($k = 0; $k < 5; $k++) {
            $sum1 += $i * $j * $k;
        }
    }
}

// Test 2: 多个累加器
$sum2 = 0;
$product = 1;
for ($i = 1; $i < 4; $i++) {
    for ($j = 1; $j < 4; $j++) {
        $sum2 += $i + $j;
        $product *= $i;
    }
}

// Test 3: 嵌套循环带条件
$sum3 = 0;
for ($i = 0; $i < 10; $i++) {
    for ($j = 0; $j < 10; $j++) {
        if ($i > $j) {
            $sum3 += $i - $j;
        }
    }
}

// Test 4: 不同步长
$sum4 = 0;
for ($i = 0; $i < 10; $i += 2) {
    for ($j = 0; $j < 10; $j += 3) {
        $sum4 += $i * $j;
    }
}

// Test 5: 嵌套循环带多个操作
$sum5 = 0;
$count = 0;
for ($i = 0; $i < 5; $i++) {
    for ($j = 0; $j < 5; $j++) {
        $sum5 += $i * $j;
        $count += 1;
    }
}

$total = $sum1 + $sum2 + $sum3 + $sum4 + $sum5 + $product + $count;

echo "Test 1 (3-level): $sum1\n";
echo "Test 2 (multi-acc): sum=$sum2, product=$product\n";
echo "Test 3 (condition): $sum3\n";
echo "Test 4 (step): $sum4\n";
echo "Test 5 (multi-op): sum=$sum5, count=$count\n";
echo "Total: $total\n";

if ($sum1 == 1000 && $sum2 == 36 && $sum3 == 165 && $sum4 == 360 && $sum5 == 100 && $count == 25 && $product == 216) {
    echo "PASS\n";
} else {
    echo "FAIL: sum1=$sum1(exp 1000), sum2=$sum2(exp 36), sum3=$sum3(exp 165), sum4=$sum4(exp 360), sum5=$sum5(exp 100), count=$count(exp 25), product=$product(exp 216)\n";
}
