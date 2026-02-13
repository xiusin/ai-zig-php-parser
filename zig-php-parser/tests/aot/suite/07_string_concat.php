<?php
// 测试: 字符串拼接
function test_string_concat() {
    $str = "Hello";
    $str = $str . " ";
    $str = $str . "World";
    return $str;
}

echo test_string_concat() . "\n";
