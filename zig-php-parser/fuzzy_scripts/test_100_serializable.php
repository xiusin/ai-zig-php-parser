<?php
// Test 100: Serialization with Serializable
class SerializableClass implements Serializable {
    private string $data;
    private int $timestamp;

    public function __construct(string $data = '', int $timestamp = 0) {
        $this->data = $data;
        $this->timestamp = $timestamp;
    }

    public function serialize(): ?string {
        return serialize([
            'data' => $this->data,
            'timestamp' => $this->timestamp,
        ]);
    }

    public function unserialize(string $data): void {
        $un = unserialize($data);
        $this->data = $un['data'];
        $this->timestamp = $un['timestamp'];
    }

    public function getData(): string {
        return $this->data;
    }

    public function getTimestamp(): int {
        return $this->timestamp;
    }
}

echo "=== Serializable interface ===\n";
$obj = new SerializableClass('test_data', time());
$serialized = serialize($obj);
echo "Serialized length: " . strlen($serialized) . "\n";

$unserialized = unserialize($serialized);
echo "Unserialized data: " . $unserialized->getData() . "\n";
echo "Unserialized timestamp: " . $unserialized->getTimestamp() . "\n";

echo "\n=== Serialize __serialize/__unserialize (PHP 7.4+) ===\n";
class SerializeNew {
    public function __construct(
        public string $name,
        public int $value
    ) {}

    public function __serialize(): array {
        return [
            'name' => $this->name,
            'value' => $this->value * 2,
        ];
    }

    public function __unserialize(array $data): void {
        $this->name = $data['name'];
        $this->value = $data['value'];
    }
}

$newObj = new SerializeNew('test', 21);
$newSerialized = serialize($newObj);
$newUnserialized = unserialize($newSerialized);
echo "New serialized name: {$newUnserialized->name}, value: {$newUnserialized->value}\n";