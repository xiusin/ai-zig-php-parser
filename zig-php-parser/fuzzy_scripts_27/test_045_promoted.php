<?php
// Test 045: Constructor property promotion, default values
class PromotedLab {
    public function __construct(
        public readonly string $name,
        public int $age = 0,
        public array $tags = [],
        private string $secret = 'default_secret'
    ) {}

    public function getSecret(): string {
        return $this->secret;
    }

    public function with(string $name, int $age): array {
        return [
            'name' => $name,
            'age' => $age,
            'tags' => $this->tags,
        ];
    }
}

class MultiplePromoted {
    public function __construct(
        public string $a = 'default_a',
        public string $b = 'default_b',
        public string $c = 'default_c'
    ) {}
}

class NullablePromoted {
    public function __construct(
        public ?string $nullable = null,
        public ?int $nullableInt = null,
        public ?array $nullableArray = null
    ) {}
}

class CombinedPromoted extends PromotedLab {
    public function __construct(
        public readonly string $code,
        string $name,
        int $age = 0,
        array $tags = [],
        string $secret = 'child_secret'
    ) {
        parent::__construct($name, $age, $tags, $secret);
    }
}

echo "=== Constructor property promotion ===\n";
$lab = new PromotedLab('Test', 30, ['php', 'zig']);
echo "Name: {$lab->name}\n";
echo "Age: {$lab->age}\n";
echo "Tags: " . implode(',', $lab->tags) . "\n";
echo "Secret: " . $lab->getSecret() . "\n";

echo "\n=== Multiple promoted with defaults ===\n";
$multi = new MultiplePromoted();
echo "a: {$multi->a}, b: {$multi->b}, c: {$multi->c}\n";

$multi2 = new MultiplePromoted('custom_a');
echo "After partial: a: {$multi2->a}, b: {$multi2->b}, c: {$multi2->c}\n";

$multi3 = new MultiplePromoted('a', 'b', 'c');
echo "After full: a: {$multi3->a}, b: {$multi3->b}, c: {$multi3->c}\n";

echo "\n=== Nullable promoted ===\n";
$nullable = new NullablePromoted();
echo "nullable: " . ($nullable->nullable ?? 'null') . "\n";
echo "nullableInt: " . ($nullable->nullableInt ?? 'null') . "\n";
echo "nullableArray: " . ($nullable->nullableArray === null ? 'null' : json_encode($nullable->nullableArray)) . "\n";

$nullable2 = new NullablePromoted('value', 42, ['a', 'b']);
echo "After set - nullable: {$nullable2->nullable}, nullableInt: {$nullable2->nullableInt}\n";

echo "\n=== Combined promoted ===\n";
$combined = new CombinedPromoted('CODE123', 'Combined', 25, ['combined'], 'supersecret');
echo "Code: {$combined->code}\n";
echo "Name: {$combined->name}\n";
echo "Secret: " . $combined->getSecret() . "\n";

echo "\n=== Promoted with named arguments ===\n";
$named = new PromotedLab(
    name: 'NamedArg',
    tags: ['named', 'args'],
    age: 50
);
echo "NamedArg - Name: {$named->name}, Age: {$named->age}, Tags: " . implode(',', $named->tags) . "\n";

echo "\n=== Promoted readonly ===\n";
class ReadonlyPromoted {
    public function __construct(
        public readonly string $id,
        public readonly int $value,
        public readonly array $data = []
    ) {}
}

$readonly = new ReadonlyPromoted('abc123', 42, ['readonly', 'promoted']);
echo "ReadonlyPromoted - id: {$readonly->id}, value: {$readonly->value}, data: " . implode(',', $readonly->data) . "\n";