<?php
function flatten(array $arr, int $depth = -1): array {
    $result = [];
    foreach ($arr as $item) {
        if (is_array($item)) {
            if ($depth > 0) {
                $result = array_merge($result, flatten($item, $depth - 1));
            } elseif ($depth === -1) {
                $result = array_merge($result, flatten($item, -1));
            } else {
                $result[] = $item;
            }
        } else {
            $result[] = $item;
        }
    }
    return $result;
}

function deepFlatten(array $arr): array {
    $result = [];
    foreach ($arr as $item) {
        if (is_array($item)) {
            $result = array_merge($result, deepFlatten($item));
        } else {
            $result[] = $item;
        }
    }
    return $result;
}

$arr = [1, [2, [3, [4, [5]]]]];
echo implode(',', flatten($arr, 1)) . "\n";
echo implode(',', flatten($arr, 2)) . "\n";
echo implode(',', deepFlatten($arr)) . "\n";

$mixed = [1, [2, 3], [[4, 5], [6, [7, 8]]]];
echo implode(',', deepFlatten($mixed)) . "\n";
echo "OK\n";
