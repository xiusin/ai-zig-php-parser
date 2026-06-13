<?php
/**
 * Benchmark: Fibonacci(35) iterative.
 */
$n = (int)($argv[1] ?? 35);

// Warmup
$a = 0; $b = 1;
for ($i = 0; $i < min($n, 5); $i++) {
    $c = $a + $b; $a = $b; $b = $c;
}

// Timed run
$start = microtime(true);
$a = 0; $b = 1;
for ($i = 0; $i < $n; $i++) {
    $c = $a + $b;
    $a = $b;
    $b = $c;
}
$elapsed = microtime(true) - $start;

printf("bench_fibonacci_iter: iterations=%d, time=%.6f seconds\n", $n, $elapsed);