<?php
// 极度混搭: 数值计算 + 矩阵运算 + 行列式 + 求逆 + 特征值(幂迭代)
echo "=== f064: Matrix + Determinant + Inverse + Eigenvalue ===\n";

class Matrix {
    public function __construct(public array $data) {}

    public function rows(): int { return count($this->data); }
    public function cols(): int { return count($this->data[0]); }

    public static function identity(int $n): self {
        $data = array_fill(0, $n, array_fill(0, $n, 0.0));
        for ($i = 0; $i < $n; $i++) $data[$i][$i] = 1.0;
        return new self($data);
    }

    public static function random(int $rows, int $cols, int $seed = 42): self {
        mt_srand($seed);
        $data = [];
        for ($i = 0; $i < $rows; $i++) {
            $row = [];
            for ($j = 0; $j < $cols; $j++) $row[] = mt_rand(1, 9);
            $data[] = $row;
        }
        return new self($data);
    }

    public function add(Matrix $other): self {
        $result = [];
        for ($i = 0; $i < $this->rows(); $i++) {
            for ($j = 0; $j < $this->cols(); $j++) {
                $result[$i][$j] = $this->data[$i][$j] + $other->data[$i][$j];
            }
        }
        return new self($result);
    }

    public function multiply(Matrix $other): self {
        $r = $this->rows(); $c = $other->cols(); $k = $this->cols();
        $result = array_fill(0, $r, array_fill(0, $c, 0.0));
        for ($i = 0; $i < $r; $i++) {
            for ($j = 0; $j < $c; $j++) {
                $sum = 0;
                for ($x = 0; $x < $k; $x++) $sum += $this->data[$i][$x] * $other->data[$x][$j];
                $result[$i][$j] = $sum;
            }
        }
        return new self($result);
    }

    public function scalarMultiply(float $s): self {
        $result = [];
        for ($i = 0; $i < $this->rows(); $i++) {
            for ($j = 0; $j < $this->cols(); $j++) {
                $result[$i][$j] = $this->data[$i][$j] * $s;
            }
        }
        return new self($result);
    }

    public function transpose(): self {
        $result = [];
        for ($i = 0; $i < $this->cols(); $i++) {
            for ($j = 0; $j < $this->rows(); $j++) {
                $result[$i][$j] = $this->data[$j][$i];
            }
        }
        return new self($result);
    }

    public function determinant(): float {
        $n = $this->rows();
        if ($n !== $this->cols()) throw new RuntimeException("Not square");
        if ($n === 1) return $this->data[0][0];
        if ($n === 2) return $this->data[0][0] * $this->data[1][1] - $this->data[0][1] * $this->data[1][0];

        // LU分解
        $data = $this->data;
        $det = 1;
        for ($i = 0; $i < $n; $i++) {
            $max = $i;
            for ($k = $i + 1; $k < $n; $k++) {
                if (abs($data[$k][$i]) > abs($data[$max][$i])) $max = $k;
            }
            if ($max !== $i) {
                $tmp = $data[$i]; $data[$i] = $data[$max]; $data[$max] = $tmp;
                $det = -$det;
            }
            if (abs($data[$i][$i]) < 1e-10) return 0;
            $det *= $data[$i][$i];
            for ($k = $i + 1; $k < $n; $k++) {
                $factor = $data[$k][$i] / $data[$i][$i];
                for ($j = $i; $j < $n; $j++) {
                    $data[$k][$j] -= $factor * $data[$i][$j];
                }
            }
        }
        return $det;
    }

