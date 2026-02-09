<?php
// 最小引用返回测试

function &getRef(array &$arr, int $idx) {
    return $arr[$idx];
}

$data = [10, 20, 30];
echo "Before: " . $data[1] . "\n";

$ref = &getRef($data, 1);
$ref = 99;

echo "After: " . $data[1] . "\n";
echo "Expected: 99\n";
