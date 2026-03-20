<?php
// Test 084: String functions
echo "=== Length functions ===\n";
echo "strlen('hello'): " . strlen('hello') . "\n";
echo "mb_strlen('中文'): " . mb_strlen('中文') . "\n";

echo "\n=== Search ===\n";
$str = "Hello World";
echo "strpos('World'): " . strpos($str, 'World') . "\n";
echo "stripos('HELLO'): " . stripos($str, 'HELLO') . "\n";
echo "strstr('World'): " . strstr($str, 'World') . "\n";
echo "strrpos('l'): " . strrpos($str, 'l') . "\n";

echo "\n=== Modify ===\n";
echo "substr(0, 5): " . substr($str, 0, 5) . "\n";
echo "str_replace('World', 'PHP', \$str): " . str_replace('World', 'PHP', $str) . "\n";
echo "strtolower: " . strtolower('HELLO') . "\n";
echo "strtoupper: " . strtoupper('hello') . "\n";
echo "ucfirst: " . ucfirst('hello world') . "\n";
echo "ucwords: " . ucwords('hello world') . "\n";

echo "\n=== Split/Join ===\n";
echo "explode(' ', 'a b c'): " . json_encode(explode(' ', 'a b c')) . "\n";
echo "implode('-', [1,2,3]): " . implode('-', [1, 2, 3]) . "\n";
echo "str_split('abc', 2): " . json_encode(str_split('abc', 2)) . "\n";

echo "\n=== Trim ===\n";
echo "trim('  hello  '): '" . trim("  hello  ") . "'\n";
echo "ltrim/rtrim: '" . ltrim("  test") . "' / '" . rtrim("test  ") . "'\n";