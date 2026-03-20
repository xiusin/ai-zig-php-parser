<?php
// Test 183: Nullsafe operator
class Nullsafe {
    public ?string $value = "hello";
}

echo "=== Nullsafe operator ===\n";
$obj = new Nullsafe();
echo "With value: " . ($obj?->value ?? 'null') . "\n";
$obj->value = null;
echo "After null: " . ($obj?->value ?? 'null') . "\n";
$obj2 = null;
echo "Null object: " . ($obj2?->value ?? 'null') . "\n";