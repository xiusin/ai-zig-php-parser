#!/bin/bash
# 极限基础功能测试

set -e
cd "$(dirname "$0")/.."

echo "╔════════════════════════════════════════════════════════════╗"
echo "║              极限基础功能测试                                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

TEST_FILE="/tmp/function_extreme.php"

echo "1. 解释执行（获取正确结果）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./zig-out/bin/php-interpreter "$TEST_FILE" 2>&1 | grep -v "Bytecode\|Performance\|Function calls\|Memory\|GC\|Execution\|Peak\|String intern\|Call stack\|====" > /tmp/func_expected.txt
head -20 /tmp/func_expected.txt
echo "..."
echo ""

echo "2. AOT 编译"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
rm -rf .zigphp_aot_build
if ./zig-out/bin/php-interpreter --compile --output=/tmp/function_extreme "$TEST_FILE" 2>&1 | grep -q "Success"; then
    echo "✅ 编译成功"
else
    echo "❌ 编译失败"
    exit 1
fi
echo ""

echo "3. 运行并验证结果"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
/tmp/function_extreme 2>&1 > /tmp/func_actual.txt

if diff /tmp/func_expected.txt /tmp/func_actual.txt >/dev/null 2>&1; then
    echo "✅ 输出完全一致"
    head -20 /tmp/func_actual.txt
    echo "..."
else
    echo "❌ 输出不一致"
    echo ""
    echo "期望:"
    head -10 /tmp/func_expected.txt
    echo ""
    echo "实际:"
    head -10 /tmp/func_actual.txt
    exit 1
fi
echo ""

echo "4. 代码质量检查"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ERRORS=0

if grep -E "runti[^m]|runtim[^e]" .zigphp_aot_build/main.zig >/dev/null 2>&1; then
    echo "❌ 发现截断的变量名"
    ((ERRORS++))
else
    echo "✅ 无截断的变量名"
fi

if grep -n "initInt(reg_" .zigphp_aot_build/main.zig | grep -v "asInt()" | grep -v "initInt([0-9]" >/dev/null 2>&1; then
    echo "❌ 发现缺少类型转换"
    ((ERRORS++))
else
    echo "✅ 所有类型转换正确"
fi

echo ""

echo "╔════════════════════════════════════════════════════════════╗"
echo "║                      验证结果                               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo "✅ 极限基础功能测试通过！"
    echo ""
    echo "测试覆盖："
    echo "  - 11个数学函数 (abs, sqrt, pow, round, floor, ceil, min, max)"
    echo "  - 8个字符串函数 (strlen, substr, strtoupper, strtolower, str_replace, strpos)"
    echo "  - 5个类型转换 (intval, floatval, strval)"
    echo "  - 函数组合调用"
    echo "  - 嵌套函数调用"
    echo "  - 复杂字符串操作"
    echo "  - 大量函数调用"
    echo ""
    echo "结果："
    echo "  - 编译成功"
    echo "  - 输出与解释执行完全一致"
    echo "  - 代码质量良好"
    echo "  - 编译器稳定"
    exit 0
else
    echo "❌ 发现 $ERRORS 个问题"
    exit 1
fi
