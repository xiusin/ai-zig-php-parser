<?php

// 最简单的性能测试 - 验证快速路径

class Config {
    public const A = 42;
    public const B = 2;
}

// 纯常量折叠 - 应该编译为单个值
$x = Config::A + Config::B;
echo "Result: $x\n";

// 纯整数操作
$a = 10;
$b = 20;
$c = $a + $b;
echo "Sum: $c\n";

// 纯整数乘法
$d = 5 * 6;
echo "Product: $d\n";
