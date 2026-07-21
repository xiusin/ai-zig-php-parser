<?php
// 迭代器模式：Iterator 接口、Generator、ArrayAccess、聚合器
echo "=== f156: Iterators + Generators + ArrayAccess ===\n";

// 自定义迭代器
class RangeIterator implements Iterator {
    private int $current;
    private int $start;
    private int $end;
    private int $step;
    private int $key = 0;

    public function __construct(int $start, int $end, int $step = 1) {
        $this->start = $start;
        $this->end = $end;
        $this->step = $step;
        $this->current = $start;
    }

    public function current(): mixed { return $this->current; }
    public function key(): mixed { return $this->key; }
    public function next(): void { $this->current += $this->step; $this->key++; }
    public function rewind(): void { $this->current = $this->start; $this->key = 0; }
    public function valid(): bool { return $this->current <= $this->end; }
}

// 过滤迭代器
class CustomFilterIterator extends IteratorIterator {
    private $callback;

    public function __construct(Iterator $iterator, callable $callback) {
        parent::__construct($iterator);
        $this->callback = $callback;
    }

    public function valid(): bool {
        while (parent::valid()) {
            if (($this->callback)(parent::current())) return true;
            parent::next();
        }
        return false;
    }
}

// 映射迭代器
class MapIterator extends IteratorIterator {
    private $callback;

    public function __construct(Iterator $iterator, callable $callback) {
        parent::__construct($iterator);
        $this->callback = $callback;
    }

    public function current(): mixed {
        return ($this->callback)(parent::current());
    }
}

// ArrayAccess 实现
class TypedArray implements ArrayAccess, IteratorAggregate, Countable {
    private array $items = [];
    private string $type;

    public function __construct(string $type, array $items = []) {
        $this->type = $type;
        foreach ($items as $item) $this[] = $item;
    }

    public function offsetExists(mixed $offset): bool {
        return isset($this->items[$offset]);
    }

    public function offsetGet(mixed $offset): mixed {
        return $this->items[$offset] ?? null;
    }

    public function offsetSet(mixed $offset, mixed $value): void {
        $actualType = match(true) {
            is_int($value) => 'int',
            is_float($value) => 'float',
            is_string($value) => 'string',
            is_bool($value) => 'bool',
            is_array($value) => 'array',
            is_object($value) => get_class($value),
            default => gettype($value),
        };
        if ($actualType !== $this->type && !($value instanceof $this->type)) {
            throw new InvalidArgumentException("Expected {$this->type}, got $actualType");
        }
        if ($offset === null) {
            $this->items[] = $value;
        } else {
            $this->items[$offset] = $value;
        }
    }

    public function offsetUnset(mixed $offset): void {
        unset($this->items[$offset]);
    }

    public function getIterator(): Iterator {
        return new ArrayIterator($this->items);
    }

    public function count(): int {
        return count($this->items);
    }
}

// Generator
function fibonacci(): Generator {
    $a = 0; $b = 1;
    while (true) {
        yield $a;
        [$a, $b] = [$b, $a + $b];
    }
}

function take(Generator $gen, int $n): array {
    $result = [];
    for ($i = 0; $i < $n; $i++) {
        $gen->next();
        if (!$gen->valid()) break;
        $result[] = $gen->current();
    }
    return $result;
}

function naturals(): Generator {
    $n = 1;
    while (true) yield $n++;
}

function filterGen(Generator $gen, callable $fn): Generator {
    foreach ($gen as $value) {
        if ($fn($value)) yield $value;
    }
}

function mapGen(Generator $gen, callable $fn): Generator {
    foreach ($gen as $value) {
        yield $fn($value);
    }
}

// 测试
echo "--- Custom Iterator (Range) ---\n";
$range = new RangeIterator(1, 10, 2);
echo "  Range(1,10,2): ";
foreach ($range as $key => $value) echo "$value ";
echo "\n";

$range2 = new RangeIterator(10, 20, 3);
echo "  Range(10,20,3): ";
foreach ($range2 as $v) echo "$v ";
echo "\n";

echo "\n--- Filter + Map Iterator ---\n";
$data = new ArrayIterator([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
$evens = new CustomFilterIterator($data, fn($n) => $n % 2 === 0);
echo "  Evens: ";
foreach ($evens as $v) echo "$v ";
echo "\n";

$data->rewind();
$squared = new MapIterator(new CustomFilterIterator($data, fn($n) => $n % 2 === 0), fn($n) => $n * $n);
echo "  Even squares: ";
foreach ($squared as $v) echo "$v ";
echo "\n";

echo "\n--- ArrayAccess ---\n";
$ints = new TypedArray('int');
$ints[] = 10;
$ints[] = 20;
$ints[] = 30;
$ints[5] = 50;
echo "  Count: " . count($ints) . "\n";
echo "  [0]={$ints[0]}, [1]={$ints[1]}, [5]={$ints[5]}\n";
echo "  Iterate: ";
foreach ($ints as $v) echo "$v ";
echo "\n";
echo "  Exists [3]: " . (isset($ints[3]) ? 'Y' : 'N') . "\n";
echo "  Exists [5]: " . (isset($ints[5]) ? 'Y' : 'N') . "\n";
unset($ints[1]);
echo "  After unset [1]: count=" . count($ints) . "\n";

echo "\n--- Generator (Fibonacci) ---\n";
$fib = fibonacci();
$first10 = [];
for ($i = 0; $i < 10; $i++) {
    $fib->current();
    $first10[] = $fib->current();
    $fib->next();
}
echo "  Fib(10): " . implode(', ', $first10) . "\n";

echo "\n--- Generator Pipeline ---\n";
$nats = naturals();
$evens = filterGen($nats, fn($n) => $n % 2 === 0);
$squared = mapGen($evens, fn($n) => $n * $n);
echo "  First 5 even squares: ";
$result = [];
foreach ($squared as $v) {
    $result[] = $v;
    if (count($result) >= 5) break;
}
echo implode(', ', $result) . "\n";

echo "\n--- Generator with yield key => value ---\n";
function indexedGen(array $keys, array $values): Generator {
    for ($i = 0; $i < count($keys); $i++) {
        yield $keys[$i] => $values[$i] ?? null;
    }
}
foreach (indexedGen(['a', 'b', 'c'], [1, 2, 3]) as $k => $v) {
    echo "  $k => $v\n";
}

echo "\n--- Generator with send() ---\n";
function accumulator(): Generator {
    $total = 0;
    while (true) {
        $value = yield $total;
        if ($value === null) break;
        $total += $value;
    }
    return $total;
}
$acc = accumulator();
$acc->current();
$acc->send(10);
$acc->send(20);
$acc->send(30);
echo "  After send(10,20,30): " . $acc->current() . "\n";

echo "=== f156 Done ===\n";
