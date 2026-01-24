<?php
// 简单的运算符测试

echo "=== Test 1: 算术运算符 ===\n";

$a = 10;
$b = 20;
$sum = $a + $b;
echo "10 + 20 = ";
echo $sum;
echo "\n";

$diff = $a - $b;
echo "10 - 20 = ";
echo $diff;
echo "\n";

$prod = $a * $b;
echo "10 * 20 = ";
echo $prod;
echo "\n";

echo "\n=== Test 2: 比较运算符 ===\n";

$x = 5;
$y = 10;

if ($x < $y) {
    echo "5 < 10: true\n";
} else {
    echo "5 < 10: false\n";
}

if ($x == $y) {
    echo "5 == 10: true\n";
} else {
    echo "5 == 10: false\n";
}

echo "\n=== Test 3: 逻辑运算符 ===\n";

$true_val = true;
$false_val = false;

if ($true_val && $false_val) {
    echo "true && false: true\n";
} else {
    echo "true && false: false\n";
}

if ($true_val || $false_val) {
    echo "true || false: true\n";
} else {
    echo "true || false: false\n";
}

echo "\n=== All tests completed ===\n";
