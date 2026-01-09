<?php
// 复杂函数调用链测试
function outer($x) {
    return function($y) use ($x) {
        return function($z) use ($x, $y) {
            return $x + $y + $z;
        };
    };
}

$func = outer(10);
$func2 = $func(20);
$result = $func2(30);
echo "Nested closure result: $result\n";

// 复杂数组操作
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
];

$flattened = array_merge(...$matrix);
echo "Flattened: " . implode(", ", $flattened) . "\n";
?>