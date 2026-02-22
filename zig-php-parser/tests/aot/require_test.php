<?php
// 测试 require 功能

echo "=== Require Test ===\n\n";

require_once __DIR__ . '/lib/Math.php';
require_once __DIR__ . '/lib/StringHelper.php';

echo "1. Math Test:\n";
$sum = Math::add(10, 20);
$product = Math::multiply(5, 6);
echo "   10 + 20 = $sum\n";
echo "   5 * 6 = $product\n\n";

echo "2. StringHelper Test:\n";
$text = "Hello";
$reversed = StringHelper::reverse($text);
$upper = StringHelper::uppercase($text);
echo "   Original: $text\n";
echo "   Reversed: $reversed\n";
echo "   Uppercase: $upper\n\n";

echo "=== Require Test Passed ===\n";
