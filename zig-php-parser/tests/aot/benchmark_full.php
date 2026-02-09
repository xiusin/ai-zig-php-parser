<?php

// 性能基准测试 - 对比优化效果

class Benchmark {
    public const ITERATIONS = 100000;
    
    public static function run($name, $fn) {
        $start = microtime(true);
        for ($i = 0; $i < self::ITERATIONS; $i++) {
            $fn();
        }
        $end = microtime(true);
        $elapsed = ($end - $start) * 1000;
        $avg = $elapsed * 1000 / self::ITERATIONS;
        echo "$name: {$elapsed}ms total, {$avg}ns avg\n";
    }
}

class Math {
    public const PI = 3.14159;
    
    public static function square($x) {
        return $x * $x;
    }
}

// 基准 1: 常量访问
Benchmark::run("Constant access", function() {
    $x = Math::PI;
});

// 基准 2: 常量折叠
Benchmark::run("Constant folding", function() {
    $x = Math::PI * 2;
});

// 基准 3: 函数调用
Benchmark::run("Function call", function() {
    $x = Math::square(5);
});

// 基准 4: 循环
Benchmark::run("Loop", function() {
    $sum = 0;
    for ($i = 0; $i < 10; $i++) {
        $sum += $i;
    }
});
