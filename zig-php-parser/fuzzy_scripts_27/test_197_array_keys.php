<?php
// Test 197: Array keys/values
$arr = ['a' => 1, 'b' => 2, 'c' => 3];

echo "=== Array keys/values ===\n";
echo "keys: " . implode(',', array_keys($arr)) . "\n";
echo "values: " . implode(',', array_values($arr)) . "\n";