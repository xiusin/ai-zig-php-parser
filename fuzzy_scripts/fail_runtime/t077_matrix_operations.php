<?php
// 矩阵操作：加法、乘法、标量乘法、转置、行列式

function matrix_add(array $a, array $b): array {
    $rows = count($a);
    $cols = count($a[0]);
    $result = [];
    for ($i = 0; $i < $rows; $i++) {
        $result[$i] = [];
        for ($j = 0; $j < $cols; $j++) {
            $result[$i][$j] = $a[$i][$j] + $b[$i][$j];
        }
    }
    return $result;
}

function matrix_multiply(array $a, array $b): array {
    $rowsA = count($a);
    $colsA = count($a[0]);
    $colsB = count($b[0]);
    $result = [];
    for ($i = 0; $i < $rowsA; $i++) {
        $result[$i] = [];
        for ($j = 0; $j < $colsB; $j++) {
            $sum = 0;
            for ($k = 0; $k < $colsA; $k++) {
                $sum += $a[$i][$k] * $b[$k][$j];
            }
            $result[$i][$j] = $sum;
        }
    }
    return $result;
}

function matrix_scalar_multiply(array $a, float $scalar): array {
    $result = [];
    for ($i = 0; $i < count($a); $i++) {
        $result[$i] = [];
        for ($j = 0; $j < count($a[0]); $j++) {
            $result[$i][$j] = $a[$i][$j] * $scalar;
        }
    }
    return $result;
}

function matrix_transpose(array $a): array {
    $rows = count($a);
    $cols = count($a[0]);
    $result = [];
    for ($i = 0; $i < $cols; $i++) {
        $result[$i] = [];
        for ($j = 0; $j < $rows; $j++) {
            $result[$i][$j] = $a[$j][$i];
        }
    }
    return $result;
}

function matrix_determinant(array $a): float {
    $n = count($a);
    if ($n === 1) return $a[0][0];
    if ($n === 2) return $a[0][0] * $a[1][1] - $a[0][1] * $a[1][0];

    $det = 0;
    for ($col = 0; $col < $n; $col++) {
        $minor = [];
        for ($i = 1; $i < $n; $i++) {
            $row = [];
            for ($j = 0; $j < $n; $j++) {
                if ($j !== $col) $row[] = $a[$i][$j];
            }
            $minor[] = $row;
        }
        $sign = ($col % 2 === 0) ? 1 : -1;
        $det += $sign * $a[0][$col] * matrix_determinant($minor);
    }
    return $det;
}

function matrix_identity(int $n): array {
    $result = [];
    for ($i = 0; $i < $n; $i++) {
        $result[$i] = [];
        for ($j = 0; $j < $n; $j++) {
            $result[$i][$j] = ($i === $j) ? 1 : 0;
        }
    }
    return $result;
}

function matrix_to_string(array $a): string {
    $parts = [];
    foreach ($a as $row) {
        $parts[] = '[' . implode(',', $row) . ']';
    }
    return '[' . implode(',', $parts) . ']';
}

// 测试矩阵加法
$a = [[1, 2, 3], [4, 5, 6], [7, 8, 9]];
$b = [[9, 8, 7], [6, 5, 4], [3, 2, 1]];
echo "add: " . matrix_to_string(matrix_add($a, $b)) . "\n";

// 测试矩阵乘法
echo "multiply: " . matrix_to_string(matrix_multiply($a, $b)) . "\n";

// 测试标量乘法
echo "scalar: " . matrix_to_string(matrix_scalar_multiply($a, 2.0)) . "\n";

// 测试转置
echo "transpose: " . matrix_to_string(matrix_transpose($a)) . "\n";

// 测试单位矩阵
echo "identity: " . matrix_to_string(matrix_identity(3)) . "\n";

// 测试行列式
$m2x2 = [[4, 7], [2, 6]];
echo "det_2x2: " . matrix_determinant($m2x2) . "\n";

$m3x3 = [[2, 1, 3], [1, 0, 2], [4, 1, 1]];
echo "det_3x3: " . matrix_determinant($m3x3) . "\n";

// 测试矩阵乘法结合单位矩阵
echo "multiply_identity: " . matrix_to_string(matrix_multiply($a, matrix_identity(3))) . "\n";

// 测试转置的转置等于原矩阵
echo "double_transpose: " . matrix_to_string(matrix_transpose(matrix_transpose($a))) . "\n";
