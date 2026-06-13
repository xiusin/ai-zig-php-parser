<?php
/**
 * Benchmark: 10,000 str_replace operations.
 */
$iterations = (int)($argv[1] ?? 10000);
$subject = 'The quick brown fox jumps over the lazy dog. The lazy dog slept.';

// Warmup
for ($i = 0; $i < min($iterations, 100); $i++) {
    str_replace('lazy', 'active', $subject);
}

// Timed run
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $r = str_replace('lazy', 'active', $subject);
}
$elapsed = microtime(true) - $start;

printf("bench_string_replace: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);