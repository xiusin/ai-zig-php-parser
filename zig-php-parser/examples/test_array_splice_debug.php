<?php

$arr = [1, 2, 3, 4, 5];
echo "Initial: " . json_encode($arr) . "\n";

// Remove element at index 2 (value 3)
$removed = array_splice($arr, 2, 1);
echo "After splice(2,1): " . json_encode($arr) . ", Removed: " . json_encode($removed) . "\n";

// Try inserting
$arr2 = [1, 2];
$arr2[] = 'a';
$arr2[] = 'b';
echo "Manual insert: " . json_encode($arr2) . "\n";
