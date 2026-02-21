<?php
// 测试: 可变参数
function sum_all(...$numbers) {
    $sum = 0;
    foreach ($numbers as $n) {
        $sum += $n;
    }
    return $sum;
}

$result = sum_all(1, 2, 3, 4, 5);
echo "Variadic: $result (expect 15)\n";
