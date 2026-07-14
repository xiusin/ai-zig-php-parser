<?php
// 日期时间函数：time, date, strtotime, mktime

// 测试 time
$timestamp = 1705321845;
echo "timestamp: $timestamp\n";

// 测试 date
echo "date_default: " . date('Y-m-d', $timestamp) . "\n";
echo "date_time: " . date('Y-m-d H:i:s', $timestamp) . "\n";
echo "date_format: " . date('d/m/Y', $timestamp) . "\n";

// 测试 strtotime
echo "strtotime_now: " . strtotime('2024-01-15') . "\n";
echo "strtotime_offset: " . date('Y-m-d', strtotime('+1 month', strtotime('2024-01-15'))) . "\n";
echo "strtotime_relative: " . date('Y-m-d', strtotime('-1 week', strtotime('2024-01-15'))) . "\n";

// 测试 mktime
$mk = mktime(12, 30, 0, 1, 15, 2024);
echo "mktime: " . date('Y-m-d H:i:s', $mk) . "\n";

// 测试日期比较
$ts1 = strtotime('2024-01-15');
$ts2 = strtotime('2024-02-15');
$diff = $ts2 - $ts1;
echo "diff_days: " . intdiv($diff, 86400) . "\n";

// 测试 checkdate
echo "checkdate_valid: " . (checkdate(2, 29, 2024) ? 'true' : 'false') . "\n";
echo "checkdate_invalid: " . (checkdate(2, 29, 2023) ? 'true' : 'false') . "\n";

// 测试日期格式化
echo "year: " . date('Y', $timestamp) . "\n";
echo "month: " . date('m', $timestamp) . "\n";
echo "day: " . date('d', $timestamp) . "\n";
