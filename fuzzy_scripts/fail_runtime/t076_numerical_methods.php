<?php
// 数值方法：牛顿法求根、二分法、弦截法

function newton_sqrt(float $n, float $tolerance = 1e-10): float {
    if ($n < 0) return NAN;
    if ($n === 0.0) return 0.0;
    $x = $n;
    while (abs($x * $x - $n) > $tolerance) {
        $x = ($x + $n / $x) / 2;
    }
    return $x;
}

function newton_cbrt(float $n, float $tolerance = 1e-10): float {
    $x = $n;
    while (abs($x * $x * $x - $n) > $tolerance) {
        $x = $x - ($x * $x * $x - $n) / (3 * $x * $x);
    }
    return $x;
}

function bisection(callable $f, float $a, float $b, float $tolerance = 1e-10): float {
    if ($f($a) * $f($b) > 0) throw new RuntimeException("No root in interval");
    while (abs($b - $a) > $tolerance) {
        $mid = ($a + $b) / 2;
        if ($f($a) * $f($mid) <= 0) {
            $b = $mid;
        } else {
            $a = $mid;
        }
    }
    return ($a + $b) / 2;
}

function secant_method(callable $f, float $x0, float $x1, float $tolerance = 1e-10): float {
    while (abs($x1 - $x0) > $tolerance) {
        $fx0 = $f($x0);
        $fx1 = $f($x1);
        if ($fx1 - $fx0 === 0.0) break;
        $x2 = $x1 - $fx1 * ($x1 - $x0) / ($fx1 - $fx0);
        $x0 = $x1;
        $x1 = $x2;
    }
    return $x1;
}

function gradient_descent(callable $f, callable $df, float $x0, float $lr = 0.01, int $maxIter = 1000, float $tolerance = 1e-8): float {
    $x = $x0;
    for ($i = 0; $i < $maxIter; $i++) {
        $gradient = $df($x);
        $x_new = $x - $lr * $gradient;
        if (abs($x_new - $x) < $tolerance) break;
        $x = $x_new;
    }
    return $x;
}

// 测试牛顿法求平方根
echo "newton_sqrt_2: " . sprintf("%.10f", newton_sqrt(2)) . "\n";
echo "newton_sqrt_9: " . sprintf("%.10f", newton_sqrt(9)) . "\n";
echo "newton_sqrt_0.5: " . sprintf("%.10f", newton_sqrt(0.5)) . "\n";

// 测试牛顿法求立方根
echo "newton_cbrt_8: " . sprintf("%.10f", newton_cbrt(8)) . "\n";
echo "newton_cbrt_27: " . sprintf("%.10f", newton_cbrt(27)) . "\n";

// 测试二分法
$root1 = bisection(fn($x) => $x * $x - 2, 1, 2);
echo "bisection_sqrt2: " . sprintf("%.10f", $root1) . "\n";

$root2 = bisection(fn($x) => $x * $x * $x - 8, 1, 3);
echo "bisection_cbrt8: " . sprintf("%.10f", $root2) . "\n";

$root3 = bisection(fn($x) => $x - cos($x), 0, 1);
echo "bisection_cos: " . sprintf("%.10f", $root3) . "\n";

// 测试弦截法
$root4 = secant_method(fn($x) => $x * $x - 2, 1, 2);
echo "secant_sqrt2: " . sprintf("%.10f", $root4) . "\n";

// 测试梯度下降（求 f(x) = x^2 + 2x + 1 的最小值，最小值在 x = -1）
$min_x = gradient_descent(
    fn($x) => $x * $x + 2 * $x + 1,
    fn($x) => 2 * $x + 2,
    0.0
);
echo "gradient_min: " . sprintf("%.10f", $min_x) . "\n";

// 测试误差
$sqrt2 = newton_sqrt(2);
echo "sqrt2_error: " . sprintf("%.2e", abs($sqrt2 * $sqrt2 - 2)) . "\n";
