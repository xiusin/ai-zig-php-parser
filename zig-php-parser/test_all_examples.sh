#!/bin/bash

# 测试所有 examples 中的 PHP 脚本
# 检查是否有错误和内存泄露

INTERPRETER="./zig-out/bin/php-interpreter"
EXAMPLES_DIR="examples"
LOG_FILE="test_results.log"
SUMMARY_FILE="test_summary.txt"

# 清空日志文件
> "$LOG_FILE"
> "$SUMMARY_FILE"

# 统计变量
TOTAL=0
PASSED=0
FAILED=0
MEMORY_LEAKS=0

echo "========================================" | tee -a "$SUMMARY_FILE"
echo "PHP 脚本测试报告" | tee -a "$SUMMARY_FILE"
echo "========================================" | tee -a "$SUMMARY_FILE"
echo "" | tee -a "$SUMMARY_FILE"

# 获取所有 PHP 文件
PHP_FILES=$(find "$EXAMPLES_DIR" -name "*.php" -type f | sort)

# 逐个执行 PHP 文件
for php_file in $PHP_FILES; do
    TOTAL=$((TOTAL + 1))
    filename=$(basename "$php_file")

    echo "测试: $filename" | tee -a "$SUMMARY_FILE"
    echo "----------------------------------------" | tee -a "$SUMMARY_FILE"

    # 执行 PHP 文件
    output=$($INTERPRETER "$php_file" 2>&1)
    exit_code=$?

    # 检查是否有错误
    if [ $exit_code -ne 0 ]; then
        echo "❌ 失败 - 退出码: $exit_code" | tee -a "$SUMMARY_FILE"
        echo "$output" | tee -a "$SUMMARY_FILE"
        FAILED=$((FAILED + 1))
    else
        # 检查是否有内存泄露
        if echo "$output" | grep -q "memory address.*leaked"; then
            echo "⚠️  内存泄露" | tee -a "$SUMMARY_FILE"
            echo "$output" | grep "memory address.*leaked" | tee -a "$SUMMARY_FILE"
            MEMORY_LEAKS=$((MEMORY_LEAKS + 1))
            FAILED=$((FAILED + 1))
        else
            echo "✓ 通过" | tee -a "$SUMMARY_FILE"
            PASSED=$((PASSED + 1))
        fi
    fi

    echo "" | tee -a "$SUMMARY_FILE"

    # 保存完整输出到日志
    echo "=== $filename ===" >> "$LOG_FILE"
    echo "$output" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
done

# 生成总结
echo "========================================" | tee -a "$SUMMARY_FILE"
echo "测试总结" | tee -a "$SUMMARY_FILE"
echo "========================================" | tee -a "$SUMMARY_FILE"
echo "总测试数: $TOTAL" | tee -a "$SUMMARY_FILE"
echo "通过: $PASSED" | tee -a "$SUMMARY_FILE"
echo "失败: $FAILED" | tee -a "$SUMMARY_FILE"
echo "内存泄露: $MEMORY_LEAKS" | tee -a "$SUMMARY_FILE"
echo "覆盖率: $((PASSED * 100 / TOTAL))%" | tee -a "$SUMMARY_FILE"
echo "========================================" | tee -a "$SUMMARY_FILE"

# 如果有失败，返回非零退出码
if [ $FAILED -gt 0 ]; then
    exit 1
fi

exit 0