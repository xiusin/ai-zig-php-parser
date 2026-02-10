<?php

// 极限性能测试 - 纯整数操作

class Perf {
    public const ITERATIONS = 10000000;  // 1000万次
}

// 测试 1: 纯整数加法
$start = microtime(true);
$sum = 0;
for ($i = 0; $i < Perf::ITERATIONS; $i++) {
    $sum = $sum + 1;
}
$end = microtime(true);
$elapsed = ($end - $start) * 1000;
$avg = $elapsed * 1000000 / Perf::ITERATIONS;
echo "Integer add: {$elapsed}ms total, {$avg}ns avg\n";

// 测试 2: 纯整数乘法
$start = microtime(true);
$result = 1;
for ($i = 0; $i < Perf::ITERATIONS; $i++) {
    $result = 42 * 2;
}
$end = microtime(true);
$elapsed = ($end - $start) * 1000;
$avg = $elapsed * 1000000 / Perf::ITERATIONS;
echo "Integer mul: {$elapsed}ms total, {$avg}ns avg\n";

// 测试 3: 常量折叠（应该被完全优化掉）
$start = microtime(true);
for ($i = 0; $i < Perf::ITERATIONS; $i++) {
    $x = 42 + 1;
}
$end = microtime(true);
$elapsed = ($end - $start) * 1000;
$avg = $elapsed * 1000000 / Perf::ITERATIONS;
echo "Constant fold: {$elapsed}ms total, {$avg}ns avg\n";
