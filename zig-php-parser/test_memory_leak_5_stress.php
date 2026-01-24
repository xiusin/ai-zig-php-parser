<?php
// 测试用例5：内存压力测试
// 目的：大量迭代，验证无内存泄漏累积

echo "Test 5: Memory stress test (100 iterations)\n";

$count = 0;
while ($count < 100) {
    $msg = "Iteration ";
    echo $msg;
    echo $count;
    echo "\n";
    $count = $count + 1;
}

echo "Test 5 completed\n";
