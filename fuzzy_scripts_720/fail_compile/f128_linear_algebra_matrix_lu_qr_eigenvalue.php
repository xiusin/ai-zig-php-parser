<?php
// 极度混搭: 线性代数 + 矩阵 + LU分解 + QR分解 + 特征值
echo "=== f128: Linear Algebra + Matrix + LU + QR + Eigenvalue ===\n";

class Matrix {
    public function __construct(public array $data) {}

    public static function zeros(int $rows, int $cols): self {
        return new self(array_fill(0, $rows, array_fill(0, $cols, 0.0)));
    }

    public static function identity(int $n): self {
        $m = self::zeros($n, $n);
        for ($i = 0; $i < $n; $i++) $m->data[$i][$i] = 1.0;
        return $m;
    }

    public static function random(int $rows, int $cols, int $seed = 42): self {
        mt_srand($seed);
        $data = [];
        for ($i = 0; $i < $rows; $i++) {
            $row = [];
            for ($j = 0; $j < $cols; $j++) $row[] = mt_rand(-100, 100) / 10;
            $data[] = $row;
        }
        return new self($data);
    }

    public function rows(): int { return count($this->data); }
    public function cols(): int { return count($this->data[0] ?? []); }

    public function add(Matrix $other): Matrix {
        $result = [];
        for ($i = 0; $i < $this->rows(); $i++) {
            $row = [];
            for ($j = 0; $j < $this->cols(); $j++) $row[] = $this->data[$i][$j] + $other->data[$i][$j];
            $result[] = $row;
        }
        return new Matrix($result);
    }

    public function subtract(Matrix $other): Matrix {
        $result = [];
        for ($i = 0; $i < $this->rows(); $i++) {
            $row = [];
            for ($j = 0; $j < $this->cols(); $j++) $row[] = $this->data[$i][$j] - $other->data[$i][$j];
            $result[] = $row;
        }
        return new Matrix($result);
    }

    public function multiply(Matrix $other): Matrix {
        $n = $this->rows(); $m = $this->cols(); $p = $other->cols();
        $result = array_fill(0, $n, array_fill(0, $p, 0.0));
        for ($i = 0; $i < $n; $i++) {
            for ($j = 0; $j < $p; $j++) {
                $sum = 0;
                for ($k = 0; $k < $m; $k++) $sum += $this->data[$i][$k] * $other->data[$k][$j];
                $result[$i][$j] = $sum;
            }
        }
        return new Matrix($result);
    }

    public function scalarMultiply(float $s): Matrix {
        $result = [];
        for ($i = 0; $i < $this->rows(); $i++) {
            $row = [];
            for ($j = 0; $j < $this->cols(); $j++) $row[] = $this->data[$i][$j] * $s;
            $result[] = $row;
        }
        return new Matrix($result);
    }

    public function transpose(): Matrix {
        $result = [];
        for ($i = 0; $i < $this->cols(); $i++) {
            $row = [];
            for ($j = 0; $j < $this->rows(); $j++) $row[] = $this->data[$j][$i];
            $result[] = $row;
        }
        return new Matrix($result);
    }

    public function determinant(): float {
        $n = $this->rows();
        if ($n !== $this->cols()) return 0;
        if ($n === 1) return $this->data[0][0];
        if ($n === 2) return $this->data[0][0] * $this->data[1][1] - $this->data[0][1] * $this->data[1][0];
        $det = 0;
        for ($j = 0; $j < $n; $j++) {
            $minor = $this->minor(0, $j);
            $det += ($j % 2 === 0 ? 1 : -1) * $this->data[0][$j] * $minor->determinant();
        }
        return $det;
    }

    public function minor(int $row, int $col): Matrix {
        $result = [];
        for ($i = 0; $i < $this->rows(); $i++) {
            if ($i === $row) continue;
            $newRow = [];
            for ($j = 0; $j < $this->cols(); $j++) {
                if ($j === $col) continue;
                $newRow[] = $this->data[$i][$j];
            }
            $result[] = $newRow;
        }
        return new Matrix($result);
    }

