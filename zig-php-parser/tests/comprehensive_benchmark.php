<?php
/**
 * Comprehensive Performance Benchmark Suite
 * 
 * Tests various aspects of the Zig-PHP interpreter performance:
 * - Integer arithmetic (fast path)
 * - Float arithmetic
 * - String operations (SIMD optimized)
 * - Array operations (packed array)
 * - Object operations (Shape system)
 * - Function calls (CallFrame pool)
 * - Memory allocation patterns
 */

echo "=== Zig-PHP Comprehensive Performance Benchmark ===\n";
echo "Date: " . date("Y-m-d H:i:s") . "\n\n";

// Benchmark helper function
function benchmark($name, $iterations, $callback) {
    // Warmup
    for ($i = 0; $i < min(100, $iterations / 10); $i++) {
        $callback();
    }
    
    $start = microtime(true);
    for ($i = 0; $i < $iterations; $i++) {
        $callback();
    }
    $end = microtime(true);
    
    $time_ms = ($end - $start) * 1000;
    $ops_per_sec = $iterations / ($end - $start);
    
    printf("%-30s %8.2f ms | %12.0f ops/s | %d iters\n", 
           $name . ":", $time_ms, $ops_per_sec, $iterations);
    
    return [
        'name' => $name,
        'time_ms' => $time_ms,
        'ops_per_sec' => $ops_per_sec,
        'iterations' => $iterations
    ];
}

$results = [];

echo "--- Integer Operations (48-bit fast path) ---\n";

// Test 1: Simple integer addition
$results[] = benchmark("Int addition", 500000, function() {
    $a = 42;
    $b = 17;
    $c = $a + $b;
    return $c;
});

// Test 2: Integer multiplication
$results[] = benchmark("Int multiplication", 500000, function() {
    $a = 123;
    $b = 456;
    $c = $a * $b;
    return $c;
});

// Test 3: Large integer (within 48-bit range)
$results[] = benchmark("Large int (48-bit)", 100000, function() {
    $a = 1000000000000; // 1 trillion
    $b = 2000000000000;
    $c = $a + $b;
    return $c;
});

// Test 4: Integer comparison
$results[] = benchmark("Int comparison", 500000, function() {
    $a = 42;
    $b = 17;
    $c = $a > $b;
    $d = $a < $b;
    $e = $a == $b;
    return $c;
});

echo "\n--- Float Operations ---\n";

// Test 5: Float addition
$results[] = benchmark("Float addition", 500000, function() {
    $a = 3.14159;
    $b = 2.71828;
    $c = $a + $b;
    return $c;
});

// Test 6: Float multiplication
$results[] = benchmark("Float multiplication", 500000, function() {
    $a = 3.14159;
    $b = 2.71828;
    $c = $a * $b;
    return $c;
});

echo "\n--- String Operations (SIMD optimized) ---\n";

// Test 7: String length
$test_string = str_repeat("x", 1000);
$results[] = benchmark("strlen (1KB)", 100000, function() use ($test_string) {
    return strlen($test_string);
});

// Test 8: String concatenation
$results[] = benchmark("String concat", 50000, function() {
    $s = "";
    for ($i = 0; $i < 10; $i++) {
        $s .= "x";
    }
    return $s;
});

// Test 9: strpos (SIMD)
$haystack = str_repeat("abc", 100) . "needle" . str_repeat("def", 100);
$results[] = benchmark("strpos (SIMD)", 100000, function() use ($haystack) {
    return strpos($haystack, "needle");
});

// Test 10: strtolower (SIMD)
$upper_string = "HELLO WORLD THIS IS A TEST STRING FOR SIMD OPTIMIZATION";
$results[] = benchmark("strtolower (SIMD)", 100000, function() use ($upper_string) {
    return strtolower($upper_string);
});

echo "\n--- Array Operations (Packed Array) ---\n";

// Test 11: Array creation and push
$results[] = benchmark("Array push", 50000, function() {
    $arr = [];
    for ($i = 0; $i < 10; $i++) {
        $arr[] = $i;
    }
    return $arr;
});

