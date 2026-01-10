<?php
// 基础并发测试
echo "Starting concurrency test\n";

// 模拟并发操作
function worker($id) {
    echo "Worker $id started\n";
    // 模拟一些工作
    for ($i = 0; $i < 3; $i++) {
        echo "Worker $id doing work $i\n";
        // 模拟延迟
        usleep(100000);
    }
    echo "Worker $id finished\n";
}

// 启动多个"线程"
for ($i = 1; $i <= 3; $i++) {
    // 在实际实现中，这会是真正的并发
    worker($i);
}

echo "Concurrency test completed\n";
?>