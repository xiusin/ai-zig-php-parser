#!/bin/bash
# 快速扫描并执行 PHP 示例程序

INTERPRETER="./zig-out/bin/php-interpreter"
EXAMPLES_DIR="./examples"
OUTPUT_DIR="./test_results"
mkdir -p "$OUTPUT_DIR"

# 需要排除的程序（可能导致无限循环或需要长时间运行）
EXCLUDE_LIST=("http_server" "benchmark" "concurrent_demo")

is_excluded() {
    local file=$1
    for excl in "${EXCLUDE_LIST[@]}"; do
        if [[ $file == *"$excl"* ]]; then
            return 0
        fi
    done
    return 1
}

echo "开始扫描和执行 PHP 示例程序..."
echo "================================"

# 清空结果文件
> "$OUTPUT_DIR/executed_files.txt"
> "$OUTPUT_DIR/failed_files.txt"
> "$OUTPUT_DIR/debug_info.txt"
> "$OUTPUT_DIR/summary.txt"

count=0
success=0
failed=0
debug_count=0
excluded=0
total=0

for file in "$EXAMPLES_DIR"/*.php; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")

        if is_excluded "$file"; then
            echo "⏭️  跳过: $filename (排除)"
            ((excluded++))
            continue
        fi

        ((total++))
        echo -n "[$total] $filename ... "

        # 执行并捕获输出（超时3秒）
        output=$(timeout 3 "$INTERPRETER" "$file" 2>&1)
        exit_code=$?

        echo "$filename" >> "$OUTPUT_DIR/executed_files.txt"

        if [ $exit_code -eq 124 ]; then
            echo "⏱️  超时"
            echo "========================================" >> "$OUTPUT_DIR/failed_files.txt"
            echo "文件: $file" >> "$OUTPUT_DIR/failed_files.txt"
            echo "状态: 超时" >> "$OUTPUT_DIR/failed_files.txt"
            ((failed++))
        elif [ $exit_code -ne 0 ]; then
            echo "❌ 失败"
            echo "========================================" >> "$OUTPUT_DIR/failed_files.txt"
            echo "文件: $file" >> "$OUTPUT_DIR/failed_files.txt"
            echo "退出码: $exit_code" >> "$OUTPUT_DIR/failed_files.txt"
            echo "输出:" >> "$OUTPUT_DIR/failed_files.txt"
            echo "$output" >> "$OUTPUT_DIR/failed_files.txt"
            ((failed++))
        else
            echo "✅"
            ((success++))
        fi

        # 检查 DEBUG/TODO 信息
        if echo "$output" | grep -qiE "DEBUG|debug|TODO|FIXME|未实现|not implemented|WARN|warn"; then
            echo "  ⚠️  包含 DEBUG/WARN 信息"
            echo "========================================" >> "$OUTPUT_DIR/debug_info.txt"
            echo "文件: $file" >> "$OUTPUT_DIR/debug_info.txt"
            echo "输出:" >> "$OUTPUT_DIR/debug_info.txt"
            echo "$output" >> "$OUTPUT_DIR/debug_info.txt"
            echo "" >> "$OUTPUT_DIR/debug_info.txt"
            ((debug_count++))
        fi
    fi
done

echo ""
echo "================================"
echo "执行完成!"
echo "总文件数: $total"
echo "成功: $success"
echo "失败: $failed"
echo "跳过: $excluded"
echo "包含 DEBUG 信息: $debug_count"

# 生成摘要
cat > "$OUTPUT_DIR/summary.txt" << EOF
扫描摘要
================================
扫描时间: $(date)
总文件数: $total
成功执行: $success
失败: $failed
跳过（排除）: $excluded
包含 DEBUG/TODO/WARN 信息: $debug_count

排除的程序: http_server, benchmark, concurrent_demo
EOF

echo ""
echo "结果已保存到 $OUTPUT_DIR 目录"