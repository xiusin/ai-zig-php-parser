<?php
// array_filter 性能测试
// 对比 Zig-PHP 实现

$iterations = 5000;
$start = microtime(true);

for ($i = 0; $i < $iterations; $i++) {
    $arr = [1, 2, 3, 4, 5];
    $filtered = array_filter($arr, function($val) {
        return $val > 2;
    });
}

$end = microtime(true);
$total_time = ($end - $start) * 1000;
$avg_time = $total_time / $iterations;
$ops_per_sec = $iterations / ($end - $start);

echo "================================================================================\n";
echo "array_filter 性能测试 - 原生 PHP\n";
echo "================================================================================\n";
echo "\n";
echo "迭代次数: $iterations\n";
echo "总耗时: " . number_format($total_time, 2) . " ms\n";
echo "平均耗时: " . number_format($avg_time, 6) . " ms\n";
echo "操作/秒: " . number_format($ops_per_sec, 2) . " ops/s\n";
echo "\n";
