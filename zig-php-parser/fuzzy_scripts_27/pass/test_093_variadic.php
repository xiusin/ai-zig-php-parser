<?php
// Test 093: Variadic functions and spread operator
function sum(int ...$nums): int {
    return array_sum($nums);
}

function concat(string ...$strs): string {
    return implode('', $strs);
}

function sumWithInitial(int $initial, int ...$nums): int {
    return $initial + array_sum($nums);
}

echo "=== Variadic functions ===\n";
echo "sum(1, 2, 3): " . sum(1, 2, 3) . "\n";
echo "sum(10, 20): " . sum(10, 20) . "\n";
echo "sum(): " . sum() . "\n";

echo "\n=== String variadic ===\n";
echo "concat('a', 'b', 'c'): " . concat('a', 'b', 'c') . "\n";

echo "\n=== With initial ===\n";
echo "sumWithInitial(100, 1, 2, 3): " . sumWithInitial(100, 1, 2, 3) . "\n";

echo "\n=== Spread operator in call ===\n";
$numbers = [1, 2, 3, 4, 5];
echo "sum(...\$numbers): " . sum(...$numbers) . "\n";

echo "\n=== Array spread ===\n";
$a = [1, 2];
$b = [3, 4];
$merged = array_merge($a, $b);
echo "array_merge([1,2], [3,4]): " . json_encode($merged) . "\n";

$prepend = array_merge([0], $a);
echo "prepend 0: " . json_encode($prepend) . "\n";