    public function inverse(): ?Matrix {
        $n = $this->rows();
        if ($n !== $this->cols()) return null;
        $det = $this->determinant();
        if (abs($det) < 1e-10) return null;
        if ($n === 1) return new Matrix([[1 / $this->data[0][0]]]);
        $cofactors = [];
        for ($i = 0; $i < $n; $i++) {
            $row = [];
            for ($j = 0; $j < $n; $j++) {
                $minor = $this->minor($i, $j);
                $row[] = (($i + $j) % 2 === 0 ? 1 : -1) * $minor->determinant();
            }
            $cofactors[] = $row;
        }
        $cofactorMatrix = (new Matrix($cofactors))->transpose();
        return $cofactorMatrix->scalarMultiply(1 / $det);
    }

    public function luDecomposition(): array {
        $n = $this->rows();
        $L = Matrix::identity($n); $U = Matrix::zeros($n, $n);
        for ($i = 0; $i < $n; $i++) {
            for ($j = $i; $j < $n; $j++) {
                $sum = 0;
                for ($k = 0; $k < $i; $k++) $sum += $L->data[$i][$k] * $U->data[$k][$j];
                $U->data[$i][$j] = $this->data[$i][$j] - $sum;
            }
            for ($j = $i; $j < $n; $j++) {
                if ($i === $j) { $L->data[$i][$i] = 1; continue; }
                $sum = 0;
                for ($k = 0; $k < $i; $k++) $sum += $L->data[$j][$k] * $U->data[$k][$i];
                if (abs($U->data[$i][$i]) < 1e-10) $L->data[$j][$i] = 0;
                else $L->data[$j][$i] = ($this->data[$j][$i] - $sum) / $U->data[$i][$i];
            }
        }
        return ['L' => $L, 'U' => $U];
    }

    public function qrDecomposition(): array {
        $n = $this->rows(); $m = $this->cols();
        $Q = Matrix::identity($n); $R = clone $this;
        for ($k = 0; $k < min($n - 1, $m); $k++) {
            // Householder
            $alpha = 0;
            for ($i = $k; $i < $n; $i++) $alpha += $R->data[$i][$k] ** 2;
            $alpha = -sqrt($alpha) * ($R->data[$k][$k] >= 0 ? 1 : -1);
            $v = array_fill(0, $n, 0.0);
            $v[$k] = $R->data[$k][$k] - $alpha;
            for ($i = $k + 1; $i < $n; $i++) $v[$i] = $R->data[$i][$k];
            $vNorm = 0;
            for ($i = $k; $i < $n; $i++) $vNorm += $v[$i] ** 2;
            if ($vNorm < 1e-10) continue;
            // H = I - 2vv'/v'v
            $H = Matrix::identity($n);
            for ($i = 0; $i < $n; $i++) {
                for ($j = 0; $j < $n; $j++) {
                    $H->data[$i][$j] -= 2 * $v[$i] * $v[$j] / $vNorm;
                }
            }
            $R = $H->multiply($R);
            $Q = $Q->multiply($H);
        }
        return ['Q' => $Q, 'R' => $R];
    }

    public function powerIteration(int $iterations = 100): array {
        $n = $this->rows();
        $v = array_fill(0, $n, 1.0);
        $norm = sqrt(array_sum(array_map(fn($x) => $x * $x, $v)));
        for ($i = 0; $i < $n; $i++) $v[$i] /= $norm;
        $eigenvalue = 0;
        for ($iter = 0; $iter < $iterations; $iter++) {
            $newV = array_fill(0, $n, 0.0);
            for ($i = 0; $i < $n; $i++) {
                for ($j = 0; $j < $n; $j++) $newV[$i] += $this->data[$i][$j] * $v[$j];
            }
            $norm = sqrt(array_sum(array_map(fn($x) => $x * $x, $newV)));
            if ($norm < 1e-10) break;
            for ($i = 0; $i < $n; $i++) $newV[$i] /= $norm;
            $newEigenvalue = 0;
            for ($i = 0; $i < $n; $i++) $newEigenvalue += $newV[$i] * array_sum(array_map(fn($a, $b) => $a * $b, $this->data[$i], $newV));
            if (abs($newEigenvalue - $eigenvalue) < 1e-8) { $eigenvalue = $newEigenvalue; $v = $newV; break; }
            $eigenvalue = $newEigenvalue; $v = $newV;
        }
        return ['eigenvalue' => $eigenvalue, 'eigenvector' => $v];
    }

