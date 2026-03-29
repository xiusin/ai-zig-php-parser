<?php
// Test 140: Foreach by reference modification
$data = [1, 2, 3, 4, 5];

echo "=== Foreach by reference ===\n";
foreach ($data as &$value) {
    $value *= 10;
}
unset($value);

echo "After modification: " . implode(',', $data) . "\n";

echo "\n=== Foreach with key reference ===\n";
$arr = ['a' => 1, 'b' => 2, 'c' => 3];
foreach ($arr as $key => &$value) {
    $value *= 2;
}
unset($value);
echo "After key ref: " . json_encode($arr) . "\n";

echo "\n=== Foreach copying ===\n";
$original = [10, 20, 30];
$copy = [];
foreach ($original as $value) {
    $copy[] = $value;
}
$copy[0] = 999;
echo "Original: " . implode(',', $original) . "\n";
echo "Copy: " . implode(',', $copy) . "\n";