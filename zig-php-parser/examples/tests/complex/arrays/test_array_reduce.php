<?php
$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

$sum = array_reduce($numbers, function($carry, $item) {
    return $carry + $item;
}, 0);

$product = array_reduce($numbers, function($carry, $item) {
    return $carry * $item;
}, 1);

$concat = array_reduce($numbers, function($carry, $item) {
    return $carry . $item;
}, "");

echo "Sum: $sum\n";
echo "Product: $product\n";
echo "Concat: $concat\n";
