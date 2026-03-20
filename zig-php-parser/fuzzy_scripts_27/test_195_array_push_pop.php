<?php
// Test 195: Array push/pop
$arr = [1, 2, 3];

echo "=== Array push/pop ===\n";
array_push($arr, 4, 5);
echo "After push: " . implode(',', $arr) . "\n";

$popped = array_pop($arr);
echo "Popped: $popped\n";

array_unshift($arr, 0);
echo "After unshift: " . implode(',', $arr) . "\n";

$shifted = array_shift($arr);
echo "Shifted: $shifted\n";