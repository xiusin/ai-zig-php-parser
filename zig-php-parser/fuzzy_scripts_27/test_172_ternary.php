<?php
// Test 172: Ternary operator
$a = 10;
$b = 20;

echo "=== Ternary operator ===\n";
echo "\$a > 5 ? 'yes' : 'no': " . ($a > 5 ? 'yes' : 'no') . "\n";
echo "\$a > 100 ? 'yes' : 'no': " . ($a > 100 ? 'yes' : 'no') . "\n";
echo "\$b > \$a ? 'b bigger' : 'a bigger': " . ($b > $a ? 'b bigger' : 'a bigger') . "\n";

echo "\n=== Nested ternary ===\n";
$val = 5;
$result = $val > 10 ? 'large' : ($val > 0 ? 'positive' : 'non-positive');
echo "Nested: $result\n";