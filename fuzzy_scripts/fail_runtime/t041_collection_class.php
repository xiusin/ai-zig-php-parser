<?php
// 集合类：数组包装、链式操作、迭代器模式

class Collection implements IteratorAggregate, Countable {
    private array $items;

    public function __construct(array $items = []) {
        $this->items = $items;
    }

    public function getIterator(): Iterator {
        return new ArrayIterator($this->items);
    }

    public function count(): int {
        return count($this->items);
    }

    public function all(): array {
        return $this->items;
    }

    public function keys(): array {
        return array_keys($this->items);
    }

    public function values(): array {
        return array_values($this->items);
    }

    public function first(mixed $default = null): mixed {
        return count($this->items) > 0 ? $this->items[array_key_first($this->items)] : $default;
    }

    public function last(mixed $default = null): mixed {
        return count($this->items) > 0 ? $this->items[array_key_last($this->items)] : $default;
    }

    public function push(mixed $value): self {
        $this->items[] = $value;
        return $this;
    }

    public function map(callable $fn): self {
        return new self(array_map($fn, $this->items));
    }

    public function filter(?callable $fn = null): self {
        if ($fn === null) {
            return new self(array_filter($this->items));
        }
        return new self(array_filter($this->items, $fn));
    }

    public function reduce(callable $fn, mixed $initial = null): mixed {
        return array_reduce($this->items, $fn, $initial);
    }

    public function each(callable $fn): self {
        foreach ($this->items as $key => $value) {
            $fn($value, $key);
        }
        return $this;
    }

    public function sort(?callable $fn = null): self {
        $items = $this->items;
        if ($fn === null) {
            sort($items);
        } else {
            usort($items, $fn);
        }
        return new self($items);
    }

    public function reverse(): self {
        return new self(array_reverse($this->items));
    }

    public function slice(int $offset, ?int $length = null): self {
        return new self(array_slice($this->items, $offset, $length));
    }

    public function merge(self $other): self {
        return new self(array_merge($this->items, $other->all()));
    }

    public function contains(mixed $value): bool {
        return in_array($value, $this->items, true);
    }

    public function sum(): int|float {
        return array_sum($this->items);
    }

    public function avg(): int|float|null {
        $count = count($this->items);
        if ($count === 0) return null;
        return array_sum($this->items) / $count;
    }

    public function min(): mixed {
        return count($this->items) > 0 ? min($this->items) : null;
    }

    public function max(): mixed {
        return count($this->items) > 0 ? max($this->items) : null;
    }

    public function implode(string $glue = ','): string {
        return implode($glue, $this->items);
    }

    public function chunk(int $size): array {
        return array_chunk($this->items, $size);
    }

    public function pluck(string $key): self {
        $result = [];
        foreach ($this->items as $item) {
            if (is_array($item) && isset($item[$key])) {
                $result[] = $item[$key];
            }
        }
        return new self($result);
    }
}

// 测试基本操作
$col = new Collection([1, 2, 3, 4, 5]);
echo "count: " . $col->count() . "\n";
echo "first: " . $col->first() . "\n";
echo "last: " . $col->last() . "\n";
echo "sum: " . $col->sum() . "\n";
echo "avg: " . $col->avg() . "\n";
echo "min: " . $col->min() . "\n";
echo "max: " . $col->max() . "\n";
echo "implode: " . $col->implode() . "\n";

// 测试 map
$doubled = $col->map(fn($x) => $x * 2);
echo "map: " . $doubled->implode() . "\n";

// 测试 filter
$evens = $col->filter(fn($x) => $x % 2 === 0);
echo "filter: " . $evens->implode() . "\n";

// 测试 reduce
$product = $col->reduce(fn($carry, $item) => $carry * $item, 1);
echo "reduce: " . $product . "\n";

// 测试 sort
$unsorted = new Collection([3, 1, 4, 1, 5, 9, 2, 6]);
echo "sort: " . $unsorted->sort()->implode() . "\n";

// 测试 reverse
echo "reverse: " . $col->reverse()->implode() . "\n";

// 测试 slice
echo "slice: " . $col->slice(1, 3)->implode() . "\n";

// 测试 contains
echo "contains_3: " . ($col->contains(3) ? 'true' : 'false') . "\n";
echo "contains_10: " . ($col->contains(10) ? 'true' : 'false') . "\n";

// 测试 pluck
$users = new Collection([
    ['name' => 'Alice', 'age' => 30],
    ['name' => 'Bob', 'age' => 25],
    ['name' => 'Charlie', 'age' => 35],
]);
echo "pluck_names: " . $users->pluck('name')->implode() . "\n";
echo "pluck_ages: " . $users->pluck('age')->implode() . "\n";

// 测试 merge
$c1 = new Collection([1, 2, 3]);
$c2 = new Collection([4, 5, 6]);
echo "merge: " . $c1->merge($c2)->implode() . "\n";

// 测试 chunk
$chunked = $col->chunk(2);
echo "chunk_count: " . count($chunked) . "\n";

// 测试链式调用
$result = (new Collection([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
    ->filter(fn($x) => $x % 2 === 0)
    ->map(fn($x) => $x * 10)
    ->sort()
    ->implode();
echo "chain: " . $result . "\n";
