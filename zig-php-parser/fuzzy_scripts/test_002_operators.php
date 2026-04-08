<?php
// 算术运算符测试
$a = 10;
$b = 3;

echo "加法: " . ($a + $b) . "\n";
echo "减法: " . ($a - $b) . "\n";
echo "乘法: " . ($a * $b) . "\n";
echo "除法: " . ($a / $b) . "\n";
echo "取模: " . ($a % $b) . "\n";
echo "幂运算: " . ($a ** $b) . "\n";

// 比较运算符
echo "相等: " . var_export($a == $b, true) . "\n";
echo "全等: " . var_export($a === $b, true) . "\n";
echo "不等: " . var_export($a != $b, true) . "\n";
echo "不全等: " . var_export($a !== $b, true) . "\n";
echo "大于: " . var_export($a > $b, true) . "\n";
echo "小于: " . var_export($a < $b, true) . "\n";
echo "大于等于: " . var_export($a >= $b, true) . "\n";
echo "小于等于: " . var_export($a <= $b, true) . "\n";
echo "太空船: " . ($a <=> $b) . "\n";

// 逻辑运算符
$x = true;
$y = false;
echo "AND: " . var_export($x && $y, true) . "\n";
echo "OR: " . var_export($x || $y, true) . "\n";
echo "NOT: " . var_export(!$x, true) . "\n";
echo "XOR: " . var_export($x xor $y, true) . "\n";

// 位运算符
echo "按位与: " . (0xFF & 0x0F) . "\n";
echo "按位或: " . (0xF0 | 0x0F) . "\n";
echo "按位异或: " . (0xAA ^ 0x55) . "\n";
echo "按位非: " . (~0) . "\n";
echo "左移: " . (1 << 4) . "\n";
echo "右移: " . (16 >> 2) . "\n";

// 赋值运算符
$c = 100;
$c += 50;
echo "+=: " . $c . "\n";
$c -= 25;
echo "-=: " . $c . "\n";
$c *= 2;
echo "*=: " . $c . "\n";
$c /= 5;
echo "/=: " . $c . "\n";
$c %= 7;
echo "%=: " . $c . "\n";
$c **= 3;
echo "**=: " . $c . "\n";

// 字符串运算符
$s1 = "Hello";
$s2 = "World";
echo "字符串拼接: " . ($s1 . " " . $s2) . "\n";
$s1 .= " PHP";
echo ".=: " . $s1 . "\n";

// 数组运算符
$arr1 = ['a' => 1, 'b' => 2];
$arr2 = ['b' => 3, 'c' => 4];
echo "数组联合: " . var_export($arr1 + $arr2, true) . "\n";
echo "数组相等: " . var_export($arr1 == $arr2, true) . "\n";
echo "数组全等: " . var_export($arr1 === $arr2, true) . "\n";
