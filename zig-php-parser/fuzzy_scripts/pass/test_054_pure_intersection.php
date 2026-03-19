<?php
// 测试54: 纯交集类型与trait组合 - 复杂的类型约束场景
// 测试目的：验证trait与接口交集类型的复杂组合

trait Timestampable {
    private DateTime $createdAt;
    
    public function initTimestamp(): void {
        $this->createdAt = new DateTime();
    }
    
    public function getCreatedAt(): string {
        return $this->createdAt->format('Y-m-d H:i:s');
    }
}

trait Versionable {
    private int $version = 1;
    
    public function bumpVersion(): void {
        $this->version++;
    }
    
    public function getVersion(): int {
        return $this->version;
    }
}

interface Identifiable {
    public function getId(): string;
    public function setId(string $id): void;
}

interface Validatable {
    public function validate(): bool;
    public function getErrors(): array;
}

interface Serializable {
    public function toArray(): array;
    public function fromArray(array $data): void;
}

// 实现多个接口 + 使用多个trait
class Entity implements Identifiable, Validatable, Serializable {
    use Timestampable, Versionable;
    
    private string $id = '';
    private array $data = [];
    private array $errors = [];
    
    public function __construct() {
        $this->initTimestamp();
    }
    
    public function getId(): string {
        return $this->id;
    }
    
    public function setId(string $id): void {
        $this->id = $id;
        $this->bumpVersion();
    }
    
    public function validate(): bool {
        $this->errors = [];
        if (empty($this->id)) {
            $this->errors[] = 'ID is required';
        }
        if (empty($this->data)) {
            $this->errors[] = 'Data cannot be empty';
        }
        return empty($this->errors);
    }
    
    public function getErrors(): array {
        return $this->errors;
    }
    
    public function toArray(): array {
        return [
            'id' => $this->id,
            'data' => $this->data,
            'version' => $this->getVersion(),
            'createdAt' => $this->getCreatedAt(),
        ];
    }
    
    public function fromArray(array $data): void {
        $this->data = $data;
        $this->bumpVersion();
    }
    
    public function setData(array $data): void {
        $this->data = $data;
    }
}

// 接受交集类型的函数
function saveEntity(Identifiable&Validatable&Serializable $entity): bool {
    if (!$entity->validate()) {
        echo "Validation failed:\n";
        foreach ($entity->getErrors() as $error) {
            echo "  - $error\n";
        }
        return false;
    }
    
    echo "Saving entity:\n";
    print_r($entity->toArray());
    return true;
}

// 测试1：无效实体
$invalid = new Entity();
$invalid->setId('123');
echo "Test 1 - Invalid entity:\n";
saveEntity($invalid); // 会失败，因为没有数据

// 测试2：有效实体
$valid = new Entity();
$valid->setId('456');
$valid->setData(['name' => 'Test', 'value' => 100]);
echo "\nTest 2 - Valid entity:\n";
saveEntity($valid);

// 测试3：版本控制
echo "\nTest 3 - Version tracking:\n";
$versioned = new Entity();
echo "Initial version: " . $versioned->getVersion() . "\n";
$versioned->setId('001');
echo "After setId: " . $versioned->getVersion() . "\n";
$versioned->fromArray(['updated' => true]);
echo "After fromArray: " . $versioned->getVersion() . "\n";

// 测试4：时间戳
echo "\nTest 4 - Timestamps:\n";
$timed = new Entity();
echo "Created at: " . $timed->getCreatedAt() . "\n";

// 返回交集类型的工厂
class EntityFactory {
    public static function create(): Identifiable&Validatable&Serializable {
        $entity = new Entity();
        $entity->setId(uniqid('entity_'));
        $entity->setData(['created_by' => 'factory']);
        return $entity;
    }
}

$factoryEntity = EntityFactory::create();
echo "\nFactory created entity:\n";
print_r($factoryEntity->toArray());

// 数组操作
$entities = [
    EntityFactory::create(),
    EntityFactory::create(),
];

echo "\nProcessing multiple entities:\n";
foreach ($entities as $i => $e) {
    echo "Entity $i ID: " . $e->getId() . "\n";
}
?>
