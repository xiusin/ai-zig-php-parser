<?php
// 测试: 多层嵌套循环 + break
function test_nested_break() {
    $sum = 0;
    for ($i = 0; $i < 5; $i++) {
        for ($j = 0; $j < 5; $j++) {
            $sum += $i + $j;
            if ($j == 2) {
                break;
            }
        }
    }
    return $sum;
}

echo test_nested_break() . "\n";
