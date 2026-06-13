<?php
/**
 * Benchmark: 10,000,000 if-else branches.
 */
$iterations = (int)($argv[1] ?? 10000000);

// Warmup
$r = 0;
for ($i = 0; $i < min($iterations, 1000); $i++) {
    if ($i % 2 === 0) { $r++; } else { $r--; }
}

// Timed run
$start = microtime(true);
$r = 0;
for ($i = 0; $i < $iterations; $i++) {
    if ($i % 2 === 0) {
        $r++;
    } else {
        $r--;
    }
}
$elapsed = microtime(true) - $start;

printf("bench_if_else: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);