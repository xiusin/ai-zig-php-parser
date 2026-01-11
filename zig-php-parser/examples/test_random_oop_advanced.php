<?php
/**
 * 高级OOP特性测试 - PHP语法版
 * 测试：多态、接口、Trait、抽象类、晚期静态绑定
 */

// 接口定义
interface LoggerInterface {
    public function logMessage(string $message): void;
    public function countLogs(): int;
}

interface NamedEntity {
    public function getName(): string;
    public function setName(string $name): void;
}

// Trait 定义
trait LoggableTrait {
    private array $logs = [];

    public function logMessage(string $message): void {
        $this->logs[] = date("Y-m-d H:i:s") . ": " . $message;
    }

    public function getLogs(): array {
        return $this->logs;
    }

    public function countLogs(): int {
        return count($this->logs);
    }

    public function clearLogs(): void {
        $this->logs = [];
    }
}

// 抽象基类
abstract class BaseEntity implements NamedEntity {
    protected string $name;
    protected string $createdAt;

    public function __construct(string $name) {
        $this->name = $name;
        $this->createdAt = date("Y-m-d H:i:s");
    }

    public function getName(): string {
        return $this->name;
    }

    public function setName(string $name): void {
        $this->name = $name;
    }

    public function getCreatedAt(): string {
        return $this->createdAt;
    }

    abstract public function getType(): string;
}

// 具体实现类
class User extends BaseEntity implements LoggerInterface {
    use LoggableTrait;

    private string $email;
    private array $roles;

    public function __construct(string $name, string $email) {
        parent::__construct($name);
        $this->email = $email;
        $this->roles = ["user"];
    }

    public function getEmail(): string {
        return $this->email;
    }

    public function setEmail(string $email): void {
        $this->email = $email;
    }

    public function addRole(string $role): void {
        if (!in_array($role, $this->roles)) {
            $this->roles[] = $role;
        }
    }

    public function getRoles(): array {
        return $this->roles;
    }

    public function getType(): string {
        return "user";
    }

    public function getName(): string {
        return "User: " . $this->name;
    }
}

class Product extends BaseEntity implements LoggerInterface {
    use LoggableTrait;

    private float $price;
    private int $stock;

    public function __construct(string $name, float $price) {
        parent::__construct($name);
        $this->price = $price;
        $this->stock = 0;
    }

    public function getPrice(): float {
        return $this->price;
    }

    public function setPrice(float $price): void {
        $this->price = $price;
    }

    public function getStock(): int {
        return $this->stock;
    }

    public function addStock(int $amount): void {
        $this->stock += $amount;
    }

    public function getType(): string {
        return "product";
    }
}

// 晚期静态绑定测试
class Registry {
    protected static array $items = [];

    public static function register(string $key, $item): void {
        self::$items[$key] = $item;
    }

    public static function get(string $key) {
        return self::$items[$key] ?? null;
    }

    public static function getAll(): array {
        return self::$items;
    }

    public static function clear(): void {
        self::$items = [];
    }

    public static function getCount(): int {
        return count(self::$items);
    }
}

class UserRegistry extends Registry {
    public static function registerUser($user): void {
        self::register($user->getName(), $user);
    }

    public static function getUser(string $name) {
        return self::get($name);
    }
}

// 执行测试
echo "=== Advanced OOP Test ===\n\n";

// 测试多态
$entities = [
    new User("Alice", "alice@example.com"),
    new Product("Laptop", 999.99),
    new User("Bob", "bob@example.com"),
    new Product("Mouse", 29.99),
];

echo "1. Polymorphism Test:\n";
foreach ($entities as $entity) {
    $type = $entity->getType();
    $name = $entity->getName();
    echo "   - $type: $name\n";
}

// 测试接口
echo "\n2. Logger Interface Test:\n";
$loggable = $entities[0];
$loggable->logMessage("User logged in");
$loggable->logMessage("User viewed dashboard");
echo "   Logs count: " . $loggable->countLogs() . "\n";

// 测试 Trait
echo "\n3. Trait Test:\n";
$product = $entities[1];
$product->logMessage("Stock updated");
$product->logMessage("Price changed");
echo "   Product logs: " . $product->countLogs() . "\n";

// 测试晚期静态绑定
echo "\n4. Late Static Binding Test:\n";
UserRegistry::registerUser($entities[0]);
UserRegistry::registerUser($entities[2]);
echo "   Registered users: " . UserRegistry::getCount() . "\n";

// 测试继承和方法重写
echo "\n5. Inheritance Test:\n";
$user = $entities[0];
echo "   User name (overridden): " . $user->getName() . "\n";
echo "   User type: " . $user->getType() . "\n";

// 测试数组集合操作
echo "\n6. Collection Operations:\n";
$users = [];
$products = [];
foreach ($entities as $entity) {
    if ($entity instanceof User) {
        $users[] = $entity;
    } else {
        $products[] = $entity;
    }
}
echo "   Users count: " . count($users) . "\n";
echo "   Products count: " . count($products) . "\n";

// 测试排序
usort($entities, function($a, $b) {
    return strcmp($a->getName(), $b->getName());
});
echo "\n7. Sorted by name:\n";
foreach ($entities as $entity) {
    echo "   - " . $entity->getName() . "\n";
}

echo "\n=== Test Complete ===\n";
