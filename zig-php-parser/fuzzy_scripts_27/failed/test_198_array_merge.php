<?php
// Test 198: Array merge
$a = [1, 2];
$b = [3, 4];

echo "=== Array merge ===\n";
echo "merge: " . implode(',', array_merge($a, $b)) . "\n";