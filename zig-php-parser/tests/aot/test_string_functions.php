<?php
// 测试：字符串内置函数
$text = "Hello World";

echo "Original: '$text'\n";
echo "Length: " . strlen($text) . "\n";
echo "Upper: " . strtoupper($text) . "\n";
echo "Lower: " . strtolower($text) . "\n";

// substr
$sub = substr($text, 0, 5);
echo "substr(0, 5): '$sub'\n";

// strpos
$pos = strpos($text, "World");
echo "strpos('World'): $pos\n";

// str_replace
$replaced = str_replace("World", "PHP", $text);
echo "str_replace: '$replaced'\n";

// trim
$padded = "  spaces  ";
$trimmed = trim($padded);
echo "trim('$padded'): '$trimmed'\n";

// explode/implode
$words = explode(" ", $text);
echo "explode: count=" . count($words) . "\n";
$joined = implode("-", $words);
echo "implode('-'): '$joined'\n";

// str_repeat
$repeated = str_repeat("*", 5);
echo "str_repeat('*', 5): '$repeated'\n";

// strcmp
$cmp = strcmp("abc", "abc");
echo "strcmp('abc', 'abc'): $cmp\n";
