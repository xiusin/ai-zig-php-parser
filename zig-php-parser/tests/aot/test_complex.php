<?php

// 复杂PHP脚本 - 测试各种优化场景

class Math {
    public const PI = 3.14159;
    
    public static function square($x) {
        return $x * $x;
    }
}

// 测试 1: 函数内联 + 常量折叠
$r = 5;
$area = Math::PI * Math::square($r);
echo "Circle area: " . $area . "\n";

// 测试 2: 循环优化
$arr = [1, 2, 3, 4, 5];
$sum = 0;
$len = 5;
for ($i = 0; $i < $len; $i++) {
    $sum += $arr[$i];
}
echo "Sum: " . $sum . "\n";

// 测试 3: 条件分支优化
$x = 5;
if ($x < 0) {
    echo "negative\n";
} elseif ($x == 0) {
    echo "zero\n";
} else {
    echo "positive\n";
}

