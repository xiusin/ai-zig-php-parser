<?php
// 数组函数测试
$numbers = [1, 2, 3, 4, 5];

// array_map
$doubled = array_map(function($x) { return $x * 2; }, $numbers);
echo "Doubled: " . implode(", ", $doubled) . "\n";

// array_filter
$evens = array_filter($numbers, function($x) { return $x % 2 === 0; });
echo "Even numbers: " . implode(", ", $evens) . "\n";

// array_reduce
$sum = array_reduce($numbers, function($carry, $item) { return $carry + $item; }, 0);
echo "Sum: $sum\n";

// array_push/array_pop
array_push($numbers, 6, 7);
echo "After push: " . implode(", ", $numbers) . "\n";

$last = array_pop($numbers);
echo "Popped: $last, Remaining: " . implode(", ", $numbers) . "\n";
?>