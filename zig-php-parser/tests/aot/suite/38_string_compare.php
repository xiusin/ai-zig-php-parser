<?php
// 测试: 字符串比较
function test_string_compare() {
    $a = "hello";
    $b = "hello";
    $c = "world";
    if ($a == $b && $a != $c) {
        return "pass";
    }
    return "fail";
}

echo test_string_compare() . "\n";
