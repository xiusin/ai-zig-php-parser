<?php
// 简单测试 .= 操作符
echo "=== 简单测试 .= 操作符 ===\n\n";

// 测试1：基本字符串连接
$a = "Hello";
$a .= " World";
echo "测试1: $a\n";
echo "\n";

// 测试2：数字转换为字符串
$b = 123;
$b .= "456";
echo "测试2: $b\n";
echo "\n";

// 测试3：布尔值转换为字符串
$c = true;
$c .= " value";
echo "测试3: $c\n";
echo "\n";

// 测试4：null 转换为字符串
$d = null;
$d .= " is null";
echo "测试4: $d\n";
echo "\n";

// 测试5：连续 .= 操作
$e = "Start";
$e .= " Middle";
$e .= " End";
echo "测试5: $e\n";
echo "\n";

echo "=== 所有测试完成 ===\n";
