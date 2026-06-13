<?php
/**
 * Benchmark: 1,000,000 closure calls.
 */
$iterations = (int)($argv[1] ?? 1000000);

$fn = function(int $x): int {
    return $x * 2 + 1;
};

// Warmup
for ($i = 0; $i < min($iterations, 1000); $i++) {
    $fn($i);
}

// Timed run
$start = microtime(true);
$sum = 0;
for ($i = 0; $i < $iterations; $i++) {
    $sum += $fn($i);
}
$elapsed = microtime(true) - $start;

printf("bench_closure: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);