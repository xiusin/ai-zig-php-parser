<?php
// 测试: 复杂条件表达式
function test_complex_condition($x, $y, $z) {
    if (($x > 5 && $y < 10) || ($z == 0 && $x != $y)) {
        return "match";
    }
    return "no_match";
}

echo test_complex_condition(6, 8, 0) . "\n";
echo test_complex_condition(4, 8, 0) . "\n";
echo test_complex_condition(6, 12, 1) . "\n";
