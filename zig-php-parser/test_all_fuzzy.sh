#!/bin/bash
# 批量测试模糊测试脚本 - 仅报告，不删除

PHP_INTERPRETER="./zig-out/bin/php-interpreter"
FUZZY_DIR="fuzzy_scripts"
TMP_DIR="/tmp/fuzzy_test_$$"

mkdir -p "$TMP_DIR"

PASSED=0
FAILED=0
COMPILATION_FAILED=0
DIFFERENT_OUTPUT=0

for php_file in "$FUZZY_DIR"/test_*.php; do
    if [ ! -f "$php_file" ]; then
        continue
    fi
    
    basename=$(basename "$php_file" .php)
    
    # 编译
    compile_output=$(timeout 60 "$PHP_INTERPRETER" --compile --output="$TMP_DIR/$basename" "$php_file" 2>&1)
    compile_status=$?
    
    if [ $compile_status -ne 0 ] || [ ! -f "$TMP_DIR/$basename" ]; then
        echo "[COMPILATION FAILED] $basename"
        echo "  Error: $compile_output"
        COMPILATION_FAILED=$((COMPILATION_FAILED + 1))
        continue
    fi
    
    # PHP 原生输出
    php "$php_file" > "$TMP_DIR/${basename}_php.txt" 2>&1
    
    # AOT 输出
    timeout 10 "$TMP_DIR/$basename" > "$TMP_DIR/${basename}_aot.txt" 2>&1
    
    # 对比
    if diff -q "$TMP_DIR/${basename}_php.txt" "$TMP_DIR/${basename}_aot.txt" >/dev/null 2>&1; then
        echo "[PASS] $basename"
        PASSED=$((PASSED + 1))
    else
        echo "[DIFFERENT OUTPUT] $basename"
        DIFFERENT_OUTPUT=$((DIFFERENT_OUTPUT + 1))
        # 显示前5行差异
        echo "  Diff (first 5 lines):"
        diff "$TMP_DIR/${basename}_php.txt" "$TMP_DIR/${basename}_aot.txt" 2>&1 | head -5 | sed 's/^/    /'
    fi
done

echo ""
echo "================================"
echo "Results:"
echo "  PASSED: $PASSED"
echo "  DIFFERENT OUTPUT: $DIFFERENT_OUTPUT"
echo "  COMPILATION_FAILED: $COMPILATION_FAILED"
echo "================================"

# 清理
rm -rf "$TMP_DIR"
