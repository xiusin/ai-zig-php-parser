<?php
/**
 * Benchmark: Tower of Hanoi (15 disks).
 */
$n = (int)($argv[1] ?? 15);

function hanoi($n, $from, $to, $aux) {
    if ($n === 1) {
        return;
    }
    hanoi($n - 1, $from, $aux, $to);
    hanoi($n - 1, $aux, $to, $from);
}

// Warmup
hanoi(min($n, 3), 'A', 'C', 'B');

// Timed run
$start = microtime(true);
hanoi($n, 'A', 'C', 'B');
$elapsed = microtime(true) - $start;

printf("bench_recursion: iterations=%d, time=%.6f seconds\n", $n, $elapsed);