<?php
// Test 019: Match expression and pattern matching
class MatchLab {
    public function process(mixed $value): string {
        return match (true) {
            $value instanceof stdClass => "stdClass instance",
            $value instanceof DateTime => "DateTime instance",
            is_array($value) => "Array with " . count($value) . " elements",
            is_string($value) => "String of length " . strlen($value),
            is_int($value) => "Integer: $value",
            is_float($value) => "Float: $value",
            is_bool($value) => "Boolean: " . ($value ? 'true' : 'false'),
            is_null($value) => "Null value",
            default => "Unknown type",
        };
    }

    public function switchLike(mixed $value): string {
        return match ($value) {
            1, 2, 3 => "Small number",
            4, 5, 6 => "Medium number",
            7, 8, 9, 10 => "Large number",
            0 => "Zero",
            -1, -2, -3 => "Negative small",
            default => "Other: $value",
        };
    }

    public function typeMatch(mixed $value): string {
        return match (gettype($value)) {
            'integer' => "INT: $value",
            'string' => "STR: $value",
            'double' => "FLOAT: $value",
            'boolean' => "BOOL: " . ($value ? 'true' : 'false'),
            'NULL' => "NULL",
            'array' => "ARRAY",
            'object' => "OBJECT: " . get_class($value),
            default => "UNKNOWN",
        };
    }
}

echo "=== Match with true condition ===\n";
$lab = new MatchLab();
$tests = [
    new stdClass(),
    new DateTime(),
    [1, 2, 3],
    "hello",
    42,
    3.14,
    true,
    false,
    null,
];

foreach ($tests as $t) {
    echo gettype($t) . ": " . $lab->process($t) . "\n";
}

echo "\n=== Match with switch-like values ===\n";
foreach ([0, 1, 5, 7, 10, 100, -2] as $n) {
    echo "  $n -> " . $lab->switchLike($n) . "\n";
}

echo "\n=== Match with type strings ===\n";
$values = [123, "test", 3.14, true, null, ['a' => 1], new stdClass()];
foreach ($values as $v) {
    echo "  " . $lab->typeMatch($v) . "\n";
}

echo "\n=== Match in expressions ===\n";
$result = match ($status = 'active') {
    'active' => 'Status is active',
    'inactive' => 'Status is inactive',
    'pending' => 'Status is pending',
    default => "Unknown status: $status",
};
echo "$result\n";

echo "\n=== Match with null coalescing ===\n";
$data = ['key' => 'value'];
$result = match ($data['missing'] ?? $data['key'] ?? 'default') {
    'value' => "Found value",
    'default' => "Got default",
};
echo "$result\n";

echo "\n=== Match without default (PHP 8.0+) ===\n";
try {
    $value = 'unknown';
    $result = match ($value) {
        'a' => 1,
        'b' => 2,
    };
    echo "Result (no match): $result\n";
} catch (UnhandledMatchError $e) {
    echo "UnhandledMatchError: " . $e->getMessage() . "\n";
}

echo "\n=== Complex match patterns ===\n";
function classify(int $age): string {
    return match (true) {
        $age < 0 => "Invalid",
        $age < 13 => "Child",
        $age < 20 => "Teenager",
        $age < 65 => "Adult",
        $age < 150 => "Senior",
        default => "Century+",
    };
}

foreach ([-1, 5, 15, 25, 70, 100, 200] as $age) {
    echo "  Age $age: " . classify($age) . "\n";
}