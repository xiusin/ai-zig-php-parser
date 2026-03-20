#!/bin/bash
# Fuzzy test runner for AOT compilation
# Tests PHP scripts against AOT compiled output

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts_27"
PHP_BIN="/opt/homebrew/bin/php"
AOT_BIN="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
TIMEOUT=3
COMPILE_TIMEOUT=120
ERROR_LOG="$SCRIPT_DIR/error_log_$(date +%Y%m%d_%H%M%S).md"

mkdir -p "$SCRIPT_DIR"

# Initialize error log
cat > "$ERROR_LOG" << 'EOFHEADER'
# AOT模糊测试错误记录

## 测试时间: $(date)

## 错误记录表

|脚本名称|PHP命令正确结果|AOT执行输出结果/错误信息/警告信息|
|--------|--------------|-------------------------------|

EOFHEADER

echo "开始AOT模糊测试..."
echo "测试目录: $SCRIPT_DIR"
echo "错误日志: $ERROR_LOG"

# Get list of PHP scripts
cd "$SCRIPT_DIR"
SCRIPTS=$(find . -maxdepth 1 -name "test_*.php" -type f 2>/dev/null | sort)
TOTAL=$(echo "$SCRIPTS" | wc -l | tr -d ' ')
echo "找到 $TOTAL 个测试脚本"

PASSED=0
FAILED=0
ERROR_LIST=""

for script in $SCRIPTS; do
    SCRIPT_NAME=$(basename "$script")
    echo -n "[$SCRIPT_NAME] "

    # Run PHP
    PHP_OUTPUT=$(timeout $TIMEOUT $PHP_BIN "$script" 2>&1)
    PHP_EXIT=$?

    # Compile with AOT
    TEMP_BIN=$(mktemp /tmp/aot_test_XXXXXX)
    COMPILE_OUTPUT=$(timeout $COMPILE_TIMEOUT $AOT_BIN --mode=tree --compile --output="$TEMP_BIN" "$script" 2>&1)
    COMPILE_EXIT=$?

    if [ $COMPILE_EXIT -ne 0 ]; then
        echo "编译失败"
        echo "| $SCRIPT_NAME | PHP exit:$PHP_EXIT | AOT编译错误: $COMPILE_OUTPUT |" >> "$ERROR_LOG"
        ERROR_LIST="$ERROR_LIST\n$script"
        FAILED=$((FAILED+1))
        rm -f "$TEMP_BIN"
        continue
    fi

    # Run AOT
    if [ -f "$TEMP_BIN" ]; then
        AOT_OUTPUT=$(timeout $TIMEOUT "$TEMP_BIN" 2>&1)
        AOT_EXIT=$?
    else
        AOT_OUTPUT="编译产物不存在"
        AOT_EXIT=255
    fi

    # Clean up AOT binary
    rm -f "$TEMP_BIN"

    # Compare outputs
    if [ "$PHP_OUTPUT" = "$AOT_OUTPUT" ] && [ $PHP_EXIT -eq $AOT_EXIT ]; then
        echo "通过"
        PASSED=$((PASSED+1))
        rm -f "$script"
    else
        echo "失败"
        echo "| $SCRIPT_NAME | PHP exit:$PHP_EXIT output:$PHP_OUTPUT | AOT exit:$AOT_EXIT output:$AOT_OUTPUT |" >> "$ERROR_LOG"
        ERROR_LIST="$ERROR_LIST\n$script"
        FAILED=$((FAILED+1))
    fi
done

echo ""
echo "======================================"
echo "测试完成: $TOTAL 个脚本"
echo "通过: $PASSED, 失败: $FAILED"
echo "======================================"
echo "错误日志已保存到: $ERROR_LOG"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo "失败的脚本:"
    echo -e "$ERROR_LIST"
fi