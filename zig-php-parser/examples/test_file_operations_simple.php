<?php
// 简化的文件操作测试

echo "=== 简化文件操作测试 ===\n\n";

// 1. 基础文件操作
echo "1. 基础文件操作\n";
$test_file = "/tmp/zigphp_simple_test.txt";
file_put_contents($test_file, "Hello, zig-php!\n");
$content = file_get_contents($test_file);
echo "内容: {$content}";
echo "文件存在: " . (file_exists($test_file) ? "true" : "false") . "\n";
echo "文件大小: " . filesize($test_file) . " 字节\n";
unlink($test_file);
echo "文件已删除\n\n";

// 2. 目录操作
echo "2. 目录操作\n";
$test_dir = "/tmp/zigphp_simple_dir";
mkdir($test_dir);
echo "目录创建成功\n";
echo "是目录: " . (is_dir($test_dir) ? "true" : "false") . "\n";
rmdir($test_dir);
echo "目录已删除\n\n";

echo "=== 测试完成 ===\n";
?>