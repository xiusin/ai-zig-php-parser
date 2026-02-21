<?php
// 测试: 数组函数组合
$arr = [3, 1, 4, 1, 5, 9, 2, 6];
$count = count($arr);
$sum = array_sum($arr);
$max = max($arr);
$min = min($arr);

echo "ArrFunc: $count,$sum,$max,$min (expect 8,31,9,1)\n";
