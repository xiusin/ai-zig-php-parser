<?php

echo "=== PHP基础功能测试 ===\n";

// 1. 变量和运算
echo "\n1. 变量和运算测试\n";
$a = 10;
$b = 20;
$sum = $a + $b;
echo "10 + 20 = " . $sum . "\n";

// 2. 字符串操作
echo "\n2. 字符串操作测试\n";
$str1 = "Hello";
$str2 = "World";
$result = $str1 . " " . $str2;
echo $result . "\n";

// 3. 条件语句
echo "\n3. 条件语句测试\n";
$x = 15;
if ($x > 10) {
    echo "x 大于 10\n";
} else {
    echo "x 小于等于 10\n";
}

// 4. 循环
echo "\n4. 循环测试\n";
$i = 1;
while ($i <= 3) {
    echo "循环 " . $i . "\n";
    $i = $i + 1;
}

// 5. 数组
echo "\n5. 数组测试\n";
$arr = [10, 20, 30];
echo "数组第一个元素: " . $arr[0] . "\n";

echo "\n=== 基础功能测试完成 ===\n";

?>
