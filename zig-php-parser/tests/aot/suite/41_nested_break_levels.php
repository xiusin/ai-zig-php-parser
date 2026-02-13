<?php
// 测试: 多层嵌套 break
function test_nested_break() {
    $result = "";
    for ($i = 0; $i < 3; $i++) {
        for ($j = 0; $j < 3; $j++) {
            for ($k = 0; $k < 3; $k++) {
                $result .= "$i$j$k ";
                if ($k == 1) break;
                if ($j == 1 && $k == 0) break 2;
            }
        }
    }
    return $result;
}

echo test_nested_break() . "\n";
