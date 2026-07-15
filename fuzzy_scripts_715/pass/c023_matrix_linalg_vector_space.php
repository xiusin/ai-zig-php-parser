<?php
// 极度混搭: 矩阵运算 + 线性代数 + 向量空间 + 数值方法 + 坐标变换
echo "=== c023: Matrix Ops + Linear Algebra + Vector Space + Numerical ===\n\n";

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
        $data = [];
        for ($i = 0; $i < $n; $i++) {
            $row = array_fill(0, $n, 0);
            $row[$i] = 1;
            $data[] = $row;
        }
        return new self($data);
    }

    public static function zeros(int $rows, int $cols): self {
        $data = [];
        for ($i = 0; $i < $rows; $i++) {
            $data[] = array_fill(0, $cols, 0);
        }
        return new self($data);
    }

    public static function random(int $rows, int $cols, int $max = 10): self {
        $data = [];
        for ($i = 0; $i < $rows; $i++) {
            $row = [];
            for ($j = 0; $j < $cols; $j++) {
                $row[] = $j * 3 + $i * 2 + 1;
            }
            $data[] = $row;
        }
        return new self($data);
    }

    public function getRows(): int { return $this->rows; }
    public function getCols(): int { return $this->cols; }
    public function get(int $row, int $col): float { return $this->data[$row][$col]; }

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

    public function multiply(Matrix $other): Matrix {
        $result = self::zeros($this->rows, $other->cols);
        for ($i = 0; $i < $this->rows; $i++) {
            for ($j = 0; $j < $other->cols; $j++) {
                $sum = 0;
                for ($k = 0; $k < $this->cols; $k++) {
                    $sum += $this->data[$i][$k] * $other->get($k, $j);
                }
                $result->data[$i][$j] = $sum;
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

    public function trace(): float {
        $sum = 0;
        $n = min($this->rows, $this->cols);
        for ($i = 0; $i < $n; $i++) {
            $sum += $this->data[$i][$i];
        }
        return $sum;
    }

    public function determinant(): float {
        if ($this->rows !== $this->cols) return 0.0;
        if ($this->rows === 1) return $this->data[0][0];
        if ($this->rows === 2) {
            return $this->data[0][0] * $this->data[1][1] - $this->data[0][1] * $this->data[1][0];
        }
        // Laplace expansion
        $det = 0;
        for ($j = 0; $j < $this->cols; $j++) {
            $det += $this->data[0][$j] * $this->cofactor(0, $j);
        }
        return $det;
    }

    private function cofactor(int $row, int $col): float {
        $sub = [];
        for ($i = 0; $i < $this->rows; $i++) {
            if ($i === $row) continue;
            $subRow = [];
            for ($j = 0; $j < $this->cols; $j++) {
                if ($j === $col) continue;
                $subRow[] = $this->data[$i][$j];
            }
            $sub[] = $subRow;
        }
        $sign = (($row + $col) % 2 === 0) ? 1 : -1;
        return $sign * (new Matrix($sub))->determinant();
    }

    public function __toString(): string {
        $lines = [];
        foreach ($this->data as $row) {
            $lines[] = "[" . implode(", ", array_map(fn($v) => number_format($v, 2), $row)) . "]";
        }
        return implode("\n", $lines);
    }
}

class Vector {
    private array $components;

    public function __construct(array $components) {
        $this->components = $components;
    }

    public function getDimension(): int {
        return count($this->components);
    }

    public function get(int $i): float {
        return $this->components[$i];
    }

    public function add(Vector $other): Vector {
        $result = [];
        for ($i = 0; $i < $this->getDimension(); $i++) {
            $result[] = $this->components[$i] + $other->get($i);
        }
        return new Vector($result);
    }

    public function dot(Vector $other): float {
        $sum = 0;
        for ($i = 0; $i < $this->getDimension(); $i++) {
            $sum += $this->components[$i] * $other->get($i);
        }
        return $sum;
    }

    public function magnitude(): float {
        return sqrt($this->dot($this));
    }

    public function normalize(): Vector {
        $mag = $this->magnitude();
        if ($mag == 0) return new Vector($this->components);
        return new Vector(array_map(fn($c) => $c / $mag, $this->components));
    }

    public function cross(Vector $other): Vector {
        if ($this->getDimension() !== 3 || $other->getDimension() !== 3) {
            throw new InvalidArgumentException("Cross product requires 3D vectors");
        }
        return new Vector([
            $this->components[1] * $other->get(2) - $this->components[2] * $other->get(1),
            $this->components[2] * $other->get(0) - $this->components[0] * $other->get(2),
            $this->components[0] * $other->get(1) - $this->components[1] * $other->get(0),
        ]);
    }

    public function angle(Vector $other): float {
        $dot = $this->dot($other);
        $mag = $this->magnitude() * $other->magnitude();
        if ($mag == 0) return 0;
        $cos = max(-1, min(1, $dot / $mag));
        return acos($cos);
    }

    public function __toString(): string {
        return "(" . implode(", ", $this->components) . ")";
    }
}

// === 测试 ===

echo "--- Matrix Operations ---\n";
$m1 = new Matrix([[1, 2, 3], [4, 5, 6]]);
$m2 = new Matrix([[7, 8], [9, 10], [11, 12]]);
echo "M1:\n$m1\n";
echo "M2:\n$m2\n";

$product = $m1->multiply($m2);
echo "M1 × M2:\n$product\n";

$transposed = $m1->transpose();
echo "M1^T:\n$transposed\n";

$identity = Matrix::identity(3);
echo "I3:\n$identity\n";

echo "\n--- Determinant ---\n";
$d2 = new Matrix([[3, 1], [2, 4]]);
echo "2x2 det: " . $d2->determinant() . "\n";

$d3 = new Matrix([[1, 2, 3], [4, 5, 6], [7, 8, 10]]);
echo "3x3 det: " . $d3->determinant() . "\n";

$d4 = new Matrix([[2, 0, 0, 0], [0, 3, 0, 0], [0, 0, 4, 0], [0, 0, 0, 5]]);
echo "Diagonal 4x4 det: " . $d4->determinant() . "\n";

echo "\n--- Trace ---\n";
echo "Trace of d3: " . $d3->trace() . "\n";
echo "Trace of d4: " . $d4->trace() . "\n";

echo "\n--- Vector Operations ---\n";
$v1 = new Vector([1, 2, 3]);
$v2 = new Vector([4, 5, 6]);
echo "v1 = $v1\n";
echo "v2 = $v2\n";
echo "v1 + v2 = " . $v1->add($v2) . "\n";
echo "v1 · v2 = " . $v1->dot($v2) . "\n";
echo "|v1| = " . number_format($v1->magnitude(), 4) . "\n";
echo "v1 × v2 = " . $v1->cross($v2) . "\n";

$angle = $v1->angle($v2);
echo "Angle = " . number_format($angle * 180 / 3.14159265, 2) . " degrees\n";

echo "\n--- Normalize ---\n";
$v3 = new Vector([3, 4]);
echo "v3 = $v3 |v3|=" . $v3->magnitude() . "\n";
echo "normalized = " . $v3->normalize() . "\n";

echo "\n--- Coordinate Transform ---\n";
// Rotation matrix for 90 degrees
$theta = 1.5707963; // pi/2
$rot = new Matrix([
    [cos($theta), -sin($theta)],
    [sin($theta), cos($theta)],
]);
$point = new Matrix([[1], [0]]);
$rotated = $rot->multiply($point);
echo "Rotate (1,0) by 90°:\n$rotated\n";

echo "\n=== c023 Done ===\n";
