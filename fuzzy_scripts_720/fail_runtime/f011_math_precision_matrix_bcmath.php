<?php
// 极度混搭: 数学运算 + 矩阵运算 + 精度控制 + 统计计算 + 数值算法
echo "=== f011: Math + Matrix + Statistics + Numerical ===\n";

class Matrix {
    private array $data;
    private int $rows;
    private int $cols;

    public function __construct(array $data) {
        $this->data = $data;
        $this->rows = count($data);
        $this->cols = $this->rows > 0 ? count($data[0]) : 0;
    }

    public static function identity(int $n): self {
        $data = array_fill(0, $n, array_fill(0, $n, 0.0));
        for ($i = 0; $i < $n; $i++) $data[$i][$i] = 1.0;
        return new self($data);
    }

    public static function filled(int $rows, int $cols, float $val): self {
        return new self(array_fill(0, $rows, array_fill(0, $cols, $val)));
    }

    public function add(self $other): self {
        $result = [];
        for ($i = 0; $i < $this->rows; $i++) {
            $row = [];
            for ($j = 0; $j < $this->cols; $j++) {
                $row[] = $this->data[$i][$j] + $other->data[$i][$j];
            }
            $result[] = $row;
        }
        return new self($result);
    }

    public function multiply(self $other): self {
        $result = Matrix::filled($this->rows, $other->cols, 0.0);
        for ($i = 0; $i < $this->rows; $i++) {
            for ($j = 0; $j < $other->cols; $j++) {
                $sum = 0.0;
                for ($k = 0; $k < $this->cols; $k++) {
                    $sum += $this->data[$i][$k] * $other->data[$k][$j];
                }
                $result->data[$i][$j] = $sum;
            }
        }
        return $result;
    }

    public function transpose(): self {
        $result = [];
        for ($j = 0; $j < $this->cols; $j++) {
            $row = [];
            for ($i = 0; $i < $this->rows; $i++) {
                $row[] = $this->data[$i][$j];
            }
            $result[] = $row;
        }
        return new self($result);
    }

    public function determinant(): float {
        if ($this->rows !== $this->cols) throw new InvalidArgumentException("Not square");
        if ($this->rows === 1) return $this->data[0][0];
        if ($this->rows === 2) return $this->data[0][0] * $this->data[1][1] - $this->data[0][1] * $this->data[1][0];

        $det = 0.0;
        for ($j = 0; $j < $this->cols; $j++) {
            $minor = $this->minor(0, $j);
            $det += ($j % 2 === 0 ? 1 : -1) * $this->data[0][$j] * $minor->determinant();
        }
        return $det;
    }

    private function minor(int $row, int $col): self {
        $result = [];
        for ($i = 0; $i < $this->rows; $i++) {
            if ($i === $row) continue;
            $newRow = [];
            for ($j = 0; $j < $this->cols; $j++) {
                if ($j === $col) continue;
                $newRow[] = $this->data[$i][$j];
            }
            $result[] = $newRow;
        }
        return new self($result);
    }

    public function trace(): float {
        $sum = 0.0;
        for ($i = 0; $i < min($this->rows, $this->cols); $i++) {
            $sum += $this->data[$i][$i];
        }
        return $sum;
    }

    public function format(int $precision = 2): string {
        $fmt = fn($v) => number_format($v, $precision);
        $rows = array_map(fn($row) => '[' . implode(', ', array_map($fmt, $row)) . ']', $this->data);
        return '[' . implode(', ', $rows) . ']';
    }

    public function getRows(): int { return $this->rows; }
    public function getCols(): int { return $this->cols; }
}

class Statistics {
    public static function mean(array $data): float {
        return array_sum($data) / count($data);
    }

    public static function median(array $data): float {
        sort($data);
        $n = count($data);
        if ($n % 2 === 0) {
            return ($data[$n/2 - 1] + $data[$n/2]) / 2;
        }
        return $data[intdiv($n, 2)];
    }

    public static function variance(array $data): float {
        $mean = self::mean($data);
        $squaredDiffs = array_map(fn($x) => ($x - $mean) ** 2, $data);
        return array_sum($squaredDiffs) / count($data);
    }

    public static function stddev(array $data): float {
        return sqrt(self::variance($data));
    }

    public static function correlation(array $x, array $y): float {
        $n = count($x);
        $mx = self::mean($x);
        $my = self::mean($y);
        $num = 0.0; $sx = 0.0; $sy = 0.0;
        for ($i = 0; $i < $n; $i++) {
            $dx = $x[$i] - $mx;
            $dy = $y[$i] - $my;
            $num += $dx * $dy;
            $sx += $dx * $dx;
            $sy += $dy * $dy;
        }
        return $num / sqrt($sx * $sy);
    }

    public static function percentile(array $data, float $p): float {
        sort($data);
        $index = ($p / 100) * (count($data) - 1);
        $lower = (int)floor($index);
        $upper = (int)ceil($index);
        if ($lower === $upper) return $data[$lower];
        $weight = $index - $lower;
        return $data[$lower] * (1 - $weight) + $data[$upper] * $weight;
    }
}

