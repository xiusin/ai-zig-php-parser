<?php
// 循环累加基准测试
function sum(int $n): int {
    $total = 0;
    for ($i = 1; $i <= $n; $i++) {
        $total += $i;
    }
    return $total;
}

$iterations = 10000;
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    sum(100);
}
$end = microtime(true);

$time_ms = ($end - $start) * 1000;

echo "Loop Sum Benchmark\n";
echo "Iterations: " . $iterations . "\n";
echo "Time: " . $time_ms . " ms\n";

