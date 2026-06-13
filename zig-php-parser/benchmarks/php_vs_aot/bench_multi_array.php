<?php
/**
 * Benchmark: 10,000 2D array operations.
 */
$iterations = (int)($argv[1] ?? 10000);
$rows = 100;
$cols = 100;

// Warmup
$matrix = [];
for ($i = 0; $i < min($rows, 10); $i++) {
    $matrix[$i] = [];
    for ($j = 0; $j < min($cols, 10); $j++) {
        $matrix[$i][$j] = $i * $j;
    }
}

// Timed run
$start = microtime(true);
$matrix = [];
for ($i = 0; $i < $rows; $i++) {
    $matrix[$i] = [];
    for ($j = 0; $j < $cols; $j++) {
        $matrix[$i][$j] = $i * $j;
    }
}
// Access all elements
$sum = 0;
for ($i = 0; $i < $rows; $i++) {
    for ($j = 0; $j < $cols; $j++) {
        $sum += $matrix[$i][$j];
    }
}
$elapsed = microtime(true) - $start;

printf("bench_multi_array: iterations=%d, time=%.6f seconds\n", $rows * $cols, $elapsed);