<?php
// 测试: 关联数组
function test_assoc_array() {
    $arr = ["a" => 1, "b" => 2, "c" => 3];
    return $arr["b"];
}

echo test_assoc_array() . "\n";
