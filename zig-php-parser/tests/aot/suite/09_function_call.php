<?php
// 测试: 函数调用
function add($a, $b) {
    return $a + $b;
}

function test_function_call() {
    $result = add(10, 20);
    return $result;
}

echo test_function_call() . "\n";
