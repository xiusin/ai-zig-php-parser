<?php
// Test 034: Object interface, ArrayAccess, ArrayObject simulation
class ObjectLike implements ArrayAccess {
    private array $data = [];

    public function __construct(array $data = []) {
        $this->data = $data;
    }

    public function offsetExists(mixed $offset): bool {
        return isset($this->data[$offset]);
    }

    public function offsetGet(mixed $offset): mixed {
        return $this->data[$offset] ?? null;
    }

    public function offsetSet(mixed $offset, mixed $value): void {
        if ($offset === null) {
            $this->data[] = $value;
        } else {
            $this->data[$offset] = $value;
        }
    }

    public function offsetUnset(mixed $offset): void {
        unset($this->data[$offset]);
    }

    public function getData(): array {
        return $this->data;
    }
}

class CountableArray implements Countable {
    private array $items = [];

    public function __construct(array $items) {
        $this->items = $items;
    }

    public function count(): int {
        return count($this->items);
    }
}

class StringableObject {
    public function __construct(private string $value) {}

    public function __toString(): string {
        return $this->value;
    }
}

class JsonSerializableObject implements JsonSerializable {
    public function __construct(
        public string $name,
        public int $value
    ) {}

    public function jsonSerialize(): array {
        return [
            'name' => $this->name,
            'value' => $this->value,
            'computed' => $this->name . '_' . $this->value,
        ];
    }
}

echo "=== ArrayAccess implementation ===\n";
$obj = new ObjectLike(['a' => 1, 'b' => 2]);
echo "obj['a']: " . $obj['a'] . "\n";
echo "isset(obj['b']): " . (isset($obj['b']) ? 'true' : 'false') . "\n";
echo "isset(obj['c']): " . (isset($obj['c']) ? 'true' : 'false') . "\n";

$obj['c'] = 3;
echo "After set obj['c'] = 3: " . $obj['c'] . "\n";

$obj[] = 4;
echo "After append: " . json_encode($obj->getData()) . "\n";

unset($obj['a']);
echo "After unset(obj['a']): " . json_encode($obj->getData()) . "\n";

echo "\n=== Countable implementation ===\n";
$countable = new CountableArray([1, 2, 3, 4, 5]);
echo "count(\$countable): " . count($countable) . "\n";

echo "\n=== Stringable implementation ===\n";
$stringable = new StringableObject('Hello Stringable');
echo "Stringable object: $stringable\n";

echo "\n=== JsonSerializable implementation ===\n";
$jsonObj = new JsonSerializableObject('test', 42);
echo "JSON: " . json_encode($jsonObj) . "\n";

echo "\n=== IteratorAggregate for traversal ===\n";
class IterableClass implements IteratorAggregate {
    private array $data = ['x' => 10, 'y' => 20, 'z' => 30];

    public function getIterator(): Traversable {
        return new ArrayIterator($this->data);
    }
}

$iterable = new IterableClass();
foreach ($iterable as $key => $value) {
    echo "  $key => $value\n";
}

echo "\n=== Serializable interface ===\n";
class SerializableClass implements Serializable {
    public function __construct(
        public string $data,
        public int $timestamp
    ) {}

    public function serialize(): ?string {
        return serialize(['d' => $this->data, 't' => $this->timestamp]);
    }

    public function unserialize(string $data): void {
        $un = unserialize($data);
        $this->data = $un['d'];
        $this->timestamp = $un['t'];
    }
}

$ser = new SerializableClass('important data', time());
$serialized = serialize($ser);
$unser = unserialize($serialized);
echo "Original: {$ser->data}, Unserialized: {$unser->data}\n";