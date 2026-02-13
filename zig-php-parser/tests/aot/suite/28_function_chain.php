<?php
// 测试: 多函数调用链
function add($a, $b) {
    return $a + $b;
}

function mul($a, $b) {
    return $a * $b;
}

function calc($x) {
    return mul(add($x, 5), 2);
}

echo calc(10) . "\n";
