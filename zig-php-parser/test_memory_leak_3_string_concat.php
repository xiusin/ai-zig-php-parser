<?php
// 测试用例3：字符串拼接
// 目的：验证字符串拼接不会泄漏

echo "Test 3: String concatenation\n";

$a = "Hello";
$b = "World";
$c = $a . " " . $b;
echo $c;
echo "\n";

echo "Test 3 completed\n";
