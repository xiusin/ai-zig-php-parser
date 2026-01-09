<?php
$numbers = [5, 2, 8, 1, 9, 3, 7, 4, 6];
$words = ["apple", "banana", "cherry", "date", "elderberry"];

echo "Numbers: " . implode(", ", $numbers) . "\n";
sort($numbers);
echo "Sorted: " . implode(", ", $numbers) . "\n";

echo "Words: " . implode(", ", $words) . "\n";
sort($words);
echo "Sorted: " . implode(", ", $words) . "\n";

// Associative array
$prices = ["apple" => 1.50, "banana" => 0.75, "cherry" => 2.00];
asort($prices);
echo "Prices (asort): ";
print_r($prices);

ksort($prices);
echo "Prices (ksort): ";
print_r($prices);
