<?php
/**
 * Benchmark: 100,000 array_push operations.
 */
$iterations = (int)($argv[1] ?? 100000);

// Warmup
$arr = [];
for ($i = 0; $i < min($iterations, 100); $i++) {
    array_push($arr, $i);
}

// Timed run
$start = microtime(true);
$arr = [];
for ($i = 0; $i < $iterations; $i++) {
    array_push($arr, $i);
}
$elapsed = microtime(true) - $start;

printf("bench_array_push: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);