<?php
// ============================================================================
// PHP 文件操作函数测试
// ============================================================================

echo "=== PHP 文件操作函数测试 ===\n\n";

// ============================================================================
// 1. 基础文件操作
// ============================================================================

echo "1. 基础文件操作\n";
echo "------------------\n";

$test_file = "/tmp/zigphp_test_file.txt";
$test_content = "Hello, zig-php!\nThis is a test file.\n";

// 写入文件
$bytes_written = file_put_contents($test_file, $test_content);
echo "写入文件: {$bytes_written} 字节\n";

// 读取文件
$content = file_get_contents($test_file);
echo "读取文件内容:\n{$content}";

// 检查文件是否存在
if (file_exists($test_file)) {
    echo "文件存在: true\n";
}

// 检查是否为文件
if (is_file($test_file)) {
    echo "是文件: true\n";
}

// 获取文件大小
$filesize = filesize($test_file);
echo "文件大小: {$filesize} 字节\n";

// 获取文件修改时间
$mtime = filemtime($test_file);
echo "文件修改时间: {$mtime}\n";

// 获取文件名
$basename = basename($test_file);
echo "文件名: {$basename}\n";

// 获取目录名
$dirname = dirname($test_file);
echo "目录名: {$dirname}\n";

echo "\n";

// ============================================================================
// 2. 文件管理操作
// ============================================================================

echo "2. 文件管理操作\n";
echo "------------------\n";

// 复制文件
$copy_file = "/tmp/zigphp_test_copy.txt";
if (copy($test_file, $copy_file)) {
    echo "文件复制成功\n";
}

// 重命名文件
$rename_file = "/tmp/zigphp_test_renamed.txt";
if (rename($copy_file, $rename_file)) {
    echo "文件重命名成功\n";
}

// 删除文件
if (unlink($rename_file)) {
    echo "文件删除成功\n";
}

echo "\n";

// ============================================================================
// 3. 目录操作
// ============================================================================

echo "3. 目录操作\n";
echo "------------------\n";

$test_dir = "/tmp/zigphp_test_dir";

// 创建目录
if (mkdir($test_dir)) {
    echo "目录创建成功\n";
}

// 检查是否为目录
if (is_dir($test_dir)) {
    echo "是目录: true\n";
}

// 在目录中创建文件
file_put_contents("{$test_dir}/test.txt", "Test content");

// 扫描目录
$files = scandir($test_dir);
echo "目录内容:\n";
foreach ($files as $file) {
    echo "  {$file}\n";
}

// 删除目录
if (rmdir($test_dir)) {
    echo "目录删除成功\n";
}

echo "\n";

// ============================================================================
// 4. 文件流操作
// ============================================================================

echo "4. 文件流操作\n";
echo "------------------\n";

// 打开文件
$fp = fopen($test_file, "r");
if ($fp) {
    echo "文件打开成功\n";
    
    // 读取文件
    $content = fread($fp, 100);
    echo "读取内容: {$content}";
    
    // 获取文件指针位置
    $pos = ftell($fp);
    echo "文件指针位置: {$pos}\n";
    
    // 移动文件指针
    fseek($fp, 0);
    echo "文件指针已移动到开头\n";
    
    // 检查是否到达文件末尾
    if (feof($fp)) {
        echo "已到达文件末尾\n";
    } else {
        echo "未到达文件末尾\n";
    }
    
    // 关闭文件
    fclose($fp);
    echo "文件已关闭\n";
}

echo "\n";

// ============================================================================
// 5. 写入文件
// ============================================================================

echo "5. 写入文件\n";
echo "------------------\n";

$fp = fopen($test_file, "w");
if ($fp) {
    $written = fwrite($fp, "New content written via fwrite\n");
    echo "写入 {$written} 字节\n";
    fclose($fp);
}

echo "\n";

// ============================================================================
// 6. 逐行读取
// ============================================================================

echo "6. 逐行读取\n";
echo "------------------\n";

$fp = fopen($test_file, "r");
if ($fp) {
    while (($line = fgets($fp)) !== false) {
        echo "行: {$line}";
    }
    fclose($fp);
}

echo "\n";

// ============================================================================
// 7. 逐字符读取
// ============================================================================

echo "7. 逐字符读取\n";
echo "------------------\n";

$fp = fopen($test_file, "r");
if ($fp) {
    $count = 0;
    while (($char = fgetc($fp)) !== false && $count < 10) {
        echo "字符 {$count}: {$char}\n";
        $count++;
    }
    fclose($fp);
}

echo "\n";

// ============================================================================
// 8. 清理
// ============================================================================

echo "8. 清理测试文件\n";
echo "------------------\n";

if (unlink($test_file)) {
    echo "测试文件已删除\n";
}

echo "\n=== 所有测试完成 ===\n";
?>