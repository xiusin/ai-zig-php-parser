#!/bin/bash
# 对每个失败的测试归类错误原因

PHP_INTERPRETER="./zig-out/bin/php-interpreter"
FUZZY_DIR="fuzzy_scripts"
TMP_DIR="/tmp/cat_err_$$"
CAT_FILE="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/error_categories.md"

mkdir -p "$TMP_DIR"
> "$CAT_FILE"

echo "# 失败脚本错误归类" >> "$CAT_FILE"
echo "" >> "$CAT_FILE"
echo "| 脚本 | 第一个关键差异 | 类别 |" >> "$CAT_FILE"
echo "|------|----------------|------|" >> "$CAT_FILE"

for php_file in "$FUZZY_DIR"/test_*.php; do
    [ -f "$php_file" ] || continue
    basename=$(basename "$php_file" .php)
    
    timeout 60 "$PHP_INTERPRETER" --compile --output="$TMP_DIR/$basename" "$php_file" 2>/dev/null
    
    php "$php_file" > "$TMP_DIR/${basename}_php.txt" 2>&1
    timeout 10 "$TMP_DIR/$basename" > "$TMP_DIR/${basename}_aot.txt" 2>&1
    
    # 归类分析
    aot_first=$(head -5 "$TMP_DIR/${basename}_aot.txt" | tr '\n' ' ' | cut -c1-200)
    php_first=$(head -5 "$TMP_DIR/${basename}_php.txt" | tr '\n' ' ' | cut -c1-200)
    
    category="OTHER"
    if echo "$aot_first" | grep -q "Parse error: Unexpected token"; then
        category="AOT-PARSE-ERROR"
    elif echo "$aot_first" | grep -q "Call to undefined function"; then
        fn=$(echo "$aot_first" | grep -oE "undefined function [a-zA-Z_]+" | head -1)
        category="UNDEFINED-FN: $fn"
    elif echo "$aot_first" | grep -q "Call to a member function on a non-object"; then
        category="NON-OBJECT-METHOD"
    elif echo "$php_first" | grep -q "PHP Fatal error" && ! echo "$aot_first" | grep -q "Fatal error"; then
        category="MISSING-PHP-FATAL"
    elif echo "$php_first" | grep -q "PHP Parse error" && ! echo "$aot_first" | grep -q "Parse error"; then
        category="MISSING-PHP-PARSE-ERR"
    elif echo "$aot_first" | grep -q "error:" && echo "$aot_first" | grep -q "zig"; then
        category="ZIG-COMPILE-ERROR"
    else
        # 取首个真实差异
        first_diff=$(diff "$TMP_DIR/${basename}_php.txt" "$TMP_DIR/${basename}_aot.txt" 2>&1 | head -4 | tr '\n' '|' | cut -c1-150)
        category="OUTPUT-DIFF: $first_diff"
    fi
    
    # Escape pipes in category
    cat_escaped=$(echo "$category" | sed 's/|/\\|/g')
    echo "| $basename | - | $cat_escaped |" >> "$CAT_FILE"
done

rm -rf "$TMP_DIR"
echo "归类完成: $CAT_FILE"
cat "$CAT_FILE"
