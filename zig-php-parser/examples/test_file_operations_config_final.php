<?php
// ============================================================================
// 文件操作安全配置测试 - 最终版本
// ============================================================================

echo "=== 文件操作安全配置测试（最终版本）===\n\n";

// 测试 1: 尝试创建上级目录
echo "测试 1: 尝试创建上级目录\n";
$result = mkdir("../config_test_dir");

if ($result === false) {
    echo "结果: ✓ 安全检查生效 - 创建被拒绝\n";
    echo "说明: allow_unsafe_paths = false\n";
} else {
    echo "结果: ✗ 安全检查已禁用 - 创建成功\n";
    echo "说明: allow_unsafe_paths = true\n";
    rmdir("../config_test_dir");
}

echo "\n";

// 测试 2: 尝试创建绝对路径目录
echo "测试 2: 尝试创建绝对路径目录\n";
$result = mkdir("/tmp/zigphp_config_test");

if ($result === false) {
    echo "结果: ✓ 安全检查生效 - 创建被拒绝\n";
    echo "说明: allow_unsafe_paths = false\n";
} else {
    echo "结果: ✗ 安全检查已禁用 - 创建成功\n";
    echo "说明: allow_unsafe_paths = true\n";
    rmdir("/tmp/zigphp_config_test");
}

echo "\n";

// 测试 3: 尝试删除上级目录
echo "测试 3: 尝试删除上级目录\n";
$result = rmdir("../config_test_dir");

if ($result === false) {
    echo "结果: ✓ 安全检查生效 - 删除被拒绝\n";
    echo "说明: allow_unsafe_paths = false\n";
} else {
    echo "结果: ✗ 安全检查已禁用 - 删除成功\n";
    echo "说明: allow_unsafe_paths = true\n";
}

echo "\n";

// 测试 4: 尝试扫描上级目录
echo "测试 4: 尝试扫描上级目录\n";
$result = scandir("..");

if ($result === false) {
    echo "结果: ✓ 安全检查生效 - 扫描被拒绝\n";
    echo "说明: allow_unsafe_paths = false\n";
} else {
    echo "结果: ✗ 安全检查已禁用 - 扫描成功\n";
    echo "说明: allow_unsafe_paths = true\n";
}

echo "\n=== 配置测试完成 ===\n";
?>