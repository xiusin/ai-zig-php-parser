<?php
/**
 * Benchmark: Sum of numbers 1 to N using a for loop.
 * Default: N = 10,000,000
 */
$iterations = (int)($argv[1] ?? 10000000);

// Warmup
$s = 0;
for ($i = 1; $i <= min($iterations, 1000); $i++) {
    $s += $i;
}

// Timed run
$start = microtime(true);
$sum = 0;
for ($i = 1; $i <= $iterations; $i++) {
    $sum += $i;
}
$elapsed = microtime(true) - $start;

printf("bench_sum: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);