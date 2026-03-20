<?php
// Test 129: Intersection types
class IntersectionTarget {
    public function process(Countable&Traversable $value): int {
        $count = 0;
        foreach ($value as $item) {
            $count++;
        }
        return $count;
    }

    public function countOnly(Countable $value): int {
        return count($value);
    }
}

class CountableTraversableImpl implements Countable, Traversable {
    private array $data;

    public function __construct(array $data) {
        $this->data = $data;
    }

    public function count(): int {
        return count($this->data);
    }

    public function getIterator(): Iterator {
        return new ArrayIterator($this->data);
    }
}

echo "=== Intersection types ===\n";
$obj = new CountableTraversableImpl([1, 2, 3, 4, 5]);
$target = new IntersectionTarget();

echo "process (Countable&Traversable): " . $target->process($obj) . "\n";
echo "countOnly (Countable): " . $target->countOnly($obj) . "\n";