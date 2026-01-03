<?php
// 测试 fn 关键字定义函数

fn add($a, $b) {
    return $a + $b;
}

fn greet($name) {
    echo "Hello, $name!\n";
}

// 使用传统 function 关键字
function multiply($a, $b) {
    return $a * $b;
}

// 测试
$sum = add(3, 5);
echo "add(3, 5) = $sum\n";

greet("World");

$product = multiply(4, 6);
echo "multiply(4, 6) = $product\n";

echo "fn 关键字测试通过!\n";
