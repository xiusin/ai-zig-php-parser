<?php
// 测试: 数组 push 多个
function test_array_push() {
    $arr = [1, 2];
    $arr[] = 3;
    $arr[] = 4;
    $arr[] = 5;
    return count($arr);
}

echo test_array_push() . "\n";
