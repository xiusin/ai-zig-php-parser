<?php
// 测试变量赋值和类型转换
$a = 1;           // 初始赋值整数
echo "初始值: ";
echo $a;
echo "\n";

$a = "123";       // 重新赋值为字符串
echo "重新赋值后: ";
echo $a;
echo "\n";

$a = 45.67;       // 赋值为浮点数
echo "浮点数赋值: ";
echo $a;
echo "\n";

$a = true;        // 赋值为布尔值
echo "布尔值赋值: ";
echo $a ? "true" : "false";
echo "\n";

$a = [1, 2, 3];   // 赋值为数组
echo "数组长度: ";
echo count($a);
echo "\n";

// 测试多个变量的相互赋值
$x = 10;
$y = "hello";
$temp = $x;        // temp = 10
$x = $y;          // x = "hello"
$y = $temp;       // y = 10

echo "变量交换测试 - x: ";
echo $x;
echo ", y: ";
echo $y;
echo "\n";
