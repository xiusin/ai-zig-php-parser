<?php
/**
 * Benchmark: Fibonacci(35) recursive.
 */
$n = (int)($argv[1] ?? 35);

function fib($n) {
    if ($n <= 1) return $n;
    return fib($n - 1) + fib($n - 2);
}

// Warmup
fib(min($n, 5));

// Timed run
$start = microtime(true);
$result = fib($n);
$elapsed = microtime(true) - $start;

printf("bench_fibonacci: iterations=%d, time=%.6f seconds\n", $n, $elapsed);