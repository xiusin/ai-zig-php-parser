<?php
echo "=== f178 v5: bare triple loop, trivial body, no writes ===\n";

class Matrix {
    public array $data;
    public int $rows;
    public int $cols;

    public function __construct(array $data) {
        $this->data = $data;
        $this->rows = count($data);
        $this->cols = $this->rows > 0 ? count($data[0]) : 0;
    }

    public function tri(Matrix $other): int {
        $x = 0;
        for ($i = 0; $i < $this->rows; $i++) {
            for ($j = 0; $j < $other->cols; $j++) {
                for ($k = 0; $k < $this->cols; $k++) {
                    $x = $x + 1;
                }
            }
        }
        return $x;
    }
}

$a = new Matrix([[1, 2, 3], [4, 5, 6], [7, 8, 9]]);
$b = new Matrix([[9, 8, 7], [6, 5, 4], [3, 2, 1]]);
echo "tri=" . $a->tri($b) . "\n";
echo "=== done ===\n";
