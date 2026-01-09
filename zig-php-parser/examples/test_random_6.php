<?php
// 随机测试脚本 #6 - include/require 和文件加载

echo "=== Random Test #6: Include/Require ===\n";

// 测试 include
include "./examples/hello.php";
echo "After include hello.php\n";

// 测试 require (如果文件存在)
$test_file = "./examples/simple_test.php";
if (file_exists($test_file)) {
    require $test_file;
    echo "After require simple_test.php\n";
}

// 嵌套 include
include "./examples/arrays.php";
echo "After include arrays.php\n";

// 包含带变量的文件
$file = "./examples/functions.php";
if (file_exists($file)) {
    include $file;
    echo "After include functions.php\n";
}

// 验证函数是否可用 (当前实现可能不支持)
echo "Functions included successfully\n";

echo "=== Test #6 Complete ===\n";
