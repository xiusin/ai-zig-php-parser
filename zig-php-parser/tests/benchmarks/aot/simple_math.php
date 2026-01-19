<?php
// 简单的数学运算测试
// 用于 AOT 性能测试

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

function sum_array($arr) {
    $sum = 0;
    foreach ($arr as $val) {
        $sum += $val;
    }
    return $sum;
}

// 执行测试
$fib_result = fibonacci(20);
$fact_result = factorial(10);

$numbers = range(1, 100);
$sum_result = sum_array($numbers);

echo "Fibonacci(20) = $fib_result\n";
echo "Factorial(10) = $fact_result\n";
echo "Sum(1..100) = $sum_result\n";
