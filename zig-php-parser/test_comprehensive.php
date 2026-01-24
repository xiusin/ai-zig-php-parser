<?php
// 综合测试：混合使用各种功能

// 1. 变量和算术
$x = 10;
$y = 20;
$sum = $x + $y;

// 2. 条件判断
if ($sum > 25) {
    echo 1;
} else {
    echo 0;
}

// 3. 循环
$i = 0;
while ($i < 3) {
    echo $i;
    $i = $i + 1;
}

// 4. 数组
$arr = array();
$arr[0] = 100;
$arr[1] = 200;
echo $arr[0];
echo $arr[1];
