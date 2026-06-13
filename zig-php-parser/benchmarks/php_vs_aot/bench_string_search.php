<?php
/**
 * Benchmark: 10,000 strpos searches.
 */
$iterations = (int)($argv[1] ?? 10000);
$haystack = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.';

// Warmup
for ($i = 0; $i < min($iterations, 100); $i++) {
    strpos($haystack, 'dolor');
}

// Timed run
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $r = strpos($haystack, 'dolor');
}
$elapsed = microtime(true) - $start;

printf("bench_string_search: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);