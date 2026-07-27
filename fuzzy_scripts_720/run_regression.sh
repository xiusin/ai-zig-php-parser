#!/bin/bash
# Regression test for pass/ directory
# Usage: bash run_regression.sh

set -uo pipefail

SCRIPT_DIR="/Users/wangjianjun/products/parser"
FUZZY_DIR="$SCRIPT_DIR/fuzzy_scripts_720"
PASS_DIR="$FUZZY_DIR/pass"
INTERPRETER="$SCRIPT_DIR/zig-out/bin/php-interpreter"
TEMP_DIR="/tmp/aot_regression_$$"
REPORT_FILE="$FUZZY_DIR/regression_report.md"
FAILURES_TSV="$FUZZY_DIR/regression_failures.tsv"

mkdir -p "$TEMP_DIR"
> "$FAILURES_TSV"

PHP_TIMEOUT=10
RUN_TIMEOUT=10

normalize_output() {
    sed -E \
        -e 's/[[:space:]]*$//' \
        -e 's/^[[:space:]]*//' \
        -e 's/0x[0-9a-fA-F]{8,}/0xADDR/g' \
        -e 's|/tmp/aot_[a-z0-9_]+|TMPDIR|g' \
        -e 's/microtime\(true\)/MICROTIME/g' \
        -e 's/[0-9]+\.[0-9]{12,}/FLOAT/g' \
        -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?/TIMESTAMP/g' \
        -e 's/in[[:space:]]+[^[:space:]:]+\.php:[0-9]+/in FILE:LINE/g' \
        | tr -s '\n' \
        | sed -E -e '/^$/d'
}

run_test() {
    local script_path="$1"
    local script_name
    script_name=$(basename "$script_path")
    local base_name="${script_name%.php}"
    local aot_binary="$TEMP_DIR/aot_compile_${base_name}"

    # PHP run
    local php_output php_exit
    php_output=$(perl -e 'alarm 10; exec @ARGV' php "$script_path" 2>&1)
    php_exit=$?
    if [ $php_exit -ne 0 ]; then
        echo "SKIP|$script_name|PHP_error_exit=$php_exit" >> "$FAILURES_TSV"
        echo "  [SKIP] $script_name (PHP error exit=$php_exit)"
        return 0
    fi

    # AOT compile
    local compile_output compile_exit
    compile_output=$(perl -e 'alarm 120; exec @ARGV' "$INTERPRETER" --compile --output="$aot_binary" "$script_path" 2>&1)
    compile_exit=$?
    if [ $compile_exit -ne 0 ]; then
        local err_summary
        err_summary=$(echo "$compile_output" | tail -5 | tr '\n' ' ' | head -c 200)
        echo "FAIL_COMPILE|$script_name|$err_summary" >> "$FAILURES_TSV"
        echo "  [FAIL_COMPILE] $script_name"
        rm -f "$aot_binary"
        return 1
    fi

    # AOT run
    local aot_output aot_exit
    aot_output=$(perl -e 'alarm 10; exec @ARGV' "$aot_binary" 2>&1)
    aot_exit=$?
    rm -f "$aot_binary"

    if [ $aot_exit -ne 0 ]; then
        local err_tail
        err_tail=$(echo "$aot_output" | tail -5 | tr '\n' ' ' | head -c 200)
        echo "FAIL_RUNTIME|$script_name|exit=$aot_exit|$err_tail" >> "$FAILURES_TSV"
        echo "  [FAIL_RUNTIME] $script_name (exit=$aot_exit)"
        return 1
    fi

    # Compare
    local norm_php norm_aot
    norm_php=$(normalize_output <<< "$php_output")
    norm_aot=$(normalize_output <<< "$aot_output")

    if [ "$norm_php" == "$norm_aot" ]; then
        echo "PASS|$script_name" >> "$FAILURES_TSV"
        echo "  [PASS] $script_name"
        return 0
    else
        local php_head aot_head
        php_head=$(echo "$norm_php" | head -3 | tr '\n' '|')
        aot_head=$(echo "$norm_aot" | head -3 | tr '\n' '|')
        echo "FAIL_DIFF|$script_name|PHP:$php_head|AOT:$aot_head" >> "$FAILURES_TSV"
        echo "  [FAIL_DIFF] $script_name"
        return 1
    fi
}

TOTAL=$(ls -1 "$PASS_DIR"/f*.php 2>/dev/null | wc -l | tr -d ' ')
echo "=========================================="
echo "Regression Test - $(date '+%Y-%m-%d %H:%M:%S')"
echo "Scripts: $TOTAL"
echo "=========================================="

PASS_CNT=0
FAIL_CNT=0
SKIP_CNT=0
IDX=0

for script in "$PASS_DIR"/f*.php; do
    [ -f "$script" ] || continue
    script_name=$(basename "$script")
    IDX=$((IDX + 1))
    echo "[$IDX/$TOTAL] $script_name"
    run_test "$script"
    rc=$?
    if [ $rc -eq 0 ]; then
        PASS_CNT=$((PASS_CNT + 1))
    else
        FAIL_CNT=$((FAIL_CNT + 1))
    fi
done

echo ""
echo "=========================================="
echo "PASS=$PASS_CNT FAIL=$FAIL_CNT"
echo "=========================================="

# Generate report
{
    echo "# fuzzy_scripts_720/pass/ 回归测试报告"
    echo ""
    echo "测试时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "AOT 编译器: $INTERPRETER"
    echo ""
    echo "## 统计"
    echo ""
    echo "| 类别 | 数量 |"
    echo "|------|------|"
    
    PASS_C=$(grep -c '^PASS|' "$FAILURES_TSV" 2>/dev/null || echo 0)
    FC_C=$(grep -c '^FAIL_COMPILE|' "$FAILURES_TSV" 2>/dev/null || echo 0)
    FR_C=$(grep -c '^FAIL_RUNTIME|' "$FAILURES_TSV" 2>/dev/null || echo 0)
    FD_C=$(grep -c '^FAIL_DIFF|' "$FAILURES_TSV" 2>/dev/null || echo 0)
    SKIP_C=$(grep -c '^SKIP|' "$FAILURES_TSV" 2>/dev/null || echo 0)
    
    echo "| Total | $TOTAL |"
    echo "| Pass | $PASS_C |"
    echo "| Fail (Compile) | $FC_C |"
    echo "| Fail (Runtime) | $FR_C |"
    echo "| Fail (Diff) | $FD_C |"
    echo "| Skip | $SKIP_C |"
    echo ""
    echo "## 失败明细"
    echo ""
    echo "| 脚本 | 类型 | 详情 |"
    echo "|------|------|------|"
    grep -v '^PASS|' "$FAILURES_TSV" 2>/dev/null | while IFS='|' read -r type name detail; do
        detail_short=$(echo "$detail" | head -c 150)
        echo "| $name | $type | $detail_short |"
    done
} > "$REPORT_FILE"

echo "报告已生成: $REPORT_FILE"
rm -rf "$TEMP_DIR"
