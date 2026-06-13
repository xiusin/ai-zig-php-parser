<?php
/**
 * Benchmark: Include a file 1,000 times.
 * Requires an include file: bench_include_target.php
 */
$iterations = (int)($argv[1] ?? 1000);

$include_file = __DIR__ . '/bench_include_target.php';
if (!file_exists($include_file)) {
    file_put_contents($include_file, '<?php $__included_var = 42; return "ok";');
}

// Warmup
for ($i = 0; $i < min($iterations, 10); $i++) {
    include $include_file;
}

// Timed run
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $ret = include $include_file;
}
$elapsed = microtime(true) - $start;

printf("bench_include: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);