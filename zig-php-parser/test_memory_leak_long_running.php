<?php
// 长时间运行的内存测试
echo "Starting long-running memory test...\n";

$count = 0;
while ($count < 10000) {
    $msg = "Iteration ";
    $temp = $msg . $count;
    $count = $count + 1;
}

echo "Completed 10000 iterations\n";
