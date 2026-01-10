<?php
// 测试 preg_match with invalid regex
echo "Test 1: Invalid regex pattern\n";
$result = preg_match('/[unclosed/', 'hello');
echo "preg_match result: $result\n";
echo "preg_last_error: " . preg_last_error() . "\n";

echo "\nTest completed\n";

