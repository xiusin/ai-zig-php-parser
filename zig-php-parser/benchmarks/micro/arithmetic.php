<?php
// 算术运算基准测试
function benchmark(): int {
    $result = 0;
    for ($i = 0; $i < 1000; $i++) {
        $a = $i * 2;
        $b = $i + 10;
        $c = $a - $b;
        $d = $c * 3;
        $result += $d;
    }
    return $result;
}

$iterations = 100;
$start = microtime(true);

for ($i = 0; $i < $iterations; $i++) {
    $result = benchmark();
}

$end = microtime(true);
$time_ms = ($end - $start) * 1000;

echo "Arithmetic Benchmark\n";
echo "Iterations: " . $iterations . "\n";
echo "Time: " . $time_ms . " ms\n";