// Test 12: Array access (packed)
$packed_array = range(0, 99);
$results[] = benchmark("Array access (packed)", 500000, function() use ($packed_array) {
    $sum = 0;
    for ($i = 0; $i < 10; $i++) {
        $sum += $packed_array[$i];
    }
    return $sum;
});

// Test 13: Array count
$results[] = benchmark("count()", 500000, function() use ($packed_array) {
    return count($packed_array);
});

// Test 14: in_array search
$results[] = benchmark("in_array", 100000, function() use ($packed_array) {
    return in_array(50, $packed_array);
});

echo "\n--- Object Operations (Shape System) ---\n";

// Test 15: Object creation
class SimpleObject {
    public $x;
    public $y;
    public $z;
    
    public function __construct($x, $y, $z) {
        $this->x = $x;
        $this->y = $y;
        $this->z = $z;
    }
}

$results[] = benchmark("Object creation", 50000, function() {
    $obj = new SimpleObject(1, 2, 3);
    return $obj;
});

// Test 16: Property access (Shape IC)
$test_obj = new SimpleObject(10, 20, 30);
$results[] = benchmark("Property access", 500000, function() use ($test_obj) {
    $x = $test_obj->x;
    $y = $test_obj->y;
    $z = $test_obj->z;
    return $x + $y + $z;
});

// Test 17: Property modification
$results[] = benchmark("Property modify", 200000, function() use ($test_obj) {
    $test_obj->x = 100;
    $test_obj->y = 200;
    return $test_obj->x;
});

echo "\n--- Function Calls (CallFrame Pool) ---\n";

// Test 18: Simple function call
function simple_add($a, $b) {
    return $a + $b;
}

$results[] = benchmark("Function call", 500000, function() {
    return simple_add(1, 2);
});

// Test 19: Function with multiple args
function multi_args($a, $b, $c, $d, $e) {
    return $a + $b + $c + $d + $e;
}

$results[] = benchmark("Multi-arg function", 200000, function() {
    return multi_args(1, 2, 3, 4, 5);
});

// Test 20: Recursive function (Fibonacci)
function fib($n) {
    if ($n <= 1) return $n;
    return fib($n - 1) + fib($n - 2);
}

$results[] = benchmark("Fibonacci(15)", 5000, function() {
    return fib(15);
});

echo "\n--- Control Flow ---\n";

// Test 21: Loop with conditionals
$results[] = benchmark("Loop + conditionals", 50000, function() {
    $count = 0;
    for ($i = 0; $i < 100; $i++) {
        if ($i % 2 == 0) {
            $count++;
        } else {
            $count--;
        }
    }
    return $count;
});

// Test 22: While loop
$results[] = benchmark("While loop", 50000, function() {
    $i = 0;
    $sum = 0;
    while ($i < 100) {
        $sum += $i;
        $i++;
    }
    return $sum;
});

// Test 23: Switch statement
$results[] = benchmark("Switch statement", 200000, function() {
    $val = 3;
    switch ($val) {
        case 1: return 10;
        case 2: return 20;
        case 3: return 30;
        case 4: return 40;
        default: return 0;
    }
});

echo "\n--- Memory Patterns ---\n";

// Test 24: Temporary allocations
$results[] = benchmark("Temp allocations", 20000, function() {
    $arr = [];
    for ($i = 0; $i < 50; $i++) {
        $arr[] = "string_" . $i;
    }
    return count($arr);
});

// Test 25: Mixed operations
$results[] = benchmark("Mixed operations", 50000, function() {
    $arr = [1, 2, 3, 4, 5];
    $sum = 0;
    foreach ($arr as $val) {
        $sum += $val * 2;
    }
    $str = "result: " . $sum;
    return strlen($str);
});

echo "\n=== Benchmark Summary ===\n";

$total_time = 0;
$total_ops = 0;
foreach ($results as $r) {
    $total_time += $r['time_ms'];
    $total_ops += $r['ops_per_sec'];
}

printf("Total benchmark time: %.2f ms\n", $total_time);
printf("Average ops/sec: %.0f\n", $total_ops / count($results));
printf("Tests completed: %d\n", count($results));

echo "\n=== Benchmark Complete ===\n";
?>
