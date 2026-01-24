<?php
// 数组求和
$arr = array();
$arr[0] = 10;
$arr[1] = 20;
$arr[2] = 30;
$arr[3] = 40;

$sum = 0;
$i = 0;

while ($i < 4) {
    $sum = $sum + $arr[$i];
    $i = $i + 1;
}

echo $sum;
