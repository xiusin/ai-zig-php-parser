<?php
$matrix = array(
    array(1, 2, 3),
    array(4, 5, 6),
    array(7, 8, 9)
);

echo "Matrix:\n";
foreach ($matrix as $row) {
    echo implode(" ", $row) . "\n";
}

// 数组转换
$doubled = array_map(function($arr) {
    return array_map(function($x) { return $x * 2; }, $arr);
}, $matrix);

echo "\nDoubled:\n";
foreach ($doubled as $row) {
    echo implode(" ", $row) . "\n";
}

// 深度数组操作
$deep = array(
    "a" => array(1, 2, 3),
    "b" => array(4, 5, 6),
    "c" => array(7, 8, 9)
);

$processed = array_map(function($arr) {
    return array(
        "sum" => array_sum($arr),
        "count" => count($arr),
        "avg" => array_sum($arr) / count($arr)
    );
}, $deep);

echo "\nProcessed:\n";
print_r($processed);
?>