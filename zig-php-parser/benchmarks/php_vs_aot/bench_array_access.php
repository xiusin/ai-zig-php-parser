<?php
/**
 * Benchmark: 100,000 array read/write operations.
 */
$iterations = (int)($argv[1] ?? 100000);

// Setup
$arr = array_fill(0, 1000, 0);

// Warmup
for ($i = 0; $i < min($iterations, 100); $i++) {
    $arr[$i % 1000] = $i;
    $v = $arr[$i % 1000];
}

// Timed run
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $idx = $i % 1000;
    $arr[$idx] = $i;
    $v = $arr[$idx];
}
$elapsed = microtime(true) - $start;

printf("bench_array_access: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);