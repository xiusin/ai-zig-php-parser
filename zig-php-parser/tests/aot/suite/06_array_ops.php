<?php
// 测试: 数组操作
function test_array() {
    $arr = [];
    $arr[] = 10;
    $arr[] = 20;
    $arr[] = 30;
    return count($arr);
}

echo test_array() . "\n";
