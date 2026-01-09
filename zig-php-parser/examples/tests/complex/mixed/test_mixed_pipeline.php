<?php
$data = [
    ["name" => "Alice", "age" => 25, "score" => 85],
    ["name" => "Bob", "age" => 30, "score" => 92],
    ["name" => "Charlie", "age" => 22, "score" => 78],
    ["name" => "Diana", "age" => 28, "score" => 95],
    ["name" => "Eve", "age" => 35, "score" => 88],
];

$pipeline = [
    "filter_score" => fn($items) => array_filter($items, fn($item) => $item["score"] >= 80),
    "sort_by_score" => fn($items) => usort($items, fn($a, $b) => $b["score"] - $a["score"]) ?: 0),
    "map_names" => fn($items) => array_map(fn($item) => $item["name"], $items),
    "implode" => fn($items) => implode(", ", $items),
];

$result = $data;
foreach ($pipeline as $name => $transform) {
    $result = $transform($result);
}

echo "Result: $result\n";
