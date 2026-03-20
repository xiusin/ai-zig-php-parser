<?php
// Test 178: Array reduce
$numbers = [1, 2, 3, 4, 5];

echo "=== Array reduce ===\n";
$sum = array_reduce($numbers, fn($c, $v) => $c + $v, 0);
echo "Sum: $sum\n";

$product = array_reduce($numbers, fn($c, $v) => $c * $v, 1);
echo "Product: $product\n";