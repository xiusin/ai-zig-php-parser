<?php
// Iterators and generators
class NumberIterator implements Iterator {
    private $current;
    private $max;
    private $step;
    
    public function __construct($max, $step = 1) {
        $this->current = 0;
        $this->max = $max;
        $this->step = $step;
    }
    
    public function rewind(): void {
        $this->current = 0;
    }
    
    public function valid(): bool {
        return $this->current <= $this->max;
    }
    
    public function current(): mixed {
        return $this->current;
    }
    
    public function key(): mixed {
        return $this->current;
    }
    
    public function next(): void {
        $this->current += $this->step;
    }
}

class FibonacciGenerator {
    private $limit;
    private $a = 0;
    private $b = 1;
    private $count = 0;
    
    public function __construct($limit) {
        $this->limit = $limit;
    }
    
    public function generate() {
        while ($this->count < $this->limit) {
            yield $this->a;
            $temp = $this->a + $this->b;
            $this->a = $this->b;
            $this->b = $temp;
            $this->count++;
        }
    }
}

class PrimeGenerator {
    public function generate($limit) {
        $count = 0;
        $number = 2;
        
        while ($count < $limit) {
            if ($this->isPrime($number)) {
                yield $number;
                $count++;
            }
            $number++;
        }
    }
    
    private function isPrime($n) {
        if ($n < 2) return false;
        if ($n == 2) return true;
        if ($n % 2 == 0) return false;
        
        for ($i = 3; $i <= sqrt($n); $i += 2) {
            if ($n % $i == 0) {
                return false;
            }
        }
        return true;
    }
}

class Collection implements IteratorAggregate {
    private $items = [];
    
    public function __construct(array $items = []) {
        $this->items = $items;
    }
    
    public function add($item): void {
        $this->items[] = $item;
    }
    
    public function remove($item): bool {
        $key = array_search($item, $this->items, true);
        if ($key !== false) {
            unset($this->items[$key]);
            return true;
        }
        return false;
    }
    
    public function getIterator(): Iterator {
        return new ArrayIterator($this->items);
    }
    
    public function map(callable $callback): array {
        return array_map($callback, $this->items);
    }
    
    public function filter(callable $callback): array {
        return array_filter($this->items, $callback);
    }
    
    public function reduce(callable $callback, $initial = null) {
        return array_reduce($this->items, $callback, $initial);
    }
}

class LazyCollection {
    private $source;
    
    public function __construct($source) {
        $this->source = $source;
    }
    
    public function map(callable $callback): self {
        return new self(function() use ($callback) {
            foreach ($this->source as $item) {
                yield $callback($item);
            }
        });
    }
    
    public function filter(callable $callback): self {
        return new self(function() use ($callback) {
            foreach ($this->source as $item) {
                if ($callback($item)) {
                    yield $item;
                }
            }
        });
    }
    
    public function take($limit): self {
        return new self(function() use ($limit) {
            $count = 0;
            foreach ($this->source as $item) {
                if ($count >= $limit) break;
                yield $item;
                $count++;
            }
        });
    }
    
    public function toArray(): array {
        return iterator_to_array($this->source);
    }
}

// Test iterators
echo "=== Number Iterator ===\n";
$iterator = new NumberIterator(10, 2);
foreach ($iterator as $key => $value) {
    echo "{$key}: {$value}\n";
}

echo "\n=== Fibonacci Generator ===\n";
$fibGen = new FibonacciGenerator(10);
foreach ($fibGen->generate() as $num) {
    echo "{$num} ";
}
echo "\n";

echo "\n=== Prime Generator ===\n";
$primeGen = new PrimeGenerator();
foreach ($primeGen->generate(10) as $prime) {
    echo "{$prime} ";
}
echo "\n";

echo "\n=== Collection ===\n";
$collection = new Collection([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

echo "Original: ";
foreach ($collection as $item) {
    echo "{$item} ";
}
echo "\n";

echo "Mapped (squared): ";
$mapped = $collection->map(fn($x) => $x * $x);
foreach ($mapped as $item) {
    echo "{$item} ";
}
echo "\n";

echo "Filtered (even): ";
$filtered = $collection->filter(fn($x) => $x % 2 == 0);
foreach ($filtered as $item) {
    echo "{$item} ";
}
echo "\n";

echo "Reduced (sum): ";
$sum = $collection->reduce(fn($carry, $item) => $carry + $item, 0);
echo "{$sum}\n";

echo "\n=== Lazy Collection ===\n";
$lazyCollection = new LazyCollection([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

$result = $lazyCollection
    ->map(fn($x) => $x * 2)
    ->filter(fn($x) => $x > 10)
    ->take(3)
    ->toArray();

echo "Result: ";
foreach ($result as $item) {
    echo "{$item} ";
}
echo "\n";

echo "\nDone\n";
