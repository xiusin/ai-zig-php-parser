<?php
// 测试: 闭包基础功能
function test_closure() {
    $x = 10;
    $add = function($y) use ($x) {
        return $x + $y;
    };
    return $add(5);
}

echo "Closure: " . test_closure() . " (expect 15)\n";
