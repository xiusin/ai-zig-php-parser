<?php
// Test 058: ArrayObject, ArrayIterator, and SPL iterators
$ao = new ArrayObject(['x' => 10, 'y' => 20, 'z' => 30]);
echo "ArrayObject count: " . $ao->count() . "\n";
echo "ArrayObject['x']: " . $ao['x'] . "\n";

$ao['x'] = 100;
echo "After ao['x']=100: " . $ao['x'] . "\n";

echo "\n=== ArrayIterator ===\n";
$ai = new ArrayIterator(['a' => 1, 'b' => 2, 'c' => 3]);
foreach ($ai as $key => $value) {
    echo "  $key => $value\n";
}

echo "\n=== SeekableIterator ===\n";
class Seekable implements SeekableIterator {
    private array $data = [];
    private int $position = 0;

    public function __construct(array $data) {
        $this->data = $data;
    }

    public function current(): mixed { return $this->data[$this->position]; }
    public function key(): int { return $this->position; }
    public function next(): void { $this->position++; }
    public function rewind(): void { $this->position = 0; }
    public function valid(): bool { return isset($this->data[$this->position]); }
    public function seek(int $position): void { $this->position = $position; }
}

$seek = new Seekable([10, 20, 30, 40, 50]);
$seek->seek(3);
echo "Seek to position 3: " . $seek->current() . "\n";

echo "\n=== RecursiveArrayIterator ===\n";
$nested = ['a' => 1, 'b' => ['c' => 2, 'd' => 3]];
$rai = new RecursiveArrayIterator($nested);
$riter = new RecursiveIteratorIterator($rai);

foreach ($riter as $key => $value) {
    echo "  $key => $value (depth: " . $riter->getDepth() . ")\n";
}

echo "\n=== AppendIterator ===\n";
$first = new ArrayIterator([1, 2, 3]);
$second = new ArrayIterator([4, 5, 6]);
$append = new AppendIterator();
$append->append($first);
$append->append($second);

foreach ($append as $value) {
    echo "  $value\n";
}

echo "\n=== LimitIterator ===\n";
$base = new ArrayIterator(range(1, 10));
$limit = new LimitIterator($base, 3, 4);
foreach ($limit as $value) {
    echo "  $value\n";
}