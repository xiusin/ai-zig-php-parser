<?php
// Test 109: Constructor property promotion with readonly
class PromotedReadonly {
    public function __construct(
        public readonly string $name,
        public readonly int $value,
        public readonly array $tags = []
    ) {}
}

class CombinedPromotedReadonly extends PromotedReadonly {
    public function __construct(
        public readonly string $code,
        string $name,
        int $value = 0,
        array $tags = []
    ) {
        parent::__construct($name, $value, $tags);
    }
}

echo "=== Readonly promoted properties ===\n";
$obj = new PromotedReadonly('test', 42, ['a', 'b']);
echo "name: {$obj->name}\n";
echo "value: {$obj->value}\n";
echo "tags: " . implode(',', $obj->tags) . "\n";

echo "\n=== Cannot modify readonly ===\n";
$obj2 = new PromotedReadonly('test2', 100);
echo "Initial: name={$obj2->name}, value={$obj2->value}\n";

echo "\n=== Combined promotion ===\n";
$combined = new CombinedPromotedReadonly('CODE', 'Combined', 50, ['combined']);
echo "code: {$combined->code}\n";
echo "name: {$combined->name}\n";
echo "value: {$combined->value}\n";