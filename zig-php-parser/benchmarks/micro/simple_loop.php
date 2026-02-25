<?php
// 简单循环基准测试
function sum(int $n): int {
    $total = 0;
    for ($i = 1; $i <= $n; $i++) {
        $total += $i;
    }
    return $total;
}

echo "Loop Sum Benchmark\n";
echo "Result: " . sum(1000) . "\n";
