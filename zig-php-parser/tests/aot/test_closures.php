<?php
// 测试：闭包和高阶函数
function map_array($arr, $fn) {
    $result = [];
    $i = 0;
    while ($i < count($arr)) {
        $result[] = $fn($arr[$i]);
        $i++;
    }
    return $result;
}

function filter_array($arr, $fn) {
    $result = [];
    $i = 0;
    while ($i < count($arr)) {
        if ($fn($arr[$i])) {
            $result[] = $arr[$i];
        }
        $i++;
    }
    return $result;
}

$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

// 使用闭包
$double = function($x) {
    return $x * 2;
};

$is_even = function($x) {
    return $x % 2 == 0;
};

$doubled = map_array($numbers, $double);
echo "Doubled: ";
$i = 0;
while ($i < count($doubled)) {
    echo $doubled[$i] . " ";
    $i++;
}
echo "\n";

$evens = filter_array($numbers, $is_even);
echo "Evens: ";
$i = 0;
while ($i < count($evens)) {
    echo $evens[$i] . " ";
    $i++;
}
echo "\n";
