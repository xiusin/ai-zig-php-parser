<?php
// 字符串高级操作测试

// 多字节字符串
$mb = "你好世界Hello";
echo "strlen: " . strlen($mb) . "\n";
echo "mb_strlen: " . mb_strlen($mb) . "\n";
echo "mb_substr: " . mb_substr($mb, 0, 2) . "\n";

// 字符串编码
$utf8 = "Hello 世界";
echo "mb_detect_encoding: " . mb_detect_encoding($utf8) . "\n";

// 字符串转换
$lower = "HELLO WORLD";
echo "mb_strtolower: " . mb_strtolower($lower) . "\n";
echo "mb_strtoupper: " . mb_strtoupper("hello world") . "\n";

// 字符串查找高级
$text = "The quick brown fox jumps over the lazy dog";
echo "strpos: " . strpos($text, "fox") . "\n";
echo "strrpos: " . strrpos($text, "o") . "\n";
echo "stripos: " . stripos($text, "FOX") . "\n";
echo "strripos: " . strripos($text, "O") . "\n";

// 字符串提取
echo "strstr: " . strstr($text, "fox") . "\n";
echo "stristr: " . stristr($text, "FOX") . "\n";
echo "strrchr: " . strrchr($text, " ") . "\n";

// 字符串替换高级
echo "str_replace count: ";
$count = 0;
str_replace("o", "0", $text, $count);
echo "$count replacements\n";

echo "substr_count: " . substr_count($text, "o") . "\n";
echo "substr_replace: " . substr_replace($text, "SLOW", 4, 5) . "\n";

// 正则替换
echo "preg_replace: " . preg_replace('/\s+/', '-', "hello   world") . "\n";
echo "preg_replace callback: " . preg_replace_callback('/\d+/', fn($m) => $m[0] * 2, "1, 2, 3") . "\n";

// 字符串分割高级
echo "preg_split: " . implode('|', preg_split('/\s+/', "a  b   c")) . "\n";
echo "str_split: " . implode('|', str_split("hello", 2)) . "\n";

// 正则匹配
$matched = preg_match('/(\w+)\s+(\w+)/', "hello world", $matches);
echo "preg_match: " . implode(', ', $matches) . "\n";

$allMatches = [];
preg_match_all('/\d+/', "a1b23c456", $allMatches);
echo "preg_match_all: " . implode(', ', $allMatches[0]) . "\n";

// 字符串比较高级
echo "strcasecmp: " . strcasecmp("Hello", "hello") . "\n";
echo "strncasecmp: " . strncasecmp("Hello World", "HELLO world", 5) . "\n";
echo "strnatcmp: " . strnatcmp("img1.png", "img10.png") . "\n";

// 字符串填充
echo "str_pad left: " . str_pad("5", 3, "0", STR_PAD_LEFT) . "\n";
echo "str_pad right: " . str_pad("5", 3, "0", STR_PAD_RIGHT) . "\n";
echo "str_pad both: " . str_pad("5", 5, "_", STR_PAD_BOTH) . "\n";

// 字符串修剪高级
echo "trim chars: '" . trim("***hello***", "*") . "'\n";
echo "ltrim chars: '" . ltrim("***hello***", "*") . "'\n";
echo "rtrim chars: '" . rtrim("***hello***", "*") . "'\n";

// 字符串反转
echo "strrev: " . strrev("hello") . "\n";

// 字符串重复
echo "str_repeat: " . str_repeat("ab", 5) . "\n";

// 字符串长度格式化
echo "sprintf width: " . sprintf("%10s", "hi") . "\n";
echo "sprintf precision: " . sprintf("%.2f", 3.14159) . "\n";
echo "sprintf multiple: " . sprintf("%s has %d items (%.1f%%)", "Array", 5, 33.333) . "\n";

// 词数统计
echo "str_word_count: " . str_word_count($text) . "\n";

// 字符串加密
echo "md5: " . md5("hello") . "\n";
echo "sha1: " . sha1("hello") . "\n";
echo "crc32: " . crc32("hello") . "\n";

// Base64编码
$encoded = base64_encode("Hello World");
echo "base64_encode: $encoded\n";
echo "base64_decode: " . base64_decode($encoded) . "\n";

// 字符串转数组
echo "count_chars: " . implode(', ', array_filter(count_chars("hello", 1))) . "\n";
