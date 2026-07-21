<?php
// 极度混搭: 集合类 + 链式调用 + 函数式操作 + 惰性求值模拟 + 比较
echo "=== f021: Collection + Fluent + Functional ===\n";

class Collection {
    private array $items;

    public function __construct(array $items = []) {
        $this->items = $items;
    }

    public static function make(array $items = []): self {
        return new self($items);
    }

    public static function range(int $start, int $end, int $step = 1): self {
        $items = [];
        for ($i = $start; $i <= $end; $i += $step) $items[] = $i;
        return new self($items);
    }

    public function map(callable $fn): self {
        return new self(array_map($fn, $this->items));
    }

    public function filter(callable $fn): self {
        return new self(array_values(array_filter($this->items, $fn)));
    }

    public function reduce(callable $fn, mixed $initial = null): mixed {
        return array_reduce($this->items, $fn, $initial);
    }

    public function each(callable $fn): self {
        foreach ($this->items as $key => $value) $fn($value, $key);
        return $this;
    }

    public function sort(callable $fn): self {
        $items = $this->items;
        usort($items, $fn);
        return new self($items);
    }

    public function sortBy(callable $fn): self {
        return $this->sort(fn($a, $b) => $fn($a) <=> $fn($b));
    }

    public function sortDesc(): self {
        return $this->sort(fn($a, $b) => $b <=> $a);
    }

    public function sortAsc(): self {
        return $this->sort(fn($a, $b) => $a <=> $b);
    }

    public function take(int $n): self {
        if ($n < 0) return new self(array_slice($this->items, $n));
        return new self(array_slice($this->items, 0, $n));
    }

    public function skip(int $n): self {
        return new self(array_slice($this->items, $n));
    }

    public function chunk(int $size): self {
        return new self(array_map(fn($c) => new Collection($c), array_chunk($this->items, $size)));
    }

    public function flatten(): self {
        $result = [];
        array_walk_recursive($this->items, function($v) use (&$result) { $result[] = $v; });
        return new self($result);
    }

    public function unique(): self {
        return new self(array_values(array_unique($this->items)));
    }

    public function reverse(): self {
        return new self(array_reverse($this->items));
    }

    public function concat(array $items): self {
        return new self(array_merge($this->items, $items));
    }

    public function zip(array $items): self {
        $result = [];
        for ($i = 0; $i < min(count($this->items), count($items)); $i++) {
            $result[] = [$this->items[$i], $items[$i]];
        }
        return new self($result);
    }

    public function groupBy(callable $fn): self {
        $groups = [];
        foreach ($this->items as $item) {
            $key = $fn($item);
            if (!isset($groups[$key])) $groups[$key] = [];
            $groups[$key][] = $item;
        }
        return new self($groups);
    }

    public function countBy(callable $fn): array {
        $counts = [];
        foreach ($this->items as $item) {
            $key = $fn($item);
            $counts[$key] = ($counts[$key] ?? 0) + 1;
        }
        return $counts;
    }

    public function first(mixed $default = null): mixed {
        return $this->items[0] ?? $default;
    }

    public function last(mixed $default = null): mixed {
        return $this->items[count($this->items) - 1] ?? $default;
    }

    public function contains(mixed $value): bool {
        return in_array($value, $this->items);
    }

    public function find(callable $fn, mixed $default = null): mixed {
        foreach ($this->items as $item) {
            if ($fn($item)) return $item;
        }
        return $default;
    }

    public function sum(): mixed { return array_sum($this->items); }
    public function avg(): mixed { return empty($this->items) ? 0 : array_sum($this->items) / count($this->items); }
    public function min(): mixed { return min($this->items); }
    public function max(): mixed { return max($this->items); }
    public function count(): int { return count($this->items); }
    public function isEmpty(): bool { return empty($this->items); }

    public function toArray(): array { return $this->items; }

    public function implode(string $glue = ', '): string {
        return implode($glue, $this->items);
    }

    public function toJson(): string { return json_encode($this->items); }
}

// === 测试 ===
echo "--- Basic Operations ---\n";
$c = Collection::range(1, 10);
echo "1-10: " . $c->implode() . "\n";
echo "Sum: " . $c->sum() . "\n";
echo "Avg: " . $c->avg() . "\n";
echo "Min: " . $c->min() . "\n";
echo "Max: " . $c->max() . "\n";
echo "Count: " . $c->count() . "\n";

echo "\n--- Chained Operations ---\n";
$result = Collection::range(1, 20)
    ->map(fn($x) => $x * $x)
    ->filter(fn($x) => $x % 2 === 1)
    ->take(5)
    ->toArray();
echo "Squares, odd, take 5: " . implode(', ', $result) . "\n";

$result2 = Collection::make([3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5])
    ->unique()
    ->sortAsc()
    ->toArray();
echo "Unique sorted: " . implode(', ', $result2) . "\n";

echo "\n--- GroupBy ---\n";
$people = [
    ['name' => 'Alice', 'dept' => 'Engineering'],
    ['name' => 'Bob', 'dept' => 'Sales'],
    ['name' => 'Charlie', 'dept' => 'Engineering'],
    ['name' => 'Dave', 'dept' => 'Sales'],
    ['name' => 'Eve', 'dept' => 'Engineering'],
];
$grouped = Collection::make($people)->groupBy(fn($p) => $p['dept']);
foreach ($grouped->toArray() as $dept => $members) {
    $names = array_map(fn($m) => $m['name'], $members);
    echo "  $dept: " . implode(', ', $names) . "\n";
}

echo "\n--- Chunk & Zip ---\n";
$chunks = Collection::range(1, 10)->chunk(3);
foreach ($chunks->toArray() as $i => $chunk) {
    if ($chunk instanceof Collection) {
        echo "  chunk[$i]: " . $chunk->implode() . "\n";
    }
}

$zipped = Collection::make(['a', 'b', 'c'])->zip([1, 2, 3]);
foreach ($zipped->toArray() as $pair) {
    echo "  $pair[0]=$pair[1]\n";
}

echo "\n--- Stats ---\n";
$scores = Collection::make([85, 90, 78, 92, 88, 95, 82, 89, 91, 87]);
echo "Scores: " . $scores->implode() . "\n";
echo "Passing (>=85): " . $scores->filter(fn($s) => $s >= 85)->count() . "\n";
echo "Top 3: " . $scores->sortDesc()->take(3)->implode() . "\n";
echo "Bottom 3: " . $scores->sortAsc()->take(3)->implode() . "\n";
echo "Average: " . number_format($scores->avg(), 1) . "\n";

echo "\n--- CountBy ---\n";
$words = Collection::make(['apple', 'banana', 'apple', 'cherry', 'banana', 'apple']);
$counts = $words->countBy(fn($w) => $w);
echo "Word counts: " . json_encode($counts) . "\n";

echo "\n--- Find & Contains ---\n";
$nums = Collection::range(1, 100);
echo "Contains 50: " . var_export($nums->contains(50), true) . "\n";
echo "Contains 101: " . var_export($nums->contains(101), true) . "\n";
echo "Find first > 50: " . $nums->find(fn($x) => $x > 50) . "\n";
echo "First: " . $nums->first() . "\n";
echo "Last: " . $nums->last() . "\n";

echo "=== f021 Done ===\n";
