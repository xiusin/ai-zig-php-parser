<?php
/**
 * Benchmark: Filter an array of 10,000 elements.
 */
$size = (int)($argv[1] ?? 10000);
$arr = range(1, $size);

// Warmup
array_filter($arr, function($v) { return $v % 2 === 0; });

// Timed run
$start = microtime(true);
$filtered = array_filter($arr, function($v) {
    return $v % 2 === 0;
});
$elapsed = microtime(true) - $start;

$count = count($filtered);
printf("bench_array_filter: iterations=%d, time=%.6f seconds\n", $size, $elapsed);