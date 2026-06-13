<?php
/**
 * Benchmark: Build a 100KB string incrementally.
 */
$target_size = (int)($argv[1] ?? 100000); // 100KB
$chunk_size = 1000;
$iterations = (int)($target_size / $chunk_size);
$chunk = str_repeat('x', $chunk_size);

// Warmup
$s = '';
for ($i = 0; $i < min($iterations, 10); $i++) {
    $s .= $chunk;
}

// Timed run
$start = microtime(true);
$s = '';
for ($i = 0; $i < $iterations; $i++) {
    $s .= $chunk;
}
$elapsed = microtime(true) - $start;

$len = strlen($s);
printf("bench_string_builder: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);