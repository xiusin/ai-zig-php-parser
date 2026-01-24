<?php
// 内存压力测试 - 大量循环创建字符串
echo "Memory stress test starting...\n";

$count = 0;
while ($count < 100) {
    echo "Iteration ";
    echo $count;
    echo "\n";
    $count = $count + 1;
}

echo "Memory stress test completed!\n";
