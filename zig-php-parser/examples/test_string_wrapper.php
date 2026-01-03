<?php

// 测试String包装类的链式方法调用

echo "=== 测试String包装类 ===\n";

// 注意：这些是扩展语法示例，展示预期的API设计
// 实际实现需要在VM中注册String类方法

// 字符串转大写
$str = "hello world";
echo "原始: $str\n";
// $upper = $str->toUpper();
// echo "大写: $upper\n";

// 字符串转小写
$mixed = "Hello WORLD";
// $lower = $mixed->toLower();
// echo "小写: $lower\n";

// 去除空白
$padded = "  hello world  ";
// $trimmed = $padded->trim();
// echo "去空白: '$trimmed'\n";

// 字符串替换
$text = "hello world";
// $replaced = $text->replace("world", "PHP");
// echo "替换: $replaced\n";

// 字符串分割
$csv = "apple,banana,orange";
// $parts = $csv->split(",");
// foreach ($parts as $part) {
//     echo "- $part\n";
// }

// 子字符串
$long = "hello world";
// $sub = $long->substring(0, 5);
// echo "子串: $sub\n";

// 查找位置
$haystack = "hello world hello";
// $pos = $haystack->indexOf("world");
// echo "位置: $pos\n";

// 链式调用示例
$input = "  HELLO WORLD  ";
// $result = $input->trim()->toLower()->replace("world", "php");
// echo "链式结果: $result\n";

// 检查包含
$text2 = "hello world";
// $contains = $text2->contains("world");
// echo "包含world: " . ($contains ? "是" : "否") . "\n";

// 开头结尾检查
// $starts = $text2->startsWith("hello");
// $ends = $text2->endsWith("world");
// echo "以hello开头: " . ($starts ? "是" : "否") . "\n";
// echo "以world结尾: " . ($ends ? "是" : "否") . "\n";

echo "\n=== String包装类测试完成 ===\n";
echo "注意: 带注释的代码需要在VM中实现String类方法支持\n";
