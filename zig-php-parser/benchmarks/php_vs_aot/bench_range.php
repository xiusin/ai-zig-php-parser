<?php
/**
 * Benchmark: range(1, 100000) and iterate.
 */
$n = (int)($argv[1] ?? 100000);

// Warmup
$r = range(1, min($n, 100));
foreach ($r as $v) { $x = $v; }

// Timed run
$start = microtime(true);
$arr = range(1, $n);
$sum = 0;
foreach ($arr as $v) {
    $sum += $v;
}
$elapsed = microtime(true) - $start;

printf("bench_range: iterations=%d, time=%.6f seconds\n", $n, $elapsed);