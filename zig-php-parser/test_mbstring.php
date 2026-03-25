<?php
echo "=== Testing mb_strlen ===\n";
echo "mb_strlen('Hello World'): " . mb_strlen('Hello World') . "\n";
echo "mb_strlen('你好世界'): " . mb_strlen('你好世界') . "\n";

echo "\n=== Testing mb_substr ===\n";
echo "mb_substr('Hello World', 0, 5): " . mb_substr('Hello World', 0, 5) . "\n";
echo "mb_substr('你好世界PHP', 0, 4): " . mb_substr('你好世界PHP', 0, 4) . "\n";

echo "\n=== Testing mb_strtoupper ===\n";
echo "mb_strtoupper('hello'): " . mb_strtoupper('hello') . "\n";

echo "\n=== Testing mb_strtolower ===\n";
echo "mb_strtolower('HELLO'): " . mb_strtolower('HELLO') . "\n";

echo "\n=== Testing substr_count ===\n";
echo "substr_count('Hello World World World', 'World'): " . substr_count('Hello World World World', 'World') . "\n";

echo "\n=== Testing ucfirst/lcfirst ===\n";
echo "ucfirst('hello'): " . ucfirst('hello') . "\n";
echo "lcfirst('HELLO'): " . lcfirst('HELLO') . "\n";

echo "\n=== Testing strrpos ===\n";
echo "strrpos('Hello World World', 'World'): " . strrpos('Hello World World', 'World') . "\n";

echo "\n=== Testing str_word_count ===\n";
echo "str_word_count('Hello World PHP'): " . str_word_count('Hello World PHP') . "\n";

echo "\n=== Testing strpos ===\n";
echo "strpos('Hello World', 'World'): " . strpos('Hello World', 'World') . "\n";

echo "\n=== Testing substr ===\n";
echo "substr('Hello World', 0, 5): " . substr('Hello World', 0, 5) . "\n";

echo "\nOK\n";
?>
