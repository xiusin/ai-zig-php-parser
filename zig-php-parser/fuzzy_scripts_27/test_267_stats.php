<?php
function average(array $nums): float {
    if (empty($nums)) return 0.0;
    return array_sum($nums) / count($nums);
}

function median(array $nums): float {
    if (empty($nums)) return 0.0;
    sort($nums);
    $n = count($nums);
    $mid = $n >> 1;
    return $n % 2 === 0 ? ($nums[$mid - 1] + $nums[$mid]) / 2 : $nums[$mid];
}

function variance(array $nums): float {
    if (empty($nums)) return 0.0;
    $avg = average($nums);
    $sumSquares = 0;
    foreach ($nums as $n) {
        $sumSquares += pow($n - $avg, 2);
    }
    return $sumSquares / count($nums);
}

function standardDeviation(array $nums): float {
    return sqrt(variance($nums));
}

$nums = [10, 20, 30, 40, 50];
echo sprintf("%.2f\n", average($nums));
echo sprintf("%.2f\n", median($nums));
echo sprintf("%.2f\n", variance($nums));
echo sprintf("%.2f\n", standardDeviation($nums));
echo "OK\n";
