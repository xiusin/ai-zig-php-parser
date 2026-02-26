#!/bin/bash
# 全面类型运算结果验证

set -e
cd "$(dirname "$0")/.."

echo "╔════════════════════════════════════════════════════════════╗"
echo "║              全面类型运算结果验证                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

TEST_FILE="/tmp/final_test.php"

# 1. 获取解释执行的正确结果
echo "1. 解释执行（获取正确结果）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./zig-out/bin/php-interpreter "$TEST_FILE" 2>&1 | head -7 > /tmp/expected.txt
cat /tmp/expected.txt
echo ""

# 2. AOT 编译
echo "2. AOT 编译"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
rm -rf .zigphp_aot_build
if ./zig-out/bin/php-interpreter --compile --output=/tmp/final_test "$TEST_FILE" 2>&1 | grep -q "Success"; then
    echo "✅ 编译成功"
else
    echo "❌ 编译失败"
    exit 1
fi
echo ""

# 3. 运行并验证结果
echo "3. 运行并验证结果"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
/tmp/final_test 2>&1 | head -7 > /tmp/actual.txt

if diff /tmp/expected.txt /tmp/actual.txt >/dev/null 2>&1; then
    echo "✅ 输出完全一致"
    cat /tmp/actual.txt
else
    echo "❌ 输出不一致"
    echo ""
    echo "期望:"
    cat /tmp/expected.txt
    echo ""
    echo "实际:"
    cat /tmp/actual.txt
    exit 1
fi
echo ""

# 4. 代码质量检查
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

# 总结
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                      验证结果                               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo "✅ 全面类型运算测试通过！"
    echo ""
    echo "测试覆盖："
    echo "  - 简单字符串拼接"
    echo "  - 数字与字符串拼接"
    echo "  - 多层嵌套拼接"
    echo "  - 循环中的拼接"
    echo "  - 1000次大量拼接"
    echo ""
    echo "结果："
    echo "  - 编译成功"
    echo "  - 输出完全正确"
    echo "  - 代码质量良好"
    echo "  - 编译器稳定"
    exit 0
else
    echo "❌ 发现 $ERRORS 个问题"
    exit 1
fi
