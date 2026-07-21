<?php
// 极度混搭: 数组函数式管道 + array_map/filter/reduce/walk + 闭包链 + 解构 + 展开
echo "=== f008: Array Functional Pipeline + Destructuring + Spread ===\n";

class Pipeline {
    private array $stages = [];

    public function __construct(private array $data = []) {}

    public function addStage(callable $fn, string $name = ''): self {
        $this->stages[] = ['fn' => $fn, 'name' => $name];
        return $this;
    }

    public function run(): array {
        $data = $this->data;
        foreach ($this->stages as $stage) {
            $data = array_map($stage['fn'], $data);
        }
        return $data;
    }

    public function filter(callable $fn): self {
        $this->data = array_filter($this->data, $fn);
        return $this;
    }

    public function map(callable $fn): self {
        $this->data = array_map($fn, $this->data);
        return $this;
    }

    public function reduce(callable $fn, mixed $initial = null): mixed {
        return array_reduce($this->data, $fn, $initial);
    }

    public function sort(callable $fn): self {
        usort($this->data, $fn);
        return $this;
    }

    public function slice(int $offset, ?int $len = null): self {
        $this->data = array_slice($this->data, $offset, $len);
        return $this;
    }

    public function get(): array { return $this->data; }

    public function count(): int { return count($this->data); }
}

// 数据集
$numbers = range(1, 20);
echo "Original: " . implode(',', $numbers) . "\n";

// 管道操作
$result = (new Pipeline($numbers))
    ->map(fn($x) => $x * 2)
    ->filter(fn($x) => $x % 3 === 0)
    ->sort(fn($a, $b) => $b <=> $a)
    ->get();

echo "Pipeline (x2, filter%3, sort desc): " . implode(',', $result) . "\n";

// reduce
$sum = (new Pipeline(range(1, 10)))
    ->reduce(fn($carry, $item) => $carry + $item, 0);
echo "Sum 1-10: $sum\n";

$product = (new Pipeline(range(1, 5)))
    ->reduce(fn($carry, $item) => $carry * $item, 1);
echo "Product 1-5: $product\n";

// array_walk 测试
$data = ['name' => 'Alice', 'age' => 30, 'city' => 'NYC'];
array_walk($data, function(&$value, $key) {
    $value = strtoupper((string)$value);
});
echo "After walk: " . json_encode($data) . "\n";

// array_map 多数组
$a = [1, 2, 3];
$b = [10, 20, 30];
$c = array_map(fn($x, $y) => $x + $y, $a, $b);
echo "Multi-map: " . implode(',', $c) . "\n";

// 数组解构
$person = ['Alice', 30, 'NYC', ['Python', 'PHP', 'Go']];
[$name, $age, $city, $languages] = $person;
echo "Destructured: name=$name, age=$age, city=$city\n";
echo "Languages: " . implode(', ', $languages) . "\n";

// 关联数组解构
$user = ['name' => 'Bob', 'role' => 'admin', 'id' => 42];
['name' => $userName, 'role' => $userRole] = $user;
echo "Assoc destructured: name=$userName, role=$userRole\n";

// spread 操作
function sumAll(int ...$nums): int {
    return array_sum($nums);
}

$args = [1, 2, 3, 4, 5];
echo "sumAll(...[1,2,3,4,5]): " . sumAll(...$args) . "\n";

// 数组展开
$arr1 = [1, 2, 3];
$arr2 = [4, 5, 6];
$merged = [...$arr1, ...$arr2, 7, 8];
echo "Spread merge: " . implode(',', $merged) . "\n";

// 关联数组展开
$defaults = ['host' => 'localhost', 'port' => 3306, 'timeout' => 30];
$custom = ['port' => 5432, 'ssl' => true];
$config = [...$defaults, ...$custom];
echo "Assoc spread: " . json_encode($config) . "\n";

// 复杂分组
$transactions = [
    ['type' => 'income', 'amount' => 1000, 'category' => 'salary'],
    ['type' => 'expense', 'amount' => 200, 'category' => 'food'],
    ['type' => 'income', 'amount' => 500, 'category' => 'bonus'],
    ['type' => 'expense', 'amount' => 100, 'category' => 'transport'],
    ['type' => 'expense', 'amount' => 300, 'category' => 'food'],
    ['type' => 'income', 'amount' => 200, 'category' => 'salary'],
];

$grouped = array_reduce($transactions, function($acc, $t) {
    $type = $t['type'];
    if (!isset($acc[$type])) $acc[$type] = [];
    $acc[$type][] = $t;
    return $acc;
}, []);

$byCategory = array_reduce($transactions, function($acc, $t) {
    $cat = $t['category'];
    if (!isset($acc[$cat])) $acc[$cat] = 0;
    $acc[$cat] += $t['amount'];
    return $acc;
}, []);

echo "\nGrouped by type:\n";
foreach ($grouped as $type => $items) {
    $total = array_sum(array_column($items, 'amount'));
    echo "  $type: " . count($items) . " transactions, total=$total\n";
}

echo "By category:\n";
arsort($byCategory);
foreach ($byCategory as $cat => $total) {
    echo "  $cat: $total\n";
}

// array_chunk
$chunked = array_chunk(range(1, 10), 3);
echo "\nChunked (size=3):\n";
foreach ($chunked as $i => $chunk) {
    echo "  chunk[$i]: " . implode(',', $chunk) . "\n";
}

// array_column
$records = [
    ['id' => 1, 'name' => 'Alice', 'score' => 85],
    ['id' => 2, 'name' => 'Bob', 'score' => 92],
    ['id' => 3, 'name' => 'Charlie', 'score' => 78],
];
$names = array_column($records, 'name', 'id');
echo "Column (name, keyed by id): " . json_encode($names) . "\n";

echo "=== f008 Done ===\n";
