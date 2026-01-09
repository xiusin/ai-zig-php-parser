<?php
$numbers = array(1, 2, 3, 4, 5, 6, 7, 8, 9, 10);

// 过滤偶数
$even = array_filter($numbers, function($x) { return $x % 2 == 0; });
echo "Even numbers: " . implode(", ", $even) . "\n";

// 平方
$squared = array_map(function($x) { return $x * $x; }, $numbers);
echo "Squared: " . implode(", ", $squared) . "\n";

// 求和
$sum = array_reduce($numbers, function($carry, $item) { return $carry + $item; }, 0);
echo "Sum: " . $sum . "\n";

// 创建加法器
function createAdder($base) {
    return function($x) use ($base) { return $base + $x; };
}

$add5 = createAdder(5);
$add10 = createAdder(10);

echo "5 + 3 = " . $add5(3) . "\n";
echo "10 + 7 = " . $add10(7) . "\n";
echo "5 + 100 = " . $add5(100) . "\n";
?>