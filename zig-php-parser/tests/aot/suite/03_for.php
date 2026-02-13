<?php
// 测试: for 循环
function test_for() {
    $sum = 0;
    for ($i = 0; $i < 10; $i++) {
        $sum += $i;
    }
    return $sum;
}

echo test_for() . "\n";
