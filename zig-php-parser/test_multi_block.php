<?php
// 测试多块函数（应该使用状态机）
// 这个函数有多个基本块（if-else），应该生成状态机

function max_value($a, $b) {
    if ($a > $b) {
        return $a;
    } else {
        return $b;
    }
}

$result = max_value(15, 25);
echo "Max: ";
echo $result;
echo "\n";
