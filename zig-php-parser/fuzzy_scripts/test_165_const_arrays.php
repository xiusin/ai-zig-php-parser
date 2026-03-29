<?php
// Test 165: Class constant arrays
class ConstArrays {
    public const NUMBERS = [1, 2, 3, 4, 5];
    public const ASSOCIATIVE = ['a' => 1, 'b' => 2, 'c' => 3];
    public const MIXED = [1, 'two', 3.0, true];
}

echo "=== Constant arrays ===\n";
echo "NUMBERS: " . json_encode(ConstArrays::NUMBERS) . "\n";
echo "ASSOCIATIVE: " . json_encode(ConstArrays::ASSOCIATIVE) . "\n";
echo "MIXED: " . json_encode(ConstArrays::MIXED) . "\n";

echo "\n=== Access elements ===\n";
echo "NUMBERS[0]: " . ConstArrays::NUMBERS[0] . "\n";
echo "ASSOCIATIVE['b']: " . ConstArrays::ASSOCIATIVE['b'] . "\n";