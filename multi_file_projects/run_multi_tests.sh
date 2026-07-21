#!/bin/bash
# 多文件项目 AOT 测试脚本
set -uo pipefail

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser"
MULTI_DIR="$SCRIPT_DIR/multi_file_projects"
INTERPRETER="$SCRIPT_DIR/zig-out/bin/php-interpreter"
TEMP_DIR="/tmp/aot_multi_$$"
REPORT_FILE="$MULTI_DIR/multi_report.md"

mkdir -p "$TEMP_DIR"

echo "# Multi-File Project AOT Test Report" > "$REPORT_FILE"
echo "Test time: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

TOTAL=0
PASSED=0
COMPILE_FAIL=0
RUN_FAIL=0
DIFF_FAIL=0

for project_dir in "$MULTI_DIR"/*/; do
    project_name=$(basename "$project_dir")
    entry="$project_dir/index.php"

    [ -f "$entry" ] || continue

    TOTAL=$((TOTAL + 1))
    echo ">>> Testing: $project_name"
    echo "" >> "$REPORT_FILE"
    echo "## $project_name" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    # PHP 运行
    php_output=$(timeout 10 php "$entry" 2>&1)
    php_exit=$?
    if [ $php_exit -ne 0 ]; then
        echo "  [SKIP] PHP error (exit=$php_exit)"
        echo "- PHP Error: $(echo "$php_output" | tail -3)" >> "$REPORT_FILE"
        continue
    fi

    # AOT 编译
    aot_binary="$TEMP_DIR/aot_compile_${project_name}"
    compile_output=$(timeout 120 "$INTERPRETER" --compile --output="$aot_binary" "$entry" 2>&1)
    compile_exit=$?

    if [ $compile_exit -ne 0 ]; then
        COMPILE_FAIL=$((COMPILE_FAIL + 1))
        echo "  [FAIL_COMPILE]"
        echo "- **Compile Failed**: $(echo "$compile_output" | tail -5)" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        echo "$compile_output" | tail -20 >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        continue
    fi

    # AOT 运行
    aot_output=$(timeout 15 "$aot_binary" 2>&1)
    aot_exit=$?
    rm -f "$aot_binary"

    if [ $aot_exit -ne 0 ]; then
        RUN_FAIL=$((RUN_FAIL + 1))
        echo "  [FAIL_RUNTIME] (exit=$aot_exit)"
        echo "- **Runtime Failed** (exit=$aot_exit): $(echo "$aot_output" | tail -5)" >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        echo "$aot_output" | tail -20 >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
        continue
    fi

    # 比对（归一化：去除时间戳/token/浮点精度/缩进/地址差异）
    norm_php=$(echo "$php_output" | sed -E \
        -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' \
        -e 's/0x[0-9a-fA-F]{8,}/0xADDR/g' \
        -e 's|/tmp/aot_[a-z0-9_]+|TMPDIR|g' \
        -e 's/[0-9]+\.[0-9]{12,}/FLOAT/g' \
        -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?/TIMESTAMP/g' \
        -e 's/in[[:space:]]+[^[:space:]:]+\.php:[0-9]+/in FILE:LINE/g' \
        -e 's/tk_[a-f0-9]+/TOKEN/g' -e 's/txn_[a-f0-9]+/TXN/g' -e 's/TRACK-[A-F0-9]+/TRACK/g' \
        | tr -s '\n' | sed -E -e '/^$/d')
    norm_aot=$(echo "$aot_output" | sed -E \
        -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' \
        -e 's/0x[0-9a-fA-F]{8,}/0xADDR/g' \
        -e 's|/tmp/aot_[a-z0-9_]+|TMPDIR|g' \
        -e 's/[0-9]+\.[0-9]{12,}/FLOAT/g' \
        -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?/TIMESTAMP/g' \
        -e 's/in[[:space:]]+[^[:space:]:]+\.php:[0-9]+/in FILE:LINE/g' \
        -e 's/tk_[a-f0-9]+/TOKEN/g' -e 's/txn_[a-f0-9]+/TXN/g' -e 's/TRACK-[A-F0-9]+/TRACK/g' \
        | tr -s '\n' | sed -E -e '/^$/d')

    if [ "$norm_php" == "$norm_aot" ]; then
        PASSED=$((PASSED + 1))
        echo "  [PASS]"
        echo "- **PASS**" >> "$REPORT_FILE"
    else
        DIFF_FAIL=$((DIFF_FAIL + 1))
        echo "  [FAIL_DIFF]"
        echo "- **Output Diff**" >> "$REPORT_FILE"
        echo '```diff' >> "$REPORT_FILE"
        diff <(echo "$norm_php") <(echo "$norm_aot") | head -30 >> "$REPORT_FILE"
        echo '```' >> "$REPORT_FILE"
    fi
done

echo "" >> "$REPORT_FILE"
echo "## Summary" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "| Metric | Value |" >> "$REPORT_FILE"
echo "|--------|-------|" >> "$REPORT_FILE"
echo "| Total | $TOTAL |" >> "$REPORT_FILE"
echo "| Passed | $PASSED |" >> "$REPORT_FILE"
echo "| Compile Failed | $COMPILE_FAIL |" >> "$REPORT_FILE"
echo "| Runtime Failed | $RUN_FAIL |" >> "$REPORT_FILE"
echo "| Output Diff | $DIFF_FAIL |" >> "$REPORT_FILE"

echo ""
echo "========================================="
echo "Multi-File Test Done!"
echo "Total: $TOTAL, Passed: $PASSED, Compile Fail: $COMPILE_FAIL, Runtime Fail: $RUN_FAIL, Diff: $DIFF_FAIL"
echo "Report: $REPORT_FILE"
echo "========================================="

rm -rf "$TEMP_DIR"
