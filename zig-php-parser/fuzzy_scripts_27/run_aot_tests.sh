#!/bin/bash
set -e

AOT="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts_27"
ERROR_LOG="$SCRIPT_DIR/error_log_$(date +%Y%m%d_%H%M%S).md"
PASSED=0
FAILED=0
TOTAL=0

echo "| 脚本内容 | PHP命令正确结果 | AOT执行输出结果/错误信息/警告信息 |" > "$ERROR_LOG"
echo "|----------|----------------|-----------------------------------|" >> "$ERROR_LOG"

for script in "$SCRIPT_DIR"/test_*.php; do
    if [ ! -f "$script" ]; then
        continue
    fi

    TOTAL=$((TOTAL + 1))
    script_name=$(basename "$script")

    timeout 3 php "$script" > /tmp/php_out_$$.txt 2>&1
    php_result=$?
    php_out=$(cat /tmp/php_out_$$.txt)

    timeout 3 "$AOT" "$script" > /tmp/aot_out_$$.txt 2>&1
    aot_result=$?
    aot_out=$(cat /tmp/aot_out_$$.txt)

    if [ $php_result -eq 0 ] && [ $aot_result -eq 0 ] && [ "$php_out" = "$aot_out" ]; then
        rm "$script"
        PASSED=$((PASSED + 1))
    else
        echo "| \`$script_name\` | \`$(echo "$php_out" | head -3 | tr '\n' ' ' | head -c 100)\` | \`$(echo "$aot_out" | head -3 | tr '\n' ' ' | head -c 100)\` |" >> "$ERROR_LOG"
        FAILED=$((FAILED + 1))
    fi

    rm -f /tmp/php_out_$$.txt /tmp/aot_out_$$.txt

    if [ $((TOTAL % 20)) -eq 0 ]; then
        echo "Progress: $TOTAL scripts tested, $PASSED passed, $FAILED failed"
    fi
done

echo "================================"
echo "Total: $TOTAL, Passed: $PASSED, Failed: $FAILED"
echo "Error log saved to: $ERROR_LOG"
