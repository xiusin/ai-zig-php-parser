<?php
// 测试: while 循环
function test_while() {
    $i = 0;
    $sum = 0;
    while ($i < 5) {
        $sum += $i;
        $i++;
    }
    return $sum;
}

echo test_while() . "\n";
