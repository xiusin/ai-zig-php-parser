<?php
// ============================================================================
// 文件操作安全配置测试 - 详细版本
// ============================================================================

echo "=== 文件操作安全配置测试（详细版本）===\n\n";

// 测试 1: 尝试访问上级目录的文件
echo "测试 1: 尝试访问上级目录的文件\n";
$result = file_get_contents("../test.txt");

if ($result === false) {
    echo "结果: ✓ 安全检查生效 - 访问被拒绝\n";
    echo "说明: allow_unsafe_paths = false\n";
} else {
    echo "结果: ✗ 安全检查已禁用 - 访问成功\n";
    echo "说明: allow_unsafe_paths = true\n";
}

echo "\n";

// 测试 2: 尝试使用绝对路径
echo "测试 2: 尝试使用绝对路径\n";
$result = file_get_contents("/etc/passwd");

if ($result === false) {
    echo "结果: ✓ 安全检查生效 - 访问被拒绝\n";
    echo "说明: allow_unsafe_paths = false\n";
} else {
    echo "结果: ✗ 安全检查已禁用 - 访问成功\n";
    echo "说明: allow_unsafe_paths = true\n";
}

echo "\n";

// 测试 3: 尝试创建上级目录
echo "测试 3: 尝试创建上级目录\n";
$result = mkdir("../test_dir");

if ($result === false) {
    echo "结果: ✓ 安全检查生效 - 创建被拒绝\n";
    echo "说明: allow_unsafe_paths = false\n";
} else {
    echo "结果: ✗ 安全检查已禁用 - 创建成功\n";
    echo "说明: allow_unsafe_paths = true\n";
    rmdir("../test_dir");
}

echo "\n=== 配置测试完成 ===\n";
?>