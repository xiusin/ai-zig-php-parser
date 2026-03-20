<?php
// Test 113: Extract, compact, and get_defined_vars
$name = 'Alice';
$age = 30;
$city = 'NYC';
$active = true;

echo "=== compact ===\n";
$result = compact('name', 'age', 'city', 'active');
echo "compact('name', 'age', 'city', 'active'): " . json_encode($result) . "\n";

$result2 = compact(['name', 'age']);
echo "compact(['name', 'age']): " . json_encode($result2) . "\n";

echo "\n=== extract ===\n";
$data = ['x' => 10, 'y' => 20, 'z' => 30];
extract($data);
echo "After extract: x=$x, y=$y, z=$z\n";

$assoc = ['user' => 'admin', 'level' => 99];
extract($assoc);
echo "User: $user, Level: $level\n";

echo "\n=== get_defined_vars ===\n";
$vars = get_defined_vars();
$keys = array_slice(array_keys($vars), 0, 15);
echo "First 15 defined vars: " . implode(', ', $keys) . "\n";

echo "\n=== extract with EXTR_PREFIX_ALL ===\n";
$arr = ['a' => 1, 'b' => 2];
extract($arr, EXTR_PREFIX_ALL, 'pre');
echo "With prefix: pre_a=$pre_a, pre_b=$pre_b\n";