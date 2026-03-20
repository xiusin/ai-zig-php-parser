<?php
function pluck(array $items, string $key): array {
    return array_map(fn($item) => $item[$key], $items);
}

function groupByKey(array $items, string $key): array {
    $result = [];
    foreach ($items as $item) {
        $group = $item[$key];
        if (!isset($result[$group])) {
            $result[$group] = [];
        }
        $result[$group][] = $item;
    }
    return $result;
}

function sortBy(array $items, string $key, bool $desc = false): array {
    usort($items, fn($a, $b) => $desc ? $b[$key] <=> $a[$key] : $a[$key] <=> $b[$key]);
    return $items;
}

$users = [
    ['name' => 'Alice', 'age' => 25],
    ['name' => 'Bob', 'age' => 30],
    ['name' => 'Charlie', 'age' => 20],
];

echo implode(',', pluck($users, 'name')) . "\n";

$grouped = groupByKey($users, 'age');
echo count($grouped) . "\n";

$sorted = sortBy($users, 'age');
echo $sorted[0]['name'] . "\n";

$sortedDesc = sortBy($users, 'age', true);
echo $sortedDesc[0]['name'] . "\n";
echo "OK\n";
