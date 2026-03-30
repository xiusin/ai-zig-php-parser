<?php
// Test 031: Nullsafe operator, isset, and empty
class NullsafeLab {
    public ?string $nullableString = 'hello';
    public ?int $nullableInt = null;
    public ?array $nullableArray = null;
    public ?object $nullableObject = null;

    public ?Nested $nested = null;

    public function getString(): ?string {
        return $this->nullableString;
    }

    public function getNested(): ?Nested {
        return $this->nested;
    }
}

class Nested {
    public string $value = 'nested_value';
    public ?Leaf $leaf = null;

    public function getLeaf(): ?Leaf {
        return $this->leaf;
    }
}

class Leaf {
    public string $data = 'leaf_data';
}

class Chain {
    public ?Chain $next = null;
    public string $name = '';

    public function __construct(string $name) {
        $this->name = $name;
    }
}

echo "=== Nullsafe operator ===\n";
$lab = new NullsafeLab();
echo "nullableString: " . ($lab->nullableString ?? 'null') . "\n";
echo "nullableInt ?? 0: " . ($lab->nullableInt ?? 0) . "\n";

$lab->nullableString = null;
echo "After null - nullableString ?? 'default': " . ($lab->nullableString ?? 'default') . "\n";

echo "\n=== Chained nullsafe ===\n";
$lab->nested = new Nested();
$lab->nested->leaf = new Leaf();

echo "nested?->value: " . ($lab->nested?->value ?? 'null') . "\n";
echo "nested?->leaf?->data: " . ($lab->nested?->leaf?->data ?? 'null') . "\n";

$lab->nested->leaf = null;
echo "After leaf=null - nested?->leaf?->data: " . ($lab->nested?->leaf?->data ?? 'null') . "\n";

$nestedObj = $lab->nested;
echo "nested?->getLeaf()?->data: " . ($nestedObj?->getLeaf()?->data ?? 'null') . "\n";

echo "\n=== isset with nullsafe ===\n";
$lab->nullableString = null;
echo "isset(lab->nullableString): " . (isset($lab->nullableString) ? 'true' : 'false') . "\n";
echo "lab->nullableString ?? 'isset default': " . ($lab->nullableString ?? 'isset default') . "\n";

echo "\n=== empty with nullsafe ===\n";
$lab->nullableString = '';
echo "empty(lab->nullableString): " . (empty($lab->nullableString) ? 'true' : 'false') . "\n";
$lab->nullableString = 'non-empty';
echo "After 'non-empty' - empty(lab->nullableString): " . (empty($lab->nullableString) ? 'true' : 'false') . "\n";

echo "\n=== Nullsafe in method chains ===\n";
$nested = new Nested();
$nested->leaf = new Leaf();
$lab->nested = $nested;

$getLeaf = $lab->getNested();
$result = $getLeaf?->data ?? 'chain failed';
echo "Chain result: $result\n";

echo "\n=== Nullsafe with arrays ===\n";
$lab->nullableArray = ['key' => 'value'];
$arr = $lab->nullableArray;
echo "nullableArray?['key']: " . ($arr['key'] ?? 'null') . "\n";
$lab->nullableArray = null;
$arr = $lab->nullableArray;
echo "After null - nullableArray?['key']: " . ($arr['key'] ?? 'null') . "\n";

echo "\n=== Linked list with nullsafe ===\n";
$head = new Chain('head');
$head->next = new Chain('middle');
$head->next->next = new Chain('tail');

$current = $head;
$name = $current?->name ?? 'not found';
$next = $current?->next;
$name2 = $next?->next?->name ?? 'not found';
echo "Traverse chain - name: $name, name2: $name2\n";

$head->next->next = null;
$current = $head;
$next = $current?->next;
$name = $next?->next?->name ?? 'not found';
echo "After break - name: $name\n";