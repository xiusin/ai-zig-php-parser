<?php
// 极度混搭: 数论 + 素数 + GCD/LCM + 模运算 + 快速幂 + 费马小定理
echo "=== f027: Number Theory + Primes + Modular ===\n";

class NumberTheory {
    public static function gcd(int $a, int $b): int {
        $a = abs($a); $b = abs($b);
        while ($b !== 0) { $t = $b; $b = $a % $b; $a = $t; }
        return $a;
    }

    public static function lcm(int $a, int $b): int {
        if ($a === 0 || $b === 0) return 0;
        return abs($a * $b) / self::gcd($a, $b);
    }

    public static function isPrime(int $n): bool {
        if ($n < 2) return false;
        if ($n < 4) return true;
        if ($n % 2 === 0 || $n % 3 === 0) return false;
        for ($i = 5; $i * $i <= $n; $i += 6) {
            if ($n % $i === 0 || $n % ($i + 2) === 0) return false;
        }
        return true;
    }

    public static function sieveOfEratosthenes(int $n): array {
        if ($n < 2) return [];
        $sieve = array_fill(0, $n + 1, true);
        $sieve[0] = $sieve[1] = false;
        for ($i = 2; $i * $i <= $n; $i++) {
            if ($sieve[$i]) {
                for ($j = $i * $i; $j <= $n; $j += $i) $sieve[$j] = false;
            }
        }
        $primes = [];
        for ($i = 2; $i <= $n; $i++) if ($sieve[$i]) $primes[] = $i;
        return $primes;
    }

    public static function primeFactors(int $n): array {
        $factors = [];
        for ($i = 2; $i * $i <= $n; $i++) {
            while ($n % $i === 0) {
                $factors[$i] = ($factors[$i] ?? 0) + 1;
                $n = (int)($n / $i);
            }
        }
        if ($n > 1) $factors[$n] = ($factors[$n] ?? 0) + 1;
        return $factors;
    }

    public static function powerMod(int $base, int $exp, int $mod): int {
        $result = 1;
        $base = $base % $mod;
        while ($exp > 0) {
            if ($exp % 2 === 1) $result = ($result * $base) % $mod;
            $exp = (int)($exp / 2);
            $base = ($base * $base) % $mod;
        }
        return $result;
    }

    public static function extendedGcd(int $a, int $b): array {
        if ($b === 0) return ['gcd' => $a, 'x' => 1, 'y' => 0];
        $result = self::extendedGcd($b, $a % $b);
        return ['gcd' => $result['gcd'], 'x' => $result['y'], 'y' => $result['x'] - (int)($a / $b) * $result['y']];
    }

    public static function modInverse(int $a, int $m): int {
        $result = self::extendedGcd($a % $m + $m, $m);
        if ($result['gcd'] !== 1) throw new RuntimeException("No modular inverse");
        return (($result['x'] % $m) + $m) % $m;
    }

    public static function fibonacci(int $n): int {
        if ($n <= 1) return $n;
        $a = 0; $b = 1;
        for ($i = 2; $i <= $n; $i++) {
            $c = $a + $b; $a = $b; $b = $c;
        }
        return $b;
    }

    public static function collatzSteps(int $n): int {
        $steps = 0;
        while ($n > 1) {
            $n = $n % 2 === 0 ? (int)($n / 2) : 3 * $n + 1;
            $steps++;
        }
        return $steps;
    }

    public static function digitSum(int $n): int {
        $sum = 0;
        $n = abs($n);
        while ($n > 0) { $sum += $n % 10; $n = (int)($n / 10); }
        return $sum;
    }

    public static function isPalindrome(int $n): bool {
        $s = (string)$n;
        return $s === strrev($s);
    }
}

// === 测试 ===
echo "--- GCD/LCM ---\n";
echo "gcd(48, 18) = " . NumberTheory::gcd(48, 18) . "\n";
echo "gcd(17, 5) = " . NumberTheory::gcd(17, 5) . "\n";
echo "lcm(4, 6) = " . NumberTheory::lcm(4, 6) . "\n";
echo "lcm(12, 18) = " . NumberTheory::lcm(12, 18) . "\n";

echo "\n--- Primes ---\n";
$primes = NumberTheory::sieveOfEratosthenes(50);
echo "Primes up to 50: " . implode(', ', $primes) . "\n";
echo "Count: " . count($primes) . "\n";

$checkNums = [1, 2, 3, 4, 5, 17, 25, 29, 97, 100];
foreach ($checkNums as $n) {
    echo "  isPrime($n): " . var_export(NumberTheory::isPrime($n), true) . "\n";
}

echo "\n--- Prime Factorization ---\n";
$factorNums = [12, 60, 84, 97, 100, 360];
foreach ($factorNums as $n) {
    $factors = NumberTheory::primeFactors($n);
    $parts = [];
    foreach ($factors as $p => $e) $parts[] = $e > 1 ? "$p^$e" : "$p";
    echo "  $n = " . implode(' × ', $parts) . "\n";
}

echo "\n--- Modular Arithmetic ---\n";
echo "pow(2, 10, 1000) = " . NumberTheory::powerMod(2, 10, 1000) . "\n";
echo "pow(3, 100, 7) = " . NumberTheory::powerMod(3, 100, 7) . "\n";
echo "pow(7, 256, 13) = " . NumberTheory::powerMod(7, 256, 13) . "\n";

echo "\n--- Extended GCD & Modular Inverse ---\n";
$egcd = NumberTheory::extendedGcd(35, 15);
echo "extgcd(35, 15): gcd={$egcd['gcd']}, x={$egcd['x']}, y={$egcd['y']}\n";
echo "modInverse(3, 7) = " . NumberTheory::modInverse(3, 7) . "\n";
echo "modInverse(10, 17) = " . NumberTheory::modInverse(10, 17) . "\n";
echo "Verify: 3 * " . NumberTheory::modInverse(3, 7) . " mod 7 = " . (3 * NumberTheory::modInverse(3, 7)) % 7 . "\n";

echo "\n--- Sequences ---\n";
echo "Fibonacci(0-15): ";
$fibs = [];
for ($i = 0; $i <= 15; $i++) $fibs[] = NumberTheory::fibonacci($i);
echo implode(', ', $fibs) . "\n";

echo "\n--- Misc ---\n";
echo "Collatz(27): " . NumberTheory::collatzSteps(27) . " steps\n";
echo "Collatz(97): " . NumberTheory::collatzSteps(97) . " steps\n";
echo "digitSum(12345): " . NumberTheory::digitSum(12345) . "\n";
echo "digitSum(99999): " . NumberTheory::digitSum(99999) . "\n";
echo "isPalindrome(12321): " . var_export(NumberTheory::isPalindrome(12321), true) . "\n";
echo "isPalindrome(12345): " . var_export(NumberTheory::isPalindrome(12345), true) . "\n";

echo "=== f027 Done ===\n";
