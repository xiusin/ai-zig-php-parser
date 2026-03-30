<?php
// Test 076: Object cloning
class CloneSource {
    public string $value = 'original';
    public array $data = [];

    public function __construct() {
        $this->data = ['initial'];
    }

    public function setValue(string $v): void {
        $this->value = $v;
    }
}

class CloneWithHook {
    public string $name = 'original';
    public array $history = [];

    public function __construct(public string $data) {}

    public function __clone() {
        $this->name = $this->name . '_cloned';
        $this->history[] = 'cloned';
    }
}

echo "=== Basic clone ===\n";
$original = new CloneSource();
$clone = clone $original;

$clone->setValue('modified');
echo "Original value: " . $original->value . "\n";
echo "Clone value: " . $clone->value . "\n";

echo "\n=== Shallow clone (shared reference) ===\n";
$original2 = new CloneSource();
$clone2 = clone $original2;

$clone2->data[] = 'added';
echo "Original data: " . json_encode($original2->data) . "\n";
echo "Clone data: " . json_encode($clone2->data) . "\n";

echo "\n=== Clone with __clone hook ===\n";
$withHook = new CloneWithHook('data_value');
$hookClone = clone $withHook;

echo "Original name: " . $withHook->name . "\n";
echo "Clone name: " . $hookClone->name . "\n";
echo "Original history: " . json_encode($withHook->history) . "\n";
echo "Clone history: " . json_encode($hookClone->history) . "\n";

echo "\n=== Clone in function ===\n";
function cloneAndModify(CloneSource $obj): CloneSource {
    $cloned = clone $obj;
    $cloned->value = 'function_modified';
    return $cloned;
}

$source = new CloneSource();
$result = cloneAndModify($source);
echo "Source value: " . $source->value . "\n";
echo "Result value: " . $result->value . "\n";