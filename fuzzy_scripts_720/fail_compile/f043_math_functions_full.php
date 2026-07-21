<?php
// 极度混搭: 数学函数全家桶 + 三角函数 + 对数 + 进制转换 + 精度
echo "=== f043: Math Functions Full Suite ===\n";

class MathTools {
    public static function factorial(int $n): int {
        $result = 1;
        for ($i = 2; $i <= $n; $i++) $result *= $i;
        return $result;
    }

    public static function fibonacci(int $n): int {
        if ($n <= 1) return $n;
        $a = 0; $b = 1;
        for ($i = 2; $i <= $n; $i++) { $c = $a + $b; $a = $b; $b = $c; }
        return $b;
    }

    public static function isPrime(int $n): bool {
        if ($n < 2) return false;
        if ($n < 4) return true;
        if ($n % 2 === 0 || $n % 3 === 0) return false;
        for ($i = 5; $i * $i <= $n; $i += 6)
            if ($n % $i === 0 || $n % ($i + 2) === 0) return false;
        return true;
    }

    public static function gcd(int $a, int $b): int {
        while ($b !== 0) { $t = $b; $b = $a % $b; $a = $t; }
        return abs($a);
    }

    public static function lcm(int $a, int $b): int {
        return $a === 0 || $b === 0 ? 0 : abs($a * $b) / self::gcd($a, $b);
    }

    public static function power(int $base, int $exp): int {
        return $base ** $exp;
    }

    public static function sqrt(float $n): float { return sqrt($n); }
    public static function cbrt(float $n): float { return (float)pow($n, 1/3); }

    public static function log(float $n, float $base = M_E): float {
        return log($n, $base);
    }

    public static function log2(float $n): float { return log($n, 2); }
    public static function log10(float $n): float { return log10($n); }
    public static function exp(float $n): float { return exp($n); }

    public static function sin(float $r): float { return sin($r); }
    public static function cos(float $r): float { return cos($r); }
    public static function tan(float $r): float { return tan($r); }
    public static function asin(float $v): float { return asin($v); }
    public static function acos(float $v): float { return acos($v); }
    public static function atan(float $v): float { return atan($v); }
    public static function atan2(float $y, float $x): float { return atan2($y, $x); }

    public static function deg2rad(float $d): float { return deg2rad($d); }
    public static function rad2deg(float $r): float { return rad2deg($r); }

    public static function floor(float $n): float { return floor($n); }
    public static function ceil(float $n): float { return ceil($n); }
    public static function round(float $n, int $p = 0): float { return round($n, $p); }
    public static function abs(float $n): float { return abs($n); }

    public static function max2(float ...$nums): float { return max($nums); }
    public static function min2(float ...$nums): float { return min($nums); }

    public static function clamp(float $v, float $min, float $max): float {
        return max($min, min($max, $v));
    }

    public static function lerp(float $a, float $b, float $t): float {
        return $a + ($b - $a) * $t;
    }

    public static function map(float $v, float $inMin, float $inMax, float $outMin, float $outMax): float {
        return $outMin + ($v - $inMin) * ($outMax - $outMin) / ($inMax - $inMin);
    }

    public static function toBin(int $n): string { return decbin($n); }
    public static function toHex(int $n): string { return dechex($n); }
    public static function toOct(int $n): string { return decoct($n); }
    public static function fromBin(string $s): int { return bindec($s); }
    public static function fromHex(string $s): int { return hexdec($s); }
    public static function fromOct(string $s): int { return octdec($s); }

    public static function formatNumber(float $n, int $dec = 2, string $decSep = '.', string $thouSep = ','): string {
        return number_format($n, $dec, $decSep, $thouSep);
    }

    public static function average(array $nums): float {
        return empty($nums) ? 0 : array_sum($nums) / count($nums);
    }

    public static function median(array $nums): float {
        sort($nums);
        $n = count($nums);
        if ($n === 0) return 0;
        return $n % 2 === 0 ? ($nums[$n/2-1] + $nums[$n/2]) / 2 : $nums[(int)($n/2)];
    }

    public static function stddev(array $nums): float {
        $avg = self::average($nums);
        $variance = array_sum(array_map(fn($x) => ($x - $avg) ** 2, $nums)) / count($nums);
        return sqrt($variance);
    }
}

// 测试
echo "factorial(10): " . MathTools::factorial(10) . "\n";
echo "fibonacci(20): " . MathTools::fibonacci(20) . "\n";
echo "isPrime(97): " . var_export(MathTools::isPrime(97), true) . "\n";
echo "isPrime(100): " . var_export(MathTools::isPrime(100), true) . "\n";
echo "gcd(48,18): " . MathTools::gcd(48, 18) . "\n";
echo "lcm(4,6): " . MathTools::lcm(4, 6) . "\n";
echo "power(2,10): " . MathTools::power(2, 10) . "\n";
echo "sqrt(144): " . MathTools::sqrt(144) . "\n";
echo "cbrt(27): " . MathTools::cbrt(27) . "\n";
echo "log(100,10): " . MathTools::log(100, 10) . "\n";
echo "log2(1024): " . MathTools::log2(1024) . "\n";
echo "exp(1): " . number_format(MathTools::exp(1), 6) . "\n";
echo "sin(PI/2): " . MathTools::sin(M_PI/2) . "\n";
echo "cos(0): " . MathTools::cos(0) . "\n";
echo "deg2rad(180): " . MathTools::deg2rad(180) . "\n";
echo "rad2deg(PI): " . MathTools::rad2deg(M_PI) . "\n";
echo "floor(3.7): " . MathTools::floor(3.7) . "\n";
echo "ceil(3.2): " . MathTools::ceil(3.2) . "\n";
echo "round(3.14159,2): " . MathTools::round(3.14159, 2) . "\n";
echo "abs(-42): " . MathTools::abs(-42) . "\n";
echo "clamp(15,0,10): " . MathTools::clamp(15, 0, 10) . "\n";
echo "lerp(0,100,0.5): " . MathTools::lerp(0, 100, 0.5) . "\n";
echo "map(5,0,10,0,100): " . MathTools::map(5, 0, 10, 0, 100) . "\n";
echo "toBin(255): " . MathTools::toBin(255) . "\n";
echo "toHex(255): " . MathTools::toHex(255) . "\n";
echo "fromBin('11111111'): " . MathTools::fromBin('11111111') . "\n";
echo "formatNumber(1234567.891,2): " . MathTools::formatNumber(1234567.891, 2) . "\n";

$nums = [85, 90, 78, 92, 88];
echo "average: " . MathTools::average($nums) . "\n";
echo "median: " . MathTools::median($nums) . "\n";
echo "stddev: " . number_format(MathTools::stddev($nums), 4) . "\n";

echo "=== f043 Done ===\n";
