<?php
// 测试字符串插值功能

$name = "张三";
$age = 25;

echo "=== 测试双引号字符串变量插值 ===\n";

// 1. 基本变量插值
echo "姓名: $name\n";
echo "年龄: $age\n";

// 2. 转义的美元符号
echo "转义测试: \$name 应该输出 $name\n";
echo "价格: \$100\n";

// 3. 混合使用
echo "用户 $name 的年龄是 $age 岁\n";

echo "\n=== 测试反引号多行字符串 ===\n";

// 4. 反引号多行字符串（不进行变量插值）
$multiline = `这是一个
多行字符串
可以包含 $name 和 $age
但不会被解析`;

echo $multiline;
echo "\n";

// 5. 反引号字符串不转义
$raw = `原始字符串: \n \t $var`;
echo $raw;
echo "\n";

echo "\n=== 测试完成 ===\n";
