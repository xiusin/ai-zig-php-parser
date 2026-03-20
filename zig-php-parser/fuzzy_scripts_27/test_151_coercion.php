<?php
// Test 151: spaceship operator and type coercion
$a = 5;
$b = 10;
$c = 5;

echo "=== Spaceship operator ===\n";
echo "$a <=> $b: " . ($a <=> $b) . " (expect -1)\n";
echo "$a <=> $c: " . ($a <=> $c) . " (expect 0)\n";
echo "$b <=> $a: " . ($b <=> $a) . " (expect 1)\n";

echo "\n=== Type coercion ===\n";
echo "10 < '10': " . ((10 < '10') ? 'true' : 'false') . "\n";
echo "10 <= '10': " . ((10 <= '10') ? 'true' : 'false') . "\n";
echo "'apple' < 'banana': " . (('apple' < 'banana') ? 'true' : 'false') . "\n";