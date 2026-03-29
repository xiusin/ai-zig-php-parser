<?php
// Test 060: CallbackFilterIterator, Generator-like without yield
class NumberRange implements Iterator {
    private int $current;
    private int $position;

    public function __construct(
        private int $start,
        private int $end,
        private int $step = 1
    ) {
        $this->current = $start;
        $this->position = 0;
    }

    public function current(): int { return $this->current; }
    public function key(): int { return $this->position; }
    public function next(): void {
        $this->current += $this->step;
        $this->position++;
    }
    public function rewind(): void {
        $this->current = $this->start;
        $this->position = 0;
    }
    public function valid(): bool { return $this->current <= $this->end; }
}

class Fibonacci implements Iterator {
    private int $current = 0;
    private int $next = 1;
    private int $position = 0;

    public function __construct(private int $limit) {}

    public function current(): int { return $this->current; }
    public function key(): int { return $this->position; }
    public function next(): void {
        $temp = $this->current + $this->next;
        $this->current = $this->next;
        $this->next = $temp;
        $this->position++;
    }
    public function rewind(): void {
        $this->current = 0;
        $this->next = 1;
        $this->position = 0;
    }
    public function valid(): bool { return $this->position < $this->limit; }
}

echo "=== NumberRange iterator ===\n";
$range = new NumberRange(0, 10, 2);
foreach ($range as $key => $value) {
    echo "  [$key] => $value\n";
}

echo "\n=== Fibonacci iterator ===\n";
$fib = new Fibonacci(10);
foreach ($fib as $key => $value) {
    echo "  [$key] => $value\n";
}

echo "\n=== Iterator to array ===\n";
$range2 = new NumberRange(1, 5);
$arr = iterator_to_array($range2);
echo "Range to array: " . implode(',', $arr) . "\n";

echo "\n=== Iterator count ===\n";
if ($range2 instanceof Countable) {
    echo "Range2 is Countable: " . count($range2) . "\n";
}

echo "\n=== CallbackFilterIterator ===\n";
$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
$callback = fn($value) => $value > 5;
$filtered = new CallbackFilterIterator(new ArrayIterator($numbers), $callback);
echo "Numbers > 5: " . implode(',', iterator_to_array($filtered)) . "\n";