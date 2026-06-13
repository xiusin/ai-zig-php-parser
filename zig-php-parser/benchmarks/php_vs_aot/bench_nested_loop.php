<?php
/**
 * Benchmark: Nested loops (100 x 1000).
 */
$outer = (int)($argv[1] ?? 100);
$inner = (int)($argv[2] ?? 1000);

// Warmup
$s = 0;
for ($i = 0; $i < min($outer, 5); $i++) {
    for ($j = 0; $j < min($inner, 5); $j++) {
        $s += $i * $j;
    }
}

// Timed run
$start = microtime(true);
$s = 0;
for ($i = 0; $i < $outer; $i++) {
    for ($j = 0; $j < $inner; $j++) {
        $s += $i * $j;
    }
}
$elapsed = microtime(true) - $start;

$total = $outer * $inner;
printf("bench_nested_loop: iterations=%d, time=%.6f seconds\n", $total, $elapsed);