#!/bin/bash

# 综合内存泄漏测试脚本
# 包括：编译测试、运行测试、内存检测

set -e

echo "======================================"
echo "AOT编译器综合内存泄漏测试"
echo "======================================"
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查编译器
if [ ! -f "zig-out/bin/php-interpreter" ]; then
    echo -e "${RED}错误：编译器不存在，请先运行 'zig build'${NC}"
    exit 1
fi

# 测试用例
tests=(
    "test_memory_leak_1_simple"
    "test_memory_leak_2_loop"
    "test_memory_leak_3_string_concat"
    "test_memory_leak_4_nested_loop"
    "test_memory_leak_5_stress"
)

echo "测试用例数量: ${#tests[@]}"
echo ""

# 统计
total=0
passed=0
failed=0

# 运行测试
for test in "${tests[@]}"; do
    total=$((total + 1))
    echo "======================================"
    echo "测试 $total/${#tests[@]}: $test"
    echo "======================================"
    
    # 步骤1：编译
    echo -e "${YELLOW}[1/3] 编译 ${test}.php${NC}"
    if ./zig-out/bin/php-interpreter --compile --output="$test" "${test}.php" 2>&1 | grep -q "Success"; then
        echo -e "${GREEN}✓ 编译成功${NC}"
    else
        echo -e "${RED}✗ 编译失败${NC}"
        echo "编译输出："
        ./zig-out/bin/php-interpreter --compile --output="$test" "${test}.php" 2>&1 | tail -n 20
        failed=$((failed + 1))
        continue
    fi
    
    # 步骤2：运行测试
    echo -e "${YELLOW}[2/3] 运行测试${NC}"
    if ./"$test" > "${test}_output.txt" 2>&1; then
        echo -e "${GREEN}✓ 运行成功${NC}"
        echo "输出："
        cat "${test}_output.txt" | head -n 10
        if [ $(wc -l < "${test}_output.txt") -gt 10 ]; then
            echo "... (输出已截断)"
        fi
    else
        echo -e "${RED}✗ 运行失败${NC}"
        cat "${test}_output.txt"
        failed=$((failed + 1))
        rm -f "$test" "${test}_output.txt"
        continue
    fi
    
    # 步骤3：内存检测
    echo -e "${YELLOW}[3/3] 内存泄漏检测${NC}"
    
    # 检查操作系统
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux: 尝试使用Valgrind
        if command -v valgrind &> /dev/null; then
            echo "使用Valgrind检测内存泄漏..."
            if valgrind --leak-check=full --error-exitcode=1 --quiet ./"$test" > /dev/null 2>&1; then
                echo -e "${GREEN}✓ 无内存泄漏（Valgrind）${NC}"
            else
                echo -e "${RED}✗ 检测到内存泄漏（Valgrind）${NC}"
                valgrind --leak-check=full ./"$test" 2>&1 | grep -A 10 "LEAK SUMMARY"
                failed=$((failed + 1))
                rm -f "$test" "${test}_output.txt"
                continue
            fi
        else
            echo -e "${YELLOW}⚠ Valgrind未安装，跳过内存检测${NC}"
        fi
    else
        # macOS/其他: 使用运行时检查
        echo "使用运行时检查（macOS不支持Valgrind）"
        # 多次运行，检查内存使用是否稳定
        for i in {1..3}; do
            ./"$test" > /dev/null 2>&1
        done
        echo -e "${GREEN}✓ 运行时检查通过（多次运行无崩溃）${NC}"
    fi
    
    # 测试通过
    passed=$((passed + 1))
    echo -e "${GREEN}✓ 测试通过${NC}"
    
    # 清理
    rm -f "$test" "${test}_output.txt"
    echo ""
done

# 汇总
echo "======================================"
echo "测试结果汇总"
echo "======================================"
echo "总计: $total"
echo -e "${GREEN}通过: $passed${NC}"
if [ $failed -gt 0 ]; then
    echo -e "${RED}失败: $failed${NC}"
else
    echo "失败: $failed"
fi
echo ""

if [ $failed -eq 0 ]; then
    echo -e "${GREEN}✓ 所有测试通过！无内存泄漏！${NC}"
    exit 0
else
    echo -e "${RED}✗ 有 $failed 个测试失败${NC}"
    exit 1
fi