    public function trace(): float { $t = 0; for ($i = 0; $i < min($this->rows(), $this->cols()); $i++) $t += $this->data[$i][$i]; return $t; }

    public function __toString(): string {
        $s = "[\n";
        foreach ($this->data as $row) $s .= "  [" . implode(', ', array_map(fn($v) => number_format($v, 4), $row)) . "]\n";
        return $s . "]";
    }
}

// 测试
echo "--- Matrix Operations ---\n";
$A = new Matrix([[1, 2, 3], [4, 5, 6], [7, 8, 10]]);
$B = new Matrix([[9, 8, 7], [6, 5, 4], [3, 2, 1]]);
echo "A =\n$A\n";
echo "B =\n$B\n";
echo "A+B =\n" . $A->add($B) . "\n";
echo "A*B =\n" . $A->multiply($B) . "\n";
echo "A^T =\n" . $A->transpose() . "\n";
echo "det(A) = " . $A->determinant() . "\n";
echo "trace(A) = " . $A->trace() . "\n";

echo "\n--- Matrix Inverse ---\n";
$inv = $A->inverse();
echo "A^(-1) =\n$inv\n";
$product = $A->multiply($inv);
echo "A * A^(-1) =\n$product\n";
echo "Should be identity: " . var_export(abs($product->trace() - 3) < 1e-6, true) . "\n";

echo "\n--- LU Decomposition ---\n";
$lu = $A->luDecomposition();
echo "L =\n" . $lu['L'] . "\n";
echo "U =\n" . $lu['U'] . "\n";
$L_U = $lu['L']->multiply($lu['U']);
echo "L*U =\n" . $L_U . "\n";
echo "L*U == A: " . var_export(abs($L_U->determinant() - $A->determinant()) < 1e-6, true) . "\n";

echo "\n--- QR Decomposition ---\n";
$qr = $A->qrDecomposition();
echo "Q =\n" . $qr['Q'] . "\n";
echo "R =\n" . $qr['R'] . "\n";
$Q_R = $qr['Q']->multiply($qr['R']);
echo "Q*R =\n" . $Q_R . "\n";
$QtQ = $qr['Q']->transpose()->multiply($qr['Q']);
echo "Q^T*Q trace (should be 3): " . number_format($QtQ->trace(), 6) . "\n";

echo "\n--- Eigenvalue (Power Iteration) ---\n";
$C = new Matrix([[2, 1, 0], [1, 3, 1], [0, 1, 2]]);
echo "C =\n$C\n";
$eig = $C->powerIteration(200);
echo "Dominant eigenvalue: " . number_format($eig['eigenvalue'], 6) . "\n";
echo "Eigenvector: [" . implode(', ', array_map(fn($v) => number_format($v, 6), $eig['eigenvector'])) . "]\n";

echo "\n--- Solving Linear Systems (Ax=b) ---\n";
$b = new Matrix([[6], [15], [25]]);
$x = $A->inverse()?->multiply($b);
echo "A =\n$A\n";
echo "b =\n$b\n";
echo "x = A^(-1)*b =\n$x\n";
$verify = $A->multiply($x);
echo "Verify A*x =\n" . $verify . "\n";

echo "\n--- Matrix Properties ---\n";
$matrices = [
    'Identity' => Matrix::identity(3),
    'Random' => Matrix::random(3, 3, 42),
    'Singular' => new Matrix([[1, 2, 3], [4, 5, 6], [7, 8, 9]]),
];
foreach ($matrices as $name => $m) {
    echo "  $name: det=" . number_format($m->determinant(), 4) . " trace=" . number_format($m->trace(), 4) . " invertible=" . var_export(abs($m->determinant()) > 1e-10, true) . "\n";
}

echo "=== f128 Done ===\n";
