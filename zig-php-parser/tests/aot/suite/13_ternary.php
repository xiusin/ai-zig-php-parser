<?php
// 测试: 三元运算符
function test_ternary($x) {
    return $x > 10 ? "big" : "small";
}

echo test_ternary(15) . "\n";
echo test_ternary(5) . "\n";
