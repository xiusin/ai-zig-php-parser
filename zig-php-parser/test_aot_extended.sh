#!/bin/bash
# AOT编译器扩展测试套件

echo "=== AOT编译器扩展测试套件 ==="
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 测试计数
TOTAL=0
PASSED=0
FAILED=0

# 测试函数
test_case() {
    local name=$1
    local file=$2
    local expected=$3
    
    TOTAL=$((TOTAL + 1))
    echo -n "测试 $TOTAL: $name ... "
    
    # 编译
    if ! ./zig-out/bin/php-interpreter --compile "$file" > /dev/null 2>&1; then
        echo -e "${RED}编译失败${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
    
    # 检查可执行文件
    if [ ! -f "./hello" ] || [ ! -s "./hello" ]; then
        echo -e "${RED}可执行文件未生成${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
    
    # 运行
    output=$(./hello 2>&1 | tr -d '%')
    
    # 检查输出
    if [ "$output" = "$expected" ]; then
        echo -e "${GREEN}通过${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}失败${NC} (期望: '$expected', 实际: '$output')"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

echo "--- 基本测试 ---"
test_case "简单整数" "test_simple_var.php" "10"
test_case "字符串拼接" "test_string_simple.php" "HelloWorld"
test_case "整数加法" "test_simple_assignment.php" "30"

echo ""
echo "--- 控制流测试 ---"
test_case "简单if" "test_simple_if.php" "10"
test_case "if/else" "test_if_else.php" "20"
test_case "while循环" "test_while_loop.php" "012"
test_case "for循环" "test_for_loop.php" "012"
test_case "嵌套if" "test_nested_if.php" "20"

echo ""
echo "--- 数组测试 ---"
test_case "基本数组" "test_array_basic.php" "102030"
test_case "数组求和" "test_sum_array.php" "100"

echo ""
echo "--- 算法测试 ---"
test_case "阶乘(5!)" "test_factorial.php" "120"
test_case "斐波那契" "test_fibonacci.php" "0112358132134"

echo ""
echo "=== 测试总结 ==="
echo "总计: $TOTAL"
echo -e "通过: ${GREEN}$PASSED${NC}"
echo -e "失败: ${RED}$FAILED${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}所有测试通过！${NC}"
    exit 0
else
    echo -e "\n${YELLOW}有 $FAILED 个测试失败${NC}"
    exit 1
fi
