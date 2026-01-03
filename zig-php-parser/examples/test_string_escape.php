<?php

// 测试双引号字符串转义功能

echo "=== 测试字符串转义序列 ===\n";

// 测试换行符
$str1 = "第一行\n第二行\n第三行";
echo $str1;
echo "\n";

// 测试制表符
$str2 = "列1\t列2\t列3";
echo $str2;
echo "\n";

// 测试引号转义
$str3 = "他说:\"你好\"";
echo $str3;
echo "\n";

// 测试反斜杠
$str4 = "路径: C:\\Users\\test\\file.txt";
echo $str4;
echo "\n";

// 测试回车换行
$str5 = "Windows换行\r\nUnix换行\n";
echo $str5;

// 测试变量插值
$name = "张三";
$age = 25;
echo "姓名: $name, 年龄: $age\n";

// 测试复杂插值
$user = "李四";
echo "欢迎 ${user} 登录系统\n";

echo "\n=== 测试反引号多行字符串 ===\n";

// 反引号字符串（原始字符串，不转义）
$raw = `这是一个
多行字符串
包含\n和\t等字符
但不会被转义`;
echo $raw;
echo "\n";

// 对比双引号和反引号
$escaped = "包含\n转义";
$raw2 = `包含\n不转义`;
echo "双引号: " . $escaped . "\n";
echo "反引号: " . $raw2 . "\n";

echo "\n=== 测试完成 ===\n";
