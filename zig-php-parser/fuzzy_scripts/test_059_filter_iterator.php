<?php
// Test 059: FilterIterator, RecursiveFilterIterator
class EvenFilter extends FilterIterator {
    public function accept(): bool {
        return $this->current() % 2 === 0;
    }
}

class KeyFilter extends FilterIterator {
    private string $prefix;

    public function __construct(Iterator $iterator, string $prefix) {
        parent::__construct($iterator);
        $this->prefix = $prefix;
    }

    public function accept(): bool {
        return str_starts_with($this->key(), $this->prefix);
    }
}

class RecursiveEvenFilter extends RecursiveFilterIterator {
    public function accept(): bool {
        $value = $this->current();
        if (is_array($value)) return true;
        return $value % 2 === 0;
    }

    public function getChildren(): RecursiveFilterIterator {
        return new self($this->getInnerIterator()->getChildren());
    }
}

echo "=== FilterIterator ===\n";
$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
$evens = new EvenFilter(new ArrayIterator($numbers));
echo "Even numbers: " . implode(',', iterator_to_array($evens)) . "\n";

echo "\n=== KeyFilter ===\n";
$assoc = ['apple' => 1, 'banana' => 2, 'apricot' => 3, 'cherry' => 4];
$filtered = new KeyFilter(new ArrayIterator($assoc), 'a');
echo "Keys starting with 'a': " . json_encode(iterator_to_array($filtered)) . "\n";

echo "\n=== RecursiveFilterIterator ===\n";
$nested = [1, 2, [3, 4, [5, 6]], 7, [8, 9]];
$rec = new RecursiveEvenFilter(new RecursiveArrayIterator($nested));
$flattened = iterator_to_array($rec, false);
echo "Even values flattened: " . implode(',', $flattened) . "\n";

echo "\n=== Multiple FilterIterator ===\n";
$multi = new EvenFilter(new KeyFilter(new ArrayIterator(range(1, 20)), '1'));
echo "Even numbers starting with '1': " . implode(',', iterator_to_array($multi)) . "\n";