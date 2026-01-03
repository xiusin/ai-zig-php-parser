<?php

// 测试String方法调用（实际可运行）

echo "=== 测试String方法调用 ===\n";

// 基础字符串操作
$str = "hello world";
echo "原始字符串: $str\n";

// 转大写
$upper = $str->toUpper();
echo "大写: $upper\n";

// 转小写
$mixed = "Hello WORLD";
$lower = $mixed->toLower();
echo "小写: $lower\n";

// 去除空白
$padded = "  hello world  ";
$trimmed = $padded->trim();
echo "去空白: '$trimmed'\n";

// 字符串替换
$text = "hello world";
$replaced = $text->replace("world", "PHP");
echo "替换: $replaced\n";

// 字符串长度
$len = $str->length();
echo "长度: $len\n";

// 子字符串
$long = "hello world";
$sub = $long->substring(0, 5);
echo "子串: $sub\n";

// 查找位置
$haystack = "hello world hello";
$pos = $haystack->indexOf("world");
echo "位置: $pos\n";

// 分割字符串
$csv = "apple,banana,orange";
$parts = $csv->split(",");
echo "分割结果:\n";
print_r($parts);

echo "\n=== String方法测试完成 ===\n";
