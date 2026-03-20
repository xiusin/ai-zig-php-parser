<?php
function arrayMap2(array $arr, callable $fn): array {
    return array_map($fn, $arr);
}

function arrayFilter2(array $arr, callable $fn): array {
    return array_filter($arr, $fn);
}

function arrayReduce2(array $arr, callable $fn, mixed $initial = null): mixed {
    return array_reduce($arr, $fn, $initial);
}

function arrayWalk2(array &$arr, callable $fn): void {
    array_walk($arr, $fn);
}

$numbers = [1, 2, 3, 4, 5];
$doubled = arrayMap2($numbers, fn($n) => $n * 2);
$evens = arrayFilter2($numbers, fn($n) => $n % 2 === 0);
$sum = arrayReduce2($numbers, fn($c, $n) => $c + $n, 0);

echo implode(',', $doubled) . "\n";
echo implode(',', $evens) . "\n";
echo $sum . "\n";

arrayWalk2($numbers, function(&$v, $k) { $v = $v * 10; });
echo implode(',', $numbers) . "\n";
echo "OK\n";
