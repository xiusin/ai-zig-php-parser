<?php
// 测试: 复杂数组操作
function test_complex_array() {
    $arr = [];
    for ($i = 0; $i < 5; $i++) {
        $arr[] = $i * 2;
    }
    $sum = 0;
    foreach ($arr as $val) {
        $sum += $val;
    }
    return $sum;
}

echo test_complex_array() . "\n";
