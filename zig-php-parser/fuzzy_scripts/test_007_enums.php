<?php
// Test 007: Class constants, enums, and backed enums
enum Status: string {
    case Active = 'active';
    case Inactive = 'inactive';
    case Pending = 'pending';

    public function label(): string {
        return match($this) {
            self::Active => 'Active Status',
            self::Inactive => 'Inactive Status',
            self::Pending => 'Pending Status',
        };
    }

    public function isActive(): bool {
        return $this === self::Active;
    }
}

interface Labeled {
    public function getLabel(): string;
}

class Entity implements Labeled {
    public const TYPE = 'Entity';
    public const VERSION = '1.0.0';
    private static int $instanceCount = 0;

    public function __construct(
        private readonly string $name,
        private Status $status = Status::Pending,
        private array $metadata = []
    ) {
        self::$instanceCount++;
    }

    public function getLabel(): string {
        return "[{$this->name}] " . $this->status->label();
    }

    public static function getInstanceCount(): int {
        return self::$instanceCount;
    }

    public function __debugInfo(): array {
        return [
            'name' => $this->name,
            'status' => $this->status->value,
            'type' => self::TYPE,
        ];
    }
}

class ChildEntity extends Entity {
    public const TYPE = 'ChildEntity';
    public const EXTENDED_VERSION = parent::VERSION . '.1';
}

// Test constants
echo "Status::Active->value: " . Status::Active->value . "\n";
echo "Status::Active->label(): " . Status::Active->label() . "\n";
echo "Status::Active->isActive(): " . (Status::Active->isActive() ? 'true' : 'false') . "\n";
echo "Status::Pending->isActive(): " . (Status::Pending->isActive() ? 'true' : 'false') . "\n";

echo "\n";

$e1 = new Entity('Test1', Status::Active, ['created' => 'today']);
$e2 = new Entity('Test2', Status::Inactive);
$e3 = new ChildEntity('Child1', Status::Pending);

echo "e1->getLabel(): " . $e1->getLabel() . "\n";
echo "e2->getLabel(): " . $e2->getLabel() . "\n";
echo "e3->getLabel(): " . $e3->getLabel() . "\n";
echo "Entity::TYPE: " . Entity::TYPE . "\n";
echo "ChildEntity::TYPE: " . ChildEntity::TYPE . "\n";
echo "ChildEntity::EXTENDED_VERSION: " . ChildEntity::EXTENDED_VERSION . "\n";
echo "Entity::VERSION: " . Entity::VERSION . "\n";

echo "\n";
echo "Instance count: " . Entity::getInstanceCount() . "\n";

// Test backed enum from string
$parsed = Status::from('active');
echo "Status::from('active'): " . $parsed->label() . "\n";

try {
    $invalid = Status::from('invalid');
} catch (ValueError $e) {
    echo "ValueError caught: " . $e->getMessage() . "\n";
}

// Test enum cases
echo "\nAll Status cases:\n";
foreach (Status::cases() as $case) {
    echo "  {$case->name} = {$case->value}\n";
}

// Test enum tryFrom
$try = Status::tryFrom('inactive');
echo "\nStatus::tryFrom('inactive'): " . ($try ? $try->label() : 'null') . "\n";

// Test constant visibility
class VisibilityTest {
    public const PUBLIC = 'public';
    private const PRIVATE = 'private';
    protected const PROTECTED = 'protected';

    public function getPrivate(): string {
        return self::PRIVATE;
    }

    public function getProtected(): string {
        return self::PROTECTED;
    }
}

$vt = new VisibilityTest();
echo "\nVisibilityTest::PUBLIC: " . VisibilityTest::PUBLIC . "\n";
echo "VisibilityTest::getPrivate(): " . $vt->getPrivate() . "\n";
echo "VisibilityTest::getProtected(): " . $vt->getProtected() . "\n";