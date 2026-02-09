<?php
// 复杂场景测试 3: 递归和算法

// 测试 1: 阶乘
function factorial(int $n): int {
    if ($n <= 1) return 1;
    return $n * factorial($n - 1);
}

echo "Factorial of 5: " . factorial(5) . "\n";
echo "Factorial of 10: " . factorial(10) . "\n";

// 测试 2: 斐波那契
function fibonacci(int $n): int {
    if ($n <= 1) return $n;
    return fibonacci($n - 1) + fibonacci($n - 2);
}

echo "Fibonacci of 10: " . fibonacci(10) . "\n";

// 测试 3: 最大公约数
function gcd(int $a, int $b): int {
    if ($b === 0) return $a;
    return gcd($b, $a % $b);
}

echo "GCD of 48 and 18: " . gcd(48, 18) . "\n";

echo "\nTest 3 passed!\n";
