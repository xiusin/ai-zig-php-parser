<?php
// Test 175: Closure with use
$outer = 'outer_value';

$closure = function() use ($outer) {
    return "Outer: $outer";
};

echo "=== Closure with use ===\n";
echo $closure() . "\n";