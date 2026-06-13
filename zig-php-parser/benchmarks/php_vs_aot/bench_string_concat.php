<?php
/**
 * Benchmark: 10,000 string concatenations in a loop.
 */
$iterations = (int)($argv[1] ?? 10000);

// Warmup
$s = '';
for ($i = 0; $i < min($iterations, 100); $i++) {
    $s .= 'x';
}

// Timed run
$start = microtime(true);
$s = '';
for ($i = 0; $i < $iterations; $i++) {
    $s .= 'a';
}
$elapsed = microtime(true) - $start;

printf("bench_string_concat: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);