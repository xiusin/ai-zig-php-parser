<?php
$fruits = ["apple" => 1.50, "banana" => 0.75, "cherry" => 2.00];

echo "Original:\n";
array_walk($fruits, function($price, $name) {
    echo "$name: \$$price\n";
});

// With reference
array_walk($fruits, function(&$price, $name) {
    $price = round($price * 1.1, 2); // 10% tax
});

echo "After tax:\n";
array_walk($fruits, function($price, $name) {
    echo "$name: \$$price\n";
});
