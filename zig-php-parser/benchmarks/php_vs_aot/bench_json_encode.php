<?php
/**
 * Benchmark: JSON encode a large array 1,000 times.
 */
$iterations = (int)($argv[1] ?? 1000);
$data = [];

// Build a complex data structure
for ($i = 0; $i < 500; $i++) {
    $data[] = [
        'id' => $i,
        'name' => 'Item ' . $i,
        'values' => range(1, 10),
        'nested' => ['a' => 1, 'b' => 2, 'c' => 3],
        'active' => $i % 2 === 0,
    ];
}

// Warmup
json_encode($data);

// Timed run
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $json = json_encode($data);
}
$elapsed = microtime(true) - $start;

printf("bench_json_encode: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);