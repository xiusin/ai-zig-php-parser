<?php
class Pipeline {
    private array $stages = [];

    public function pipe(callable $fn): self {
        $this->stages[] = $fn;
        return $this;
    }

    public function process(mixed $value): mixed {
        foreach ($this->stages as $stage) {
            $value = $stage($value);
        }
        return $value;
    }
}

$result = (new Pipeline())
    ->pipe(fn($x) => $x * 2)
    ->pipe(fn($x) => $x + 10)
    ->pipe(fn($x) => $x - 5)
    ->process(100);
echo $result . "\n";

$strings = (new Pipeline())
    ->pipe(fn($arr) => array_map('strtoupper', $arr))
    ->pipe(fn($arr) => array_filter($arr, fn($s) => strlen($s) > 3))
    ->pipe(fn($arr) => array_values($arr))
    ->process(['a', 'ab', 'abc', 'abcd', 'abcde']);
echo implode(',', $strings) . "\n";
echo "OK\n";
