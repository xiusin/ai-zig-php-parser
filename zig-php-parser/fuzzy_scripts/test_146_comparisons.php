<?php
// Test 146: Comparison operators
$a = 10;
$b = 20;
$c = "10";
$d = 20;

echo "=== Comparisons ===\n";
echo "$a == $c (loose): " . ($a == $c ? 'true' : 'false') . "\n";
echo "$a === $c (strict): " . ($a === $c ? 'true' : 'false') . "\n";
echo "$a != $b: " . ($a != $b ? 'true' : 'false') . "\n";
echo "$a !== $c: " . ($a !== $c ? 'true' : 'false') . "\n";
echo "$a < $b: " . ($a < $b ? 'true' : 'false') . "\n";
echo "$a <= $b: " . ($a <= $b ? 'true' : 'false') . "\n";
echo "$b >= $d: " . ($b >= $d ? 'true' : 'false') . "\n";
echo "$b <=> $a (spaceship): " . ($b <=> $a) . "\n";

echo "\n=== Null comparisons ===\n";
$null = null;
echo "null == null: " . ($null == null ? 'true' : 'false') . "\n";
echo "null === null: " . ($null === null ? 'true' : 'false') . "\n";
echo "null != 0: " . ($null != 0 ? 'true' : 'false') . "\n";
echo "null == 0: " . ($null == 0 ? 'true' : 'false') . "\n";