<?php
// 测试: 嵌套循环
function test_nested_loop() {
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        for ($j = 0; $j < 3; $j++) {
            $sum += $i * $j;
        }
    }
    return $sum;
}

echo test_nested_loop() . "\n";
