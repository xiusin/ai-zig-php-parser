<?php
// 极度混搭: 数学 + 数论 + 素数 + 欧几里得 + 模逆 + 中国剩余定理
echo "=== f135: Math + NumberTheory + GCD + CRT + MillerRabin ===\n";

class NumberTheory {
    public static function gcd(int $a, int $b): int { return $b === 0 ? abs($a) : self::gcd($b, $a % $b); }
    public static function lcm(int $a, int $b): int { return $a * $b / self::gcd($a, $b); }

    public static function extendedGcd(int $a, int $b): array {
        if ($b === 0) return ['gcd' => $a, 'x' => 1, 'y' => 0];
        $result = self::extendedGcd($b, $a % $b);
        return ['gcd' => $result['gcd'], 'x' => $result['y'], 'y' => $result['x'] - (int)($a / $b) * $result['y']];
    }

    public static function modInverse(int $a, int $m): int {
        $result = self::extendedGcd($a % $m + $m, $m);
        if ($result['gcd'] !== 1) return -1;
        return (($result['x'] % $m) + $m) % $m;
    }

    public static function modPow(int $base, int $exp, int $mod): int {
        $result = 1; $base = $base % $mod;
        while ($exp > 0) {
            if ($exp & 1) $result = ($result * $base) % $mod;
            $exp >>= 1;
            $base = ($base * $base) % $mod;
        }
        return $result;
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

    public static function millerRabin(int $n, int $k = 10): bool {
        if ($n < 2) return false;
        if ($n < 4) return true;
        if ($n % 2 === 0) return false;
        $d = $n - 1; $r = 0;
        while ($d % 2 === 0) { $d /= 2; $r++; }
        for ($i = 0; $i < $k; $i++) {
            $a = 2 + mt_rand() % ($n - 3);
            $x = self::modPow($a, $d, $n);
            if ($x === 1 || $x === $n - 1) continue;
            $composite = true;
            for ($j = 0; $j < $r - 1; $j++) {
                $x = self::modPow($x, 2, $n);
                if ($x === $n - 1) { $composite = false; break; }
            }
            if ($composite) return false;
        }
        return true;
    }

    public static function sieveOfEratosthenes(int $n): array {
        $sieve = array_fill(0, $n + 1, true);
        $sieve[0] = $sieve[1] = false;
        for ($i = 2; $i * $i <= $n; $i++) {
            if ($sieve[$i]) for ($j = $i * $i; $j <= $n; $j += $i) $sieve[$j] = false;
        }
        $primes = [];
        for ($i = 2; $i <= $n; $i++) if ($sieve[$i]) $primes[] = $i;
        return $primes;
    }

    public static function primeFactorize(int $n): array {
        $factors = [];
        for ($d = 2; $d * $d <= $n; $d++) {
            while ($n % $d === 0) { $factors[$d] = ($factors[$d] ?? 0) + 1; $n /= $d; }
        }
        if ($n > 1) $factors[$n] = ($factors[$n] ?? 0) + 1;
        return $factors;
    }

    public static function chineseRemainderTheorem(array $remainders, array $moduli): int {
        $M = 1;
        foreach ($moduli as $m) $M *= $m;
        $x = 0;
        for ($i = 0; $i < count($remainders); $i++) {
            $Mi = $M / $moduli[$i];
            $yi = self::modInverse($Mi, $moduli[$i]);
            $x += $remainders[$i] * $Mi * $yi;
        }
        return $x % $M;
    }

    public static function eulerTotient(int $n): int {
        $result = $n;
        $factors = self::primeFactorize($n);
        foreach (array_keys($factors) as $p) $result = (int)($result * (1 - 1 / $p));
        return $result;
    }

    public static function fibonacci(int $n): int {
        if ($n <= 1) return $n;
        $a = 0; $b = 1;
        for ($i = 2; $i <= $n; $i++) { $temp = $a + $b; $a = $b; $b = $temp; }
        return $b;
    }

    public static function catalan(int $n): int {
        $c = 1;
        for ($i = 0; $i < $n; $i++) $c = $c * 2 * (2 * $i + 1) / ($i + 2);
        return (int)$c;
    }
}

class ModularArithmetic {
    public static function add(int $a, int $b, int $m): int { return (($a % $m) + ($b % $m)) % $m; }
    public static function sub(int $a, int $b, int $m): int { return ((($a % $m) - ($b % $m)) % $m + $m) % $m; }
    public static function mul(int $a, int $b, int $m): int { return (($a % $m) * ($b % $m)) % $m; }
    public static function div(int $a, int $b, int $m): int { return self::mul($a, NumberTheory::modInverse($b, $m), $m); }
}

// 测试
echo "--- GCD & LCM ---\n";
echo "gcd(48, 18) = " . NumberTheory::gcd(48, 18) . " (expected 6)\n";
echo "gcd(1071, 462) = " . NumberTheory::gcd(1071, 462) . " (expected 21)\n";
echo "lcm(12, 18) = " . NumberTheory::lcm(12, 18) . " (expected 36)\n";

echo "\n--- Extended GCD ---\n";
$ext = NumberTheory::extendedGcd(35, 15);
echo "extGcd(35, 15): gcd={$ext['gcd']} x={$ext['x']} y={$ext['y']}\n";
echo "Verify: 35*{$ext['x']} + 15*{$ext['y']} = " . (35 * $ext['x'] + 15 * $ext['y']) . " = {$ext['gcd']}\n";

echo "\n--- Modular Inverse ---\n";
echo "modInverse(3, 11) = " . NumberTheory::modInverse(3, 11) . " (expected 4)\n";
echo "modInverse(7, 26) = " . NumberTheory::modInverse(7, 26) . " (expected 15)\n";
echo "Verify: 3*4 mod 11 = " . (3 * 4 % 11) . "\n";

echo "\n--- Modular Exponentiation ---\n";
echo "modPow(2, 10, 1000) = " . NumberTheory::modPow(2, 10, 1000) . " (expected 24)\n";
echo "modPow(3, 100, 7) = " . NumberTheory::modPow(3, 100, 7) . "\n";
echo "modPow(7, 256, 13) = " . NumberTheory::modPow(7, 256, 13) . "\n";

echo "\n--- Primality Testing ---\n";
$primes = [2, 3, 5, 7, 11, 13, 97, 101, 103, 997];
$composites = [1, 4, 6, 8, 9, 15, 21, 25, 100, 561];
echo "Deterministic:\n";
foreach ($primes as $p) echo NumberTheory::isPrime($p) ? "✓" : "✗"; echo " primes\n";
foreach ($composites as $c) echo NumberTheory::isPrime($c) ? "✗" : "✓"; echo " composites\n";

echo "Miller-Rabin (large primes):\n";
$largePrimes = [1000003, 1000033, 1000037, 1000039, 1000081];
foreach ($largePrimes as $p) echo "  $p: " . var_export(NumberTheory::millerRabin($p), true) . "\n";

echo "\n--- Sieve of Eratosthenes ---\n";
$sieve = NumberTheory::sieveOfEratosthenes(100);
echo "Primes under 100: " . implode(', ', $sieve) . "\n";
echo "Count: " . count($sieve) . "\n";

echo "\n--- Prime Factorization ---\n";
$numbers = [12, 60, 84, 360, 1024, 99991];
foreach ($numbers as $n) {
    $factors = NumberTheory::primeFactorize($n);
    $parts = array_map(fn($p, $e) => $e > 1 ? "$p^$e" : "$p", array_keys($factors), $factors);
    echo "  $n = " . implode(' × ', $parts) . "\n";
}

echo "\n--- Chinese Remainder Theorem ---\n";
$remainders = [2, 3, 2];
$moduli = [3, 5, 7];
$result = NumberTheory::chineseRemainderTheorem($remainders, $moduli);
echo "CRT: x ≡ 2 (mod 3), x ≡ 3 (mod 5), x ≡ 2 (mod 7)\n";
echo "Solution: x = $result\n";
foreach ($moduli as $i => $m) echo "  Verify: $result mod $m = " . ($result % $m) . " (expected {$remainders[$i]})\n";

echo "\n--- Euler's Totient ---\n";
foreach ([1, 2, 6, 9, 12, 36] as $n) echo "  φ($n) = " . NumberTheory::eulerTotient($n) . "\n";

echo "\n--- Fibonacci ---\n";
$fibs = [];
for ($i = 0; $i <= 15; $i++) $fibs[] = NumberTheory::fibonacci($i);
echo "Fibonacci(0..15): " . implode(', ', $fibs) . "\n";

echo "\n--- Catalan Numbers ---\n";
$catas = [];
for ($i = 0; $i <= 10; $i++) $catas[] = NumberTheory::catalan($i);
echo "Catalan(0..10): " . implode(', ', $catas) . "\n";

echo "\n--- Modular Arithmetic ---\n";
echo "(5 + 7) mod 3 = " . ModularArithmetic::add(5, 7, 3) . "\n";
echo "(5 * 7) mod 3 = " . ModularArithmetic::mul(5, 7, 3) . "\n";
echo "(10 / 3) mod 7 = " . ModularArithmetic::div(10, 3, 7) . " (3^(-1) mod 7 = " . NumberTheory::modInverse(3, 7) . ")\n";

echo "=== f135 Done ===\n";
