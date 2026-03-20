<?php
function binarySearch(array $arr, int $target): int {
    $left = 0;
    $right = count($arr) - 1;

    while ($left <= $right) {
        $mid = ($left + $right) >> 1;
        if ($arr[$mid] === $target) return $mid;
        if ($arr[$mid] < $target) $left = $mid + 1;
        else $right = $mid - 1;
    }

    return -1;
}

function lowerBound(array $arr, int $target): int {
    $left = 0;
    $right = count($arr);

    while ($left < $right) {
        $mid = ($left + $right) >> 1;
        if ($arr[$mid] < $target) $left = $mid + 1;
        else $right = $mid;
    }

    return $left;
}

$sorted = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19];
echo binarySearch($sorted, 7) . "\n";
echo binarySearch($sorted, 8) . "\n";
echo binarySearch($sorted, 1) . "\n";
echo binarySearch($sorted, 19) . "\n";
echo lowerBound($sorted, 8) . "\n";
echo lowerBound($sorted, 7) . "\n";
echo "OK\n";
