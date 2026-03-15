<?php
// 测试49: PHP 7.4箭头函数
$nums = [1, 2, 3, 4, 5];

// 基本箭头函数
$squared = array_map(fn($x) => $x * $x, $nums);
echo "Squared: " . implode(", ", $squared) . "
";

// 捕获外部变量
$factor = 3;
$multiplied = array_map(fn($x) => $x * $factor, $nums);
echo "Multiplied by $factor: " . implode(", ", $multiplied) . "
";

// 引用捕获
$sum = 0;
array_walk($nums, fn($x) => $sum += $x);
echo "Sum: $sum
";

// 多参数
$pairs = array_map(fn($x, $y) => "($x,$y)", $nums, array_reverse($nums));
echo "Pairs: " . implode(", ", $pairs) . "
";

// 复杂表达式
$complex = array_map(fn($x) => ($x % 2 === 0 ? $x * 2 : $x * 3), $nums);
echo "Complex: " . implode(", ", $complex) . "
";

// 数组过滤
$even = array_filter($nums, fn($x) => $x % 2 === 0);
echo "Even: " . implode(", ", $even) . "
";

// 数组归约
$product = array_reduce($nums, fn($acc, $x) => $acc * $x, 1);
echo "Product: $product
";

// 嵌套箭头函数
$outer = 10;
$fn = fn($x) => fn($y) => $x * $y * $outer;
$inner = $fn(2);
echo "Nested result: " . $inner(3) . "
";

// 与闭包对比
$multiplier = 5;
$closure = function($x) use ($multiplier) { return $x * $multiplier; };
$arrow = fn($x) => $x * $multiplier;
echo "Closure: " . $closure(10) . ", Arrow: " . $arrow(10) . "
";
?>