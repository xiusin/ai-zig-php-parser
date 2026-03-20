<?php
function mergeSorted(array $a, array $b): array {
    $result = [];
    $i = $j = 0;

    while ($i < count($a) && $j < count($b)) {
        if ($a[$i] <= $b[$j]) {
            $result[] = $a[$i++];
        } else {
            $result[] = $b[$j++];
        }
    }

    while ($i < count($a)) $result[] = $a[$i++];
    while ($j < count($b)) $result[] = $b[$j++];

    return $result;
}

function quickSort(array $arr): array {
    if (count($arr) <= 1) return $arr;

    $pivot = $arr[count($arr) >> 1];
    $left = $right = [];

    foreach ($arr as $v) {
        if ($v < $pivot) $left[] = $v;
        elseif ($v > $pivot) $right[] = $v;
    }

    return array_merge(quickSort($left), [$pivot], quickSort($right));
}

$a = [1, 3, 5, 7, 9];
$b = [2, 4, 6, 8, 10];
echo implode(',', mergeSorted($a, $b)) . "\n";

$unsorted = [64, 34, 25, 12, 22, 11, 90, 5, 77, 30, 45, 23];
echo implode(',', quickSort($unsorted)) . "\n";

$empty = [];
echo implode(',', quickSort($empty)) . "\n";

$single = [42];
echo implode(',', quickSort($single)) . "\n";
echo "OK\n";
