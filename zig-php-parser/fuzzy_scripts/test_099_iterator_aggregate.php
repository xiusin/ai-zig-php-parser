<?php
// Test 099: IteratorAggregate implementation
class IterableCollection implements IteratorAggregate {
    private array $items = [];
    private int $position = 0;

    public function __construct(array $items) {
        $this->items = $items;
    }

    public function getIterator(): Traversable {
        return new ArrayIterator($this->items);
    }

    public function add(mixed $item): void {
        $this->items[] = $item;
    }

    public function count(): int {
        return count($this->items);
    }
}

class KeyValueIterable implements IteratorAggregate {
    private array $data = [];

    public function __construct(array $data) {
        $this->data = $data;
    }

    public function getIterator(): Traversable {
        return new ArrayIterator($this->data);
    }
}

echo "=== IteratorAggregate ===\n";
$collection = new IterableCollection(['a', 'b', 'c', 'd']);
foreach ($collection as $key => $value) {
    echo "  [$key] => $value\n";
}

echo "\n=== With custom add ===\n";
$collection->add('e');
$collection->add('f');
foreach ($collection as $v) {
    echo "  $v\n";
}

echo "\n=== KeyValue ===\n";
$kv = new KeyValueIterable(['x' => 10, 'y' => 20, 'z' => 30]);
foreach ($kv as $key => $value) {
    echo "  $key => $value\n";
}

echo "\n=== Count via Countable ===\n";
echo "count(collection): " . count($collection) . "\n";