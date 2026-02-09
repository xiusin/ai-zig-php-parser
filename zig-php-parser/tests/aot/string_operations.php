<?php
// 测试字符串操作

// 1. 字符串插值
$name = "World";
$count = 42;
echo "Hello, $name! Count: $count\n";
echo "Expression: {$count * 2}\n";

// 2. 字符串连接
$str1 = "Hello";
$str2 = "World";
$result = $str1 . " " . $str2;
echo "$result\n";

// 3. 字符串函数
$text = "  PHP is awesome!  ";
echo "Original: '$text'\n";
echo "Trimmed: '" . trim($text) . "'\n";
echo "Upper: " . strtoupper($text) . "\n";
echo "Lower: " . strtolower($text) . "\n";
echo "Length: " . strlen(trim($text)) . "\n";

// 4. 子字符串
$sentence = "The quick brown fox";
echo "Substr(4, 5): " . substr($sentence, 4, 5) . "\n";
echo "Substr(10): " . substr($sentence, 10) . "\n";
echo "Substr(-3): " . substr($sentence, -3) . "\n";

// 5. 字符串查找
$haystack = "Hello World Hello PHP";
echo "Position of 'World': " . strpos($haystack, "World") . "\n";
echo "Last position of 'Hello': " . strrpos($haystack, "Hello") . "\n";
echo "Contains 'PHP': " . (str_contains($haystack, "PHP") ? "yes" : "no") . "\n";

// 6. 字符串替换
$template = "Hello {name}, you have {count} messages";
$output = str_replace(["{name}", "{count}"], ["Alice", "5"], $template);
echo "$output\n";

// 7. 字符串分割和连接
$csv = "apple,banana,orange,grape";
$fruits = explode(",", $csv);
echo "Fruits: " . implode(" | ", $fruits) . "\n";

// 8. 字符串格式化
$price = 1234.56;
$formatted = sprintf("Price: $%.2f", $price);
echo "$formatted\n";

// 9. 多行字符串
$multiline = <<<EOT
This is a
multi-line
string with $name
EOT;
echo "$multiline\n";

// 10. 字符串比较
$str_a = "apple";
$str_b = "banana";
echo "Compare 'apple' vs 'banana': " . strcmp($str_a, $str_b) . "\n";
echo "Case-insensitive compare: " . strcasecmp("HELLO", "hello") . "\n";

// 11. 字符串填充
$num = "42";
echo "Padded: '" . str_pad($num, 5, "0", STR_PAD_LEFT) . "'\n";

// 12. 字符串重复
echo "Repeat: " . str_repeat("*", 10) . "\n";

// 13. 字符串反转
echo "Reversed: " . strrev("Hello") . "\n";

// 14. 字符串编码
$encoded = base64_encode("Hello World");
$decoded = base64_decode($encoded);
echo "Encoded: $encoded\n";
echo "Decoded: $decoded\n";

// 15. 正则表达式
$email = "test@example.com";
if (preg_match('/^[\w\.-]+@[\w\.-]+\.\w+$/', $email)) {
    echo "Valid email: $email\n";
}

$text = "Price: $100, Discount: $20";
preg_match_all('/\$(\d+)/', $text, $matches);
echo "Found prices: " . implode(", ", $matches[1]) . "\n";
