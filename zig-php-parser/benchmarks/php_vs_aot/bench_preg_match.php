<?php
/**
 * Benchmark: 100,000 regex matches with preg_match.
 */
$iterations = (int)($argv[1] ?? 100000);
$subject = 'Contact us at support@example.com or sales@company.org. Visit https://example.com for more info. Phone: 555-1234.';

// Warmup
for ($i = 0; $i < min($iterations, 100); $i++) {
    preg_match('/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/', $subject, $matches);
}

// Timed run
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    preg_match('/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/', $subject, $matches);
}
$elapsed = microtime(true) - $start;

printf("bench_preg_match: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);