<?php
// Test 185: Union types
function unionArg(int|string $value): string {
    if (is_int($value)) {
        return "int: $value";
    }
    return "string: $value";
}

echo "=== Union types ===\n";
echo unionArg(42) . "\n";
echo unionArg("hello") . "\n";