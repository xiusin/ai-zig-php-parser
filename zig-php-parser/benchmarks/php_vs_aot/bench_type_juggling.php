<?php
/**
 * Benchmark: 10,000,000 mixed int/float operations (type juggling).
 */
$iterations = (int)($argv[1] ?? 10000000);

// Warmup
$x = 0;
for ($i = 0; $i < min($iterations, 1000); $i++) {
    $x = $i * 1.5 + $i / 3.0 - $i * 0.1;
}

// Timed run
$start = microtime(true);
$x = 0;
for ($i = 0; $i < $iterations; $i++) {
    $x = $i * 1.5 + $i / 3.0 - $i * 0.1;
}
$elapsed = microtime(true) - $start;

printf("bench_type_juggling: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);