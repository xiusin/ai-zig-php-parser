<?php
// 测试 preg_match with valid regex first
echo "Test 1: Valid regex\n";
$result = preg_match('/test/', 'hello world');
echo "preg_match result: $result\n";
echo "preg_last_error: " . preg_last_error() . "\n";

echo "\nTests completed\n";

