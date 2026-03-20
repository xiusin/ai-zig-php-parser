<?php
function maxElement(array $arr): mixed {
    if (empty($arr)) return null;
    $max = $arr[0];
    foreach ($arr as $v) {
        if ($v > $max) $max = $v;
    }
    return $max;
}

function minElement(array $arr): mixed {
    if (empty($arr)) return null;
    $min = $arr[0];
    foreach ($arr as $v) {
        if ($v < $min) $min = $v;
    }
    return $min;
}

function maxBy(array $arr, callable $keyFn): mixed {
    if (empty($arr)) return null;
    $maxItem = $arr[0];
    $maxKey = $keyFn($arr[0]);
    foreach ($arr as $item) {
        $key = $keyFn($item);
        if ($key > $maxKey) {
            $maxKey = $key;
            $maxItem = $item;
        }
    }
    return $maxItem;
}

function minBy(array $arr, callable $keyFn): mixed {
    if (empty($arr)) return null;
    $minItem = $arr[0];
    $minKey = $keyFn($arr[0]);
    foreach ($arr as $item) {
        $key = $keyFn($item);
        if ($key < $minKey) {
            $minKey = $key;
            $minItem = $item;
        }
    }
    return $minItem;
}

$nums = [3, 1, 4, 1, 5, 9, 2, 6];
echo maxElement($nums) . "\n";
echo minElement($nums) . "\n";

$users = [['name' => 'Alice', 'age' => 25], ['name' => 'Bob', 'age' => 30], ['name' => 'Charlie', 'age' => 20]];
echo maxBy($users, fn($u) => $u['age'])['name'] . "\n";
echo minBy($users, fn($u) => $u['age'])['name'] . "\n";
echo "OK\n";
