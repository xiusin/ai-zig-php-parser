<?php
/**
 * Benchmark: 10,000,000 ternary operations.
 */
$iterations = (int)($argv[1] ?? 10000000);

// Warmup
for ($i = 0; $i < min($iterations, 1000); $i++) {
    $r = ($i % 2 === 0) ? $i + 1 : $i - 1;
}

// Timed run
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $r = ($i % 2 === 0) ? $i + 1 : $i - 1;
}
$elapsed = microtime(true) - $start;

printf("bench_ternary: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);