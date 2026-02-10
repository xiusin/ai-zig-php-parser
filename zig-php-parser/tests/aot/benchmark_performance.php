<?php

// 性能基准测试

echo "=== AOT Performance Benchmark ===\n\n";

// Test 1: Simple loop
$start = microtime(true);
$sum = 0;
for ($i = 0; $i < 100000; $i++) {
    $sum += 1;
}
$time1 = (microtime(true) - $start) * 1000;
echo "1. Simple loop (100K): {$time1}ms, sum=$sum\n";

// Test 2: Nested loop
$start = microtime(true);
$sum = 0;
for ($i = 0; $i < 100; $i++) {
    for ($j = 0; $j < 100; $j++) {
        $sum += 1;
    }
}
$time2 = (microtime(true) - $start) * 1000;
echo "2. Nested loop (100x100): {$time2}ms, sum=$sum\n";

// Test 3: Arithmetic
$start = microtime(true);
$result = 0;
for ($i = 0; $i < 10000; $i++) {
    $result = $i * 2 + 3 - 1;
}
$time3 = (microtime(true) - $start) * 1000;
echo "3. Arithmetic (10K): {$time3}ms, result=$result\n";

// Test 4: Array operations
$start = microtime(true);
$arr = [1, 2, 3, 4, 5];
$sum = 0;
for ($i = 0; $i < 10000; $i++) {
    $sum = array_sum($arr);
}
$time4 = (microtime(true) - $start) * 1000;
echo "4. Array sum (10K): {$time4}ms, sum=$sum\n";

// Test 5: String operations
$start = microtime(true);
$str = "";
for ($i = 0; $i < 1000; $i++) {
    $str = "Hello" . " " . "World";
}
$time5 = (microtime(true) - $start) * 1000;
echo "5. String concat (1K): {$time5}ms, len=" . strlen($str) . "\n";

$total = $time1 + $time2 + $time3 + $time4 + $time5;
echo "\nTotal time: {$total}ms\n";
