<?php
function arrayFirst(array $arr, callable $fn = null): mixed {
    if ($fn === null) return $arr[0] ?? null;
    foreach ($arr as $value) {
        if ($fn($value)) return $value;
    }
    return null;
}

function arrayLast(array $arr, callable $fn = null): mixed {
    if ($fn === null) return $arr[count($arr) - 1] ?? null;
    for ($i = count($arr) - 1; $i >= 0; $i--) {
        if ($fn($arr[$i])) return $arr[$i];
    }
    return null;
}

function arrayFind(array $arr, callable $fn): mixed {
    foreach ($arr as $value) {
        if ($fn($value)) return $value;
    }
    return null;
}

function arrayFindIndex(array $arr, callable $fn): int {
    foreach ($arr as $index => $value) {
        if ($fn($value)) return $index;
    }
    return -1;
}

$nums = [1, 2, 3, 4, 5];
echo arrayFirst($nums) . "\n";
echo arrayLast($nums) . "\n";
echo arrayFirst($nums, fn($n) => $n > 3) . "\n";
echo arrayFindIndex($nums, fn($n) => $n % 2 === 0) . "\n";
echo "OK\n";
