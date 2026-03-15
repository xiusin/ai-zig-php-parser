<?php
// 测试6: 字符串函数复杂混搭
$str = "  Hello, World! Welcome to PHP Testing 123  ";

// 字符串处理链
$lower = strtolower(trim($str));
$upper = strtoupper($str);
$replaced = str_replace(['Hello', 'World'], ['Hi', 'Universe'], $str);
$reversed = strrev($str);

// 查找与分割
$pos = strpos($str, 'World');
$lastPos = strrpos($str, ' ');
$parts = explode(' ', trim($str));
$joined = implode('-', $parts);

// 子串操作
$sub = substr($str, 7, 5);
$subReplace = substr_replace($str, 'Universe', 7, 5);

// 正则表达式
preg_match('/Testing (\d+)/', $str, $matches);
preg_match_all('/[A-Z][a-z]+/', $str, $words);
$regexReplaced = preg_replace('/\d+/', 'NUM', $str);
$split = preg_split('/\s+/', trim($str));

// 编码与哈希
$md5 = md5($str);
$sha1 = sha1($str);
$base64 = base64_encode($str);
$decoded = base64_decode($base64);

// 格式化
$formatted = sprintf("Position: %d, Length: %d", $pos, strlen($str));
$parsed = sscanf("10 20 30", "%d %d %d");

echo $lower . "\n";
echo $replaced . "\n";
print_r($matches);
print_r($parts);
echo $formatted . "\n";
?>