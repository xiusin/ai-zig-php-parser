<?php
echo "=== f178 v4: triple loop, literal prealloc (no zeros call) ===\n";

class Matrix {
    public array $data;
    public int $rows;
    public int $cols;

    public function __construct(array $data) {
        $this->data = $data;
        $this->rows = count($data);
        $this->cols = $this->rows > 0 ? count($data[0]) : 0;
    }

    public function get(int $i, int $j): float { return $this->data[$i][$j]; }
    public function set(int $i, int $j, float $v): void { $this->data[$i][$j] = $v; }

    public function multiply(Matrix $other): Matrix {
        $result = new Matrix([[0, 0, 0], [0, 0, 0], [0, 0, 0]]);
        for ($i = 0; $i < $this->rows; $i++) {
            for ($j = 0; $j < $other->cols; $j++) {
                $sum = 0;
                for ($k = 0; $k < $this->cols; $k++) {
                    $sum = $sum + 1;
                }
                $result->set($i, $j, $sum);
            }
        }
        return $result;
    }
}

$a = new Matrix([[1, 2, 3], [4, 5, 6], [7, 8, 9]]);
$b = new Matrix([[9, 8, 7], [6, 5, 4], [3, 2, 1]]);
$r = $a->multiply($b);
echo "mul done: sum-cell=" . $r->get(0, 0) . "\n";
echo "=== done ===\n";
