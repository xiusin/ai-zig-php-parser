<?php
// 闭包测试
$multiplier = function($factor) {
    return function($number) use ($factor) {
        return $number * $factor;
    };
};

$double = $multiplier(2);
echo "Double of 5: " . $double(5) . "\n";

// 箭头函数测试
$numbers = [1, 2, 3, 4, 5];
$squared = array_map(fn($x) => $x * $x, $numbers);
echo "Squared: " . implode(", ", $squared) . "\n";
?>