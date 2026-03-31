<?php
// Test 083: ArrayAccess implementation
class Collection implements ArrayAccess {
    private array $data = [];

    public function __construct(array $data = []) {
        $this->data = $data;
    }

    public function offsetExists(mixed $offset): bool {
        return isset($this->data[$offset]);
    }

    public function offsetGet(mixed $offset): mixed {
        return $this->data[$offset] ?? null;
    }

    public function offsetSet(mixed $offset, mixed $value): void {
        if ($offset === null) {
            $this->data[] = $value;
        } else {
            $this->data[$offset] = $value;
        }
    }

    public function offsetUnset(mixed $offset): void {
        unset($this->data[$offset]);
    }

    public function count(): int {
        return count($this->data);
    }
}

echo "=== ArrayAccess ===\n";
$col = new Collection(['a' => 1, 'b' => 2]);
echo "col['a']: " . $col['a'] . "\n";
echo "col['b']: " . $col['b'] . "\n";

echo "\n=== Set/Unset ===\n";
$col['c'] = 3;
echo "After set col['c']=3: " . $col['c'] . "\n";
echo "isset(col['c']): " . (isset($col['c']) ? 'yes' : 'no') . "\n";

unset($col['a']);
echo "After unset col['a'], isset(col['a']): " . (isset($col['a']) ? 'yes' : 'no') . "\n";

echo "\n=== Append ===\n";
$col[] = 100;
$col[] = 200;
echo "After append: " . count($col) . " items\n";

echo "\n=== Countable ===\n";
echo "count(col): " . count($col) . "\n";