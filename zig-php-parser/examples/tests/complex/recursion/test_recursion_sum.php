<?php
function arraySum($arr) {
    if (empty($arr)) {
        return 0;
    }
    $first = array_shift($arr);
    if (is_array($first)) {
        return arraySum($first) + arraySum($arr);
    }
    return $first + arraySum($arr);
}

$testArrays = [
    [1, 2, 3, 4, 5],
    [10, [20, 30], 40],
    [[1, [2, [3, [4]]]]],
    range(1, 100),
];

foreach ($testArrays as $i => $arr) {
    echo "Array $i sum: " . arraySum($arr) . "\n";
}
