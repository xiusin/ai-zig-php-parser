<?php
// 测试: 嵌套 foreach
function test_nested_foreach() {
    $arr1 = [1, 2, 3];
    $arr2 = [10, 20];
    $sum = 0;
    foreach ($arr1 as $a) {
        foreach ($arr2 as $b) {
            $sum += $a * $b;
        }
    }
    return $sum;
}

echo test_nested_foreach() . "\n";
