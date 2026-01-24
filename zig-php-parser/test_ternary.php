<?php
// 测试1: 标准三元运算符
$a = 10;
$b = 20;
$max = $a > $b ? $a : $b;
echo "Max: ";
echo $max;
echo "\n";

// 测试2: 嵌套三元运算符
$x = 5;
$result = $x > 10 ? "large" : ($x > 5 ? "medium" : "small");
echo "Result: ";
echo $result;
echo "\n";

// 测试3: 短路三元运算符（Elvis运算符）
$name = "";
$display = $name ?: "Anonymous";
echo "Display: ";
echo $display;
echo "\n";

// 测试4: 三元运算符在表达式中
$sum = ($a > $b ? $a : $b) + 10;
echo "Sum: ";
echo $sum;
echo "\n";

// 测试5: Elvis运算符与非空值
$username = "Alice";
$greeting = $username ?: "Guest";
echo "Greeting: ";
echo $greeting;
echo "\n";

// 测试6: 三元运算符与字符串
$age = 18;
$status = $age >= 18 ? "Adult" : "Minor";
echo "Status: ";
echo $status;
echo "\n";
