<?php
/**
 * Simple Performance Benchmark Suite
 * Compatible with Zig-PHP interpreter
 */

echo "=== Zig-PHP Simple Performance Benchmark ===\n\n";

function benchmark($name, $iterations, $callback) {
    // Warmup
    $warmup = $iterations / 10;
    if ($warmup < 10) $warmup = 10;
    for ($i = 0; $i < $warmup; $i++) {
        $callback();
    }
    
    $start = microtime(true);
    for ($i = 0; $i < $iterations; $i++) {
        $callback();
    }
    $end = microtime(true);
    
    $time_ms = ($end - $start) * 1000;
    $ops_per_sec = $iterations / ($end - $start);
    
    echo $name . ": " . round($time_ms, 2) . " ms (" . round($ops_per_sec) . " ops/s)\n";
    
    return $time_ms;
}

$total_time = 0;

echo "--- Integer Operations ---\n";

$total_time += benchmark("Int addition", 500000, function() {
    $a = 42;
    $b = 17;
    $c = $a + $b;
    return $c;
});

$total_time += benchmark("Int multiplication", 500000, function() {
    $a = 123;
    $b = 456;
    $c = $a * $b;
    return $c;
});

$total_time += benchmark("Int comparison", 500000, function() {
    $a = 42;
    $b = 17;
    $c = $a > $b;
    return $c;
});

$total_time += benchmark("Large int (48-bit)", 100000, function() {
    $a = 1000000000000;
    $b = 2000000000000;
    $c = $a + $b;
    return $c;
});

echo "\n--- Float Operations ---\n";

$total_time += benchmark("Float addition", 500000, function() {
    $a = 3.14159;
    $b = 2.71828;
    $c = $a + $b;
    return $c;
});

$total_time += benchmark("Float multiplication", 500000, function() {
    $a = 3.14159;
    $b = 2.71828;
    $c = $a * $b;
    return $c;
});

echo "\n--- String Operations ---\n";

$test_string = str_repeat("x", 100);

$total_time += benchmark("strlen", 200000, function() use ($test_string) {
    return strlen($test_string);
});

$total_time += benchmark("String concat", 50000, function() {
    $s = "";
    for ($i = 0; $i < 10; $i++) {
        $s = $s . "x";
    }
    return $s;
});

$haystack = "abcdefghijklmnopqrstuvwxyz_needle_abcdefghijklmnopqrstuvwxyz";

$total_time += benchmark("strpos", 200000, function() use ($haystack) {
    return strpos($haystack, "needle");
});

$upper = "HELLO WORLD TEST STRING";

$total_time += benchmark("strtolower", 200000, function() use ($upper) {
    return strtolower($upper);
});

echo "\n--- Array Operations ---\n";

$total_time += benchmark("Array push", 50000, function() {
    $arr = [];
    for ($i = 0; $i < 10; $i++) {
        $arr[] = $i;
    }
    return $arr;
});

$arr = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

$total_time += benchmark("Array access", 500000, function() use ($arr) {
    $sum = 0;
    for ($i = 0; $i < 10; $i++) {
        $sum = $sum + $arr[$i];
    }
    return $sum;
});

$total_time += benchmark("count()", 500000, function() use ($arr) {
    return count($arr);
});

echo "\n--- Object Operations ---\n";

class Point {
    public $x;
    public $y;
    
    public function __construct($x, $y) {
        $this->x = $x;
        $this->y = $y;
    }
}

$total_time += benchmark("Object creation", 50000, function() {
    $obj = new Point(10, 20);
    return $obj;
});

$point = new Point(100, 200);

$total_time += benchmark("Property access", 500000, function() use ($point) {
    $x = $point->x;
    $y = $point->y;
    return $x + $y;
});

echo "\n--- Function Calls ---\n";

function add_nums($a, $b) {
    return $a + $b;
}

$total_time += benchmark("Function call", 500000, function() {
    return add_nums(1, 2);
});

function fib_small($n) {
    if ($n <= 1) return $n;
    return fib_small($n - 1) + fib_small($n - 2);
}

$total_time += benchmark("Fibonacci(15)", 5000, function() {
    return fib_small(15);
});

echo "\n--- Control Flow ---\n";

$total_time += benchmark("Loop + conditionals", 50000, function() {
    $count = 0;
    for ($i = 0; $i < 100; $i++) {
        if ($i % 2 == 0) {
            $count = $count + 1;
        }
    }
    return $count;
});

$total_time += benchmark("While loop", 50000, function() {
    $i = 0;
    $sum = 0;
    while ($i < 100) {
        $sum = $sum + $i;
        $i = $i + 1;
    }
    return $sum;
});

echo "\n=== Summary ===\n";
echo "Total time: " . round($total_time, 2) . " ms\n";
echo "Tests completed: 18\n";
echo "\n=== Benchmark Complete ===\n";
?>
