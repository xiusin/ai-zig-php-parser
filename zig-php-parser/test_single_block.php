<?php
// 测试单块函数优化
// 这个函数只有一个基本块，应该生成线性代码而不是状态机

function simple_add($a, $b) {
    return $a + $b;
}

$result = simple_add(10, 20);
echo "Result: ";
echo $result;
echo "\n";
