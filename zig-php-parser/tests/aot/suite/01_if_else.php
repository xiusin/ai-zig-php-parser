<?php
// 测试: if-else 基础控制流
function test_if_else($x) {
    if ($x > 10) {
        return "large";
    } else {
        return "small";
    }
}

echo test_if_else(15) . "\n";
echo test_if_else(5) . "\n";
