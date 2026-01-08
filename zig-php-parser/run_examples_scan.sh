#!/bin/bash

# 扫描 examples/ 目录下的所有 PHP 文件并执行测试

PHP_INTERPRETER="./zig-out/bin/php-interpreter"
RESULTS_DIR="./test_results"
DEBUG_INFO_FILE="$RESULTS_DIR/debug_info.txt"
MEMORY_ERRORS_FILE="$RESULTS_DIR/memory_errors.txt"
SUMMARY_FILE="$RESULTS_DIR/summary.txt"
EXECUTED_FILE="$RESULTS_DIR/executed_files.txt"
FAILED_FILE="$RESULTS_DIR/failed_files.txt"

# 创建结果目录
mkdir -p "$RESULTS_DIR"

# 清空文件
> "$DEBUG_INFO_FILE"
> "$MEMORY_ERRORS_FILE"
> "$SUMMARY_FILE"
> "$EXECUTED_FILE"
> "$FAILED_FILE"

echo "开始扫描 examples/ 目录下的 PHP 文件..."
echo "========================================" | tee -a "$SUMMARY_FILE"

TOTAL=0
SUCCESS=0
FAILED=0
DEBUG_COUNT=0

# 遍历所有 PHP 文件
for php_file in examples/*.php; do
    if [ ! -f "$php_file" ]; then
        continue
    fi

    filename=$(basename "$php_file")
    TOTAL=$((TOTAL + 1))

    echo "[$TOTAL] 正在执行: $filename" | tee -a "$SUMMARY_FILE"

    # 执行 PHP 文件，捕获输出和错误（5秒超时）
    output=$(timeout 5 "$PHP_INTERPRETER" "$php_file" 2>&1)
    exit_code=$?

    # 检查是否超时
    if [ $exit_code -eq 124 ]; then
        echo "[超时] $filename 执行超过 5 秒" | tee -a "$SUMMARY_FILE"
        FAILED=$((FAILED + 1))
        echo "$php_file (超时)" >> "$FAILED_FILE"
        continue
    fi

    # 记录执行的脚本
    echo "$php_file (退出码: $exit_code)" >> "$EXECUTED_FILE"

    # 检查是否有 DEBUG 信息（ZIG 端未实现功能的标记）
    if echo "$output" | grep -qi "DEBUG\|TODO\|FIXME\|未实现\|TODO\|not implemented"; then
        DEBUG_COUNT=$((DEBUG_COUNT + 1))
        echo "=== $filename (包含 DEBUG/未实现信息) ===" >> "$DEBUG_INFO_FILE"
        echo "$output" >> "$DEBUG_INFO_FILE"
        echo "----------------------------------------" >> "$DEBUG_INFO_FILE"
        echo "[注意] $filename 包含 DEBUG/未实现信息" | tee -a "$SUMMARY_FILE"
    fi

    # 检查退出码
    if [ $exit_code -ne 0 ]; then
        FAILED=$((FAILED + 1))
        echo "=== $filename (失败) ===" >> "$FAILED_FILE"
        echo "退出码: $exit_code" >> "$FAILED_FILE"
        echo "输出: $output" >> "$FAILED_FILE"
        echo "----------------------------------------" >> "$FAILED_FILE"
        echo "[失败] $filename (退出码: $exit_code)" | tee -a "$SUMMARY_FILE"
    else
        SUCCESS=$((SUCCESS + 1))
    fi

    # 简短输出显示
    if [ $exit_code -eq 0 ]; then
        echo "  -> 成功" | tee -a "$SUMMARY_FILE"
    else
        echo "  -> 失败" | tee -a "$SUMMARY_FILE"
    fi
done

echo "" | tee -a "$SUMMARY_FILE"
echo "========================================" | tee -a "$SUMMARY_FILE"
echo "执行完成!" | tee -a "$SUMMARY_FILE"
echo "总文件数: $TOTAL" | tee -a "$SUMMARY_FILE"
echo "成功: $SUCCESS" | tee -a "$SUMMARY_FILE"
echo "失败: $FAILED" | tee -a "$SUMMARY_FILE"
echo "包含 DEBUG 信息的文件: $DEBUG_COUNT" | tee -a "$SUMMARY_FILE"
echo "========================================" | tee -a "$SUMMARY_FILE"

# 输出 DEBUG 信息文件位置
if [ $DEBUG_COUNT -gt 0 ]; then
    echo "" | tee -a "$SUMMARY_FILE"
    echo "包含 DEBUG 信息的文件已保存到: $DEBUG_INFO_FILE" | tee -a "$SUMMARY_FILE"
fi

# 输出失败文件位置
if [ $FAILED -gt 0 ]; then
    echo "失败的文件列表已保存到: $FAILED_FILE" | tee -a "$SUMMARY_FILE"
fi

echo "" | tee -a "$SUMMARY_FILE"
echo "详细结果请查看 $RESULTS_DIR 目录下的文件"
