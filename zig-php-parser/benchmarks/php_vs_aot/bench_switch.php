<?php
/**
 * Benchmark: 1,000,000 switch-case operations.
 */
$iterations = (int)($argv[1] ?? 1000000);

// Warmup
for ($i = 0; $i < min($iterations, 1000); $i++) {
    $v = $i % 10;
    switch ($v) {
        case 0: $r = 'zero'; break;
        case 1: $r = 'one'; break;
        case 2: $r = 'two'; break;
        case 3: $r = 'three'; break;
        case 4: $r = 'four'; break;
        case 5: $r = 'five'; break;
        case 6: $r = 'six'; break;
        case 7: $r = 'seven'; break;
        case 8: $r = 'eight'; break;
        default: $r = 'nine'; break;
    }
}

// Timed run
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $v = $i % 10;
    switch ($v) {
        case 0: $r = 'zero'; break;
        case 1: $r = 'one'; break;
        case 2: $r = 'two'; break;
        case 3: $r = 'three'; break;
        case 4: $r = 'four'; break;
        case 5: $r = 'five'; break;
        case 6: $r = 'six'; break;
        case 7: $r = 'seven'; break;
        case 8: $r = 'eight'; break;
        default: $r = 'nine'; break;
    }
}
$elapsed = microtime(true) - $start;

printf("bench_switch: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);