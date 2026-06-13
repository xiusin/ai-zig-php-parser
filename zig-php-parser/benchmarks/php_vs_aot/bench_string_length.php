<?php
/**
 * Benchmark: 10,000,000 strlen calls.
 */
$iterations = (int)($argv[1] ?? 10000000);
$test_string = 'Hello, World! This is a test string for benchmarking strlen.';

// Warmup
for ($i = 0; $i < min($iterations, 1000); $i++) {
    $len = strlen($test_string);
}

// Timed run
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $len = strlen($test_string);
}
$elapsed = microtime(true) - $start;

printf("bench_string_length: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);