<?php
// Test 187: Constructor property promotion
class Promoted {
    public function __construct(
        public string $name,
        public int $value = 0
    ) {}
}

echo "=== Constructor promotion ===\n";
$obj = new Promoted('test', 42);
echo "name: {$obj->name}, value: {$obj->value}\n";