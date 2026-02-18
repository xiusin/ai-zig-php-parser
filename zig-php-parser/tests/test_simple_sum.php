<?php
// 简单累加测试
function test_simple_sum() {
    $sum = 0;
    for ($i = 0; $i < 3; $i++) {
        $sum += 1;
    }
    return $sum;
}

$result = test_simple_sum();
echo "Result: $result (expect 3)\n";
