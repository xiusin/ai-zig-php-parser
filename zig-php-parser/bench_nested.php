<?php
$iterations = 1000;
$start = microtime(true);

for ($iter = 0; $iter < $iterations; $iter++) {
    $sum = 0;
    for ($i = 0; $i < 100; $i++) {
        for ($j = 0; $j < 100; $j++) {
            $sum += $i * $j;
        }
    }
}

$end = microtime(true);
$time = ($end - $start) * 1000;
echo "Nested loop benchmark: " . number_format($time, 2) . " ms\n";
echo "Result: $sum\n";
