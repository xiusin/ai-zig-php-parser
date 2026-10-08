<?php
echo "=== f178 multiply minimal repro ===\n";

class Matrix {
    public array $data;
    public int $rows;
    public int $cols;

    public function __construct(array $data) {
        $this->data = $data;
        $this->rows = count($data);
        $this->cols = $this->rows > 0 ? count($data[0]) : 0;
    }

    public static function zeros(int $rows, int $cols): self {
        return new self(array_fill(0, $rows, array_fill(0, $cols, 0)));
    }

    public function get(int $i, int $j): float { return $this->data[$i][$j]; }
    public function set(int $i, int $j, float $v): void { $this->data[$i][$j] = $v; }

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

    public function toString(): string {
        $out = [];
        foreach ($this->data as $row) {
            $cells = [];
            foreach ($row as $v) $cells[] = sprintf('[%6.2f]', $v);
            $out[] = '  ' . implode(', ', $cells);
        }
        return implode("\n", $out);
    }
}

$a = new Matrix([[1, 2, 3], [4, 5, 6], [7, 8, 9]]);
$b = new Matrix([[9, 8, 7], [6, 5, 4], [3, 2, 1]]);
echo "A * B:\n" . $a->multiply($b)->toString() . "\n";
echo "=== done ===\n";
