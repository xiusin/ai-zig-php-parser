<?php
// 测试51: 命名参数 (PHP 8.0)
function createUser(string $name, int $age = 0, string $email = '', bool $active = true): array {
    return compact('name', 'age', 'email', 'active');
}

// 按名称传参
$user1 = createUser(name: "Alice", age: 30);
print_r($user1);

$user2 = createUser("Bob", email: "bob@test.com", active: false);
print_r($user2);

// 跳过中间参数
$user3 = createUser(name: "Charlie", active: false);
print_r($user3);

// 与位置参数混合
function mixArgs($a, $b, $c = 'default') {
    return "a=$a, b=$b, c=$c";
}
echo mixArgs("pos1", c: "named", b: "pos2") . "\n";

// 类构造函数
class Product {
    public function __construct(
        public string $name,
        public float $price = 0.0,
        public int $stock = 0
    ) {}
}

$product = new Product(name: "Book", price: 29.99);
echo "Product: {$product->name}, \${$product->price}\n";
?>