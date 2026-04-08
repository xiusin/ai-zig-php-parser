<?php
// 遍历接口测试

// Iterator接口完整实现
class MyIterator implements Iterator {
    private array $items = [];
    private int $position = 0;

    public function __construct(array $items) {
        $this->items = array_values($items);
    }

    public function current(): mixed {
        return $this->items[$this->position];
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
        return isset($this->items[$this->position]);
    }
}

$iterator = new MyIterator(['a', 'b', 'c', 'd']);
echo "MyIterator:\n";
foreach ($iterator as $key => $value) {
    echo "  $key => $value\n";
}

// IteratorAggregate接口
class MyAggregate implements IteratorAggregate {
    private array $data;

    public function __construct(array $data) {
        $this->data = $data;
    }

    public function getIterator(): Traversable {
        return new ArrayIterator($this->data);
    }
}

$aggregate = new MyAggregate(['x' => 1, 'y' => 2, 'z' => 3]);
echo "IteratorAggregate:\n";
foreach ($aggregate as $key => $value) {
    echo "  $key => $value\n";
}

// Generator作为Traversable
function numberGenerator(int $max): Generator {
    for ($i = 1; $i <= $max; $i++) {
        yield $i => $i * $i;
    }
}

echo "Generator:\n";
foreach (numberGenerator(5) as $num => $square) {
    echo "  $num^2 = $square\n";
}

// ArrayIterator
$arrIterator = new ArrayIterator([10, 20, 30]);
echo "ArrayIterator first: " . $arrIterator->current() . "\n";

// OuterIterator包装
class OuterIteratorWrapper implements OuterIterator {
    private Iterator $inner;

    public function __construct(Iterator $inner) {
        $this->inner = $inner;
    }

    public function getInnerIterator(): Iterator {
        return $this->inner;
    }

    public function current(): mixed {
        return strtoupper($this->inner->current());
    }

    public function key(): mixed {
        return $this->inner->key();
    }

    public function next(): void {
        $this->inner->next();
    }

    public function rewind(): void {
        $this->inner->rewind();
    }

    public function valid(): bool {
        return $this->inner->valid();
    }
}

$wrapped = new OuterIteratorWrapper(new MyIterator(['a', 'b']));
echo "OuterIterator:\n";
foreach ($wrapped as $k => $v) {
    echo "  $k => $v\n";
}

// SeekableIterator
class SeekableIteratorImpl implements SeekableIterator {
    private array $items;
    private int $position = 0;

    public function __construct(array $items) {
        $this->items = array_values($items);
    }

    public function seek(int $offset): void {
        if (!isset($this->items[$offset])) {
            throw new OutOfBoundsException("Offset $offset does not exist");
        }
        $this->position = $offset;
    }

    public function current(): mixed { return $this->items[$this->position]; }
    public function key(): int { return $this->position; }
    public function next(): void { $this->position++; }
    public function rewind(): void { $this->position = 0; }
    public function valid(): bool { return isset($this->items[$this->position]); }
}

$seekable = new SeekableIteratorImpl(['a', 'b', 'c', 'd', 'e']);
$seekable->seek(2);
echo "Seekable at 2: " . $seekable->current() . "\n";

// Countable接口
class CountableCollection implements Countable {
    private array $items;

    public function __construct(array $items) {
        $this->items = $items;
    }

    public function count(): int {
        return count($this->items);
    }
}

$countable = new CountableCollection([1, 2, 3, 4, 5]);
echo "Countable count: " . count($countable) . "\n";

echo "Traversable tests completed\n";
