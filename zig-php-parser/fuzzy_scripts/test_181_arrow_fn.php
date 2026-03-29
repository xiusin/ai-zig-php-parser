<?php
// Test 181: Arrow function
$nums = [1, 2, 3, 4, 5];

echo "=== Arrow functions ===\n";
$doubled = array_map(fn($x) => $x * 2, $nums);
echo "Doubled: " . implode(',', $doubled) . "\n";

$squared = array_map(fn($x) => $x ** 2, $nums);
echo "Squared: " . implode(',', $squared) . "\n";