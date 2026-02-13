<?php
// 测试: 前置/后置递增
function test_increment() {
    $a = 5;
    $b = $a++;
    $c = ++$a;
    return $b + $c;
}

echo test_increment() . "\n";
