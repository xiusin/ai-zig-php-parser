#!/bin/bash
# 使用 PHP CLI 验证编译器正确性

set -e

TEST_FILE="$1"
if [ -z "$TEST_FILE" ]; then
    echo "Usage: $0 <test.php>"
    exit 1
fi

echo "=== 验证测试: $(basename $TEST_FILE) ==="
echo ""

# 1. PHP CLI 执行（标准参考）
echo "1. PHP CLI 执行..."
php "$TEST_FILE" > /tmp/php_cli_output.txt 2>&1
echo "✅ PHP CLI 完成"

# 2. 解释器执行
echo "2. 解释器执行..."
./zig-out/bin/php-interpreter "$TEST_FILE" 2>&1 | grep -v "Bytecode\|Performance\|Function calls\|Memory\|GC\|Execution\|Peak\|String intern\|Call stack\|====" > /tmp/interpreter_output.txt
echo "✅ 解释器完成"

# 3. AOT 编译
echo "3. AOT 编译..."
rm -rf .zigphp_aot_build
OUTPUT_NAME="/tmp/$(basename $TEST_FILE .php)"
./zig-out/bin/php-interpreter --compile --output="$OUTPUT_NAME" "$TEST_FILE" 2>&1 | tail -3
if [ ! -f "$OUTPUT_NAME" ]; then
    echo "❌ 编译失败"
    exit 1
fi
echo "✅ 编译完成"

# 4. AOT 执行
echo "4. AOT 执行..."
"$OUTPUT_NAME" > /tmp/aot_output.txt 2>&1
echo "✅ AOT 完成"

# 5. 对比结果（忽略空行差异）
echo ""
echo "=== 结果对比 ==="

# 移除空行
sed '/^$/d' /tmp/php_cli_output.txt > /tmp/php_cli_clean.txt
sed '/^$/d' /tmp/interpreter_output.txt > /tmp/interpreter_clean.txt
sed '/^$/d' /tmp/aot_output.txt > /tmp/aot_clean.txt

# PHP CLI vs 解释器
if diff /tmp/php_cli_clean.txt /tmp/interpreter_clean.txt > /dev/null 2>&1; then
    echo "✅ 解释器 vs PHP CLI: 一致"
else
    echo "❌ 解释器 vs PHP CLI: 不一致"
    echo "差异:"
    diff /tmp/php_cli_clean.txt /tmp/interpreter_clean.txt || true
    exit 1
fi

# PHP CLI vs AOT
if diff /tmp/php_cli_clean.txt /tmp/aot_clean.txt > /dev/null 2>&1; then
    echo "✅ AOT vs PHP CLI: 一致"
else
    echo "❌ AOT vs PHP CLI: 不一致"
    echo "差异:"
    diff /tmp/php_cli_clean.txt /tmp/aot_clean.txt || true
    exit 1
fi

echo ""
echo "🎉 所有输出完全一致！"
