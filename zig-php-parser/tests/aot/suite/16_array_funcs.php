<?php
// 测试: 数组内置函数
function test_array_funcs() {
    $arr = [3, 1, 4, 1, 5];
    return array_sum($arr);
}

echo test_array_funcs() . "\n";
