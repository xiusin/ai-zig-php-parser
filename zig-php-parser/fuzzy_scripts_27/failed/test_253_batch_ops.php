<?php
function batch(array $items, int $size): array {
    $batches = [];
    $batch = [];

    foreach ($items as $item) {
        $batch[] = $item;
        if (count($batch) === $size) {
            $batches[] = $batch;
            $batch = [];
        }
    }

    if (!empty($batch)) {
        $batches[] = $batch;
    }

    return $batches;
}

function transpose2(array $matrix): array {
    if (empty($matrix)) return [];
    $rows = count($matrix);
    $cols = count($matrix[0]);
    $result = [];
    for ($j = 0; $j < $cols; $j++) {
        $result[$j] = [];
        for ($i = 0; $i < $rows; $i++) {
            $result[$j][$i] = $matrix[$i][$j];
        }
    }
    return $result;
}

function shuffleArray(array $arr): array {
    $result = $arr;
    $n = count($result);
    for ($i = $n - 1; $i > 0; $i--) {
        $j = rand(0, $i);
        [$result[$i], $result[$j]] = [$result[$j], $result[$i]];
    }
    return $result;
}

$items = range(1, 10);
$batches = batch($items, 3);
echo count($batches) . "\n";
foreach ($batches as $b) {
    echo implode(',', $b) . " ";
}
echo "\n";

$matrix = [[1, 2, 3], [4, 5, 6]];
$transposed = transpose2($matrix);
echo $transposed[1][0] . "\n";
echo "OK\n";
