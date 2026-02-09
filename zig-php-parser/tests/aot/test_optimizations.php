<?php

// 测试编译器优化

class Config {
    public const VALUE = 42;
    public const MAX = 4;
}

// 测试 1: 常量折叠
$x = Config::VALUE + 1;  // 应该折叠为 43
echo "Constant folding: " . $x . "\n";

// 测试 2: 死代码消除
$unused = Config::VALUE * 2;  // 未使用，应该被消除
$y = Config::VALUE + 2;
echo "Dead code elimination: " . $y . "\n";

// 测试 3: 循环展开（小常量边界）
$sum = 0;
for ($i = 0; $i < Config::MAX; $i++) {
    $sum += $i;
}
echo "Loop unrolling: " . $sum . "\n";

// 测试 4: 组合优化
$result = (Config::VALUE + 1) * 2;  // 应该折叠为 86
echo "Combined: " . $result . "\n";
