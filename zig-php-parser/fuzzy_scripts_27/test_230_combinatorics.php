<?php
function combination(int $n, int $k): int {
    if ($k < 0 || $k > $n) return 0;
    if ($k === 0 || $k === $n) return 1;

    $k = min($k, $n - $k);
    $result = 1;

    for ($i = 0; $i < $k; $i++) {
        $result = $result * ($n - $i) / ($i + 1);
    }

    return (int)$result;
}

function permutations(int $n, int $k): int {
    if ($k < 0 || $k > $n) return 0;
    $result = 1;
    for ($i = 0; $i < $k; $i++) {
        $result *= ($n - $i);
    }
    return $result;
}

function fibonacci(int $n): int {
    if ($n <= 1) return $n;
    $a = 0;
    $b = 1;
    for ($i = 2; $i <= $n; $i++) {
        [$a, $b] = [$b, $a + $b];
    }
    return $b;
}

function isPrime(int $n): bool {
    if ($n < 2) return false;
    if ($n === 2) return true;
    if ($n % 2 === 0) return false;
    for ($i = 3; $i * $i <= $n; $i += 2) {
        if ($n % $i === 0) return false;
    }
    return true;
}

function gcd(int $a, int $b): int {
    while ($b !== 0) {
        [$a, $b] = [$b, $a % $b];
    }
    return $a;
}

function lcm(int $a, int $b): int {
    return abs($a * $b) / gcd($a, $b);
}

echo combination(5, 2) . "\n";
echo combination(10, 3) . "\n";
echo permutations(5, 2) . "\n";
echo fibonacci(10) . "\n";
echo isPrime(17) ? 'true' : 'false' . "\n";
echo isPrime(18) ? 'true' : 'false' . "\n";
echo gcd(48, 18) . "\n";
echo lcm(4, 6) . "\n";
echo "OK\n";
