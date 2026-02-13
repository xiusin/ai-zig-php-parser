<?php
// 测试: foreach with break
function test_foreach_break() {
    $arr = [1, 2, 3, 4, 5];
    $sum = 0;
    foreach ($arr as $val) {
        $sum += $val;
        if ($val == 3) {
            break;
        }
    }
    return $sum;
}

echo test_foreach_break() . "\n";
