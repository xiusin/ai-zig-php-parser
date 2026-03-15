<?php
// 测试15: 文件操作函数
$tempFile = sys_get_temp_dir() . '/test_' . uniqid() . '.txt';
$content = "Line 1\nLine 2\nLine 3\n";

// 写入文件
file_put_contents($tempFile, $content);

// 读取文件
$readContent = file_get_contents($tempFile);
echo "Content:\n$readContent";

// 逐行读取
$lines = file($tempFile);
echo "Lines count: " . count($lines) . "\n";

// 文件信息
echo "File exists: " . (file_exists($tempFile) ? "yes" : "no") . "\n";
echo "File size: " . filesize($tempFile) . "\n";
echo "Is readable: " . (is_readable($tempFile) ? "yes" : "no") . "\n";
echo "Is writable: " . (is_writable($tempFile) ? "yes" : "no") . "\n";

// 文件指针操作
$fp = fopen($tempFile, 'r');
echo "First line: " . fgets($fp);
fseek($fp, 0);
echo "First 5 bytes: " . fread($fp, 5) . "\n";
fclose($fp);

// 目录操作
$tempDir = sys_get_temp_dir();
$files = scandir($tempDir);
echo "Files in temp dir: " . count($files) . "\n";

// 清理
unlink($tempFile);
echo "File deleted: " . (file_exists($tempFile) ? "no" : "yes") . "\n";
?>
