<?php
// ============================================================================
// PHP 文件操作函数全面测试 - 验证可用性和行为一致性
// ============================================================================

echo "=== PHP 文件操作函数全面测试 ===\n\n";

class TestRunner {
    public $success_count = 0;
    public $fail_count = 0;

    public function test_result($name, $result, $expected = true) {
        if ($result === $expected) {
            echo "✓ {$name}: 通过\n";
            $this->success_count++;
        } else {
            echo "✗ {$name}: 失败 (期望: " . var_export($expected, true) . ", 实际: " . var_export($result, true) . ")\n";
            $this->fail_count++;
        }
    }
}

$test = new TestRunner();

// ============================================================================
// 1. 基础文件操作
// ============================================================================

echo "1. 基础文件操作\n";
echo "------------------\n";

$test_file = "/tmp/zigphp_comprehensive_test.txt";
$test_content = "Hello, zig-php!\nThis is a comprehensive test.\nLine 3\n";

// file_put_contents
$bytes = file_put_contents($test_file, $test_content);
$test->test_result("file_put_contents", $bytes > 0, true);

// file_get_contents
$content = file_get_contents($test_file);
$test->test_result("file_get_contents", $content, $test_content);

// file_exists
$test->test_result("file_exists", file_exists($test_file), true);
$test->test_result("file_exists (不存在的文件)", file_exists("/tmp/nonexistent_file.txt"), false);

// is_file
$test->test_result("is_file", is_file($test_file), true);
$test->test_result("is_file (目录)", is_file("/tmp"), false);

// is_dir
$test->test_result("is_dir (文件)", is_dir($test_file), false);
$test->test_result("is_dir (目录)", is_dir("/tmp"), true);

// filesize
$test->test_result("filesize", filesize($test_file), strlen($test_content));

// filemtime
$mtime = filemtime($test_file);
$test->test_result("filemtime", is_numeric($mtime), true);

// basename
$test->test_result("basename", basename($test_file), "zigphp_comprehensive_test.txt");
$test->test_result("basename (带路径)", basename("/tmp/test.txt"), "test.txt");

// dirname
$test->test_result("dirname", dirname($test_file), "/tmp");
$test->test_result("dirname (深层)", dirname("/tmp/a/b/c.txt"), "/tmp/a/b");

echo "\n";

// ============================================================================
// 2. 文件管理操作
// ============================================================================

echo "2. 文件管理操作\n";
echo "------------------\n";

// copy
$copy_file = "/tmp/zigphp_comprehensive_copy.txt";
$test->test_result("copy", copy($test_file, $copy_file), true);
$test->test_result("copy 后内容一致", file_get_contents($copy_file), $test_content);

// rename
$rename_file = "/tmp/zigphp_comprehensive_renamed.txt";
$test->test_result("rename", rename($copy_file, $rename_file), true);
$test->test_result("rename 后原文件不存在", file_exists($copy_file), false);
$test->test_result("rename 后新文件存在", file_exists($rename_file), true);

// unlink
$test->test_result("unlink", unlink($rename_file), true);
$test->test_result("unlink 后文件不存在", file_exists($rename_file), false);

echo "\n";

// ============================================================================
// 3. 目录操作
// ============================================================================

echo "3. 目录操作\n";
echo "------------------\n";

$test_dir = "/tmp/zigphp_comprehensive_dir";

// mkdir
$test->test_result("mkdir", mkdir($test_dir), true);
$test->test_result("mkdir 后目录存在", is_dir($test_dir), true);

// 在目录中创建文件
file_put_contents("{$test_dir}/file1.txt", "Content 1");
file_put_contents("{$test_dir}/file2.txt", "Content 2");

// scandir
$files = scandir($test_dir);
$test->test_result("scandir 返回数组", is_array($files), true);
$test->test_result("scandir 包含文件", count($files) >= 4, true); // ., .., file1.txt, file2.txt

// rmdir (先删除文件)
unlink("{$test_dir}/file1.txt");
unlink("{$test_dir}/file2.txt");
$test->test_result("rmdir", rmdir($test_dir), true);
$test->test_result("rmdir 后目录不存在", file_exists($test_dir), false);

echo "\n";

// ============================================================================
// 4. 文件流操作
// ============================================================================

echo "4. 文件流操作\n";
echo "------------------\n";

