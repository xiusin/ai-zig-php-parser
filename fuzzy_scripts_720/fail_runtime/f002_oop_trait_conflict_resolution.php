<?php
// 极度混搭: interface多实现 + 排序 + 验证 + 序列化 + 比较 + 闭包规则
echo "=== f002: Multi-Interface + Sort + Validate + Serialize ===\n";

interface Comparable {
    public function compareTo(object $other): int;
}

interface Serializable2 {
    public function toArray(): array;
    public function fromArray(array $data): void;
}

interface Countable2 {
    public function count2(): int;
}

class Product implements Comparable, Serializable2, Countable2 {
    private array $container = [];
    private array $rules = [];

    public function __construct(
        public readonly int $id,
        public string $name,
        public float $price,
        public int $stock = 0
    ) {
        $this->addRule('name', fn($v) => empty($v) ? 'Name required' : true);
        $this->addRule('price', fn($v) => $v < 0 ? 'Price must be non-negative' : true);
        $this->addRule('stock', fn($v) => $v < 0 ? 'Stock must be non-negative' : true);
    }

    public static function sort(array &$items): void {
        usort($items, fn($a, $b) => $a->compareTo($b));
    }

    public function setTag(string $key, mixed $value): void {
        $this->container[$key] = $value;
    }

    public function getTag(string $key): mixed {
        return $this->container[$key] ?? null;
    }

    public function hasTag(string $key): bool {
        return isset($this->container[$key]);
    }

    protected function addRule(string $field, callable $rule): void {
        $this->rules[$field][] = $rule;
    }

    public function validate(array $data): array {
        $errors = [];
        foreach ($this->rules as $field => $fieldRules) {
            $value = $data[$field] ?? null;
            foreach ($fieldRules as $rule) {
                $result = $rule($value);
                if ($result !== true) {
                    $errors[$field][] = $result;
                }
            }
        }
        return $errors;
    }

    public function compareTo(object $other): int {
        if (!$other instanceof Product) throw new InvalidArgumentException("Not a Product");
        return $this->price <=> $other->price;
    }

    public function toArray(): array {
        return ['id' => $this->id, 'name' => $this->name, 'price' => $this->price, 'stock' => $this->stock];
    }

    public function fromArray(array $data): void {
        $this->name = $data['name'] ?? $this->name;
        $this->price = $data['price'] ?? $this->price;
        $this->stock = $data['stock'] ?? $this->stock;
    }

    public function count2(): int {
        return count($this->container);
    }

    public function __toString(): string {
        return sprintf("Product#%d %s \$%.2f stock=%d", $this->id, $this->name, $this->price, $this->stock);
    }
}

// 创建产品
$products = [
    new Product(3, "Widget", 9.99, 100),
    new Product(1, "Gadget", 19.99, 50),
    new Product(2, "Doohickey", 4.99, 200),
    new Product(4, "Gizmo", 14.99, 0),
];

// 排序
Product::sort($products);

echo "Sorted by price:\n";
foreach ($products as $p) {
    echo "  $p\n";
}

// Tag 操作
$p = $products[0];
$p->setTag('tag1', 'electronics');
$p->setTag('tag2', 'sale');
echo "Tags: " . $p->getTag('tag1') . ", " . $p->getTag('tag2') . "\n";
echo "Container count: " . $p->count2() . "\n";
echo "Has tag1: " . var_export($p->hasTag('tag1'), true) . "\n";
echo "Has tag3: " . var_export($p->hasTag('tag3'), true) . "\n";

// 验证
$errors = $p->validate(['name' => '', 'price' => -5, 'stock' => 10]);
echo "Validation errors: " . json_encode($errors) . "\n";

$valid = $p->validate(['name' => 'OK', 'price' => 10, 'stock' => 5]);
echo "Valid (empty errors): " . var_export(empty($valid), true) . "\n";

// 序列化
$arr = $p->toArray();
echo "Array: " . json_encode($arr) . "\n";

$p->fromArray(['name' => 'Updated Widget', 'price' => 12.50]);
echo "After fromArray: $p\n";

// 比较测试
echo "Compare 0 vs 1: " . $products[0]->compareTo($products[1]) . "\n";
echo "Compare 1 vs 0: " . $products[1]->compareTo($products[0]) . "\n";
echo "Compare 0 vs 0: " . $products[0]->compareTo($products[0]) . "\n";

// 异常测试
try {
    $obj = new stdClass();
    $products[0]->compareTo($obj);
} catch (InvalidArgumentException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

echo "=== f002 Done ===\n";
