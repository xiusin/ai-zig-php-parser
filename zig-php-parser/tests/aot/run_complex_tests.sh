#!/bin/bash

# AOT 复杂功能测试套件
# 测试各种高级 PHP 特性的 AOT 编译

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../.."
INTERPRETER="$PROJECT_ROOT/zig-out/bin/php-interpreter"
TEST_DIR="$SCRIPT_DIR"
OUTPUT_DIR="/tmp/aot_complex_tests"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

mkdir -p "$OUTPUT_DIR"

echo "=========================================="
echo "AOT 复杂功能测试套件"
echo "=========================================="
echo ""

# 测试用例列表
tests=(
    "test_nested_ref_foreach:嵌套引用迭代"
    "test_string_array_ops:字符串数组操作"
    "test_recursion_complex:复杂递归"
    "test_assoc_array_ref:关联数组引用"
    "test_control_flow_complex:复杂控制流"
    "test_math_bitwise:数学位运算"
)

passed=0
failed=0
total=${#tests[@]}

for test_entry in "${tests[@]}"; do
    IFS=':' read -r test_name test_desc <<< "$test_entry"
    test_file="$TEST_DIR/${test_name}.php"
    output_bin="$OUTPUT_DIR/${test_name}"
    
    echo -n "[$((passed + failed + 1))/$total] 测试: $test_desc ... "
    
    if [ ! -f "$test_file" ]; then
        echo -e "${RED}SKIP${NC} (文件不存在)"
        continue
    fi
    
    # 编译
    if ! "$INTERPRETER" --compile --output="$output_bin" "$test_file" > "$OUTPUT_DIR/${test_name}.compile.log" 2>&1; then
        echo -e "${RED}FAIL${NC} (编译失败)"
        echo "  编译日志: $OUTPUT_DIR/${test_name}.compile.log"
        ((failed++))
        continue
    fi
    
    # 运行
    if ! "$output_bin" > "$OUTPUT_DIR/${test_name}.output.txt" 2>&1; then
        echo -e "${RED}FAIL${NC} (运行失败)"
        echo "  输出: $OUTPUT_DIR/${test_name}.output.txt"
        ((failed++))
        continue
    fi
    
    echo -e "${GREEN}PASS${NC}"
    ((passed++))
    
    # 显示输出摘要
    head -n 3 "$OUTPUT_DIR/${test_name}.output.txt" | sed 's/^/  > /'
done

echo ""
echo "=========================================="
echo "测试结果汇总"
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
    exit 0
else
    echo -e "${RED}❌ 有测试失败${NC}"
    echo "详细日志位于: $OUTPUT_DIR/"
    exit 1
fi
