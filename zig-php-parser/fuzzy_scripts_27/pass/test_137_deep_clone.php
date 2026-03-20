<?php
// Test 137: Clone with nested objects
class NestedA {
    public function __construct(
        public string $value,
        public ?NestedB $b = null
    ) {}
}

class NestedB {
    public function __construct(
        public string $value,
        public ?NestedC $c = null
    ) {}
}

class NestedC {
    public function __construct(public string $value) {}
}

echo "=== Deep clone ===\n";
$a = new NestedA('a1');
$a->b = new NestedB('b1');
$a->b->c = new NestedC('c1');

$clone = clone $a;
$clone->b->c->value = 'modified_c';

echo "Original a->b->c->value: " . $a->b->c->value . "\n";
echo "Clone a->b->c->value: " . $clone->b->c->value . "\n";

echo "\n=== Clone isolation ===\n";
$clone2 = clone $a;
$clone2->value = 'modified_a';
$clone2->b->value = 'modified_b';

echo "Original a->value: " . $a->value . "\n";
echo "Clone2 a->value: " . $clone2->value . "\n";