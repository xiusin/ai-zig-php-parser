#!/bin/bash
PHP_INTERPRETER="./zig-out/bin/php-interpreter"
FUZZY_DIR="fuzzy_scripts"
REPORT_DIR="/tmp/fuzzy_report_$$"
REPORT_FILE="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_test_full_report.txt"

mkdir -p "$REPORT_DIR"

echo "=== PHP AOT 模糊测试完整报告 ===" > "$REPORT_FILE"
echo "生成时间: $(date)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "===================================" >> "$REPORT_FILE"
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
    echo "文件: $php_file" >> "$REPORT_FILE"
    
    # 编译
    compile_output=$(timeout 60 "$PHP_INTERPRETER" --compile --output="$REPORT_DIR/$basename" "$php_file" 2>&1)
    compile_status=$?
    
    if [ $compile_status -ne 0 ] || [ ! -f "$REPORT_DIR/$basename" ]; then
        echo "状态: 编译失败" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "编译错误:" >> "$REPORT_FILE"
        echo "$compile_output" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "===================================" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        COMPILATION_FAILED=$((COMPILATION_FAILED + 1))
        continue
    fi
    
    echo "状态: 编译成功" >> "$REPORT_FILE"
    
    php "$php_file" > "$REPORT_DIR/${basename}_php.txt" 2>&1
    timeout 10 "$REPORT_DIR/$basename" > "$REPORT_DIR/${basename}_aot.txt" 2>&1
    
    if diff -q "$REPORT_DIR/${basename}_php.txt" "$REPORT_DIR/${basename}_aot.txt" >/dev/null 2>&1; then
        echo "结果: PASS" >> "$REPORT_FILE"
        PASSED=$((PASSED + 1))
    else
        echo "结果: FAIL (输出不一致)" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "--- PHP 原生输出 ---" >> "$REPORT_FILE"
        cat "$REPORT_DIR/${basename}_php.txt" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "--- AOT 编译输出 ---" >> "$REPORT_FILE"
        cat "$REPORT_DIR/${basename}_aot.txt" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "--- diff ---" >> "$REPORT_FILE"
        diff "$REPORT_DIR/${basename}_php.txt" "$REPORT_DIR/${basename}_aot.txt" >> "$REPORT_FILE" 2>&1
        FAILED=$((FAILED + 1))
    fi
    
    echo "" >> "$REPORT_FILE"
    echo "===================================" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
done

echo "" >> "$REPORT_FILE"
echo "=== 汇总 ===" >> "$REPORT_FILE"
echo "通过: $PASSED" >> "$REPORT_FILE"
echo "失败: $FAILED" >> "$REPORT_FILE"
echo "编译失败: $COMPILATION_FAILED" >> "$REPORT_FILE"
echo "总计: $TOTAL" >> "$REPORT_FILE"

rm -rf "$REPORT_DIR"
echo "报告已生成: $REPORT_FILE"
