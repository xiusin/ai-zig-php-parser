<?php

echo "=== String方法测试 ===\n\n";

// 测试1: toUpper
echo "1. toUpper测试:\n";
$str1 = "hello world";
echo "原始: $str1\n";
$upper = strtoupper($str1);
echo "大写: $upper\n\n";

// 测试2: toLower
echo "2. toLower测试:\n";
$str2 = "HELLO WORLD";
echo "原始: $str2\n";
$lower = strtolower($str2);
echo "小写: $lower\n\n";

// 测试3: trim
echo "3. trim测试:\n";
$str3 = "  hello world  ";
echo "原始: '$str3'\n";
$trimmed = trim($str3);
echo "去空白: '$trimmed'\n\n";

// 测试4: length
echo "4. length测试:\n";
$str4 = "hello";
echo "字符串: $str4\n";
$len = strlen($str4);
echo "长度: $len\n\n";

// 测试5: replace
echo "5. replace测试:\n";
$str5 = "hello world";
echo "原始: $str5\n";
$replaced = str_replace("world", "PHP", $str5);
echo "替换后: $replaced\n\n";

// 测试6: substring
echo "6. substring测试:\n";
$str6 = "hello world";
echo "原始: $str6\n";
$sub = substr($str6, 0, 5);
echo "子串(0,5): $sub\n\n";

// 测试7: indexOf
echo "7. indexOf测试:\n";
$str7 = "hello world";
echo "字符串: $str7\n";
$pos = strpos($str7, "world");
echo "world的位置: $pos\n\n";

// 测试8: split
echo "8. split测试:\n";
$str8 = "apple,banana,orange";
echo "原始: $str8\n";
$parts = explode(",", $str8);
echo "分割结果: ";
print_r($parts);
echo "\n";

echo "=== String方法测试完成 ===\n";

?>
