<?php
// 数值计算：矩阵运算、线性代数、统计
echo "=== f178: Numeric + Matrix + Linear Algebra ===\n";

class Matrix {
    private array $data;
    public int $rows;
    public int $cols;

    public function __construct(array $data) {
        $this->data = $data;
        $this->rows = count($data);
        $this->cols = $this->rows > 0 ? count($data[0]) : 0;
    }

    public static function identity(int $n): self {
        $data = array_fill(0, $n, array_fill(0, $n, 0));
        for ($i = 0; $i < $n; $i++) $data[$i][$i] = 1;
        return new self($data);
    }

    public static function zeros(int $rows, int $cols): self {
        return new self(array_fill(0, $rows, array_fill(0, $cols, 0)));
    }

    public static function random(int $rows, int $cols, int $min = 0, int $max = 100): self {
        $data = [];
        for ($i = 0; $i < $rows; $i++) {
            $row = [];
            for ($j = 0; $j < $cols; $j++) {
                $row[] = mt_rand($min, $max);
            }
            $data[] = $row;
        }
        return new self($data);
    }

    public function get(int $i, int $j): float { return $this->data[$i][$j]; }
    public function set(int $i, int $j, float $v): void { $this->data[$i][$j] = $v; }

    public function add(Matrix $other): Matrix {
        $result = [];
        for ($i = 0; $i < $this->rows; $i++) {
            $row = [];
            for ($j = 0; $j < $this->cols; $j++) {
                $row[] = $this->data[$i][$j] + $other->get($i, $j);
            }
            $result[] = $row;
        }
        return new Matrix($result);
    }

    public function subtract(Matrix $other): Matrix {
        $result = [];
        for ($i = 0; $i < $this->rows; $i++) {
            $row = [];
            for ($j = 0; $j < $this->cols; $j++) {
                $row[] = $this->data[$i][$j] - $other->get($i, $j);
            }
            $result[] = $row;
        }
        return new Matrix($result);
    }

    public function multiply(Matrix $other): Matrix {
        $result = Matrix::zeros($this->rows, $other->cols);
        for ($i = 0; $i < $this->rows; $i++) {
            for ($j = 0; $j < $other->cols; $j++) {
                $sum = 0;
                for ($k = 0; $k < $this->cols; $k++) {
                    $sum += $this->data[$i][$k] * $other->get($k, $j);
                }
                $result->set($i, $j, $sum);
            }
        }
        return $result;
    }

    public function scalarMultiply(float $scalar): Matrix {
        $result = [];
        for ($i = 0; $i < $this->rows; $i++) {
            $row = [];
            for ($j = 0; $j < $this->cols; $j++) {
                $row[] = $this->data[$i][$j] * $scalar;
            }
            $result[] = $row;
        }
        return new Matrix($result);
    }

    public function transpose(): Matrix {
        $result = [];
        for ($j = 0; $j < $this->cols; $j++) {
            $row = [];
            for ($i = 0; $i < $this->rows; $i++) {
                $row[] = $this->data[$i][$j];
            }
            $result[] = $row;
        }
        return new Matrix($result);
    }

    public function determinant(): float {
        if ($this->rows !== $this->cols) throw new Exception("Determinant requires square matrix");
        if ($this->rows === 1) return $this->data[0][0];
        if ($this->rows === 2) return $this->data[0][0] * $this->data[1][1] - $this->data[0][1] * $this->data[1][0];
        $det = 0;
        for ($j = 0; $j < $this->cols; $j++) {
            $minor = $this->minor(0, $j);
            $det += ($j % 2 === 0 ? 1 : -1) * $this->data[0][$j] * $minor->determinant();
        }
        return $det;
    }

    public function minor(int $row, int $col): Matrix {
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
        return new Matrix($result);
    }

    public function trace(): float {
        if ($this->rows !== $this->cols) throw new Exception("Trace requires square matrix");
        $sum = 0;
        for ($i = 0; $i < $this->rows; $i++) $sum += $this->data[$i][$i];
        return $sum;
    }

    public function toString(): string {
        $lines = [];
        foreach ($this->data as $row) {
            $lines[] = '  [' . implode(', ', array_map(fn($v) => sprintf('%8.2f', $v), $row)) . ']';
        }
        return implode("\n", $lines);
    }
}

