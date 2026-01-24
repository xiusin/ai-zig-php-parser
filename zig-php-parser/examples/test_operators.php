<?php
// 测试所有运算符

echo "=== Test 1: 算术运算符 ===\n";

// 加法
$a = 10;
$b = 20;
echo "$a + $b = " . ($a + $b) . "\n";

// 减法
echo "$a - $b = " . ($a - $b) . "\n";

// 乘法
echo "$a * $b = " . ($a * $b) . "\n";

// 除法
echo "$a / $b = " . ($a / $b) . "\n";

// 取模
echo "$a % $b = " . ($a % $b) . "\n";

echo "\n=== Test 2: 比较运算符 ===\n";

$x = 5;
$y = 10;

echo "$x == $y: " . ($x == $y ? "true" : "false") . "\n";
echo "$x != $y: " . ($x != $y ? "true" : "false") . "\n";
echo "$x < $y: " . ($x < $y ? "true" : "false") . "\n";
echo "$x <= $y: " . ($x <= $y ? "true" : "false") . "\n";
echo "$x > $y: " . ($x > $y ? "true" : "false") . "\n";
echo "$x >= $y: " . ($x >= $y ? "true" : "false") . "\n";

echo "\n=== Test 3: 逻辑运算符 ===\n";

$true_val = true;
$false_val = false;

echo "true && false: " . ($true_val && $false_val ? "true" : "false") . "\n";
echo "true || false: " . ($true_val || $false_val ? "true" : "false") . "\n";
echo "!true: " . (!$true_val ? "true" : "false") . "\n";
echo "!false: " . (!$false_val ? "true" : "false") . "\n";

echo "\n=== Test 4: 字符串运算 ===\n";

$str1 = "Hello";
$str2 = "World";
echo "$str1 . $str2 = " . ($str1 . " " . $str2) . "\n";

echo "\n=== Test 5: 类型转换 ===\n";

$int_val = 42;
$float_val = 3.14;
$bool_val = true;
$null_val = null;

echo "int to float: " . ($int_val + 0.0) . "\n";
echo "float to int: " . intval($float_val) . "\n";
echo "bool to int: " . intval($bool_val) . "\n";
echo "null to int: " . intval($null_val) . "\n";

echo "\n=== Test 6: 混合运算 ===\n";

// 整数和浮点数混合
echo "10 + 3.14 = " . (10 + 3.14) . "\n";
echo "10 * 2.5 = " . (10 * 2.5) . "\n";

// 字符串和数字混合
$num_str = "123";
echo "\"123\" + 456 = " . ($num_str + 456) . "\n";

echo "\n=== All operator tests completed ===\n";
