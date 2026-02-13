<?php
// 测试: match 嵌套在循环中
function test_match_in_loop() {
    $result = "";
    for ($i = 1; $i <= 3; $i++) {
        $val = match ($i) {
            1 => "a",
            2 => "b",
            default => "c"
        };
        $result .= $val;
    }
    return $result;
}

echo test_match_in_loop() . "\n";
