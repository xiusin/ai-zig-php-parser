<?php
// 测试: 空值处理
function test_null() {
    $x = null;
    if ($x === null) {
        return "is_null";
    }
    return "not_null";
}

echo test_null() . "\n";
