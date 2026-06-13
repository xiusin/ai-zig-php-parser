<?php
/**
 * Benchmark: 10,000,000 global variable accesses.
 */
$iterations = (int)($argv[1] ?? 10000000);

$GLOBALS['bench_counter'] = 0;

function bench_global_access(): void {
    $GLOBALS['bench_counter']++;
}

// Warmup
for ($i = 0; $i < min($iterations, 1000); $i++) {
    bench_global_access();
}

// Timed run
$GLOBALS['bench_counter'] = 0;
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    bench_global_access();
}
$elapsed = microtime(true) - $start;

printf("bench_global: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);