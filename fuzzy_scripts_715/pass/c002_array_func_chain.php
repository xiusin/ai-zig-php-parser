<?php
// 极度混搭: 数组函数链式调用 + 闭包 + 递归 + 类型推导 + 位运算
echo "=== c002: Array Chain + Closure + Recursion + BitOps ===\n\n";

class ArrayPipeline {
    private array $data;

    public function __construct(array $data) {
        $this->data = $data;
    }

    public function map(callable $fn): self {
        $this->data = array_map($fn, $this->data);
        return $this;
    }

    public function filter(callable $fn): self {
        $this->data = array_filter($this->data, $fn);
        return $this;
    }

    public function reduce(callable $fn, $initial = 0): mixed {
        return array_reduce($this->data, $fn, $initial);
    }

    public function sort(callable $fn): self {
        usort($this->data, $fn);
        return $this;
    }

    public function slice(int $offset, int $length = 0): self {
        $this->data = $length > 0 ? array_slice($this->data, $offset, $length) : array_slice($this->data, $offset);
        return $this;
    }

    public function chunk(int $size): array {
        return array_chunk($this->data, $size);
    }

    public function unique(): self {
        $this->data = array_unique($this->data);
        return $this;
    }

    public function reverse(): self {
        $this->data = array_reverse($this->data);
        return $this;
    }

    public function flatten(): self {
        $result = [];
        array_walk_recursive($this->data, function($v) use (&$result) {
            $result[] = $v;
        });
        $this->data = $result;
        return $this;
    }

    public function count(): int {
        return count($this->data);
    }

    public function get(): array {
        return $this->data;
    }

    public function implode(string $sep): string {
        return implode($sep, $this->data);
    }
}

// === 测试 ===

// 1. 数字处理管道
$nums = range(1, 20);
$pipeline = new ArrayPipeline($nums);

$sum = $pipeline->filter(fn($x) => $x % 2 == 0)
    ->map(fn($x) => $x * $x)
    ->reduce(fn($carry, $x) => $carry + $x, 0);

echo "Even squares sum: $sum\n";

// 2. 字符串处理管道
$words = ["banana", "apple", "cherry", "date", "elderberry", "fig", "grape"];
$sorted = (new ArrayPipeline($words))
    ->filter(fn($w) => strlen($w) > 4)
    ->sort(fn($a, $b) => strlen($a) <=> strlen($b))
    ->map(fn($w) => strtoupper($w))
    ->implode(" | ");

echo "Long fruits: $sorted\n";

// 3. 位运算与数组混合
$bits = range(0, 15);
$bitwise = (new ArrayPipeline($bits))
    ->map(fn($x) => $x & 0b1010)
    ->unique()
    ->sort(fn($a, $b) => $a <=> $b)
    ->get();

echo "Bitwise AND 0b1010: " . implode(",", $bitwise) . "\n";

// 4. 递归阶乘数组
function factorial(int $n): int {
    return $n <= 1 ? 1 : $n * factorial($n - 1);
}

$facts = (new ArrayPipeline(range(1, 8)))
    ->map(fn($x) => factorial($x))
    ->get();

echo "Factorials: " . implode(",", $facts) . "\n";

// 5. 嵌套数组展平
$nested = [[1, 2, [3, 4]], [5, [6, [7, 8]]], 9];
$flat = (new ArrayPipeline($nested))->flatten()->get();
echo "Flattened: " . implode(",", $flat) . "\n";

// 6. 分块处理
$chunked = (new ArrayPipeline(range(1, 10)))->chunk(3);
foreach ($chunked as $i => $chunk) {
    echo "Chunk $i: [" . implode(",", $chunk) . "]\n";
}

// 7. 复杂reduce: 统计字符频率
$chars = str_split("hello world programming is fun");
$freq = (new ArrayPipeline($chars))
    ->filter(fn($c) => trim($c) !== "")
    ->reduce(function($carry, $c) {
        $c = strtolower($c);
        if (!isset($carry[$c])) $carry[$c] = 0;
        $carry[$c]++;
        return $carry;
    }, []);

ksort($freq);
echo "Char freq: " . json_encode($freq) . "\n";

// 8. 数组运算: 交集/差集
$a = [1, 2, 3, 4, 5, 6];
$b = [3, 4, 5, 6, 7, 8];
$inter = array_values(array_intersect($a, $b));
$diff = array_values(array_diff($a, $b));
echo "Intersection: " . implode(",", $inter) . "\n";
echo "Difference: " . implode(",", $diff) . "\n";

// 9. 多级排序
$people = [
    ['name' => 'Alice', 'age' => 30, 'score' => 85],
    ['name' => 'Bob', 'age' => 25, 'score' => 90],
    ['name' => 'Charlie', 'age' => 30, 'score' => 75],
    ['name' => 'Diana', 'age' => 25, 'score' => 90],
    ['name' => 'Eve', 'age' => 30, 'score' => 85],
];

usort($people, function($a, $b) {
    if ($a['age'] !== $b['age']) return $b['age'] <=> $a['age'];
    if ($a['score'] !== $b['score']) return $b['score'] <=> $a['score'];
    return strcmp($a['name'], $b['name']);
});

foreach ($people as $p) {
    echo "{$p['name']}: age={$p['age']} score={$p['score']}\n";
}

// 10. 数组key-value转换
$keyvals = ['a' => 1, 'b' => 2, 'c' => 3];
$flipped = array_flip($keyvals);
$combined = array_combine(array_keys($keyvals), array_map(fn($v) => $v * 10, array_values($keyvals)));
echo "Flipped: " . json_encode($flipped) . "\n";
echo "Combined: " . json_encode($combined) . "\n";

echo "\n=== c002 Done ===\n";
