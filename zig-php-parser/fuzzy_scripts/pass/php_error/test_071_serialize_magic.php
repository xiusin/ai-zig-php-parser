<?php
// 测试71: 序列化与反序列化魔术方法 - __sleep, __wakeup, __serialize, __unserialize
// 测试目的：验证PHP 7.4+的新序列化机制和向后兼容

class OldStyleSerialization {
    private string $password = 'secret123';
    public string $name = 'User';
    public array $data = [];
    private $resource = null;
    
    public function __construct() {
        $this->data = ['key' => 'value'];
    }
    
    // PHP < 7.4 风格
    public function __sleep(): array {
        echo "  __sleep called\n";
        // 不序列化password和resource
        return ['name', 'data'];
    }
    
    public function __wakeup(): void {
        echo "  __wakeup called\n";
        // 恢复默认值
        $this->password = 'default';
    }
}

class NewStyleSerialization {
    private string $password = 'secret456';
    public string $name = 'User';
    public array $data = [];
    private int $timestamp;
    
    public function __construct() {
        $this->data = ['info' => 'test'];
        $this->timestamp = time();
    }
    
    // PHP 7.4+ 风格
    public function __serialize(): array {
        echo "  __serialize called\n";
        return [
            'name' => $this->name,
            'data' => $this->data,
            'serialized_at' => date('Y-m-d H:i:s'),
        ];
    }
    
    public function __unserialize(array $data): void {
        echo "  __unserialize called\n";
        $this->name = $data['name'];
        $this->data = $data['data'];
        $this->password = 'restored_default';
        $this->timestamp = time();
    }
}

// 测试旧风格
echo "=== Old Style ===\n";
$old = new OldStyleSerialization();
$oldSerialized = serialize($old);
echo "Serialized: " . strlen($oldSerialized) . " bytes\n";

$oldRestored = unserialize($oldSerialized);
echo "Restored name: {$oldRestored->name}\n";

// 测试新风格
echo "\n=== New Style ===\n";
$new = new NewStyleSerialization();
$newSerialized = serialize($new);
echo "Serialized: " . strlen($newSerialized) . " bytes\n";

$newRestored = unserialize($newSerialized);
echo "Restored name: {$newRestored->name}\n";

// 匿名类序列化
echo "\n=== Anonymous Class ===\n";
$anon = new class {
    public $value = 42;
    public function __serialize(): array {
        return ['value' => $this->value];
    }
    public function __unserialize(array $data): void {
        $this->value = $data['value'];
    }
};

$anonSerialized = serialize($anon);
$anonRestored = unserialize($anonSerialized);
echo "Anon value: {$anonRestored->value}\n";

// 循环引用序列化
class Node {
    public ?self $next = null;
    public string $value;
    
    public function __construct(string $value) {
        $this->value = $value;
    }
}

echo "\n=== Circular Reference ===\n";
$node1 = new Node("A");
$node2 = new Node("B");
$node1->next = $node2;
$node2->next = $node1; // 循环

$serialized = serialize($node1);
$restored = unserialize($serialized);
echo "Circular preserved: " . ($restored->next->next === $restored ? 'yes' : 'no') . "\n";

// JSON序列化对比
echo "\n=== JSON vs Serialize ===\n";
$data = ['name' => 'Test', 'nested' => ['x' => 1, 'y' => 2]];
$jsonEncoded = json_encode($data);
$phpSerialized = serialize($data);

echo "JSON: " . strlen($jsonEncoded) . " bytes\n";
echo "PHP: " . strlen($phpSerialized) . " bytes\n";

$jsonDecoded = json_decode($jsonEncoded, true);
$phpRestored = unserialize($phpSerialized);
echo "JSON equal: " . ($jsonDecoded === $data ? 'yes' : 'no') . "\n";
echo "PHP equal: " . ($phpRestored === $data ? 'yes' : 'no') . "\n";

// 序列化对象到数据库存储模拟
class SerializableEntity {
    public int $id = 0;
    public string $data = '';
    
    public static function fromDatabase(string $serialized): self {
        $entity = new self();
        $data = unserialize($serialized);
        $entity->id = $data['id'] ?? 0;
        $entity->data = $data['data'] ?? '';
        return $entity;
    }
    
    public function toDatabase(): string {
        return serialize(['id' => $this->id, 'data' => $this->data]);
    }
}

$entity = new SerializableEntity();
$entity->id = 123;
$entity->data = "Important data";

echo "\nDatabase storage:\n";
$dbData = $entity->toDatabase();
echo "Stored: " . strlen($dbData) . " bytes\n";
$loaded = SerializableEntity::fromDatabase($dbData);
echo "Loaded ID: {$loaded->id}, Data: {$loaded->data}\n";
?>