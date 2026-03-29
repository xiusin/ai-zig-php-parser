<?php
// Test 117: array_find, array_find_key (PHP 8)
$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

echo "=== array_find ===\n";
if (function_exists('array_find')) {
    $first_even = array_find($numbers, fn($v) => $v % 2 === 0);
    echo "First even: " . ($first_even ?? 'not found') . "\n";

    $first_above_5 = array_find($numbers, fn($v) => $v > 5);
    echo "First above 5: " . ($first_above_5 ?? 'not found') . "\n";

    $not_found = array_find($numbers, fn($v) => $v > 100);
    echo "Not found result: " . ($not_found ?? 'null') . "\n";
} else {
    echo "array_find not available\n";
}

echo "\n=== Custom find ===\n";
$firstEven = null;
foreach ($numbers as $v) {
    if ($v % 2 === 0) {
        $firstEven = $v;
        break;
    }
}
echo "Custom first even: $firstEven\n";