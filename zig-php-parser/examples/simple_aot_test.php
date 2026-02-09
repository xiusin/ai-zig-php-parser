<?php
// 简单的 AOT 编译测试

echo "Hello from AOT compiled PHP!\n";

$x = 10;
$y = 20;
$sum = $x + $y;

echo "Sum: $sum\n";

function add($a, $b) {
    return $a + $b;
}

$result = add(5, 3);
echo "Result: $result\n";
