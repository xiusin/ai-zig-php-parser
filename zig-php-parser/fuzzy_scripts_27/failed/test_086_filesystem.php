<?php
// Test 086: Directory functions
$tmp = sys_get_temp_dir();
echo "=== Directory functions ===\n";
echo "sys_get_temp_dir(): $tmp\n";

$testDir = $tmp . '/php_test_' . getmypid();
mkdir($testDir, 0755);

echo "\n=== File operations ===\n";
$testFile = $testDir . '/test.txt';
file_put_contents($testFile, "Line 1\nLine 2\nLine 3");
echo "is_file: " . (is_file($testFile) ? 'yes' : 'no') . "\n";
echo "file_exists: " . (file_exists($testFile) ? 'yes' : 'no') . "\n";
echo "filesize: " . filesize($testFile) . "\n";
echo "file_get_contents: " . trim(file_get_contents($testFile)) . "\n";

echo "\n=== Directory listing ===\n";
$subDir = $testDir . '/subdir';
mkdir($subDir, 0755);
$files = scandir($testDir);
echo "scandir: " . implode(', ', $files) . "\n";

echo "\n=== Glob ===\n";
$pattern = $testDir . '/*.txt';
$matches = glob($pattern);
echo "glob($pattern): " . implode(', ', $matches) . "\n";

echo "\n=== Path info ===\n";
$pathInfo = pathinfo($testFile);
echo "dirname: " . $pathInfo['dirname'] . "\n";
echo "basename: " . $pathInfo['basename'] . "\n";
echo "extension: " . $pathInfo['extension'] . "\n";

echo "\n=== Cleanup ===\n";
unlink($testFile);
rmdir($subDir);
rmdir($testDir);
echo "Cleanup done\n";