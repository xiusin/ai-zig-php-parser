<?php
// Test 144: Constant expressions with functions
const TIME_BASED = 100 + 200;
const ARRAY_CONST = [1, 2, 3, 4, 5];
const STRING_CONCAT = "Hello" . " " . "World";

class ConstFunc {
    public const COMPUTED = 50 * 2;
    public const FROM_CONST = TIME_BASED;
}

echo "=== Constant expressions ===\n";
echo "TIME_BASED: " . TIME_BASED . "\n";
echo "ARRAY_CONST: " . json_encode(ARRAY_CONST) . "\n";
echo "STRING_CONCAT: " . STRING_CONCAT . "\n";

echo "\n=== Class constant from function ===\n";
echo "ConstFunc::COMPUTED: " . ConstFunc::COMPUTED . "\n";
echo "ConstFunc::FROM_CONST: " . ConstFunc::FROM_CONST . "\n";