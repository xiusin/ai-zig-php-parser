<?php
function unique(array $arr): array {
    return array_values(array_unique($arr));
}

function uniqueBy(array $arr, callable $keyFn): array {
    $seen = [];
    $result = [];
    foreach ($arr as $item) {
        $key = $keyFn($item);
        if (!isset($seen[$key])) {
            $seen[$key] = true;
            $result[] = $item;
        }
    }
    return $result;
}

function duplicates(array $arr): array {
    $freq = array_count_values($arr);
    return array_keys(array_filter($freq, fn($count) => $count > 1));
}

function frequencies(array $arr): array {
    return array_count_values($arr);
}

$nums = [1, 2, 2, 3, 3, 3, 4, 4, 4, 4];
echo implode(',', unique($nums)) . "\n";

$users = [['name' => 'Alice', 'age' => 25], ['name' => 'Bob', 'age' => 30], ['name' => 'Alice', 'age' => 35]];
$uniqueUsers = uniqueBy($users, fn($u) => $u['name']);
echo count($uniqueUsers) . "\n";

echo implode(',', duplicates([1, 2, 2, 3, 3, 3])) . "\n";

$freq = frequencies(['a', 'b', 'a', 'c', 'b', 'a']);
echo $freq['a'] . "\n";
echo "OK\n";
