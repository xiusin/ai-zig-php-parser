<?php
// 最简单的循环测试
function bench_simple_loop() {
    $count = 0;
    for ($i = 0; $i < 1000000; $i++) {
        $count++;
    }
    return $count;
}

$start = microtime(true);
$result = bench_simple_loop();
$time = microtime(true) - $start;

echo "Result: $result\n";
echo "Time: " . number_format($time * 1000, 2) . " ms\n";
