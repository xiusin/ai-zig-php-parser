<?php
// 测试：数学运算 + 位运算 + 类型转换
function calculate_stats($numbers) {
    $sum = 0;
    $min = $numbers[0];
    $max = $numbers[0];
    
    foreach ($numbers as $num) {
        $sum += $num;
        if ($num < $min) $min = $num;
        if ($num > $max) $max = $num;
    }
    
    $count = count($numbers);
    $avg = $sum / $count;
    
    return [
        "sum" => $sum,
        "avg" => $avg,
        "min" => $min,
        "max" => $max,
        "count" => $count
    ];
}

$data = [12, 45, 23, 67, 34, 89, 15, 56, 78, 91];

echo "Data: ";
foreach ($data as $n) {
    echo $n . " ";
}
echo "\n\n";

$stats = calculate_stats($data);
echo "Statistics:\n";
echo "  Count: " . $stats["count"] . "\n";
echo "  Sum: " . $stats["sum"] . "\n";
echo "  Average: " . $stats["avg"] . "\n";
echo "  Min: " . $stats["min"] . "\n";
echo "  Max: " . $stats["max"] . "\n";

// 位运算测试
echo "\nBitwise operations:\n";
$a = 12;  // 1100
$b = 10;  // 1010
echo "$a & $b = " . ($a & $b) . "\n";  // 1000 = 8
echo "$a | $b = " . ($a | $b) . "\n";  // 1110 = 14
echo "$a ^ $b = " . ($a ^ $b) . "\n";  // 0110 = 6
echo "$a << 2 = " . ($a << 2) . "\n";  // 48
echo "$a >> 1 = " . ($a >> 1) . "\n";  // 6

// 幂运算
echo "\nPower operations:\n";
for ($i = 0; $i <= 5; $i++) {
    echo "2^$i = " . pow(2, $i) . "\n";
}
