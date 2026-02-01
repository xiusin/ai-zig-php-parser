<?php
// 测试时间和随机数函数

echo "=== 时间函数测试 ===\n";

// time() - 返回当前时间戳
$timestamp = time();
echo "当前时间戳: " . $timestamp . "\n";

// microtime() - 返回微秒时间
$microtime_str = microtime(false);
echo "microtime(字符串): " . $microtime_str . "\n";

$microtime_float = microtime(true);
echo "microtime(浮点数): " . $microtime_float . "\n";

// date() - 格式化日期（简化版）
$date_str = date("Y-m-d H:i:s", $timestamp);
echo "格式化日期: " . $date_str . "\n";

echo "\n=== 随机数函数测试 ===\n";

// rand() - 生成随机数
$rand1 = rand(0, 2147483647);  // RAND_MAX
echo "rand(): " . $rand1 . "\n";

$rand2 = rand(1, 100);
echo "rand(1, 100): " . $rand2 . "\n";

// mt_rand() - Mersenne Twister随机数
$mt_rand1 = mt_rand(0, 2147483647);  // MT_RAND_MAX
echo "mt_rand(): " . $mt_rand1 . "\n";

$mt_rand2 = mt_rand(1, 100);
echo "mt_rand(1, 100): " . $mt_rand2 . "\n";

// srand() - 设置随机数种子
srand(12345);
$seeded_rand1 = rand(1, 100);
echo "srand(12345) 后 rand(1, 100): " . $seeded_rand1 . "\n";

// 再次设置相同种子，应该得到相同的随机数
srand(12345);
$seeded_rand2 = rand(1, 100);
echo "再次 srand(12345) 后 rand(1, 100): " . $seeded_rand2 . "\n";
echo "两次结果相同: " . ($seeded_rand1 === $seeded_rand2 ? "是" : "否") . "\n";

// random_int() - 密码学安全的随机整数
$random_int = random_int(1, 100);
echo "random_int(1, 100): " . $random_int . "\n";

// random_bytes() - 密码学安全的随机字节
$random_bytes = random_bytes(16);
echo "random_bytes(16) 长度: " . strlen($random_bytes) . "\n";

echo "\n=== 测试完成 ===\n";
