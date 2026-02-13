<?php
// 测试: 混合 break/continue 多层级
function test_mixed_levels() {
    $result = "";
    for ($i = 0; $i < 3; $i++) {
        for ($j = 0; $j < 3; $j++) {
            for ($k = 0; $k < 3; $k++) {
                for ($l = 0; $l < 3; $l++) {
                    $result .= "$i$j$k$l ";
                    if ($l == 1) continue;
                    if ($k == 1 && $l == 0) continue 2;
                    if ($j == 1 && $k == 0 && $l == 0) break 3;
                }
            }
        }
    }
    return $result;
}

echo test_mixed_levels() . "\n";
