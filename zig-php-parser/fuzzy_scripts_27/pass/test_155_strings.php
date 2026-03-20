<?php
// Test 155: String positions and substr
$str = "Hello World";

echo "=== String positions ===\n";
echo "strpos('World'): " . strpos($str, 'World') . "\n";
echo "strrpos('l'): " . strrpos($str, 'l') . "\n";
echo "stripos('HELLO'): " . stripos($str, 'HELLO') . "\n";

echo "\n=== Substrings ===\n";
echo "substr(0, 5): " . substr($str, 0, 5) . "\n";
echo "substr(-5, 5): " . substr($str, -5, 5) . "\n";
echo "substr(6): " . substr($str, 6) . "\n";