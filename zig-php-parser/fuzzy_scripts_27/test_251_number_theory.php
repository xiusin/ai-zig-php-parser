<?php
function gcd2(int $a, int $b): int {
    while ($b !== 0) {
        [$a, $b] = [$b, $a % $b];
    }
    return $a;
}

function lcm2(int $a, int $b): int {
    return abs($a * $b) / gcd2($a, $b);
}

function areCoprime(int $a, int $b): bool {
    return gcd2($a, $b) === 1;
}

function primeFactors(int $n): array {
    $factors = [];
    $d = 2;
    while ($d * $d <= $n) {
        while ($n % $d === 0) {
            $factors[] = $d;
            $n /= $d;
        }
        $d++;
    }
    if ($n > 1) $factors[] = $n;
    return $factors;
}

function isPerfectNumber(int $n): bool {
    if ($n < 2) return false;
    $sum = 1;
    for ($i = 2; $i * $i <= $n; $i++) {
        if ($n % $i === 0) {
            $sum += $i;
            if ($i !== $n / $i) $sum += $n / $i;
        }
    }
    return $sum === $n;
}

echo gcd2(48, 18) . "\n";
echo lcm2(4, 6) . "\n";
echo areCoprime(7, 11) ? 'true' : 'false' . "\n";
echo areCoprime(7, 14) ? 'true' : 'false' . "\n";
echo implode(',', primeFactors(60)) . "\n";
echo isPerfectNumber(6) ? 'true' : 'false' . "\n";
echo isPerfectNumber(28) ? 'true' : 'false' . "\n";
echo "OK\n";
