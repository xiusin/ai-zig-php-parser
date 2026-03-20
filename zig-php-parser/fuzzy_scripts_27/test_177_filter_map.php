<?php
// Test 177: Array filter and map
$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

echo "=== Array filter ===\n";
$evens = array_filter($numbers, fn($v) => $v % 2 === 0);
echo "Evens: " . implode(',', $evens) . "\n";

echo "\n=== Array map ===\n";
$doubled = array_map(fn($v) => $v * 2, $numbers);
echo "Doubled: " . implode(',', $doubled) . "\n";