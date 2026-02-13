<?php
// 测试: 布尔运算
function test_bool() {
    $a = true;
    $b = false;
    if ($a && !$b) {
        return "yes";
    }
    return "no";
}

echo test_bool() . "\n";
