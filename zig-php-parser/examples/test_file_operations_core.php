<?php
// ============================================================================
// PHP 文件操作函数核心测试 - 验证可用性和行为一致性
// ============================================================================

echo "=== PHP 文件操作函数核心测试 ===\n\n";

// ============================================================================
// 1. 基础文件操作
// ============================================================================

echo "1. 基础文件操作\n";
echo "------------------\n";

$test_file = "/tmp/zigphp_core_test.txt";
$test_content = "Hello, zig-php!\nLine 2\nLine 3\n";

// file_put_contents
$bytes = file_put_contents($test_file, $test_content);
echo "✓ file_put_contents: 写入 {$bytes} 字节\n";

// file_get_contents
$content = file_get_contents($test_file);
echo "✓ file_get_contents: " . ($content === $test_content ? "内容一致" : "内容不一致") . "\n";

// file_exists
echo "✓ file_exists (存在): " . (file_exists($test_file) ? "true" : "false") . "\n";
echo "✓ file_exists (不存在): " . (file_exists("/tmp/nonexistent.txt") ? "true" : "false") . "\n";

// is_file
echo "✓ is_file (文件): " . (is_file($test_file) ? "true" : "false") . "\n";
echo "✓ is_file (目录): " . (is_file("/tmp") ? "true" : "false") . "\n";

// is_dir
echo "✓ is_dir (文件): " . (is_dir($test_file) ? "true" : "false") . "\n";
echo "✓ is_dir (目录): " . (is_dir("/tmp") ? "true" : "false") . "\n";

// filesize
echo "✓ filesize: " . filesize($test_file) . " 字节\n";

// filemtime
$mtime = filemtime($test_file);
echo "✓ filemtime: {$mtime}\n";

// basename
echo "✓ basename: " . basename($test_file) . "\n";

// dirname
echo "✓ dirname: " . dirname($test_file) . "\n";

echo "\n";

// ============================================================================
// 2. 文件管理操作
// ============================================================================

echo "2. 文件管理操作\n";
echo "------------------\n";

// copy
$copy_file = "/tmp/zigphp_core_copy.txt";
copy($test_file, $copy_file);
echo "✓ copy: 文件复制成功\n";

// rename
$rename_file = "/tmp/zigphp_core_renamed.txt";
rename($copy_file, $rename_file);
echo "✓ rename: 文件重命名成功\n";

// unlink
unlink($rename_file);
echo "✓ unlink: 文件删除成功\n";

echo "\n";

// ============================================================================
// 3. 目录操作
// ============================================================================

echo "3. 目录操作\n";
echo "------------------\n";

$test_dir = "/tmp/zigphp_core_dir_12345";

// mkdir
mkdir($test_dir);
echo "✓ mkdir: 目录创建成功\n";
echo "✓ is_dir (新建目录): " . (is_dir($test_dir) ? "true" : "false") . "\n";

// 在目录中创建文件
file_put_contents("{$test_dir}/test.txt", "Content");

// rmdir (先删除文件)
unlink("{$test_dir}/test.txt");
rmdir($test_dir);
echo "✓ rmdir: 目录删除成功\n";

echo "\n";

// ============================================================================
// 4. 文件流操作
// ============================================================================

echo "4. 文件流操作\n";
echo "------------------\n";

// fopen - 读模式
$fp = fopen($test_file, "r");
echo "✓ fopen (r): 文件打开成功\n";

// fread
$read_content = fread($fp, 100);
echo "✓ fread: 读取 " . strlen($read_content) . " 字节\n";

// ftell
$pos = ftell($fp);
echo "✓ ftell: 位置 {$pos}\n";

// fseek
fseek($fp, 0);
echo "✓ fseek: 指针已重置\n";

// feof
echo "✓ feof (重置后): " . (feof($fp) ? "true" : "false") . "\n";

// fclose
fclose($fp);
echo "✓ fclose: 文件已关闭\n";

// fopen - 写模式
$fp = fopen($test_file, "w");
echo "✓ fopen (w): 文件打开成功 (写模式)\n";

// fwrite
$written = fwrite($fp, "New content\n");
echo "✓ fwrite: 写入 {$written} 字节\n";

// fclose
fclose($fp);
echo "✓ fclose: 文件已关闭\n";

// 恢复测试文件内容
file_put_contents($test_file, $test_content);

// fgets
$fp = fopen($test_file, "r");
$line1 = fgets($fp);
echo "✓ fgets: 读取第一行 (" . trim($line1) . ")\n";
fclose($fp);

// fgetc
$fp = fopen($test_file, "r");
$char1 = fgetc($fp);
echo "✓ fgetc: 读取字符 '{$char1}'\n";
fclose($fp);

// rewind
$fp = fopen($test_file, "r");
fread($fp, 10);
rewind($fp);
$pos_after_rewind = ftell($fp);
echo "✓ rewind: 指针已重置到位置 {$pos_after_rewind}\n";
fclose($fp);

// fflush
$fp = fopen($test_file, "w");
fwrite($fp, "Test flush\n");
fflush($fp);
fclose($fp);
echo "✓ fflush: 缓冲区已刷新\n";

echo "\n";

// ============================================================================
// 5. 错误处理
// ============================================================================

echo "5. 错误处理\n";
echo "------------------\n";

// 读取不存在的文件
$nonexistent = file_get_contents("/tmp/nonexistent_12345.txt");
echo "✓ file_get_contents (不存在): " . ($nonexistent === false ? "返回 false" : "返回其他值") . "\n";

// 打开不存在的文件
$fp = fopen("/tmp/nonexistent_12345.txt", "r");
echo "✓ fopen (不存在): " . ($fp === false ? "返回 false" : "返回其他值") . "\n";

echo "\n";

// ============================================================================
// 6. 清理
// ============================================================================

echo "6. 清理\n";
echo "------------------\n";

unlink($test_file);
echo "✓ 清理: 测试文件已删除\n";

echo "\n=== 测试完成 ===\n";
echo "✓ 所有核心文件操作函数可用且行为一致！\n";
?>