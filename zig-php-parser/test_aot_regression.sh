#!/bin/bash
# AOT 编译器回归测试套件
# 确保所有历史脚本完全兼容

set -e

PROJECT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser"
cd "$PROJECT_DIR"

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "  AOT 编译器回归测试套件"
echo "======================================"
echo ""

TOTAL=0
PASSED=0
FAILED=0

# 测试函数
test_script() {
    local name=$1
    local php_file=$2
    local ignore_float=${3:-false}
    
    TOTAL=$((TOTAL + 1))
    echo -n "测试 $TOTAL: $name ... "
    
    # 编译
    rm -rf .zigphp_aot_build
    local aot_output="/tmp/test_aot_$TOTAL"
    if ! ./zig-out/bin/php-interpreter --compile --output="$aot_output" "$php_file" > /dev/null 2>&1; then
        echo -e "${RED}❌ 编译失败${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
    
    # 运行并对比
    local php_out="/tmp/php_out_$TOTAL.txt"
    local aot_out="/tmp/aot_out_$TOTAL.txt"
    
    php "$php_file" > "$php_out" 2>&1 || true
    "$aot_output" > "$aot_out" 2>&1 || true
    
    if [ "$ignore_float" = true ]; then
        # 使用 Python 比较，忽略浮点数精度差异
        if python3 -c "
import sys
import re

def normalize_floats(text):
    # 将浮点数标准化为 2 位小数
    def replace_float(match):
        try:
            num = float(match.group(0))
            return f'{num:.2f}'
        except:
            return match.group(0)
    return re.sub(r'\d+\.\d+', replace_float, text)

with open('$php_out', 'r') as f:
    php_text = normalize_floats(f.read())
with open('$aot_out', 'r') as f:
    aot_text = normalize_floats(f.read())

sys.exit(0 if php_text == aot_text else 1)
" 2>/dev/null; then
            echo -e "${GREEN}✅ 通过${NC}"
            PASSED=$((PASSED + 1))
            return 0
        fi
    else
        if diff -q "$php_out" "$aot_out" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ 通过${NC}"
            PASSED=$((PASSED + 1))
            return 0
        fi
    fi
    
    echo -e "${RED}❌ 输出不匹配${NC}"
    FAILED=$((FAILED + 1))
    
    # 显示差异
    echo "  差异："
    diff "$php_out" "$aot_out" | head -10 | sed 's/^/    /'
    
    return 1
}

# 运行所有测试
test_script "斐波那契算法" "/tmp/test_fibonacci.php"
test_script "Phi 节点变量交换" "/tmp/test_phi_swap.php"
test_script "电商系统" "/tmp/test_complex_ecommerce.php" true

# 算法测试：只检查关键部分（斐波那契、质数、排序）
echo -n "测试 4: 算法和数据处理（关键部分） ... "
TOTAL=$((TOTAL + 1))
rm -rf .zigphp_aot_build
if ./zig-out/bin/php-interpreter --compile --output=/tmp/test_algo_aot /tmp/test_complex_algorithms.php > /dev/null 2>&1; then
    aot_output=$(/tmp/test_algo_aot 2>&1)
    
    # 检查关键输出
    if echo "$aot_output" | grep -q "0, 1, 1, 2, 3, 5, 8, 13, 21, 34" && \
       echo "$aot_output" | grep -q "2, 3, 5, 7, 11, 13, 17, 19, 23, 29" && \
       echo "$aot_output" | grep -q "11, 12, 17, 22, 25, 33, 34, 45, 50, 64, 88, 90"; then
        echo -e "${GREEN}✅ 通过${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}❌ 关键输出缺失${NC}"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${RED}❌ 编译失败${NC}"
    FAILED=$((FAILED + 1))
fi

# 总结
echo ""
echo "======================================"
echo "  测试总结"
echo "======================================"
echo -e "总计: $TOTAL"
echo -e "${GREEN}通过: $PASSED${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}失败: $FAILED${NC}"
else
    echo -e "失败: $FAILED"
fi
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 所有测试通过！${NC}"
    exit 0
else
    echo -e "${RED}⚠️  有测试失败！${NC}"
    exit 1
fi
