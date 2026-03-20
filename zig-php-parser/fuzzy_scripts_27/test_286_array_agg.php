<?php
function arraySum(array $arr): int|float {
    return array_sum($arr);
}

function arrayProduct(array $arr): int|float {
    return array_reduce($arr, fn($c, $v) => $c * $v, 1);
}

function arrayAvg(array $arr): float {
    return empty($arr) ? 0.0 : array_sum($arr) / count($arr);
}

function arrayMax2(array $arr): mixed {
    return empty($arr) ? null : max($arr);
}

function arrayMin2(array $arr): mixed {
    return empty($arr) ? null : min($arr);
}

function arrayMode(array $arr): mixed {
    $freq = array_count_values($arr);
    arsort($freq);
    return array_key_first($freq);
}

$nums = [1, 2, 3, 4, 5, 5, 4, 3, 2, 1];
echo arraySum($nums) . "\n";
echo arrayProduct([1, 2, 3, 4]) . "\n";
echo arrayAvg($nums) . "\n";
echo arrayMax2($nums) . "\n";
echo arrayMin2($nums) . "\n";
echo arrayMode($nums) . "\n";
echo "OK\n";
