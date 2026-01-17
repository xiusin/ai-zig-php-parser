<?php
// 字符串函数性能测试
echo "=== 字符串函数性能测试 ===\n";

$iterations = 10000;
$test_string = "Hello World! This is a test string for benchmarking PHP interpreter performance.";
$short_string = "hello";

// 字符串长度
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $len = strlen($test_string . $i);
}
$end = microtime(true);
echo sprintf("strlen %d 次: %.4f 秒\n", $iterations, $end - $start);

// 字符串查找
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $pos = strpos($test_string, "test");
    $last_pos = strrpos($test_string, " ");
}
$end = microtime(true);
echo sprintf("strpos/strrpos %d 次: %.4f 秒\n", $iterations, $end - $start);

// 字符串截取
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $substr = substr($test_string, 6, 10);
    $left = substr($test_string, 0, 5);
    $right = substr($test_string, -5);
}
$end = microtime(true);
echo sprintf("substr %d 次: %.4f 秒\n", $iterations, $end - $start);

// 字符串替换
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $replaced = str_replace("Hello", "Hi", $test_string);
    $ireplaced = str_ireplace("world", "universe", $test_string);
}
$end = microtime(true);
echo sprintf("str_replace %d 次: %.4f 秒\n", $iterations, $end - $start);

// 字符串大小写转换
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $upper = strtoupper($test_string);
    $lower = strtolower($test_string);
    $ucfirst = ucfirst($test_string);
    $ucwords = ucwords($test_string);
}
$end = microtime(true);
echo sprintf("大小写转换 %d 次: %.4f 秒\n", $iterations, $end - $start);

// 字符串分割和连接
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $parts = explode(" ", $test_string);
    $joined = implode("-", $parts);
}
$end = microtime(true);
echo sprintf("explode/implode %d 次: %.4f 秒\n", $iterations, $end - $start);

// 字符串修剪
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $trimmed = trim($test_string . " \t\n\r");
    $ltrimmed = ltrim($test_string . " \t\n\r");
    $rtrimmed = rtrim($test_string . " \t\n\r");
}
$end = microtime(true);
echo sprintf("trim/ltrim/rtrim %d 次: %.4f 秒\n", $iterations, $end - $start);

// 正则表达式
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $matched = preg_match("/test/i", $test_string);
    $replaced = preg_replace("/\s+/", "_", $test_string);
}
$end = microtime(true);
echo sprintf("preg_match/preg_replace %d 次: %.4f 秒\n", $iterations, $end - $start);
