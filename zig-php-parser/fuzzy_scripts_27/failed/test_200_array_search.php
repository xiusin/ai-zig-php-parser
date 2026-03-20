<?php
// Test 200: Array search
$arr = ['a', 'b', 'c', 'd'];

echo "=== Array search ===\n";
echo "search c: " . array_search('c', $arr) . "\n";
echo "in_array b: " . (in_array('b', $arr) ? 'true' : 'false') . "\n";