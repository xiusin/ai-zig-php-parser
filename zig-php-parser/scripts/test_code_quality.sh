#!/bin/bash
# 验证生成的代码质量
# 检查是否有常见的错误模式

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== 生成代码质量验证 ==="
echo ""

# 测试文件
TEST_FILE="/tmp/test_concat_int.php"

if [ ! -f "$TEST_FILE" ]; then
    cat > "$TEST_FILE" << 'EOF'
<?php
$x = 42;
echo "Value: " . $x . "\n";
EOF
fi

# 编译
rm -rf .zigphp_aot_build
./zig-out/bin/php-interpreter --compile --output=/tmp/quality_test "$TEST_FILE" >/dev/null 2>&1

if [ ! -f ".zigphp_aot_build/main.zig" ]; then
    echo "❌ 编译失败"
    exit 1
fi

GENERATED_CODE=".zigphp_aot_build/main.zig"

echo "检查生成的代码..."
echo ""

ERRORS=0

# 检查 1: 不应该有 initInt(reg_) 而没有 asInt()
echo "检查 1: initInt(reg_) 必须有 .asInt()"
if grep -n "initInt(reg_" "$GENERATED_CODE" | grep -v "asInt()" | grep -v "initInt(42)" | grep -v "initInt(0)" | grep -v "initInt(1)"; then
    echo "  ❌ 发现 initInt(reg_) 没有 .asInt()"
    ((ERRORS++))
else
    echo "  ✅ 通过"
fi
echo ""

# 检查 2: 不应该有 initFloat(reg_) 而没有 asFloat()
echo "检查 2: initFloat(reg_) 必须有 .asFloat()"
if grep -n "initFloat(reg_" "$GENERATED_CODE" | grep -v "asFloat()"; then
    echo "  ❌ 发现 initFloat(reg_) 没有 .asFloat()"
    ((ERRORS++))
else
    echo "  ✅ 通过"
fi
echo ""

# 检查 3: 不应该有 initBool(reg_) 而没有 toBool()
echo "检查 3: initBool(reg_) 必须有 .toBool()"
if grep -n "initBool(reg_" "$GENERATED_CODE" | grep -v "toBool()"; then
    echo "  ❌ 发现 initBool(reg_) 没有 .toBool()"
    ((ERRORS++))
else
    echo "  ✅ 通过"
fi
echo ""

# 检查 4: 不应该有截断的变量名（如 runti, runtim）
echo "检查 4: 不应该有截断的变量名"
if grep -E "runti[^m]|runtim[^e]" "$GENERATED_CODE"; then
    echo "  ❌ 发现截断的变量名"
    ((ERRORS++))
else
    echo "  ✅ 通过"
fi
echo ""

# 检查 5: 所有 reg_ 引用都应该是完整的
echo "检查 5: 所有 reg_ 引用都应该是完整的"
if grep -oE "reg_[0-9]+" "$GENERATED_CODE" | sort -u > /tmp/regs.txt; then
    INCOMPLETE=$(grep -E "reg_[^0-9]" "$GENERATED_CODE" || true)
    if [ -n "$INCOMPLETE" ]; then
        echo "  ❌ 发现不完整的 reg_ 引用"
        echo "$INCOMPLETE"
        ((ERRORS++))
    else
        echo "  ✅ 通过"
    fi
else
    echo "  ✅ 通过（没有寄存器）"
fi
echo ""

# 检查 6: 验证代码可以编译
echo "检查 6: 验证生成的代码可以编译"
if /tmp/quality_test >/dev/null 2>&1; then
    echo "  ✅ 通过"
else
    echo "  ❌ 生成的代码无法运行"
    /tmp/quality_test 2>&1 | head -5
    ((ERRORS++))
fi
echo ""

# 检查 7: 验证输出正确
echo "检查 7: 验证输出正确"
EXPECTED="Value: 42"
ACTUAL=$(/tmp/quality_test 2>&1)
if echo "$ACTUAL" | grep -q "$EXPECTED"; then
    echo "  ✅ 通过"
else
    echo "  ❌ 输出不正确"
    echo "  期望: $EXPECTED"
    echo "  实际: $ACTUAL"
    ((ERRORS++))
fi
echo ""

echo "=== 验证结果 ==="
if [ $ERRORS -eq 0 ]; then
    echo "✅ 所有检查通过！生成的代码质量良好。"
    exit 0
else
    echo "❌ 发现 $ERRORS 个问题。"
    exit 1
fi
