#!/bin/bash

# 内存泄漏测试脚本
# 编译并运行所有内存泄漏测试用例

set -e  # 遇到错误立即退出

echo "======================================"
echo "AOT编译器内存泄漏测试套件"
echo "======================================"
echo ""

# 检查编译器是否存在
if [ ! -f "zig-out/bin/php-interpreter" ]; then
    echo "错误：编译器不存在，请先运行 'zig build'"
    exit 1
fi

# 测试用例列表
tests=(
    "test_memory_leak_1_simple"
    "test_memory_leak_2_loop"
    "test_memory_leak_3_string_concat"
    "test_memory_leak_4_nested_loop"
    "test_memory_leak_5_stress"
)

# 统计
total_tests=${#tests[@]}
passed_tests=0
failed_tests=0

echo "共 $total_tests 个测试用例"
echo ""

# 运行每个测试
for test in "${tests[@]}"; do
    echo "--------------------------------------"
    echo "测试: $test"
    echo "--------------------------------------"
    
    # 编译
    echo "1. 编译 ${test}.php ..."
    if ./zig-out/bin/php-interpreter --compile "${test}.php" --output "$test" 2>&1 | grep -q "Success"; then
        echo "   ✓ 编译成功"
    else
        echo "   ✗ 编译失败"
        failed_tests=$((failed_tests + 1))
        continue
    fi
    
    # 运行
    echo "2. 运行 $test ..."
    if ./"$test" > /dev/null 2>&1; then
        echo "   ✓ 运行成功"
        passed_tests=$((passed_tests + 1))
    else
        echo "   ✗ 运行失败"
        failed_tests=$((failed_tests + 1))
        continue
    fi
    
    # 清理
    rm -f "$test"
    
    echo ""
done

echo "======================================"
echo "测试结果汇总"
echo "======================================"
echo "总计: $total_tests"
echo "通过: $passed_tests"
echo "失败: $failed_tests"
echo ""

if [ $failed_tests -eq 0 ]; then
    echo "✓ 所有测试通过！"
    exit 0
else
    echo "✗ 有 $failed_tests 个测试失败"
    exit 1
fi
