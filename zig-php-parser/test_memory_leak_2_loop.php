<?php
// 测试用例2：循环中的变量
// 目的：验证循环中的临时变量正确释放

echo "Test 2: Loop with variables\n";

$i = 0;
while ($i < 10) {
    $temp = $i + 1;
    echo $temp;
    echo "\n";
    $i = $i + 1;
}

echo "Test 2 completed\n";
