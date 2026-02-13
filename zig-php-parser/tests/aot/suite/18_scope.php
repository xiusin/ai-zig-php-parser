<?php
// 测试: 简单变量作用域
$global_var = 100;

function test_scope() {
    $local_var = 50;
    return $local_var;
}

echo test_scope() . "\n";
