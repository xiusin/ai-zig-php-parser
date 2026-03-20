<?php
// Test 188: Readonly properties
class ReadonlyProp {
    public function __construct(
        public readonly string $name,
        public readonly int $value
    ) {}
}

echo "=== Readonly properties ===\n";
$obj = new ReadonlyProp('test', 100);
echo "name: {$obj->name}, value: {$obj->value}\n";