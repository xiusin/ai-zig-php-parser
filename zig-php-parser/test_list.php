<?php
/**
 * Test list() assignment
 */
echo "=== List Assignment Test ===\n";

// Test 1: list with variable
echo "Test 1: list with variable\n";
$arr1 = [1, 2, 3];
list($a, $b, $c) = $arr1;
echo "Result: $a, $b, $c\n";

// Test 2: list with function returning array
echo "\nTest 2: list with function call\n";
function retArr() { return [10, 20, 30]; }
list($i, $j, $k) = retArr();
echo "From function: $i, $j, $k\n";

// Test 3: nested list
echo "\nTest 3: nested list\n";
$arr3 = [[1, 2], [3, 4]];
list($x, list($y, $z)) = $arr3;
echo "Nested: $x, $y, $z\n";

echo "\n=== Done ===\n";
