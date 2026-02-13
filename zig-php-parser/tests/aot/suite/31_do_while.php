<?php
// 测试: do-while
function test_do_while() {
    $i = 0;
    $sum = 0;
    do {
        $sum += $i;
        $i++;
    } while ($i < 5);
    return $sum;
}

echo test_do_while() . "\n";
