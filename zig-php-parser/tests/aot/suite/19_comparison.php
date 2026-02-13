<?php
// 测试: 比较运算符
function test_comparison($a, $b) {
    if ($a == $b) return "equal";
    if ($a != $b) return "not_equal";
    return "unknown";
}

echo test_comparison(5, 5) . "\n";
echo test_comparison(5, 10) . "\n";