    public function inverse(): ?self {
        $n = $this->rows();
        if ($n !== $this->cols()) return null;
        $det = $this->determinant();
        if (abs($det) < 1e-10) return null;

        // 增广矩阵 [A|I]
        $aug = [];
        for ($i = 0; $i < $n; $i++) {
            $aug[$i] = array_merge($this->data[$i], array_map(fn($j) => $i === $j ? 1.0 : 0.0, range(0, $n - 1)));
        }
        // 高斯消元
        for ($i = 0; $i < $n; $i++) {
            $max = $i;
            for ($k = $i + 1; $k < $n; $k++) {
                if (abs($aug[$k][$i]) > abs($aug[$max][$i])) $max = $k;
            }
            if ($max !== $i) [$aug[$i], $aug[$max]] = [$aug[$max], $aug[$i]];
            $pivot = $aug[$i][$i];
            for ($j = 0; $j < 2 * $n; $j++) $aug[$i][$j] /= $pivot;
            for ($k = 0; $k < $n; $k++) {
                if ($k === $i) continue;
                $factor = $aug[$k][$i];
                for ($j = 0; $j < 2 * $n; $j++) $aug[$k][$j] -= $factor * $aug[$i][$j];
            }
        }
        $inv = [];
        for ($i = 0; $i < $n; $i++) $inv[$i] = array_slice($aug[$i], $n);
        return new self($inv);
    }

    public function powerIteration(int $iterations = 100): array {
        $n = $this->rows();
        $v = array_fill(0, $n, 1.0);
        $eigenvalue = 0;
        for ($iter = 0; $iter < $iterations; $iter++) {
            // Av
            $newV = array_fill(0, $n, 0.0);
            for ($i = 0; $i < $n; $i++) {
                for ($j = 0; $j < $n; $j++) $newV[$i] += $this->data[$i][$j] * $v[$j];
            }
            // 归一化
            $norm = sqrt(array_sum(array_map(fn($x) => $x * $x, $newV)));
            if ($norm < 1e-10) break;
            $v = array_map(fn($x) => $x / $norm, $newV);
            // Rayleigh商
            $av = array_fill(0, $n, 0.0);
            for ($i = 0; $i < $n; $i++) {
                for ($j = 0; $j < $n; $j++) $av[$i] += $this->data[$i][$j] * $v[$j];
            }
            $eigenvalue = array_sum(array_map(fn($x, $y) => $x * $y, $v, $av));
        }
        return ['eigenvalue' => $eigenvalue, 'eigenvector' => $v];
    }

    public function __toString(): string {
        $lines = [];
        foreach ($this->data as $row) {
            $lines[] = "  [" . implode(', ', array_map(fn($v) => number_format($v, 2), $row)) . "]";
        }
        return implode("\n", $lines);
    }
}

// 测试
echo "--- Matrix Operations ---\n";
$a = Matrix::random(3, 3, 42);
$b = Matrix::identity(3);
echo "A:\n$a\n";
echo "B (identity):\n$b\n";
echo "A+B:\n" . $a->add($b) . "\n";
echo "A*B:\n" . $a->multiply($b) . "\n";
echo "A*2:\n" . $a->scalarMultiply(2) . "\n";
echo "A^T:\n" . $a->transpose() . "\n";

echo "\n--- Determinant ---\n";
$c = new Matrix([[1, 2], [3, 4]]);
echo "C:\n$c\n";
echo "det(C) = " . $c->determinant() . "\n";

$d = new Matrix([[6, 1, 1], [4, -2, 5], [2, 8, 7]]);
echo "D:\n$d\n";
echo "det(D) = " . $d->determinant() . "\n";

echo "\n--- Matrix Inverse ---\n";
$cInv = $c->inverse();
echo "C^-1:\n$cInv\n";
echo "C * C^-1 (should be identity):\n" . $c->multiply($cInv) . "\n";

$dInv = $d->inverse();
echo "D^-1:\n$dInv\n";

echo "\n--- Eigenvalue (Power Iteration) ---\n";
$e = new Matrix([[2, 1], [1, 3]]);
echo "E:\n$e\n";
$result = $e->powerIteration(100);
echo "Largest eigenvalue: " . number_format($result['eigenvalue'], 6) . "\n";
echo "Eigenvector: [" . implode(', ', array_map(fn($v) => number_format($v, 6), $result['eigenvector'])) . "]\n";

echo "=== f064 Done ===\n";
