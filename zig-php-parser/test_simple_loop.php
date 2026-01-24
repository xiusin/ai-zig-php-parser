<?php
// 简单的循环测试，验证内存管理
echo "Testing memory management in loops\n";

// 测试1：简单while循环
$i = 0;
while ($i < 5) {
    echo "Iteration ";
    echo $i;
    echo "\n";
    $i = $i + 1;
}

echo "Done!\n";
