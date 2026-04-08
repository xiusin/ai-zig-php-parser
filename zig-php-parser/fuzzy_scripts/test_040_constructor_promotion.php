<?php
// 构造器属性提升测试 (PHP 8.0+)

// 基础构造器提升
class User {
    public function __construct(
        public string $name,
        public int $age,
        protected string $email,
        private string $password
    ) {}

    public function getInfo(): string {
        return "Name: {$this->name}, Age: {$this->age}";
    }

    public function getEmail(): string {
        return $this->email;
    }

    public function getPassword(): string {
        return $this->password;
    }
}

$user = new User('Alice', 25, 'alice@example.com', 'secret');
echo $user->getInfo() . "\n";
echo "Email: " . $user->getEmail() . "\n";
echo "Password: " . $user->getPassword() . "\n";

// 带默认值
class Configuration {
    public function __construct(
        public string $env = 'development',
        public bool $debug = false,
        public int $timeout = 30
    ) {}
}

$config = new Configuration();
echo "Default env: " . $config->env . "\n";
echo "Default debug: " . var_export($config->debug, true) . "\n";
echo "Default timeout: " . $config->timeout . "\n";

$config2 = new Configuration(env: 'production', debug: true);
echo "Custom env: " . $config2->env . "\n";

// 只读属性(PHP 8.1+)
class ImmutablePoint {
    public function __construct(
        public readonly float $x,
        public readonly float $y
    ) {}

    public function distance(ImmutablePoint $other): float {
        return sqrt(pow($this->x - $other->x, 2) + pow($this->y - $other->y, 2));
    }
}

$p1 = new ImmutablePoint(0, 0);
$p2 = new ImmutablePoint(3, 4);
echo "Distance: " . $p1->distance($p2) . "\n";

// 继承
class BaseEntity {
    public function __construct(
        public int $id,
        public string $createdAt
    ) {}
}

class Product extends BaseEntity {
    public function __construct(
        int $id,
        string $createdAt,
        public string $name,
        public float $price
    ) {
        parent::__construct($id, $createdAt);
    }
}

$product = new Product(1, '2024-01-01', 'Widget', 9.99);
echo "Product: {$product->name} costs \${$product->price}\n";

// 复杂类型
class Order {
    public function __construct(
        public int $id,
        public array $items,
        public ?string $notes = null
    ) {}

    public function getTotal(): float {
        return array_sum(array_column($this->items, 'price'));
    }
}

$order = new Order(1, [
    ['name' => 'Item 1', 'price' => 10.0],
    ['name' => 'Item 2', 'price' => 20.0],
    ['name' => 'Item 3', 'price' => 30.0]
], 'Express delivery');

echo "Order total: " . $order->getTotal() . "\n";
echo "Order notes: " . $order->notes . "\n";

// 接口实现
interface Identifiable {
    public function getId(): int;
}

class Entity implements Identifiable {
    public function __construct(
        private int $id,
        public string $name
    ) {}

    public function getId(): int {
        return $this->id;
    }
}

$entity = new Entity(42, 'Test Entity');
echo "Entity ID: " . $entity->getId() . "\n";
echo "Entity name: " . $entity->name . "\n";

// Trait中使用
trait Timestampable {
    public function __construct(
        public string $createdAt,
        public ?string $updatedAt = null
    ) {}
}

class Article {
    use Timestampable;

    public function __construct(
        string $createdAt,
        ?string $updatedAt,
        public string $title,
        public string $content
    ) {
        // 手动调用trait的构造不适用，这里演示属性
        $this->createdAt = $createdAt;
        $this->updatedAt = $updatedAt;
    }
}

$article = new Article('2024-01-15', null, 'Hello', 'World');
echo "Article title: " . $article->title . "\n";

echo "Constructor promotion tests completed\n";
