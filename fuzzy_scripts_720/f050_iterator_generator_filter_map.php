<?php
// 极度混搭: 迭代器模式 + 生成器模拟 + 过滤器迭代器 + 映射迭代器 + 无限序列
echo "=== f050: Iterator + Generator + Filter + Map ===\n";

class RangeIterator implements \Iterator {
    private int $current;
    private int $key = 0;

    public function __construct(
        private int $start,
        private int $end,
        private int $step = 1
    ) {
        $this->current = $start;
    }

    public function current(): mixed { return $this->current; }
    public function key(): mixed { return $this->key; }
    public function next(): void { $this->current += $this->step; $this->key++; }
    public function rewind(): void { $this->current = $this->start; $this->key = 0; }
    public function valid(): bool { return $this->current <= $this->end; }
}

class MapIterator extends \IteratorIterator {
    private $fn;

    public function __construct(\Traversable $inner, callable $fn) {
        parent::__construct($inner);
        $this->fn = $fn;
    }

    public function current(): mixed {
        return ($this->fn)(parent::current());
    }
}

class FilterIterator extends \FilterIterator {
    private $fn;

    public function __construct(\Iterator $inner, callable $fn) {
        parent::__construct($inner);
        $this->fn = $fn;
    }

    public function accept(): bool {
        return ($this->fn)($this->getInnerIterator()->current());
    }
}

class TakeIterator implements \Iterator {
    private int $taken = 0;
    private int $key = 0;

    public function __construct(
        private \Iterator $inner,
        private int $limit
    ) {}

    public function current(): mixed { return $this->inner->current(); }
    public function key(): mixed { return $this->key; }
    public function next(): void { $this->inner->next(); $this->taken++; $this->key++; }
    public function rewind(): void { $this->inner->rewind(); $this->taken = 0; $this->key = 0; }
    public function valid(): bool { return $this->taken < $this->limit && $this->inner->valid(); }
}

class ZipIterator implements \Iterator {
    private int $key = 0;

    public function __construct(private \Iterator $a, private \Iterator $b) {}

    public function current(): mixed { return [$this->a->current(), $this->b->current()]; }
    public function key(): mixed { return $this->key; }
    public function next(): void { $this->a->next(); $this->b->next(); $this->key++; }
    public function rewind(): void { $this->a->rewind(); $this->b->rewind(); $this->key = 0; }
    public function valid(): bool { return $this->a->valid() && $this->b->valid(); }
}

class CycleIterator implements \Iterator {
    private int $key = 0;

    public function __construct(private array $items) {}

    public function current(): mixed { return $this->items[$this->key % count($this->items)]; }
    public function key(): mixed { return $this->key; }
    public function next(): void { $this->key++; }
    public function rewind(): void { $this->key = 0; }
    public function valid(): bool { return true; } // 无限
}

// 测试
echo "--- RangeIterator ---\n";
$range = new RangeIterator(1, 10, 2);
foreach ($range as $k => $v) echo "  [$k] $v\n";

echo "\n--- MapIterator ---\n";
$range2 = new RangeIterator(1, 5);
$squared = new MapIterator($range2, fn($x) => $x * $x);
foreach ($squared as $k => $v) echo "  [$k] $v\n";

echo "\n--- FilterIterator ---\n";
$range3 = new RangeIterator(1, 20);
$evens = new FilterIterator($range3, fn($x) => $x % 2 === 0);
foreach ($evens as $k => $v) echo "  [$k] $v\n";

echo "\n--- TakeIterator (take 5 from filter) ---\n";
$range4 = new RangeIterator(1, 100);
$evenFilter = new FilterIterator($range4, fn($x) => $x % 3 === 0);
$take5 = new TakeIterator($evenFilter, 5);
foreach ($take5 as $k => $v) echo "  [$k] $v\n";

echo "\n--- ZipIterator ---\n";
$names = new RangeIterator(1, 3);
$values = new RangeIterator(10, 12);
$zip = new ZipIterator($names, $values);
foreach ($zip as $k => $v) echo "  [$k] $v[0]=$v[1]\n";

echo "\n--- Chain: Map → Filter → Take ---\n";
$r = new RangeIterator(1, 50);
$mapped = new MapIterator($r, fn($x) => $x * $x);
$filtered = new FilterIterator($mapped, fn($x) => $x > 20);
$taken = new TakeIterator($filtered, 5);
$result = [];
foreach ($taken as $v) $result[] = $v;
echo "  Result: " . implode(', ', $result) . "\n";

echo "\n--- CycleIterator (take 7 from cycle) ---\n";
$cycle = new CycleIterator(['A', 'B', 'C']);
$taken2 = new TakeIterator($cycle, 7);
$result2 = [];
foreach ($taken2 as $v) $result2[] = $v;
echo "  Result: " . implode(', ', $result2) . "\n";

echo "\n--- Iterator to Array ---\n";
$range5 = new RangeIterator(1, 5);
$arr = iterator_to_array($range5);
echo "  Array: " . implode(', ', $arr) . "\n";

echo "=== f050 Done ===\n";
