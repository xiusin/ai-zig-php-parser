<?php
/**
 * Benchmark: 1,000,000 method calls on an object.
 */
$iterations = (int)($argv[1] ?? 1000000);

class Counter {
    private int $value = 0;
    public function increment(): void { $this->value++; }
    public function getValue(): int { return $this->value; }
    public function reset(): void { $this->value = 0; }
}

$obj = new Counter();

// Warmup
for ($i = 0; $i < min($iterations, 1000); $i++) {
    $obj->increment();
}

// Timed run
$obj->reset();
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $obj->increment();
}
$elapsed = microtime(true) - $start;

printf("bench_oop: iterations=%d, time=%.6f seconds\n", $iterations, $elapsed);