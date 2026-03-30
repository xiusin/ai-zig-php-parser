<?php
// Test 130: Spread operator in method calls
class SpreadMethod {
    public function sum(int $a, int $b, int $c = 0, int $d = 0): int {
        return $a + $b + $c + $d;
    }

    public function concat(string $a, string $b, string $c = ''): string {
        return $a . $b . $c;
    }
}

echo "=== Spread in method calls ===\n";
$obj = new SpreadMethod();

$numbers = [10, 20, 30];
echo "sum(...[10,20,30]): " . $obj->sum(...$numbers) . "\n";

$partial = [100, 200];
echo "sum(...[100,200], d=5): " . $obj->sum($partial[0], $partial[1], 0, 5) . "\n";

$strings = ['Hello', ' ', 'World'];
echo "concat(...\$strings): " . $obj->concat(...$strings) . "\n";