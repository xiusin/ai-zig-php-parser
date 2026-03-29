<?php
// Test 186: Mixed type
function mixedArg(mixed $value): string {
    return gettype($value) . ": " . var_export($value, true);
}

echo "=== Mixed type ===\n";
echo mixedArg(42) . "\n";
echo mixedArg("hello") . "\n";
echo mixedArg([1, 2, 3]) . "\n";