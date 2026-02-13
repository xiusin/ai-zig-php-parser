<?php
// 测试: 逻辑运算符
function test_logical($a, $b) {
    if ($a > 5 && $b < 10) {
        return "both";
    } elseif ($a > 5 || $b < 10) {
        return "one";
    } else {
        return "none";
    }
}

echo test_logical(6, 8) . "\n";
echo test_logical(4, 8) . "\n";
echo test_logical(6, 12) . "\n";
