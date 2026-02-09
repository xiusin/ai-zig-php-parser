<?php
// 测试递归 quicksort

function quicksort(array $arr): array {
    if (count($arr) <= 1) {
        return $arr;
    }
    
    $pivot = $arr[0];
    $left = [];
    $right = [];
    
    for ($i = 1; $i < count($arr); $i++) {
        if ($arr[$i] < $pivot) {
            $left[] = $arr[$i];
        } else {
            $right[] = $arr[$i];
        }
    }
    
    return array_merge(quicksort($left), [$pivot], quicksort($right));
}

$arr = [3, 1, 4, 1, 5, 9, 2, 6];
$sorted = quicksort($arr);
echo "Sorted: " . implode(", ", $sorted) . "\n";
echo "Expected: 1, 1, 2, 3, 4, 5, 6, 9\n";
