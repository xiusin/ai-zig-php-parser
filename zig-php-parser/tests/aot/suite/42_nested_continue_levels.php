<?php
// 测试: 多层嵌套 continue
function test_nested_continue() {
    $result = "";
    for ($i = 0; $i < 3; $i++) {
        for ($j = 0; $j < 3; $j++) {
            if ($j == 1) continue;
            for ($k = 0; $k < 3; $k++) {
                if ($i == 1 && $k == 1) continue 2;
                $result .= "$i$j$k ";
            }
        }
    }
    return $result;
}

echo test_nested_continue() . "\n";
