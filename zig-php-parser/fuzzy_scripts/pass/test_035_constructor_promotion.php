<?php
// 测试35: 构造函数属性提升 (PHP 8.0)
class User {
    public function __construct(
        public string $name,
        public int $age,
        public ?string $email = null
    ) {}
    
    public function getInfo(): string {
        return "{$this->name}, {$this->age} years old" . ($this->email ? " ({$this->email})" : "");
    }
}

class Product {
    public function __construct(
        private string $name,
        private float $price,
        private int $stock = 0
    ) {}
    
    public function getPrice(): float {
        return $this->price;
    }
    
    public function isAvailable(): bool {
        return $this->stock > 0;
    }
}

$user = new User("Alice", 30, "alice@example.com");
echo $user->getInfo() . "\n";
echo "Name: " . $user->name . "\n";

$product = new Product("Laptop", 999.99, 10);
echo "Price: " . $product->getPrice() . "\n";
echo "Available: " . ($product->isAvailable() ? "yes" : "no") . "\n";

// 只读属性 (PHP 8.1)
class Config {
    public function __construct(
        public readonly string $key,
        public readonly array $values
    ) {}
}

$config = new Config("api_key", ["prod", "dev"]);
echo "Key: " . $config->key . "\n";
// $config->key = "new"; // 错误：只读属性
?>