class Numerical {
    public static function newtonRaphson(callable $f, callable $df, float $x0, int $maxIter = 100, float $tol = 1e-6): array {
        $x = $x0;
        $iterations = 0;
        $history = [];
        for ($i = 0; $i < $maxIter; $i++) {
            $fx = $f($x);
            $dfx = $df($x);
            $history[] = ['iter' => $i, 'x' => $x, 'fx' => $fx];
            if (abs($fx) < $tol) {
                $iterations = $i + 1;
                break;
            }
            if (abs($dfx) < 1e-15) {
                return ['root' => null, 'iterations' => $i, 'error' => 'Derivative too small', 'history' => $history];
            }
            $x = $x - $fx / $dfx;
            $iterations = $i + 1;
        }
        return ['root' => $x, 'iterations' => $iterations, 'history' => $history];
    }

    public static function simpsonRule(callable $f, float $a, float $b, int $n = 100): float {
        if ($n % 2 !== 0) $n++;
        $h = ($b - $a) / $n;
        $sum = $f($a) + $f($b);
        for ($i = 1; $i < $n; $i++) {
            $x = $a + $i * $h;
            $sum += ($i % 2 === 0 ? 2 : 4) * $f($x);
        }
        return $sum * $h / 3;
    }

    public static function gradientDescent(callable $f, callable $df, float $x0, float $lr = 0.01, int $maxIter = 1000): array {
        $x = $x0;
        $history = [$x];
        for ($i = 0; $i < $maxIter; $i++) {
            $grad = $df($x);
            $x = $x - $lr * $grad;
            $history[] = $x;
            if (abs($grad) < 1e-8) break;
        }
        return ['minimum' => $x, 'value' => $f($x), 'iterations' => count($history) - 1, 'history' => $history];
    }
}

// === 测试 ===
echo "--- Matrix ---\n";
$m1 = new Matrix([[1, 2], [3, 4]]);
$m2 = new Matrix([[5, 6], [7, 8]]);

echo "m1 = " . $m1->format() . "\n";
echo "m2 = " . $m2->format() . "\n";
echo "m1+m2 = " . $m1->add($m2)->format() . "\n";
echo "m1*m2 = " . $m1->multiply($m2)->format() . "\n";
echo "m1^T = " . $m1->transpose()->format() . "\n";
echo "det(m1) = " . $m1->determinant() . "\n";
echo "trace(m1) = " . $m1->trace() . "\n";

$m3 = new Matrix([[2, 0, 0], [0, 3, 0], [0, 0, 4]]);
echo "det(diag(2,3,4)) = " . $m3->determinant() . "\n";
echo "trace(diag(2,3,4)) = " . $m3->trace() . "\n";

$I = Matrix::identity(3);
echo "I3 = " . $I->format() . "\n";
echo "m3*I = " . $m3->multiply($I)->format() . "\n";

echo "\n--- Statistics ---\n";
$data = [85, 90, 87, 92, 78, 88, 95, 82, 89, 91];
echo "data: " . implode(', ', $data) . "\n";
echo "mean: " . number_format(Statistics::mean($data), 2) . "\n";
echo "median: " . Statistics::median($data) . "\n";
echo "variance: " . number_format(Statistics::variance($data), 2) . "\n";
echo "stddev: " . number_format(Statistics::stddev($data), 4) . "\n";
echo "p25: " . Statistics::percentile($data, 25) . "\n";
echo "p50: " . Statistics::percentile($data, 50) . "\n";
echo "p75: " . Statistics::percentile($data, 75) . "\n";

$x = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
$y = [2, 4, 5, 4, 5, 7, 8, 9, 10, 12];
echo "correlation: " . number_format(Statistics::correlation($x, $y), 4) . "\n";

echo "\n--- Numerical ---\n";
// 求解 x^2 - 4 = 0，期望根为 2 或 -2
$result = Numerical::newtonRaphson(
    fn($x) => $x * $x - 4,
    fn($x) => 2 * $x,
    1.0
);
echo "Newton-Raphson x^2-4=0: root=" . number_format($result['root'], 6) . " iter={$result['iterations']}\n";

// 数值积分 sin(x) 从 0 到 PI
$integral = Numerical::simpsonRule(fn($x) => sin($x), 0, M_PI, 100);
echo "Simpson ∫sin(x)dx [0,π]: " . number_format($integral, 6) . " (expected ~2.0)\n";

// 梯度下降求 f(x) = x^2 + 2x + 1 的最小值
$gd = Numerical::gradientDescent(
    fn($x) => $x * $x + 2 * $x + 1,
    fn($x) => 2 * $x + 2,
    5.0,
    0.1
);
echo "Gradient descent min x^2+2x+1: x=" . number_format($gd['minimum'], 6) . " f(x)=" . number_format($gd['value'], 6) . "\n";

echo "=== f011 Done ===\n";
