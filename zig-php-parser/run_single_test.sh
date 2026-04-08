#!/bin/bash
# 简单测试脚本 - 输出到文件

SCRIPT="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/fuzzy_scripts/test_002_operators.php"
OUTPUT="/tmp/test_result.txt"
AOT="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/zig-out/bin/php-interpreter"
TEMP_BIN="/tmp/test_binary"

echo "=== Testing: $SCRIPT ===" > "$OUTPUT"
echo "" >> "$OUTPUT"

echo "--- PHP Output ---" >> "$OUTPUT"
php "$SCRIPT" >> "$OUTPUT" 2>&1
echo "" >> "$OUTPUT"

echo "--- AOT Compile ---" >> "$OUTPUT"
"$AOT" --compile --output="$TEMP_BIN" "$SCRIPT" >> "$OUTPUT" 2>&1
COMPILE_EXIT=$?
echo "Exit code: $COMPILE_EXIT" >> "$OUTPUT"
echo "" >> "$OUTPUT"

if [ $COMPILE_EXIT -eq 0 ]; then
    echo "--- AOT Output ---" >> "$OUTPUT"
    "$TEMP_BIN" >> "$OUTPUT" 2>&1
    rm -f "$TEMP_BIN"
fi

echo "Test completed. Output saved to $OUTPUT"
