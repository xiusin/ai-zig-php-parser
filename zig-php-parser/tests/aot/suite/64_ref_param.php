<?php
// 测试: 引用传递
function addTen(&$num) {
    $num += 10;
}

$x = 5;
addTen($x);
echo "RefParam: $x (expect 15)\n";
