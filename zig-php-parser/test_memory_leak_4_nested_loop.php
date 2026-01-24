<?php
// 测试用例4：嵌套循环
// 目的：验证嵌套循环中的内存管理

echo "Test 4: Nested loops\n";

$i = 0;
while ($i < 3) {
    $j = 0;
    while ($j < 3) {
        echo "i=";
        echo $i;
        echo " j=";
        echo $j;
        echo "\n";
        $j = $j + 1;
    }
    $i = $i + 1;
}

echo "Test 4 completed\n";
