<?php
// 测试: foreach 循环
function test_foreach() {
    $arr = [1, 2, 3, 4, 5];
    $sum = 0;
    foreach ($arr as $val) {
        $sum += $val;
    }
    return $sum;
}

echo test_foreach() . "\n";
