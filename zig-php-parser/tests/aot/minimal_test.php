<?php
// 最小综合测试
echo "=== Minimal Comprehensive Test ===\n\n";

// 1. 基本循环
$sum = 0;
for ($i = 0; $i < 10; $i++) {
    $sum += $i;
}
echo "1. Loop sum: $sum\n";

// 2. 数组
$arr = array(1, 2, 3, 4, 5);
$count = count($arr);
echo "2. Array count: $count\n";

// 3. 字符串
$str = "Hello";
$len = strlen($str);
echo "3. String length: $len\n";

// 4. 多个循环
$sum1 = 0;
for ($i = 0; $i < 5; $i++) {
    $sum1 += $i;
}
$sum2 = 0;
for ($j = 0; $j < 5; $j++) {
    $sum2 += $j;
}
echo "4. Multiple loops: $sum1, $sum2\n";

echo "\n=== Test Complete ===\n";
