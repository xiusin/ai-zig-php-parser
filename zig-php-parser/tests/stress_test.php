<?php
// Stress test for Zig-PHP interpreter
// Tests: loops, recursion, array operations, string operations, OOP

echo "=== Stress Test Start ===\n";

// Test 1: Loop performance
$start = microtime(true);
$sum = 0;
for ($i = 0; $i < 10000; $i++) {
    $sum += $i;
}
echo "Loop sum (10000 iterations): $sum\n";

// Test 2: Array operations
$arr = [];
for ($i = 0; $i < 1000; $i++) {
    $arr[] = $i * 2;
}
echo "Array size: " . count($arr) . "\n";

// Test 3: String operations
$str = "";
for ($i = 0; $i < 100; $i++) {
    $str .= "x";
}
echo "String length: " . strlen($str) . "\n";

// Test 4: Recursive function
function fib($n) {
    if ($n <= 1) return $n;
    return fib($n - 1) + fib($n - 2);
}
echo "Fibonacci(20): " . fib(20) . "\n";

// Test 5: OOP
class Counter {
    private $count = 0;
    
    public function increment() {
        $this->count++;
    }
    
    public function getCount() {
        return $this->count;
    }
}

$counter = new Counter();
for ($i = 0; $i < 1000; $i++) {
    $counter->increment();
}
echo "Counter value: " . $counter->getCount() . "\n";

// Test 6: Nested loops
$matrix_sum = 0;
for ($i = 0; $i < 100; $i++) {
    for ($j = 0; $j < 100; $j++) {
        $matrix_sum += $i * $j;
    }
}
echo "Matrix sum (100x100): $matrix_sum\n";

echo "=== Stress Test Complete ===\n";
?>
