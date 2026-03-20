<?php
function arrayReverse2(array $arr, bool $preserve_keys = false): array {
    return array_reverse($arr, $preserve_keys);
}

function arraySort(array $arr, callable $cmp): array {
    usort($arr, $cmp);
    return $arr;
}

function arraySortByKey(array $arr, string $key, bool $desc = false): array {
    usort($arr, fn($a, $b) => $desc ? $b[$key] <=> $a[$key] : $a[$key] <=> $b[$key]);
    return $arr;
}

function arrayShuffle2(array $arr): array {
    $shuffled = $arr;
    shuffle($shuffled);
    return $shuffled;
}

function arrayUnique2(array $arr): array {
    return array_values(array_unique($arr));
}

$nums = [3, 1, 4, 1, 5, 9, 2, 6];
print_r(arrayReverse2($nums));
print_r(arraySort($nums, fn($a, $b) => $b <=> $a));
print_r(arraySortByKey([['v' => 3], ['v' => 1], ['v' => 2]], 'v', true));
print_r(arrayUnique2([1, 2, 2, 3, 3, 3]));
echo "OK\n";
