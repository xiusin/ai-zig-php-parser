<?php
function hashMap(array $pairs): array {
    $map = [];
    foreach ($pairs as $key => $value) {
        $map[$key] = $value;
    }
    return $map;
}

function groupBy(array $items, callable $keyFn): array {
    $groups = [];
    foreach ($items as $item) {
        $key = $keyFn($item);
        if (!isset($groups[$key])) {
            $groups[$key] = [];
        }
        $groups[$key][] = $item;
    }
    return $groups;
}

function chunk(array $arr, int $size): array {
    $chunks = [];
    for ($i = 0; $i < count($arr); $i += $size) {
        $chunks[] = array_slice($arr, $i, $size);
    }
    return $chunks;
}

function zip(array $a, array $b): array {
    $result = [];
    $len = min(count($a), count($b));
    for ($i = 0; $i < $len; $i++) {
        $result[] = [$a[$i], $b[$i]];
    }
    return $result;
}

$users = [
    ['name' => 'Alice', 'age' => 25],
    ['name' => 'Bob', 'age' => 30],
    ['name' => 'Charlie', 'age' => 25],
    ['name' => 'Diana', 'age' => 30],
];

$grouped = groupBy($users, fn($u) => $u['age']);
foreach ($grouped as $age => $group) {
    echo "$age: " . count($group) . " users\n";
}

echo implode(',', chunk(range(1, 10), 3)[1]) . "\n";

$zipped = zip(['a', 'b', 'c'], [1, 2, 3, 4]);
echo count($zipped) . "\n";
echo "OK\n";
