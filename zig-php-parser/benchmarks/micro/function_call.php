<?php
// 函数调用基准测试
function add(int $a, int $b): int {
    return $a + $b;
}

function multiply(int $a, int $b): int {
    return $a * $b;
}

$iterations = 10000;
$start = microtime(true);
for ($i = 0; $i < $iterations; $i++) {
    $result = add(multiply($i, 2), 1);
}
$end = microtime(true);

$time_ms = ($end - $start) * 1000;

echo "Function Call Benchmark\n";
echo "Iterations: " . $iterations . "\n";
echo "Time: " . $time_ms . " ms\n";

