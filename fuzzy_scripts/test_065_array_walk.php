<?php
// array_walk和回调测试

// array_walk基础
$arr = ['a' => 1, 'b' => 2, 'c' => 3];
echo "Before walk: " . implode(', ', $arr) . "\n";

array_walk($arr, function(&$value, $key) {
    $value = $value * 2;
});
echo "After walk: " . implode(', ', $arr) . "\n";

// array_walk带用户数据
$multiplier = 10;
array_walk($arr, function(&$value, $key, $factor) {
    $value = $value * $factor;
}, $multiplier);
echo "After walk with data: " . implode(', ', $arr) . "\n";

// array_walk_recursive
$nested = [
    'a' => 1,
    'b' => ['c' => 2, 'd' => 3],
    'e' => ['f' => ['g' => 4]]
];

$flattened = [];
array_walk_recursive($nested, function($value, $key) use (&$flattened) {
    $flattened[] = $value;
});
echo "Flattened: " . implode(', ', $flattened) . "\n";

// array_map vs array_walk
$numbers = [1, 2, 3, 4, 5];

$mapped = array_map(fn($x) => $x * $x, $numbers);
echo "array_map: " . implode(', ', $mapped) . "\n";

$walked = $numbers;
array_walk($walked, function(&$x) { $x = $x * $x; });
echo "array_walk: " . implode(', ', $walked) . "\n";

// array_filter结合
$filtered = array_filter($numbers, fn($x) => $x > 2);
echo "Filtered: " . implode(', ', $filtered) . "\n";

// array_reduce
$sum = array_reduce($numbers, fn($carry, $item) => $carry + $item, 0);
echo "Reduced sum: $sum\n";

$product = array_reduce($numbers, fn($carry, $item) => $carry * $item, 1);
echo "Reduced product: $product\n";

// 复杂回调
$users = [
    ['name' => 'Alice', 'age' => 25],
    ['name' => 'Bob', 'age' => 30],
    ['name' => 'Charlie', 'age' => 35]
];

$names = array_map(fn($u) => $u['name'], $users);
echo "Names: " . implode(', ', $names) . "\n";

$totalAge = array_reduce($users, fn($carry, $u) => $carry + $u['age'], 0);
echo "Total age: $totalAge\n";

// array_map多数组
$a = [1, 2, 3];
$b = [4, 5, 6];
$c = [7, 8, 9];
$sums = array_map(fn($x, $y, $z) => $x + $y + $z, $a, $b, $c);
echo "Multi-array sums: " . implode(', ', $sums) . "\n";

// array_map带null（转置矩阵）
$matrix = [
    [1, 2, 3],
    [4, 5, 6]
];
$transposed = array_map(null, ...$matrix);
echo "Transposed rows: " . count($transposed) . "\n";

// usort回调
$products = [
    ['name' => 'Widget', 'price' => 19.99],
    ['name' => 'Gadget', 'price' => 29.99],
    ['name' => 'Thing', 'price' => 9.99]
];

usort($products, fn($a, $b) => $a['price'] <=> $b['price']);
echo "Sorted by price: " . implode(', ', array_column($products, 'name')) . "\n";

echo "array_walk tests completed\n";
