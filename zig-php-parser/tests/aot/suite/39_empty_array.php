<?php
// 测试: 空数组
function test_empty_array() {
    $arr = [];
    return count($arr);
}

echo test_empty_array() . "\n";
