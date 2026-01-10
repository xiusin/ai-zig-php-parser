<?php
// 测试 preg_last_error
echo "Test 1: Basic preg_last_error\n";
$result = preg_match('/test/', 'hello world');
echo "preg_match result: $result\n";
echo "preg_last_error: " . preg_last_error() . "\n";

// Test with invalid regex
echo "\nTest 2: Invalid regex\n";
$result2 = preg_match('/[unclosed/', 'hello');
echo "preg_match result (should be 0): $result2\n";
echo "preg_last_error (should be non-zero): " . preg_last_error() . "\n";

echo "\nAll tests completed\n";
