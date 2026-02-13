<?php
// 测试: if-elseif 替代 match
function test_match($x) {
    if ($x === 1) {
        return "one";
    } elseif ($x === 2) {
        return "two";
    } elseif ($x === 3) {
        return "three";
    } else {
        return "other";
    }
}

echo test_match(2) . "\n";
echo test_match(5) . "\n";
