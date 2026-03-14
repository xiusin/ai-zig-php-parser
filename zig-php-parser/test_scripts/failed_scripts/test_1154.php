<?php
// 综合运算测试 10
$nums = [1, 2, 3, 4, 5];
$doubled = array_map(fn($x) => $x * 2, $nums);
$filtered = array_filter($doubled, fn($x) => $x > 4);
$sum = array_sum($filtered);
$str = implode("-", $filtered);
echo $str . ":" . $sum;
echo "
";
?>