<?php
// 微基准测试：循环性能
function bench_loop() {
    $sum = 0;
    for ($i = 0; $i < 1000000; $i++) {
        $sum += $i;
    }
    return $sum;
}

$start = microtime(true);
$result = bench_loop();
$time = microtime(true) - $start;

echo "Result: $result\n";
echo "Time: " . number_format($time * 1000, 2) . " ms\n";
