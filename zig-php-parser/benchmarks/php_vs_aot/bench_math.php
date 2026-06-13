<?php
/**
 * Benchmark: 10,000,000 iterations of sin/cos/tan/sqrt operations.
 */
$iterations = (int)($argv[1] ?? 10000000);

// Warmup
$x = 0.0;
for ($i = 0; $i < min($iterations, 1000); $i++) {
    $x = sin((float)$i);
    $x = cos($x);
    $x = tan($x);
    $x = sqrt(abs($x) + 1.0);
}

// Timed run
$start = microtime(true);
$x = 0.0;
for ($i = 0; $i < $iterations; $i++) {
    $x = sin((float)$i);
    $x = cos($x);
    $x = tan($x);
    $x = sqrt(abs($x) + 1.0);
}
$elapsed = microtime(true) - $start;

printf("bench_math: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);