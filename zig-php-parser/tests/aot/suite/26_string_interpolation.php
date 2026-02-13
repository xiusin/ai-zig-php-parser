<?php
// 测试: 字符串插值
function test_string_interpolation() {
    $name = "World";
    $num = 42;
    return "Hello $name, number is $num";
}

echo test_string_interpolation() . "\n";
