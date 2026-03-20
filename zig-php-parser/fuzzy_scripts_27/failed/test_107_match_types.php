<?php
// Test 107: match expression with various types
function matchTypes(mixed $value): string {
    return match (true) {
        is_int($value) => "int: $value",
        is_float($value) => "float: $value",
        is_string($value) => "string: $value",
        is_bool($value) => "bool: " . ($value ? 'true' : 'false'),
        is_array($value) => "array: " . count($value) . " elements",
        is_null($value) => "null",
        default => "unknown",
    };
}

function matchValues(int|string $value): string {
    return match ($value) {
        1 => "one",
        2 => "two",
        'a' => "letter a",
        'b' => "letter b",
        default => "other",
    };
}

echo "=== match with true ===\n";
echo matchTypes(42) . "\n";
echo matchTypes(3.14) . "\n";
echo matchTypes("hello") . "\n";
echo matchTypes(true) . "\n";
echo matchTypes([1, 2]) . "\n";
echo matchTypes(null) . "\n";

echo "\n=== match with union type ===\n";
echo matchValues(1) . "\n";
echo matchValues('a') . "\n";
echo matchValues('unknown') . "\n";

echo "\n=== match in expression ===\n";
$result = match ($status = random_int(0, 1) ? 'active' : 'inactive') {
    'active' => 'Status is active',
    'inactive' => 'Status is inactive',
    default => 'Unknown',
};
echo "Status result: $result\n";