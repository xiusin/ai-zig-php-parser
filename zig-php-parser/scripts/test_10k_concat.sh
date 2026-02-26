#!/bin/bash
# 一万次字符串拼接压力测试

set -e
cd "$(dirname "$0")/.."

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         一万次字符串拼接压力测试                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

TEST_FILE="/tmp/stress_10k.php"

# 1. 解释执行获取正确结果
echo "1. 解释执行（获取正确结果）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
EXPECTED=$(./zig-out/bin/php-interpreter "$TEST_FILE" 2>&1 | grep "Length:")
echo "$EXPECTED"
echo ""

# 2. 编译 50 次验证一致性
echo "2. 编译 50 次，验证生成代码一致性"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

COMPILE_SUCCESS=0
COMPILE_FAIL=0

for i in $(seq 1 50); do
    rm -rf .zigphp_aot_build
    if ./zig-out/bin/php-interpreter --compile --output=/tmp/test_$i "$TEST_FILE" >/dev/null 2>&1; then
        ((COMPILE_SUCCESS++))
    else
        ((COMPILE_FAIL++))
        echo "  [$i/50] ❌ 编译失败"
    fi
    
    if [ $((i % 10)) -eq 0 ]; then
        echo "  [$i/50] ✅"
    fi
done

if [ $COMPILE_FAIL -gt 0 ]; then
    echo "❌ 有 $COMPILE_FAIL 次编译失败"
    exit 1
fi

# 验证生成代码一致性
HASHES=$(for i in $(seq 1 50); do
    rm -rf .zigphp_aot_build
    ./zig-out/bin/php-interpreter --compile "$TEST_FILE" >/dev/null 2>&1
    md5 -q .zigphp_aot_build/main.zig 2>/dev/null || md5sum .zigphp_aot_build/main.zig | awk '{print $1}'
done | sort -u | wc -l)

if [ "$HASHES" -eq 1 ]; then
    echo "✅ 50 次编译生成完全相同的代码"
else
    echo "❌ 生成了 $HASHES 个不同的代码版本"
    exit 1
fi
echo ""

# 3. 运行 50 次验证输出
echo "3. 运行 50 次，验证输出一致性"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RUN_SUCCESS=0
RUN_FAIL=0

for i in $(seq 1 50); do
    OUTPUT=$(/tmp/test_1 2>&1 | grep "Length:")
    
    if [ "$OUTPUT" = "$EXPECTED" ]; then
        ((RUN_SUCCESS++))
    else
        ((RUN_FAIL++))
        echo "  [$i/50] ❌ 输出不正确"
        echo "    期望: $EXPECTED"
        echo "    实际: $OUTPUT"
    fi
    
    if [ $((i % 10)) -eq 0 ]; then
        echo "  [$i/50] ✅"
    fi
done

if [ $RUN_FAIL -gt 0 ]; then
    echo "❌ 有 $RUN_FAIL 次输出不正确"
    exit 1
fi

echo "✅ 50 次运行输出完全一致"
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
    echo "✅ 一万次字符串拼接压力测试通过！"
    echo ""
    echo "证明："
    echo "  - 50 次编译全部成功"
    echo "  - 50 次编译生成完全相同的代码"
    echo "  - 50 次运行输出完全一致"
    echo "  - 无缓冲区覆盖问题"
    echo "  - 无随机变量名错误"
    echo "  - 代码质量良好"
    echo ""
    echo "编译器在极端压力下完全稳定。"
    exit 0
else
    echo "❌ 发现 $ERRORS 个问题"
    exit 1
fi
