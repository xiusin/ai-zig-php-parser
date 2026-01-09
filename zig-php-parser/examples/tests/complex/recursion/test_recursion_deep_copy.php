<?php
function deepCopy($arr) {
    if (!is_array($arr)) {
        return $arr;
    }
    $copy = [];
    foreach ($arr as $key => $value) {
        $copy[$key] = deepCopy($value);
    }
    return $copy;
}

$original = [
    "a" => 1,
    "b" => [2, 3, "c" => [4, 5]],
    "d" => [
        "e" => 6,
        "f" => [7, 8, 9]
    ]
];

$copy = deepCopy($original);
$copy["b"]["c"][0] = 999;
echo "Original: " . json_encode($original) . "\n";
echo "Copy: " . json_encode($copy) . "\n";
echo "Original unchanged: " . ($original["b"]["c"][0] == 4 ? "YES" : "NO") . "\n";
