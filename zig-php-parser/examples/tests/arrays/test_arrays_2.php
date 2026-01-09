<?php
// 数组引用测试
$array = [1, 2, 3];
$ref = &$array[0];
$ref = 100;
echo "Array after reference modification: " . implode(", ", $array) . "\n";

// 数组排序测试
$unsorted = [3, 1, 4, 1, 5, 9, 2, 6];
sort($unsorted);
echo "Sorted: " . implode(", ", $unsorted) . "\n";
?>