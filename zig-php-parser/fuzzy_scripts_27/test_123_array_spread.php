<?php
// Test 123: Array unpacking with string keys
$a = ['x' => 1, 'y' => 2];
$b = ['y' => 3, 'z' => 4];

echo "=== Array unpacking with keys ===\n";
$merged = ['first' => true, ...$a, ...$b];
echo "Merged with string keys: " . json_encode($merged) . "\n";

echo "\n=== Spread in array ===\n";
$base = ['a' => 1, 'b' => 2];
$extended = ['c' => 3, ...$base, 'd' => 4];
echo "Extended: " . json_encode($extended) . "\n";

echo "\n=== Override with spread ===\n";
$first = ['x' => 1, 'y' => 2];
$second = ['x' => 10, 'y' => 20];
$combined = [...$first, ...$second];
echo "First overrides second: " . json_encode($combined) . "\n";

echo "\n=== Nested spread ===\n";
$n1 = ['a' => 1];
$n2 = ['b' => 2];
$n3 = [...$n1, ...$n2, 'c' => 3];
echo "Nested: " . json_encode($n3) . "\n";