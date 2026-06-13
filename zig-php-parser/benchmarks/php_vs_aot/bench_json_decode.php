<?php
/**
 * Benchmark: JSON decode a string 1,000 times.
 */
$iterations = (int)($argv[1] ?? 1000);
$json = json_encode([
    'users' => array_map(function($i) {
        return [
            'id' => $i,
            'name' => 'User ' . $i,
            'email' => 'user' . $i . '@example.com',
            'roles' => ['admin', 'user'],
            'meta' => ['created' => '2024-01-01', 'visits' => $i * 10],
        ];
    }, range(1, 200)),
]);

// Warmup
json_decode($json, true);

// Timed run
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $data = json_decode($json, true);
}
$elapsed = microtime(true) - $start;

printf("bench_json_decode: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);