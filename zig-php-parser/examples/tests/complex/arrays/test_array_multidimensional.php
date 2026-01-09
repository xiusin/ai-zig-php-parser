<?php
$matrix = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9],
];

echo "Matrix:\n";
foreach ($matrix as $row) {
    echo implode(" ", $row) . "\n";
}

echo "Diagonal: ";
echo $matrix[0][0] . ", " . $matrix[1][1] . ", " . $matrix[2][2] . "\n";

// Transpose
$transposed = [];
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        $transposed[$i][$j] = $matrix[$j][$i];
    }
}

echo "Transposed:\n";
foreach ($transposed as $row) {
    echo implode(" ", $row) . "\n";
}
