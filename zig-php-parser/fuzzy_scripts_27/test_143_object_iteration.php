<?php
// Test 143: Object iteration
class IterObj implements Iterator {
    private int $position = 0;
    private array $data = [];

    public function __construct(array $data) {
        $this->data = $data;
    }

    public function current(): mixed { return $this->data[$this->position]; }
    public function key(): int { return $this->position; }
    public function next(): void { $this->position++; }
    public function rewind(): void { $this->position = 0; }
    public function valid(): bool { return isset($this->data[$this->position]); }
}

echo "=== Object iteration ===\n";
$obj = new IterObj(['first', 'second', 'third']);
foreach ($obj as $key => $value) {
    echo "  [$key] => $value\n";
}

echo "\n=== Countable iteration ===\n";
if ($obj instanceof Countable) {
    echo "Count: " . count($obj) . "\n";
}