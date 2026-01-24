<?php
// 测试循环中的内存管理
$i = 0;
while ($i < 3) {
    $msg = "Iteration ";
    $num = $i;
    echo $msg;
    echo $num;
    echo "\n";
    $i = $i + 1;
}
