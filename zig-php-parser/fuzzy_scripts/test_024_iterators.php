<?php
// Test 024: Iterator, Generator-like (without yield), and Traversable
class RangeIterator implements Iterator {
    private int $current = 0;
    private int $position = 0;

    public function __construct(
        private int $start,
        private int $end,
        private int $step = 1
    ) {
        $this->current = $start;
    }

    public function current(): mixed {
        return $this->current;
    }

    public function key(): int {
        return $this->position;
    }

    public function next(): void {
        $this->current += $this->step;
        $this->position++;
    }

    public function rewind(): void {
        $this->current = $this->start;
        $this->position = 0;
    }

    public function valid(): bool {
        return $this->current <= $this->end;
    }
}

class ArrayIterator implements Iterator {
    private array $data;
    private int $position = 0;

    public function __construct(array $data) {
        $this->data = $data;
    }

    public function current(): mixed {
        return $this->data[$this->position];
    }

    public function key(): int {
        return $this->position;
    }

    public function next(): void {
        $this->position++;
    }

    public function rewind(): void {
        $this->position = 0;
    }

    public function valid(): bool {
        return isset($this->data[$this->position]);
    }

    public function count(): int {
        return count($this->data);
    }
}

class DirectoryReader implements Iterator {
    private array $files = [];
    private int $position = 0;

    public function __construct(string $path) {
        if (is_dir($path)) {
            $this->files = scandir($path) ?: [];
        }
    }

    public function current(): mixed {
        return $this->files[$this->position] ?? null;
    }

    public function key(): int {
        return $this->position;
    }

    public function next(): void {
        $this->position++;
    }

    public function rewind(): void {
        $this->position = 0;
    }

    public function valid(): bool {
        return isset($this->files[$this->position]);
    }
}

class FilterIterator implements Iterator {
    private array $data;
    private int $position = 0;
    private array $filtered = [];

    public function __construct(array $data, $callback) {
        $this->data = $data;
        $this->callback = $callback;
        $this->applyFilter();
    }

    private $callback;

    private function applyFilter(): void {
        $this->filtered = [];
        foreach ($this->data as $key => $value) {
            if (($this->callback)($value, $key)) {
                $this->filtered[$key] = $value;
            }
        }
    }

    public function current(): mixed {
        return current($this->filtered);
    }

    public function key(): int {
        return key($this->filtered);
    }

    public function next(): void {
        $this->position++;
        next($this->filtered);
    }

    public function rewind(): void {
        reset($this->filtered);
        $this->position = 0;
    }

    public function valid(): bool {
        return $this->position < count($this->filtered);
    }
}

echo "=== RangeIterator ===\n";
$range = new RangeIterator(0, 10, 2);
foreach ($range as $key => $value) {
    echo "  [$key] => $value\n";
}

echo "\n=== ArrayIterator ===\n";
$arrIter = new ArrayIterator(['a', 'b', 'c', 'd']);
echo "Count: " . $arrIter->count() . "\n";
foreach ($arrIter as $key => $value) {
    echo "  [$key] => $value\n";
}

echo "\n=== DirectoryReader ===\n";
$dirReader = new DirectoryReader(sys_get_temp_dir());
foreach ($dirReader as $key => $value) {
    if ($value !== '.' && $value !== '..') {
        echo "  [$key] => $value\n";
        break;
    }
}

echo "\n=== FilterIterator ===\n";
$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
$evens = new FilterIterator($numbers, fn($v) => $v % 2 === 0);
foreach ($evens as $key => $value) {
    echo "  [$key] => $value\n";
}

echo "\n=== Iterator to array ===\n";
$range2 = new RangeIterator(1, 5);
$asArray = iterator_to_array($range2);
echo "Iterator to array: " . implode(',', $asArray) . "\n";

echo "\n=== Countable Iterator ===\n";
class CountableIterator implements Iterator, Countable {
    private array $data;
    private int $pos = 0;

    public function __construct(array $data) {
        $this->data = $data;
    }

    public function count(): int {
        return count($this->data);
    }

    public function current(): mixed {
        return $this->data[$this->pos];
    }

    public function key(): int {
        return $this->pos;
    }

    public function next(): void {
        $this->pos++;
    }

    public function rewind(): void {
        $this->pos = 0;
    }

    public function valid(): bool {
        return isset($this->data[$this->pos]);
    }
}

$ci = new CountableIterator(['x' => 10, 'y' => 20, 'z' => 30]);
echo "CountableIterator count: " . count($ci) . "\n";