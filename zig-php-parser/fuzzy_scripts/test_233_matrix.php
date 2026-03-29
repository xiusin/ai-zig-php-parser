<?php
function transpose(array $matrix): array {
    if (empty($matrix)) return [];
    $rows = count($matrix);
    $cols = count($matrix[0]);
    $result = array_fill(0, $cols, array_fill(0, $rows, 0));

    for ($i = 0; $i < $rows; $i++) {
        for ($j = 0; $j < $cols; $j++) {
            $result[$j][$i] = $matrix[$i][$j];
        }
    }

    return $result;
}

function multiplyMatrix(array $a, array $b): array {
    $rowsA = count($a);
    $colsA = count($a[0]);
    $colsB = count($b[0]);

    $result = array_fill(0, $rowsA, array_fill(0, $colsB, 0));

    for ($i = 0; $i < $rowsA; $i++) {
        for ($j = 0; $j < $colsB; $j++) {
            for ($k = 0; $k < $colsA; $k++) {
                $result[$i][$j] += $a[$i][$k] * $b[$k][$j];
            }
        }
    }

    return $result;
}

$a = [[1, 2], [3, 4]];
$b = [[5, 6], [7, 8]];

$transposed = transpose($a);
echo $transposed[0][1] . "\n";

$product = multiplyMatrix($a, $b);
echo $product[0][0] . "\n";
echo $product[1][1] . "\n";
echo "OK\n";
