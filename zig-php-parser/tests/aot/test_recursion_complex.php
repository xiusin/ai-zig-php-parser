<?php
// 测试：递归 + 数组 + 条件
function fibonacci($n) {
    if ($n <= 1) {
        return $n;
    }
    return fibonacci($n - 1) + fibonacci($n - 2);
}

function factorial($n) {
    if ($n <= 1) {
        return 1;
    }
    return $n * factorial($n - 1);
}

echo "Fibonacci sequence:\n";
for ($i = 0; $i < 10; $i++) {
    echo fibonacci($i) . " ";
}
echo "\n";

echo "\nFactorials:\n";
for ($i = 1; $i <= 8; $i++) {
    echo "$i! = " . factorial($i) . "\n";
}

// 递归数组求和
function array_sum_recursive($arr) {
    if (count($arr) == 0) {
        return 0;
    }
    $first = $arr[0];
    $rest = [];
    for ($i = 1; $i < count($arr); $i++) {
        $rest[] = $arr[$i];
    }
    return $first + array_sum_recursive($rest);
}

$numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
echo "\nRecursive sum of [1..10]: " . array_sum_recursive($numbers) . "\n";
