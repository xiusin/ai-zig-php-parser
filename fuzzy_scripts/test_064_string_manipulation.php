<?php
// 字符串操作高级测试

// 多字节字符串处理
echo "=== Multibyte String ===\n";
$mbStr = "Hello 你好世界 🌍";
echo "strlen: " . strlen($mbStr) . "\n";
echo "mb_strlen: " . mb_strlen($mbStr) . "\n";
echo "mb_substr: " . mb_substr($mbStr, 6, 3) . "\n";

// 字符串编码转换
echo "\n=== Encoding ===\n";
$utf8 = "Hello World";
echo "mb_detect_encoding: " . mb_detect_encoding($utf8) . "\n";

// 大小写转换
echo "\n=== Case Conversion ===\n";
$mixed = "HeLLo WoRLd";
echo "strtolower: " . strtolower($mixed) . "\n";
echo "strtoupper: " . strtoupper($mixed) . "\n";
echo "ucfirst: " . ucfirst($mixed) . "\n";
echo "lcfirst: " . lcfirst($mixed) . "\n";
echo "ucwords: " . ucwords(strtolower($mixed)) . "\n";
echo "mb_strtolower: " . mb_strtolower('ß') . "\n";
echo "mb_strtoupper: " . mb_strtoupper('ß') . "\n";

// 字符串查找
echo "\n=== String Search ===\n";
$search = "The quick brown fox jumps over the lazy dog";
echo "strpos 'fox': " . strpos($search, 'fox') . "\n";
echo "strrpos 'o': " . strrpos($search, 'o') . "\n";
echo "stripos 'FOX': " . stripos($search, 'FOX') . "\n";
echo "strripos 'O': " . strripos($search, 'O') . "\n";

// 字符串提取
echo "\n=== String Extract ===\n";
echo "substr(4, 5): " . substr($search, 4, 5) . "\n";
echo "substr(-8): " . substr($search, -8) . "\n";
echo "strstr 'fox': " . strstr($search, 'fox') . "\n";
echo "stristr 'FOX': " . stristr($search, 'FOX') . "\n";
echo "strrchr ' ': " . strrchr($search, ' ') . "\n";

// 字符串替换
echo "\n=== String Replace ===\n";
echo "str_replace: " . str_replace('fox', 'cat', $search) . "\n";
echo "str_ireplace: " . str_ireplace('FOX', 'cat', $search) . "\n";
echo "substr_replace: " . substr_replace($search, 'SLOW', 4, 5) . "\n";

$replaced = str_replace(['quick', 'brown', 'fox'], ['slow', 'white', 'dog'], $search);
echo "multi replace: $replaced\n";

// 字符串分割
echo "\n=== String Split ===\n";
echo "explode: " . implode('|', explode(' ', $search)) . "\n";
echo "str_split(5): " . implode('|', str_split('hello world', 5)) . "\n";
echo "chunk_split: " . chunk_split('hello', 2, '-') . "\n";

// 字符串填充
echo "\n=== String Padding ===\n";
echo "str_pad LEFT: " . str_pad('5', 5, '0', STR_PAD_LEFT) . "\n";
echo "str_pad RIGHT: " . str_pad('5', 5, '0', STR_PAD_RIGHT) . "\n";
echo "str_pad BOTH: " . str_pad('5', 5, '_', STR_PAD_BOTH) . "\n";

// 字符串修剪
echo "\n=== String Trim ===\n";
echo "trim: '" . trim('  hello  ') . "'\n";
echo "ltrim: '" . ltrim('  hello  ') . "'\n";
echo "rtrim: '" . rtrim('  hello  ') . "'\n";
echo "trim chars: '" . trim('xxxhelloxxx', 'x') . "'\n";

// 字符串格式化
echo "\n=== String Format ===\n";
echo "sprintf: " . sprintf("%s has %d items", "Array", 5) . "\n";
echo "printf: ";
printf("Value: %.2f\n", 3.14159);
echo "number_format: " . number_format(1234567.8912, 2, ',', '.') . "\n";

// 字符串比较
echo "\n=== String Compare ===\n";
echo "strcmp: " . strcmp('a', 'b') . "\n";
echo "strcasecmp: " . strcasecmp('A', 'a') . "\n";
echo "strnatcmp: " . strnatcmp('img1.png', 'img10.png') . "\n";
echo "strncasecmp: " . strncasecmp('Hello', 'HELLO world', 5) . "\n";

// 字符串反转和重复
echo "\n=== String Misc ===\n";
echo "strrev: " . strrev('hello') . "\n";
echo "str_repeat: " . str_repeat('ab', 3) . "\n";
echo "str_shuffle length: " . strlen(str_shuffle('hello world')) . "\n";

// 字符串统计
echo "\n=== String Stats ===\n";
echo "strlen: " . strlen('hello') . "\n";
echo "str_word_count: " . str_word_count($search) . "\n";
echo "substr_count 'o': " . substr_count($search, 'o') . "\n";

echo "\nString manipulation tests completed\n";
