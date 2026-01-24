<?php
// AOT编译器性能基准测试

// 测试1: 简单循环
$sum = 0;
$i = 0;
while ($i < 1000) {
    $sum = $sum + $i;
    $i = $i + 1;
}
echo $sum;
echo "\n";

// 测试2: 数组操作
$arr = array();
$j = 0;
while ($j < 100) {
    $arr[$j] = $j * 2;
    $j = $j + 1;
}

$total = 0;
$k = 0;
while ($k < 100) {
    $total = $total + $arr[$k];
    $k = $k + 1;
}
echo $total;
echo "\n";

// 测试3: 嵌套循环
$result = 0;
$m = 0;
while ($m < 10) {
    $n = 0;
    while ($n < 10) {
        $result = $result + 1;
        $n = $n + 1;
    }
    $m = $m + 1;
}
echo $result;
