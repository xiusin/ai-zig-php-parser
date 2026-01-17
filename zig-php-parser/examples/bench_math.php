<?php
// 数学函数性能测试
echo "=== 数学函数性能测试 ===\n";

// 整数运算
$iterations = 100000;
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = abs(-$i) + intval($i / 2) + ceil($i * 0.7) + floor($i * 0.3);
}
$end = microtime(true);
echo sprintf("整数运算 %d 次: %.4f 秒\n", $iterations, $end - $start);

// 浮点运算
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = sqrt($i + 1) + pow($i % 100, 2.5) + sin($i * 0.01) + cos($i * 0.01);
}
$end = microtime(true);
echo sprintf("浮点运算 %d 次: %.4f 秒\n", $iterations, $end - $start);

// 数学函数
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = max($i, $i + 1) + min($i, $i - 1) + round($i * 1.23456, 2);
}
$end = microtime(true);
echo sprintf("数学函数 %d 次: %.4f 秒\n", $iterations, $end - $start);
