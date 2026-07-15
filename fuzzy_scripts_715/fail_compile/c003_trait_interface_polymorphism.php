<?php
// 极度混搭: Trait组合 + 接口多态 + 抽象类 + 静态绑定 + 异常层级
echo "=== c003: Trait + Interface + Abstract + Static Binding ===\n\n";

interface Comparable {
    public function compareTo(mixed $other): int;
}

interface StringRepresentable {
    public function __toString(): string;
}

interface Hashable {
    public function hash(): int;
}

trait Sortable {
    public static function sort(array &$items): void {
        usort($items, fn($a, $b) => $a->compareTo($b));
    }
}

trait CounterTrait {
    private static int $count = 0;

    public static function getCount(): int {
        return self::$count;
    }

    protected static function incrementCount(): void {
        self::$count++;
    }
}

abstract class Entity implements Comparable, StringRepresentable, Hashable {
    use CounterTrait;

    public function __construct(
        public readonly int $id,
        public readonly string $name
    ) {
        static::incrementCount();
    }

    abstract public function hash(): int;

    public function compareTo(mixed $other): int {
        if (!($other instanceof Entity)) {
            throw new TypeError("Cannot compare Entity with " . get_class($other));
        }
        return $this->id <=> $other->id;
    }

    public function __toString(): string {
        return static::class . "#{$this->id}({$this->name})";
    }
}

final class Product extends Entity {
    use Sortable;

    private float $price;
    private array $tags = [];

    public function __construct(int $id, string $name, float $price) {
        parent::__construct($id, $name);
        $this->price = $price;
    }

    public function hash(): int {
        return crc32($this->name . $this->id);
    }

    public function getPrice(): float {
        return $this->price;
    }

    public function addTag(string ...$tags): self {
        foreach ($tags as $tag) {
            $this->tags[] = strtolower($tag);
        }
        return $this;
    }

    public function getTags(): array {
        return array_unique($this->tags);
    }
}

final class User extends Entity {
    use Sortable;

    private array $permissions = [];

    public function __construct(int $id, string $name) {
        parent::__construct($id, $name);
    }

    public function hash(): int {
        return abs(crc32($this->name)) % 1000;
    }

    public function grant(string ...$perms): self {
        $this->permissions = array_unique(array_merge($this->permissions, $perms));
        return $this;
    }

    public function can(string $perm): bool {
        return in_array($perm, $this->permissions);
    }
}

// === 测试 ===

$products = [
    new Product(3, "Laptop", 1200.50),
    new Product(1, "Mouse", 25.99),
    new Product(2, "Keyboard", 75.00),
    new Product(5, "Monitor", 300.00),
    new Product(4, "Headset", 150.00),
];

$products[0]->addTag("electronics", "computing", "portable");
$products[1]->addTag("accessory", "computing");
$products[2]->addTag("accessory", "computing", "mechanical");

echo "Before sort:\n";
foreach ($products as $p) {
    echo "  $p\n";
}

Product::sort($products);

echo "\nAfter sort:\n";
foreach ($products as $p) {
    echo "  $p tags=[" . implode(",", $p->getTags()) . "]\n";
}

$users = [
    (new User(101, "Alice"))->grant("read", "write"),
    (new User(102, "Bob"))->grant("read"),
    (new User(103, "Charlie"))->grant("read", "write", "admin"),
];

User::sort($users);

echo "\nUsers:\n";
foreach ($users as $u) {
    echo "  $u can_admin=" . var_export($u->can("admin"), true) . "\n";
}

echo "\nEntity count: " . Entity::getCount() . "\n";

// 多态比较
$entityA = new Product(10, "A", 100);
$entityB = new User(10, "UserA");
try {
    $cmp = $entityA->compareTo($entityB);
    echo "Cross-type compare: $cmp\n";
} catch (TypeError $e) {
    echo "Cross-type error: " . $e->getMessage() . "\n";
}

// Hash 测试
echo "Product hash: " . $products[0]->hash() . "\n";
echo "User hash: " . $users[0]->hash() . "\n";

// instanceof + interface polymorphism
$entities = [$products[0], $users[0]];
foreach ($entities as $e) {
    echo match(true) {
        $e instanceof Product => "Product: {$e->getPrice()}\n",
        $e instanceof User => "User: " . ($e->can("read") ? "reader" : "no-access") . "\n",
        default => "Unknown\n",
    };
}

echo "\n=== c003 Done ===\n";