class Statistics {
    public static function mean(array $data): float {
        return array_sum($data) / count($data);
    }

    public static function median(array $data): float {
        sort($data);
        $n = count($data);
        if ($n % 2 === 0) return ($data[$n/2-1] + $data[$n/2]) / 2;
        return $data[(int)($n/2)];
    }

    public static function variance(array $data): float {
        $mean = self::mean($data);
        $sum = 0;
        foreach ($data as $v) $sum += ($v - $mean) ** 2;
        return $sum / count($data);
    }

    public static function stdDev(array $data): float {
        return sqrt(self::variance($data));
    }

    public static function correlation(array $x, array $y): float {
        $n = count($x);
        $mx = self::mean($x);
        $my = self::mean($y);
        $num = 0; $sx = 0; $sy = 0;
        for ($i = 0; $i < $n; $i++) {
            $dx = $x[$i] - $mx;
            $dy = $y[$i] - $my;
            $num += $dx * $dy;
            $sx += $dx ** 2;
            $sy += $dy ** 2;
        }
        return $num / sqrt($sx * $sy);
    }

    public static function linearRegression(array $x, array $y): array {
        $n = count($x);
        $mx = self::mean($x);
        $my = self::mean($y);
        $num = 0; $den = 0;
        for ($i = 0; $i < $n; $i++) {
            $num += ($x[$i] - $mx) * ($y[$i] - $my);
            $den += ($x[$i] - $mx) ** 2;
        }
        $slope = $den == 0 ? 0 : $num / $den;
        $intercept = $my - $slope * $mx;
        return ['slope' => $slope, 'intercept' => $intercept];
    }
}

// 测试
echo "--- Matrix Operations ---\n";
$a = new Matrix([[1, 2, 3], [4, 5, 6], [7, 8, 9]]);
$b = new Matrix([[9, 8, 7], [6, 5, 4], [3, 2, 1]]);

echo "  Matrix A:\n" . $a->toString() . "\n";
echo "  Matrix B:\n" . $b->toString() . "\n";

echo "\n  A + B:\n" . $a->add($b)->toString() . "\n";
echo "\n  A - B:\n" . $a->subtract($b)->toString() . "\n";
echo "\n  A * B:\n" . $a->multiply($b)->toString() . "\n";
echo "\n  A^T:\n" . $a->transpose()->toString() . "\n";
echo "\n  A * 2:\n" . $a->scalarMultiply(2)->toString() . "\n";

echo "\n--- Matrix Properties ---\n";
$c = new Matrix([[3, 0, 2], [0, 1, 1], [2, 1, 0]]);
echo "  Matrix C:\n" . $c->toString() . "\n";
echo "  det(C) = " . $c->determinant() . "\n";
echo "  trace(C) = " . $c->trace() . "\n";

$I = Matrix::identity(3);
echo "\n  Identity(3):\n" . $I->toString() . "\n";

echo "\n--- Matrix Chain (A * B * C) ---\n";
$abc = $a->multiply($b)->multiply($c);
echo $abc->toString() . "\n";

echo "\n--- Statistics ---\n";
$data = [2, 4, 4, 4, 5, 5, 7, 9];
echo "  Data: " . implode(', ', $data) . "\n";
echo "  Mean: " . Statistics::mean($data) . "\n";
echo "  Median: " . Statistics::median($data) . "\n";
echo "  Variance: " . Statistics::variance($data) . "\n";
echo "  Std Dev: " . round(Statistics::stdDev($data), 4) . "\n";

echo "\n--- Correlation ---\n";
$x = [1, 2, 3, 4, 5, 6, 7, 8];
$y1 = [2, 4, 6, 8, 10, 12, 14, 16]; // Perfect positive
$y2 = [16, 14, 12, 10, 8, 6, 4, 2]; // Perfect negative
echo "  corr(x, y1) = " . round(Statistics::correlation($x, $y1), 4) . "\n";
echo "  corr(x, y2) = " . round(Statistics::correlation($x, $y2), 4) . "\n";

echo "\n--- Linear Regression ---\n";
$reg = Statistics::linearRegression($x, $y1);
echo "  y = {$reg['slope']}x + {$reg['intercept']}\n";
echo "  Predict x=10: y=" . ($reg['slope'] * 10 + $reg['intercept']) . "\n";

echo "=== f178 Done ===\n";
