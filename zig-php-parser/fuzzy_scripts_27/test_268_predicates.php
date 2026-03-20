<?php
function any(array $arr, callable $fn): bool {
    foreach ($arr as $value) {
        if ($fn($value)) return true;
    }
    return false;
}

function all(array $arr, callable $fn): bool {
    foreach ($arr as $value) {
        if (!$fn($value)) return false;
    }
    return true;
}

function none(array $arr, callable $fn): bool {
    foreach ($arr as $value) {
        if ($fn($value)) return false;
    }
    return true;
}

function count2(array $arr, callable $fn): int {
    $count = 0;
    foreach ($arr as $value) {
        if ($fn($value)) $count++;
    }
    return $count;
}

$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
echo any($numbers, fn($n) => $n > 8) ? 'true' : 'false' . "\n";
echo all($numbers, fn($n) => $n > 0) ? 'true' : 'false' . "\n";
echo none($numbers, fn($n) => $n < 0) ? 'true' : 'false' . "\n";
echo count2($numbers, fn($n) => $n % 2 === 0) . "\n";
echo "OK\n";
