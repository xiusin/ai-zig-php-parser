<?php
function arrayTake(array $arr, int $count): array {
    return array_slice($arr, 0, $count);
}

function arrayTakeRight(array $arr, int $count): array {
    return array_slice($arr, -$count);
}

function arrayDrop(array $arr, int $count): array {
    return array_slice($arr, $count);
}

function arrayDropRight(array $arr, int $count): array {
    return array_slice($arr, 0, -$count);
}

function arrayRange(int $start, int $end, int $step = 1): array {
    $result = [];
    if ($step > 0) {
        for ($i = $start; $i <= $end; $i += $step) {
            $result[] = $i;
        }
    }
    return $result;
}

$nums = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
print_r(arrayTake($nums, 3));
print_r(arrayTakeRight($nums, 3));
print_r(arrayDrop($nums, 2));
print_r(arrayDropRight($nums, 2));
print_r(arrayRange(1, 10, 2));
echo "OK\n";
