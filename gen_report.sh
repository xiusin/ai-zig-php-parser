#!/bin/bash
PHP_INTERPRETER="./zig-out/bin/php-interpreter"
FUZZY_DIR="fuzzy_scripts"
REPORT_DIR="/tmp/fuzzy_report_$$"
REPORT_FILE="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_test_full_report.txt"

mkdir -p "$REPORT_DIR"
> "$REPORT_FILE"
echo "=== PHP AOT 模糊测试完整报告 ===" >> "$REPORT_FILE"
echo "生成时间: $(date)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

PASSED=0
FAILED=0
COMPILATION_FAILED=0
TOTAL=0

for php_file in "$FUZZY_DIR"/test_*.php; do
    [ -f "$php_file" ] || continue
    TOTAL=$((TOTAL + 1))
    basename=$(basename "$php_file" .php)
    
    echo "=== [$basename] ===" >> "$REPORT_FILE"
    
    compile_output=$(timeout 60 "$PHP_INTERPRETER" --compile --output="$REPORT_DIR/$basename" "$php_file" 2>&1)
    compile_status=$?
    
    if [ $compile_status -ne 0 ] || [ ! -f "$REPORT_DIR/$basename" ]; then
        echo "状态: 编译失败" >> "$REPORT_FILE"
        echo "$compile_output" >> "$REPORT_FILE"
        COMPILATION_FAILED=$((COMPILATION_FAILED + 1))
        echo "" >> "$REPORT_FILE"
        continue
    fi
    
    php "$php_file" > "$REPORT_DIR/${basename}_php.txt" 2>&1
    timeout 10 "$REPORT_DIR/$basename" > "$REPORT_DIR/${basename}_aot.txt" 2>&1
    
    # 忽略缩进差异和时间戳差异
    sed 's/^[ \t]*//' "$REPORT_DIR/${basename}_php.txt" | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}/TIME/g' > "$REPORT_DIR/${basename}_php_n.txt"
    sed 's/^[ \t]*//' "$REPORT_DIR/${basename}_aot.txt" | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}/TIME/g' > "$REPORT_DIR/${basename}_aot_n.txt"
    
    if diff -q "$REPORT_DIR/${basename}_php_n.txt" "$REPORT_DIR/${basename}_aot_n.txt" >/dev/null 2>&1; then
        echo "结果: PASS (忽略缩进/时间戳)" >> "$REPORT_FILE"
        PASSED=$((PASSED + 1))
        rm -f "$php_file"
        echo "已删除: $php_file" >> "$REPORT_FILE"
    else
        echo "结果: FAIL" >> "$REPORT_FILE"
        echo "--- PHP ---" >> "$REPORT_FILE"
        cat "$REPORT_DIR/${basename}_php.txt" >> "$REPORT_FILE"
        echo "--- AOT ---" >> "$REPORT_FILE"
        cat "$REPORT_DIR/${basename}_aot.txt" >> "$REPORT_FILE"
        echo "--- diff ---" >> "$REPORT_FILE"
        diff "$REPORT_DIR/${basename}_php.txt" "$REPORT_DIR/${basename}_aot.txt" >> "$REPORT_FILE" 2>&1
        FAILED=$((FAILED + 1))
    fi
    echo "" >> "$REPORT_FILE"
done

echo "=== 汇总 ===" >> "$REPORT_FILE"
echo "通过: $PASSED / 失败: $FAILED / 编译失败: $COMPILATION_FAILED / 总计: $TOTAL" >> "$REPORT_FILE"
rm -rf "$REPORT_DIR"
echo "PASSED=$PASSED FAILED=$FAILED COMPILATION_FAILED=$COMPILATION_FAILED TOTAL=$TOTAL"
