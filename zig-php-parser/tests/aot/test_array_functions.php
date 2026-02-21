<?php
// 测试：数组内置函数
$arr = [5, 2, 8, 1, 9, 3, 7, 4, 6];

echo "Original: ";
$i = 0;
while ($i < count($arr)) {
    echo $arr[$i] . " ";
    $i++;
}
echo "\n";

// array_push
array_push($arr, 10);
echo "After push(10): count=" . count($arr) . "\n";

// array_pop
$last = array_pop($arr);
echo "Popped: $last, count=" . count($arr) . "\n";

// array_shift
$first = array_shift($arr);
echo "Shifted: $first, count=" . count($arr) . "\n";

// array_unshift
array_unshift($arr, 0);
echo "After unshift(0): count=" . count($arr) . "\n";

// in_array
$search = 5;
$found = in_array($search, $arr);
echo "in_array($search): " . ($found ? "true" : "false") . "\n";

// array_sum
$sum = array_sum($arr);
echo "Sum: $sum\n";

// min/max
echo "Min: " . min($arr) . "\n";
echo "Max: " . max($arr) . "\n";
