<?php
// Test 196: Array slice
$arr = [1, 2, 3, 4, 5];

echo "=== Array slice ===\n";
echo "slice[0:2]: " . implode(',', array_slice($arr, 0, 2)) . "\n";
echo "slice[2:3]: " . implode(',', array_slice($arr, 2, 3)) . "\n";
echo "slice[-2:]: " . implode(',', array_slice($arr, -2)) . "\n";