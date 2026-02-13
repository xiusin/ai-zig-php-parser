<?php
// 测试: do-while 循环
function test_do_while() {
    $i = 1;
    $sum = 0;
    do {
        $sum += $i;
        $i++;
    } while ($i <= 5);
    return $sum;
}

echo test_do_while() . "\n";
