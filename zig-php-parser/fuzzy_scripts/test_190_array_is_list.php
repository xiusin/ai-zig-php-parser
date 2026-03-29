<?php
// Test 190: Array_is_list
echo "=== array_is_list ===\n";
echo "[1,2,3]: " . (array_is_list([1, 2, 3]) ? 'true' : 'false') . "\n";
echo "['a'=>1]: " . (array_is_list(['a' => 1]) ? 'true' : 'false') . "\n";
echo "[]: " . (array_is_list([]) ? 'true' : 'false') . "\n";