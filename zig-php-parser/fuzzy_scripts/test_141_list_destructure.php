<?php
// Test 141: List destructuring with arrays
$data = ['first', 'second', 'third', 'fourth', 'fifth'];

echo "=== List destructuring ===\n";
list($a, $b, $c) = $data;
echo "First three: $a, $b, $c\n";

echo "\n=== Partial list ===\n";
list($first, , $third) = $data;
echo "First and third: $first, $third\n";

echo "\n=== Keyed list ===\n";
$assoc = ['x' => 'value_x', 'y' => 'value_y'];
list('x' => $xVal, 'y' => $yVal) = $assoc;
echo "x=$xVal, y=$yVal\n";

echo "\n=== Nested list ===\n";
$nested = [['a', 'b'], ['c', 'd']];
list(list($n1, $n2), list($n3, $n4)) = $nested;
echo "Nested: $n1, $n2, $n3, $n4\n";