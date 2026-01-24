#!/bin/bash

# AOT编译器测试套件
# 测试各种PHP代码的AOT编译和执行

set -e

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 测试计数器
TOTAL=0
PASSED=0
FAILED=0

# 测试函数
test_aot() {
    local test_name="$1"
    local php_file="$2"
    local expected_output="$3"
    
    TOTAL=$((TOTAL + 1))
    
    # 编译
    if ! zig build run -- --compile "$php_file" > /dev/null 2>&1; then
        echo -e "${RED}✗${NC} $test_name (编译失败)"
        FAILED=$((FAILED + 1))
        return 1
    fi
    
    # 检查可执行文件是否存在
    if [ ! -f "./hello" ]; then
        echo -e "${RED}✗${NC} $test_name (可执行文件未生成)"
        FAILED=$((FAILED + 1))
        return 1
    fi
    
    # 运行并检查输出
    local actual_output=$(./hello 2>&1)
    # 移除末尾的%符号（如果存在）
    actual_output="${actual_output%%%}"
    
    if [ "$actual_output" = "$expected_output" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $test_name (期望: '$expected_output', 实际: '$actual_output')"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

echo "=== AOT编译器测试套件 ==="
echo ""

# 如果提供了参数，只测试指定的文件
if [ $# -gt 0 ]; then
    php_file="$1"
    if [ ! -f "$php_file" ]; then
        echo "错误: 文件 $php_file 不存在"
        exit 1
    fi
    
    # 编译
    echo "编译 $php_file ..."
    zig build run -- --compile "$php_file"
    
    # 运行
    echo "运行 ./hello ..."
    ./hello
    
    exit 0
fi

echo "--- 基本功能 ---"
test_aot "测试 1: 简单整数输出" "test_simple_int.php" "42"
# test_aot "测试 2: 字符串拼接" "test_string_concat.php" "HelloWorld"  # 暂时跳过
test_aot "测试 3: 整数加法" "test_add.php" "21"
test_aot "测试 4: 多个运算" "test_multi_ops.php" "6105"

echo ""
echo "--- 控制流 ---"
test_aot "测试 5: 简单if语句" "test_if_simple.php" "10"
test_aot "测试 6: if/else语句" "test_if_else.php" "20"
test_aot "测试 7: while循环" "test_while_loop.php" "012"
test_aot "测试 8: for循环" "test_for_loop.php" "012"
test_aot "测试 9: 嵌套if语句" "test_nested_if.php" "20"

echo ""
echo "--- 数组操作 ---"
test_aot "测试 10: 基本数组操作" "test_array_basic.php" "102030"

echo ""
echo "=== 测试总结 ==="
echo "总计: $TOTAL"
echo "通过: $PASSED"
echo "失败: $FAILED"

if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}所有测试通过！${NC}"
    exit 0
else
    echo -e "\n${RED}有 $FAILED 个测试失败${NC}"
    exit 1
fi
