#!/bin/bash
# 精准测试指定脚本 - 只测试修复的脚本，不浪费时间

set -e

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser"
cd "$SCRIPT_DIR"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 统计变量
PASS=0
FAIL=0
TOTAL=0

# 测试单个脚本
test_script() {
    local script="$1"
    local name=$(basename "$script")
    
    TOTAL=$((TOTAL + 1))
    echo -n "[$TOTAL] Testing: $name ... "
    
    # 编译
    timeout 10 ./zig-out/bin/php-interpreter --compile "$script" --output=/tmp/test_$$ 2>&1 > /tmp/compile_$$.log
    
    if [ ! -f /tmp/test_$$ ]; then
        echo -e "${RED}COMPILE_FAIL${NC}"
        FAIL=$((FAIL + 1))
        rm -f /tmp/compile_$$.log
        return
    fi
    
    # 运行AOT
    timeout 5 /tmp/test_$$ > /tmp/aot_output_$$ 2>&1 || true
    
    # 运行PHP
    timeout 5 php "$script" > /tmp/php_output_$$ 2>&1 || true
    
    # 对比输出
    if diff -q /tmp/aot_output_$$ /tmp/php_output_$$ > /dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${YELLOW}MISMATCH${NC}"
        FAIL=$((FAIL + 1))
    fi
    
    # 清理
    rm -f /tmp/test_$$ /tmp/aot_output_$$ /tmp/php_output_$$ /tmp/compile_$$.log
}

# 主函数
main() {
    if [ $# -eq 0 ]; then
        echo "Usage: $0 <script1.php> [script2.php] ..."
        echo "Example: $0 fuzzy_scripts/test_076_shell_exec.php"
        exit 1
    fi
    
    echo "=== 精准测试开始 ==="
    echo ""
    
    for script in "$@"; do
        test_script "$script"
    done
    
    echo ""
    echo "=== 测试结果 ==="
    echo -e "总计: $TOTAL"
    echo -e "${GREEN}PASS: $PASS${NC}"
    echo -e "${RED}FAIL: $FAIL${NC}"
    if [ $TOTAL -gt 0 ]; then
        RATE=$(echo "scale=1; ($PASS * 100) / $TOTAL" | bc)
        echo -e "通过率: ${RATE}%"
    fi
}

main "$@"
