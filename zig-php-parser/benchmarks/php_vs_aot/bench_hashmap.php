<?php
/**
 * Benchmark: 100,000 key-value insert/lookup operations.
 */
$iterations = (int)($argv[1] ?? 100000);

// Warmup
$map = [];
for ($i = 0; $i < min($iterations, 100); $i++) {
    $key = 'key_' . $i;
    $map[$key] = $i;
    $v = $map[$key];
}

// Timed run
$start = microtime(true);
$map = [];
for ($i = 0; $i < $iterations; $i++) {
    $key = 'key_' . $i;
    $map[$key] = $i;
}
for ($i = 0; $i < $iterations; $i++) {
    $key = 'key_' . $i;
    $v = $map[$key];
}
$elapsed = microtime(true) - $start;

printf("bench_hashmap: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);