// fopen - 读模式
$fp = fopen($test_file, "r");
$test->test_result("fopen (r)", $fp !== false, true);
if ($fp) {
    // fread
    $read_content = fread($fp, 100);
    $test->test_result("fread", $read_content, $test_content);
    
    // ftell
    $pos = ftell($fp);
    $test->test_result("ftell (读取后)", $pos > 0, true);
    
    // fseek
    $seek_result = fseek($fp, 0);
    $test->test_result("fseek (SEEK_SET)", $seek_result, 0);
    
    $pos_after_seek = ftell($fp);
    $test->test_result("ftell (seek后)", $pos_after_seek, 0);
    
    // feof
    $test->test_result("feof (seek后)", feof($fp), false);
    
    // fclose
    $test->test_result("fclose", fclose($fp), true);
}

// fopen - 写模式
$fp = fopen($test_file, "w");
$test->test_result("fopen (w)", $fp !== false, true);
if ($fp) {
    // fwrite
    $written = fwrite($fp, "New content\n");
    $test->test_result("fwrite", $written > 0, true);
    
    $test->test_result("fclose (写模式)", fclose($fp), true);
    
    // 验证写入内容
    $new_content = file_get_contents($test_file);
    $test->test_result("fwrite 后内容一致", $new_content, "New content\n");
}

// 恢复测试文件内容
file_put_contents($test_file, $test_content);

// fgets - 逐行读取
$fp = fopen($test_file, "r");
$test->test_result("fopen (fgets)", $fp !== false, true);
if ($fp) {
    $line1 = fgets($fp);
    $test->test_result("fgets (第一行)", $line1, "Hello, zig-php!\n");
    
    $line2 = fgets($fp);
    $test->test_result("fgets (第二行)", $line2, "This is a comprehensive test.\n");
    
    // 读取到末尾
    fgets($fp);
    fgets($fp);
    
    $test->test_result("feof (读取完)", feof($fp), true);
    
    $test->test_result("fclose (fgets)", fclose($fp), true);
}

// fgetc - 逐字符读取
$fp = fopen($test_file, "r");
$test->test_result("fopen (fgetc)", $fp !== false, true);
if ($fp) {
    $char1 = fgetc($fp);
    $test->test_result("fgetc (第一个字符)", $char1, "H");
    
    $char2 = fgetc($fp);
    $test->test_result("fgetc (第二个字符)", $char2, "e");
    
    $test->test_result("fclose (fgetc)", fclose($fp), true);
}

// rewind
$fp = fopen($test_file, "r");
$test->test_result("fopen (rewind)", $fp !== false, true);
if ($fp) {
    // 读取一些内容
    fread($fp, 10);
    $pos = ftell($fp);
    $test->test_result("ftell (rewind前)", $pos, 10);
    
    // rewind
    rewind($fp);
    $pos_after_rewind = ftell($fp);
    $test->test_result("ftell (rewind后)", $pos_after_rewind, 0);
    
    $test->test_result("fclose (rewind)", fclose($fp), true);
}

// fflush
$fp = fopen($test_file, "w");
$test->test_result("fopen (fflush)", $fp !== false, true);
if ($fp) {
    fwrite($fp, "Test flush\n");
    $test->test_result("fflush", fflush($fp), true);
    $test->test_result("fclose (fflush)", fclose($fp), true);
    
    // 验证内容
    $flush_content = file_get_contents($test_file);
    $test->test_result("fflush 后内容", $flush_content, "Test flush\n");
}

echo "\n";

// ============================================================================
// 5. 错误处理
// ============================================================================

echo "5. 错误处理\n";
echo "------------------\n";

// 读取不存在的文件
$nonexistent = file_get_contents("/tmp/nonexistent_file_12345.txt");
$test->test_result("file_get_contents (不存在的文件)", $nonexistent, false);

// 删除不存在的文件
$test->test_result("unlink (不存在的文件)", unlink("/tmp/nonexistent_file_12345.txt"), false);

// 打开不存在的文件
$fp = fopen("/tmp/nonexistent_file_12345.txt", "r");
$test->test_result("fopen (不存在的文件)", $fp, false);

echo "\n";

// ============================================================================
// 6. 清理
// ============================================================================

echo "6. 清理\n";
echo "------------------\n";

$test->test_result("unlink (清理测试文件)", unlink($test_file), true);

echo "\n";
echo "=== 测试结果 ===\n";
echo "成功: {$test->success_count}\n";
echo "失败: {$test->fail_count}\n";

if ($test->fail_count == 0) {
    echo "\n✓ 所有测试通过！文件操作函数可用且行为一致。\n";
} else {
    echo "\n✗ 有 {$test->fail_count} 个测试失败。\n";
}
?>