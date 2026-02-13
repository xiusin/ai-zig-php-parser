<?php
// 测试: continue 语句
function test_continue() {
    $sum = 0;
    for ($i = 0; $i < 10; $i++) {
        if ($i % 2 == 0) {
            continue;
        }
        $sum += $i;
    }
    return $sum;
}

echo test_continue() . "\n";
