<?php
function factorial(int $n): int|float {
    if ($n < 0) return 0;
    if ($n <= 1) return 1;
    $result = 1;
    for ($i = 2; $i <= $n; $i++) {
        $result *= $i;
    }
    return $result;
}

function fibonacci2(int $n): int {
    if ($n <= 1) return $n;
    $a = 0;
    $b = 1;
    for ($i = 2; $i <= $n; $i++) {
        [$a, $b] = [$b, $a + $b];
    }
    return $b;
}

function isFibonacci(int $n): bool {
    $a = 5 * $n * $n + 4;
    $b = 5 * $n * $n - 4;
    $sqrtA = sqrt($a);
    $sqrtB = sqrt($b);
    return ($sqrtA * $sqrtA === (int)$sqrtA || $sqrtB * $sqrtB === (int)$sqrtB);
}

function triangularNumber(int $n): int {
    return $n * ($n + 1) / 2;
}

function isTriangular(int $n): bool {
    $x = (-1 + sqrt(1 + 8 * $n)) / 2;
    return $x === (int)$x;
}

echo factorial(5) . "\n";
echo fibonacci2(10) . "\n";
echo isFibonacci(5) ? 'true' : 'false' . "\n";
echo isFibonacci(4) ? 'true' : 'false' . "\n";
echo triangularNumber(7) . "\n";
echo isTriangular(10) ? 'true' : 'false' . "\n";
echo "OK\n";
