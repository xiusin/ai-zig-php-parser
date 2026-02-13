<?php
// 测试: 数组修改
function test_array_modify() {
    $arr = [1, 2, 3];
    $arr[1] = 10;
    $arr[2] = $arr[0] + $arr[1];
    return $arr[2];
}

echo test_array_modify() . "\n";
