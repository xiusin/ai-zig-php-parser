<?php
// 简单的计数器并发测试
$counter = 0;

// 模拟并发增加
for ($i = 0; $i < 10; $i++) {
    $counter++;
    echo "Counter: $counter\n";
}

echo "Final counter value: $counter\n";
?>