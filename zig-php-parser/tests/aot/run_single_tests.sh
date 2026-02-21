#!/bin/bash

# AOT 单功能测试套件
# 每个测试独立运行，避免多循环问题

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../.."
INTERPRETER="$PROJECT_ROOT/zig-out/bin/php-interpreter"
TEST_DIR="$SCRIPT_DIR"
OUTPUT_DIR="/tmp/aot_single_tests"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$OUTPUT_DIR"

echo "=========================================="
echo "AOT 单功能测试套件"
echo "=========================================="
echo ""

# 单功能测试（避免多循环）
tests=(
    "test_oop_basic:面向对象基础"
    "test_closures:闭包和高阶函数"
    "test_array_functions:数组内置函数"
    "test_string_functions:字符串内置函数"
    "test_ternary_null:三元运算符"
    "test_type_checking:类型判断转换"
    "test_variadic_params:可变参数"
)

passed=0
failed=0
total=${#tests[@]}

for test_entry in "${tests[@]}"; do
    IFS=':' read -r test_name test_desc <<< "$test_entry"
    test_file="$TEST_DIR/${test_name}.php"
    output_bin="$OUTPUT_DIR/${test_name}"
    
    echo -n "[$((passed + failed + 1))/$total] $test_desc ... "
    
    if [ ! -f "$test_file" ]; then
        echo -e "${YELLOW}SKIP${NC} (文件不存在)"
        continue
    fi
    
    # 编译
    if ! "$INTERPRETER" --compile --output="$output_bin" "$test_file" > "$OUTPUT_DIR/${test_name}.compile.log" 2>&1; then
        echo -e "${RED}FAIL${NC} (编译失败)"
        tail -5 "$OUTPUT_DIR/${test_name}.compile.log" | sed 's/^/  /'
        ((failed++))
        continue
    fi
    
    # 运行
    if ! "$output_bin" > "$OUTPUT_DIR/${test_name}.output.txt" 2>&1; then
        echo -e "${RED}FAIL${NC} (运行失败)"
        tail -5 "$OUTPUT_DIR/${test_name}.output.txt" | sed 's/^/  /'
        ((failed++))
        continue
    fi
    
    echo -e "${GREEN}PASS${NC}"
    ((passed++))
done

echo ""
echo "=========================================="
echo "测试结果"
echo "=========================================="
echo -e "总计: $total"
echo -e "${GREEN}通过: $passed${NC}"
if [ $failed -gt 0 ]; then
    echo -e "${RED}失败: $failed${NC}"
else
    echo -e "失败: $failed"
fi
echo ""

if [ $failed -eq 0 ]; then
    echo -e "${GREEN}✅ 所有测试通过！${NC}"
    echo ""
    echo "查看输出："
    echo "  ls $OUTPUT_DIR/*.output.txt"
    exit 0
else
    echo -e "${RED}❌ 有测试失败${NC}"
    echo "详细日志: $OUTPUT_DIR/"
    exit 1
fi
