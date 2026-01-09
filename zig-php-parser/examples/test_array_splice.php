<?php

// Test 1: Basic array_splice
$arr1 = [1, 2, 3, 4, 5];
$removed1 = array_splice($arr1, 2);
echo "Test 1 - Remove from index 2: ";
echo "Original: " . json_encode($arr1) . ", Removed: " . json_encode($removed1) . "\n";

// Test 2: array_splice with length
$arr2 = [1, 2, 3, 4, 5];
$removed2 = array_splice($arr2, 1, 2);
echo "Test 2 - Remove 2 elements from index 1: ";
echo "Original: " . json_encode($arr2) . ", Removed: " . json_encode($removed2) . "\n";

// Test 3: array_splice with replacement
$arr3 = [1, 2, 3, 4, 5];
$removed3 = array_splice($arr3, 2, 1, ['a', 'b']);
echo "Test 3 - Replace at index 2: ";
echo "Original: " . json_encode($arr3) . ", Removed: " . json_encode($removed3) . "\n";

// Test 4: array_splice with negative offset
$arr4 = [1, 2, 3, 4, 5];
$removed4 = array_splice($arr4, -2);
echo "Test 4 - Remove last 2: ";
echo "Original: " . json_encode($arr4) . ", Removed: " . json_encode($removed4) . "\n";

echo "Done\n";
