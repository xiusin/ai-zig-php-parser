<?php
// 只读属性测试 (PHP 8.1+)

// 单个只读属性
class User {
    public function __construct(
        public readonly int $id,
        public readonly string $name,
        public string $email // 可修改
    ) {}
}

$user = new User(1, 'Alice', 'alice@example.com');
echo "User: {$user->name} <{$user->email}>\n";

$user->email = 'alice.new@example.com';
echo "Updated email: {$user->email}\n";

// 尝试修改只读属性会报错（注释掉以允许脚本继续）
// $user->id = 2; // Error: Cannot modify readonly property

// 完全只读类 (PHP 8.2+)
readonly class Point {
    public function __construct(
        public float $x,
        public float $y,
        public float $z = 0.0
    ) {}

    public function distance(Point $other): float {
        return sqrt(
            pow($this->x - $other->x, 2) +
            pow($this->y - $other->y, 2) +
            pow($this->z - $other->z, 2)
        );
    }

    public function withX(float $x): self {
        return new self($x, $this->y, $this->z);
    }
}

$p1 = new Point(0, 0, 0);
$p2 = new Point(3, 4, 0);
echo "Distance: " . $p1->distance($p2) . "\n";

$p3 = $p2->withX(5);
echo "New point x: {$p3->x}\n";

// 只读属性与继承
class Entity {
    public function __construct(
        public readonly string $id,
        public readonly \DateTimeImmutable $createdAt
    ) {}
}

class Product extends Entity {
    public function __construct(
        string $id,
        \DateTimeImmutable $createdAt,
        public readonly string $name,
        public readonly float $price
    ) {
        parent::__construct($id, $createdAt);
    }
}

$product = new Product(
    'prod-001',
    new \DateTimeImmutable('2024-01-01'),
    'Widget',
    19.99
);
echo "Product: {$product->name} costs \${$product->price}\n";

// 只读属性与复杂类型
class Configuration {
    public function __construct(
        public readonly array $settings,
        public readonly ?string $env = null
    ) {}

    public function get(string $key, mixed $default = null): mixed {
        return $this->settings[$key] ?? $default;
    }
}

$config = new Configuration(
    ['debug' => true, 'cache' => false, 'timeout' => 30],
    'production'
);
echo "Debug: " . var_export($config->get('debug'), true) . "\n";
echo "Missing: " . var_export($config->get('missing', 'default'), true) . "\n";

// 只读属性与clone
class ImmutableCollection {
    public function __construct(
        public readonly array $items
    ) {}

    public function add(mixed $item): self {
        return new self([...$this->items, $item]);
    }

    public function count(): int {
        return count($this->items);
    }
}

$col1 = new ImmutableCollection([1, 2, 3]);
$col2 = $col1->add(4);
echo "Col1 count: " . $col1->count() . "\n";
echo "Col2 count: " . $col2->count() . "\n";

// 只读属性初始化检查
class DelayedInit {
    public readonly string $value;

    public function init(string $value): void {
        // 只能初始化一次
        if (!isset($this->value)) {
            $this->value = $value;
        }
    }
}

$delayed = new DelayedInit();
$delayed->init('initialized');
echo "Delayed: {$delayed->value}\n";

// 只读与引用类型
class Container {
    public function __construct(
        public readonly ?object $content
    ) {}
}

$container = new Container(new class { public $data = 'test'; });
echo "Container content exists: " . var_export($container->content !== null, true) . "\n";

$emptyContainer = new Container(null);
echo "Empty container: " . var_export($emptyContainer->content === null, true) . "\n";

echo "Readonly properties tests completed\n";
