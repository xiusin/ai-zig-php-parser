<?php
class Tuple {
    public function __construct(public readonly array $values) {}

    public function get(int $index): mixed {
        return $this->values[$index] ?? null;
    }

    public function count(): int {
        return count($this->values);
    }

    public function toArray(): array {
        return $this->values;
    }

    public function map(callable $fn): self {
        return new self(array_map($fn, $this->values));
    }

    public function filter(callable $fn): self {
        return new self(array_filter($fn, $this->values));
    }

    public function reduce(callable $fn, mixed $initial = null): mixed {
        return array_reduce($this->values, $fn, $initial);
    }
}

$tuple = new Tuple([1, 'hello', 3.14, true]);
echo $tuple->get(0) . "\n";
echo $tuple->get(1) . "\n";
echo $tuple->count() . "\n";

$mapped = $tuple->map(fn($v) => is_numeric($v) ? $v * 2 : $v);
echo $mapped->get(0) . "\n";

$reduced = $tuple->reduce(fn($carry, $v) => $carry + (is_numeric($v) ? $v : 0), 0);
echo $reduced . "\n";
echo "OK\n";
