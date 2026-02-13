#!/bin/bash
# AOT 测试套件运行器

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../.."
SUITE_DIR="$SCRIPT_DIR/suite"
COMPILER="$PROJECT_ROOT/zig-out/bin/php-interpreter"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

passed=0
failed=0
total=0

echo "=== AOT 测试套件 ==="
echo "编译器: $COMPILER"
echo "测试目录: $SUITE_DIR"
echo ""

# 清理旧的编译产物
rm -rf "$PROJECT_ROOT/.zigphp_aot_build"

# 遍历所有测试文件
for test_file in "$SUITE_DIR"/*.php; do
    if [ ! -f "$test_file" ]; then
        continue
    fi
    
    test_name=$(basename "$test_file" .php)
    total=$((total + 1))
    
    echo -n "[$total] $test_name ... "
    
    # 1. 用 PHP 运行获取期望输出
    expected=$(php "$test_file" 2>&1)
    php_exit=$?
    
    # 2. AOT 编译
    if ! "$COMPILER" --compile "$test_file" > /dev/null 2>&1; then
        echo -e "${RED}FAIL${NC} (编译失败)"
        failed=$((failed + 1))
        "$COMPILER" --compile "$test_file" 2>&1 | tail -5
        continue
    fi
    
    # 3. 运行编译后的程序
    exe_name="$PROJECT_ROOT/$test_name"
    if [ ! -f "$exe_name" ]; then
        echo -e "${RED}FAIL${NC} (可执行文件不存在)"
        failed=$((failed + 1))
        continue
    fi
    
    actual=$("$exe_name" 2>&1)
    aot_exit=$?
    
    # 4. 比较输出
    if [ "$expected" = "$actual" ] && [ $php_exit -eq $aot_exit ]; then
        echo -e "${GREEN}PASS${NC}"
        passed=$((passed + 1))
    else
        echo -e "${RED}FAIL${NC}"
        failed=$((failed + 1))
        echo "  期望: $expected"
        echo "  实际: $actual"
    fi
    
    # 清理
    rm -f "$exe_name"
done

echo ""
echo "=== 测试结果 ==="
echo -e "通过: ${GREEN}$passed${NC}"
echo -e "失败: ${RED}$failed${NC}"
echo "总计: $total"

if [ $failed -eq 0 ]; then
    echo -e "\n${GREEN}✓ 所有测试通过${NC}"
    exit 0
else
    echo -e "\n${RED}✗ 有测试失败${NC}"
    exit 1
fi
