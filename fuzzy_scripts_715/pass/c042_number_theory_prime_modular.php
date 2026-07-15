<?php
// 极度混搭: 数论 + 素数筛 + 模运算 + 最大公约数 + 组合数学 + 进制转换
echo "=== c042: NumberTheory + PrimeSieve + Modular + Combinatorics ===\n\n";

class NumberTheory {
    public static function gcd(int $a, int $b): int {
        $a = abs($a);
        $b = abs($b);
        while ($b != 0) {
            $temp = $b;
            $b = $a % $b;
            $a = $temp;
        }
        return $a;
    }

    public static function lcm(int $a, int $b): int {
        if ($a == 0 || $b == 0) return 0;
        return abs($a * $b) / self::gcd($a, $b);
    }

    public static function isPrime(int $n): bool {
        if ($n < 2) return false;
        if ($n < 4) return true;
        if ($n % 2 == 0 || $n % 3 == 0) return false;
        $i = 5;
        while ($i * $i <= $n) {
            if ($n % $i == 0 || $n % ($i + 2) == 0) return false;
            $i += 6;
        }
        return true;
    }

    public static function sieveOfEratosthenes(int $limit): array {
        $sieve = array_fill(0, $limit + 1, true);
        $sieve[0] = $sieve[1] = false;
        for ($i = 2; $i * $i <= $limit; $i++) {
            if ($sieve[$i]) {
                for ($j = $i * $i; $j <= $limit; $j += $i) {
                    $sieve[$j] = false;
                }
            }
        }
        $primes = [];
        for ($i = 2; $i <= $limit; $i++) {
            if ($sieve[$i]) $primes[] = $i;
        }
        return $primes;
    }

    public static function factorize(int $n): array {
        $factors = [];
        for ($d = 2; $d * $d <= $n; $d++) {
            while ($n % $d == 0) {
                $factors[$d] = ($factors[$d] ?? 0) + 1;
                $n = intdiv($n, $d);
            }
        }
        if ($n > 1) {
            $factors[$n] = ($factors[$n] ?? 0) + 1;
        }
        return $factors;
    }

    public static function modPow(int $base, int $exp, int $mod): int {
        $result = 1;
        $base = $base % $mod;
        while ($exp > 0) {
            if ($exp % 2 == 1) {
                $result = ($result * $base) % $mod;
            }
            $exp = intdiv($exp, 2);
            $base = ($base * $base) % $mod;
        }
        return $result;
    }

    public static function modInverse(int $a, int $m): int {
        $a = $a % $m;
        for ($x = 1; $x < $m; $x++) {
            if (($a * $x) % $m == 1) return $x;
        }
        return -1;
    }

    public static function factorial(int $n): int {
        $result = 1;
        for ($i = 2; $i <= $n; $i++) {
            $result *= $i;
        }
        return $result;
    }

    public static function binomialCoefficient(int $n, int $k): int {
        if ($k > $n - $k) $k = $n - $k;
        $result = 1;
        for ($i = 0; $i < $k; $i++) {
            $result = $result * ($n - $i) / ($i + 1);
        }
        return (int)$result;
    }

    public static function permutations(int $n, int $k): int {
        $result = 1;
        for ($i = 0; $i < $k; $i++) {
            $result *= ($n - $i);
        }
        return $result;
    }

    public static function fibonacci(int $n): int {
        if ($n <= 1) return $n;
        $a = 0; $b = 1;
        for ($i = 2; $i <= $n; $i++) {
            $c = $a + $b;
            $a = $b;
            $b = $c;
        }
        return $b;
    }

    public static function collatzSteps(int $n): array {
        $steps = [$n];
        while ($n != 1) {
            if ($n % 2 == 0) {
                $n = intdiv($n, 2);
            } else {
                $n = 3 * $n + 1;
            }
            $steps[] = $n;
        }
        return $steps;
    }

    public static function toBase(int $n, int $base): string {
        if ($n == 0) return '0';
        $digits = '0123456789ABCDEF';
        $result = '';
        while ($n > 0) {
            $result = $digits[$n % $base] . $result;
            $n = intdiv($n, $base);
        }
        return $result;
    }

