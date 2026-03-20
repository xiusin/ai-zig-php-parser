<?php
// Test 106: Array_is_list, array functions
echo "=== array_is_list ===\n";
echo "array_is_list([1,2,3]): " . (array_is_list([1,2,3]) ? 'true' : 'false') . "\n";
echo "array_is_list(['a'=>1,'b'=>2]): " . (array_is_list(['a'=>1,'b'=>2]) ? 'true' : 'false') . "\n";
echo "array_is_list([]): " . (array_is_list([]) ? 'true' : 'false') . "\n";
echo "array_is_list([0=>1, 1=>2, 2=>3]): " . (array_is_list([0=>1, 1=>2, 2=>3]) ? 'true' : 'false') . "\n";
echo "array_is_list([1=>1, 0=>2]): " . (array_is_list([1=>1, 0=>2]) ? 'true' : 'false') . "\n";

echo "\n=== array_key functions ===\n";
$arr = ['a' => 1, 'b' => 2, 'c' => 3];
echo "array_keys: " . implode(',', array_keys($arr)) . "\n";
echo "array_values: " . implode(',', array_values($arr)) . "\n";
echo "array_key_exists('b', \$arr): " . (array_key_exists('b', $arr) ? 'yes' : 'no') . "\n";
echo "array_key_first(\$arr): " . (array_key_first($arr) ?? 'null') . "\n";
echo "array_key_last(\$arr): " . (array_key_last($arr) ?? 'null') . "\n";

echo "\n=== array_map with keys ===\n";
$mapped = array_map(fn($v) => $v * 2, $arr);
echo "Mapped *2: " . json_encode($mapped) . "\n";

echo "\n=== array_filter with keys ===\n";
$filtered = array_filter($arr, fn($v) => $v > 1);
echo "Filtered > 1: " . json_encode($filtered) . "\n";