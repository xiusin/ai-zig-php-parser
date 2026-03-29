<?php
// Test 133: Callback array functions
class CallbackArray {
    public array $data;

    public function __construct(array $data) {
        $this->data = $data;
    }

    public function filter(callback $predicate): array {
        return array_filter($this->data, $predicate);
    }

    public function map(callback $transform): array {
        return array_map($transform, $this->data);
    }
}

echo "=== Callback class ===\n";
$obj = new CallbackArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

$evens = $obj->filter(fn($v) => $v % 2 === 0);
echo "Evens: " . implode(',', $evens) . "\n";

$doubled = $obj->map(fn($v) => $v * 2);
echo "Doubled: " . implode(',', $doubled) . "\n";

echo "\n=== ArrayObject as callback target ===\n";
$ao = new ArrayObject([10, 20, 30]);
$sum = array_reduce($ao, fn($c, $v) => $c + $v, 0);
echo "Sum via ArrayObject: $sum\n";