    public static function fromBase(string $str, int $base): int {
        $result = 0;
        $len = strlen($str);
        for ($i = 0; $i < $len; $i++) {
            $val = ord($str[$i]);
            if ($val >= 48 && $val <= 57) $val -= 48;
            elseif ($val >= 65 && $val <= 70) $val -= 55;
            elseif ($val >= 97 && $val <= 102) $val -= 87;
            else continue;
            $result = $result * $base + $val;
        }
        return $result;
    }

    public static function digitSum(int $n): int {
        $sum = 0;
        while ($n > 0) {
            $sum += $n % 10;
            $n = intdiv($n, 10);
        }
        return $sum;
    }

    public static function digitalRoot(int $n): int {
        while ($n >= 10) {
            $n = self::digitSum($n);
        }
        return $n;
    }
}

// === 测试 ===

echo "--- GCD/LCM ---\n";
echo "gcd(48, 18) = " . NumberTheory::gcd(48, 18) . "\n";
echo "gcd(17, 13) = " . NumberTheory::gcd(17, 13) . "\n";
echo "lcm(12, 18) = " . NumberTheory::lcm(12, 18) . "\n";
echo "lcm(7, 13) = " . NumberTheory::lcm(7, 13) . "\n";

echo "\n--- Prime Numbers ---\n";
echo "isPrime(2): " . var_export(NumberTheory::isPrime(2), true) . "\n";
echo "isPrime(17): " . var_export(NumberTheory::isPrime(17), true) . "\n";
echo "isPrime(100): " . var_export(NumberTheory::isPrime(100), true) . "\n";
echo "isPrime(997): " . var_export(NumberTheory::isPrime(997), true) . "\n";

$primes = NumberTheory::sieveOfEratosthenes(50);
echo "Primes up to 50: " . implode(", ", $primes) . "\n";

echo "\n--- Factorization ---\n";
$nums = [12, 100, 360, 1024, 997];
foreach ($nums as $n) {
    $factors = NumberTheory::factorize($n);
    $parts = [];
    foreach ($factors as $p => $e) {
        $parts[] = $e > 1 ? "$p^$e" : "$p";
    }
    echo "  $n = " . implode(" * ", $parts) . "\n";
}

echo "\n--- Modular Arithmetic ---\n";
echo "modPow(2, 10, 1000) = " . NumberTheory::modPow(2, 10, 1000) . "\n";
echo "modPow(3, 100, 7) = " . NumberTheory::modPow(3, 100, 7) . "\n";
echo "modInverse(3, 11) = " . NumberTheory::modInverse(3, 11) . "\n";
echo "modInverse(7, 26) = " . NumberTheory::modInverse(7, 26) . "\n";

echo "\n--- Combinatorics ---\n";
echo "5! = " . NumberTheory::factorial(5) . "\n";
echo "10! = " . NumberTheory::factorial(10) . "\n";
echo "C(10, 3) = " . NumberTheory::binomialCoefficient(10, 3) . "\n";
echo "C(20, 10) = " . NumberTheory::binomialCoefficient(20, 10) . "\n";
echo "P(10, 3) = " . NumberTheory::permutations(10, 3) . "\n";

echo "\n--- Fibonacci ---\n";
$fibs = [];
for ($i = 0; $i < 15; $i++) {
    $fibs[] = NumberTheory::fibonacci($i);
}
echo "Fib(0..14): " . implode(", ", $fibs) . "\n";

echo "\n--- Collatz Conjecture ---\n";
foreach ([6, 19, 27] as $n) {
    $steps = NumberTheory::collatzSteps($n);
    echo "  Collatz($n): " . count($steps) . " steps, max=" . max($steps) . "\n";
}

echo "\n--- Base Conversion ---\n";
foreach ([10, 255, 1024, 65535] as $n) {
    $bin = NumberTheory::toBase($n, 2);
    $oct = NumberTheory::toBase($n, 8);
    $hex = NumberTheory::toBase($n, 16);
    $back = NumberTheory::fromBase($hex, 16);
    echo "  $n: bin=$bin oct=$oct hex=$hex back=$back\n";
}

echo "\n--- Digital Root ---\n";
foreach ([0, 9, 12, 38, 12345, 999999] as $n) {
    echo "  digitSum($n) = " . NumberTheory::digitSum($n) . ", digitalRoot = " . NumberTheory::digitalRoot($n) . "\n";
}

echo "\n=== c042 Done ===\n";
