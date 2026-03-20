<?php
// Test 163: Array access with various keys
$arr = [
    'string' => 'value1',
    0 => 'zero',
    1 => 'one',
    'nested' => ['a' => 1, 'b' => 2],
];

echo "=== Array access ===\n";
echo "string key: " . $arr['string'] . "\n";
echo "numeric 0: " . $arr[0] . "\n";
echo "numeric 1: " . $arr[1] . "\n";
echo "nested a: " . $arr['nested']['a'] . "\n";

echo "\n=== Unset ===\n";
unset($arr['string']);
echo "After unset string: " . (isset($arr['string']) ? 'exists' : 'removed') . "\n";

echo "\n=== Array modification ===\n";
$arr['new'] = 'new_value';
echo "New key: " . $arr['new'] . "\n";