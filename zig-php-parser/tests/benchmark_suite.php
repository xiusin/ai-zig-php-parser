<?php
// Performance Benchmark Suite for Zig-PHP Interpreter

echo "=== Zig-PHP Performance Benchmark Suite ===\n\n";

function benchmark($name, $iterations, $callback) {
    $start = microtime(true);
    for ($i = 0; $i < $iterations; $i++) {
        $callback();
    }
    $end = microtime(true);
    $time_ms = ($end - $start) * 1000;
    $ops_per_sec = $iterations / ($end - $start);
    echo $name . ": " . round($time_ms, 2) . " ms (" . $iterations . " iters, " . round($ops_per_sec) . " ops/s)\n";
    return $time_ms;
}

// Benchmark 1: Integer arithmetic
benchmark("Integer arithmetic", 100000, function() {
    $a = 42;
    $b = 17;
    $c = $a + $b;
    $d = $a * $b;
    $e = $a - $b;
});

// Benchmark 2: Float arithmetic
benchmark("Float arithmetic", 100000, function() {
    $a = 3.14159;
    $b = 2.71828;
    $c = $a + $b;
    $d = $a * $b;
    $e = $a / $b;
});

// Benchmark 3: String concatenation
benchmark("String concat", 10000, function() {
    $s = "";
    for ($i = 0; $i < 10; $i++) {
        $s .= "x";
    }
});

// Benchmark 4: Array push
benchmark("Array push", 10000, function() {
    $arr = [];
    for ($i = 0; $i < 10; $i++) {
        $arr[] = $i;
    }
});

// Benchmark 5: Array access
benchmark("Array access", 100000, function() {
    $arr = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
    $sum = 0;
    for ($i = 0; $i < 10; $i++) {
        $sum += $arr[$i];
    }
});

// Benchmark 6: Function calls
function simple_add($a, $b) {
    return $a + $b;
}
benchmark("Function calls", 100000, function() {
    simple_add(1, 2);
});

// Benchmark 7: Object creation
class SimpleClass {
    public $value;
    public function __construct($v) {
        $this->value = $v;
    }
}
benchmark("Object creation", 10000, function() {
    $obj = new SimpleClass(42);
});

// Benchmark 8: Property access
benchmark("Property access", 100000, function() {
    $obj = new SimpleClass(42);
    $v = $obj->value;
});

// Benchmark 9: Recursive fibonacci (small)
function fib_small($n) {
    if ($n <= 1) return $n;
    return fib_small($n - 1) + fib_small($n - 2);
}
benchmark("Fibonacci(15)", 1000, function() {
    fib_small(15);
});

// Benchmark 10: Loop with conditionals
benchmark("Loop conditionals", 10000, function() {
    $count = 0;
    for ($i = 0; $i < 100; $i++) {
        if ($i % 2 == 0) {
            $count++;
        }
    }
});

echo "\n=== Benchmark Complete ===\n";
?>
