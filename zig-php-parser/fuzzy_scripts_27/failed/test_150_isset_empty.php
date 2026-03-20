<?php
// Test 150: isset with multiple arguments
$a = 'value_a';
$b = null;
$c = 'value_c';

echo "=== isset with multiple args ===\n";
echo "isset(\$a, \$b, \$c): " . (isset($a, $b, $c) ? 'yes' : 'no') . "\n";
echo "isset(\$a, \$c): " . (isset($a, $c) ? 'yes' : 'no') . "\n";

echo "\n=== Empty ===\n";
$emptystr = '';
$emptynum = 0;
$emptyarr = [];
echo "empty(\$emptystr): " . (empty($emptystr) ? 'true' : 'false') . "\n";
echo "empty(\$emptynum): " . (empty($emptynum) ? 'true' : 'false') . "\n";
echo "empty(\$emptyarr): " . (empty($emptyarr) ? 'true' : 'false') . "\n";