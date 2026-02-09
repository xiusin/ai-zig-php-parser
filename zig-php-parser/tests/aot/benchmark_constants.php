<?php

// 性能基准测试：类常量访问

class Config {
    public const ITERATIONS = 1000000;
    public const VALUE = 42;
    public const NAME = "benchmark";
}

$start = microtime(true);

for ($i = 0; $i < Config::ITERATIONS; $i++) {
    $x = Config::VALUE;
    $y = Config::NAME;
}

$end = microtime(true);
$elapsed = ($end - $start) * 1000; // 转换为毫秒

echo "Iterations: " . Config::ITERATIONS . "\n";
echo "Time: " . $elapsed . " ms\n";
echo "Avg per access: " . ($elapsed * 1000000 / Config::ITERATIONS / 2) . " ns\n";
