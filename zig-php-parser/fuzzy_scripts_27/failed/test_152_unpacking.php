<?php
// Test 152: Unpacking arrays in function arguments
function unpacked(int $a, int $b, int $c, int $d = 0): int {
    return $a + $b + $c + $d;
}

echo "=== Unpacking arrays ===\n";
$numbers = [1, 2, 3, 4];
echo "unpacked(...[1,2,3,4]): " . unpacked(...$numbers) . "\n";

echo "\n=== Spread in array ===\n";
$first = [1, 2];
$second = [3, 4];
$combined = array_merge($first, $second);
echo "Combined: " . implode(',', $combined) . "\n";