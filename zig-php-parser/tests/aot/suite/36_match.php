<?php
// 测试: match 表达式
function test_match($x) {
    return match ($x) {
        1 => "one",
        2 => "two",
        3 => "three",
        default => "other"
    };
}

echo test_match(2) . "\n";
echo test_match(5) . "\n";
