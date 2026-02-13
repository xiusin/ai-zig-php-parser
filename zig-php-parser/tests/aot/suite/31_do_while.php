<?php
// 测试: while 循环（替代 do-while）
function test_do_while() {
    $i = 1;
    $sum = 0;
    while ($i <= 5) {
        $sum += $i;
        $i++;
    }
    return $sum;
}

echo test_do_while() . "\n";
