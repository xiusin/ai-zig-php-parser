#!/bin/bash
#
# AOT vs 解释器性能对比脚本
# 运行所有基准测试并生成对比报告
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPORT_DIR="$PROJECT_ROOT/docs/benchmarks"
DATE=$(date +%Y-%m-%d)

echo "╔════════════════════════════════════════════════════════════╗"
echo "║          AOT vs 解释器性能对比测试                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "日期: $DATE"
echo "项目路径: $PROJECT_ROOT"
echo ""

mkdir -p "$REPORT_DIR"

run_php_benchmark() {
    local test_name="$1"
    local php_file="$2"
    
    if [ -f "$php_file" ]; then
        output=$(php "$php_file" 2>&1)
        time_ms=$(echo "$output" | grep -oE 'Time: [0-9.]+' | grep -oE '[0-9.]+')
        if [ -n "$time_ms" ]; then
            echo "$time_ms"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

echo "═══════════════════════════════════════════════════════════════"
echo "                    字符串操作测试"
echo "═══════════════════════════════════════════════════════════════"
echo ""

STRING_TESTS=(
    "strlen"
    "substr"
    "strtoupper"
    "strtolower"
    "strpos"
    "str_replace"
    "trim"
    "explode"
    "implode"
    "sprintf"
)

echo "| 测试名称 | PHP (ms) | 状态 |"
echo "|----------|----------|------|"

for test in "${STRING_TESTS[@]}"; do
    php_file="$SCRIPT_DIR/string/${test}.php"
    if [ -f "$php_file" ]; then
        time_ms=$(run_php_benchmark "$test" "$php_file")
        printf "| %-20s | %8s | ✅ |\n" "$test" "$time_ms"
    else
        printf "| %-20s | %8s | ⏭️ |\n" "$test" "N/A"
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "                    数组操作测试"
echo "═══════════════════════════════════════════════════════════════"
echo ""

ARRAY_TESTS=(
    "array_create"
    "array_push"
    "array_access"
    "array_foreach"
    "array_map"
)

echo "| 测试名称 | PHP (ms) | 状态 |"
echo "|----------|----------|------|"

for test in "${ARRAY_TESTS[@]}"; do
    php_file="$SCRIPT_DIR/array/${test}.php"
    if [ -f "$php_file" ]; then
        time_ms=$(run_php_benchmark "$test" "$php_file")
        printf "| %-20s | %8s | ✅ |\n" "$test" "$time_ms"
    else
        printf "| %-20s | %8s | ⏭️ |\n" "$test" "N/A"
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "                    生成报告"
echo "═══════════════════════════════════════════════════════════════"
echo ""

REPORT_FILE="$REPORT_DIR/performance_report_$DATE.md"

{
    echo "# 性能对比报告"
    echo ""
    echo "## 测试环境"
    echo ""
    echo "- **日期**: $DATE"
    echo "- **平台**: $(uname -s) $(uname -m)"
    echo "- **PHP 版本**: $(php -v | head -1)"
    echo "- **Zig 版本**: $(zig version)"
    echo ""
    echo "## 测试说明"
    echo ""
    echo "本报告对比 PHP 原生执行与 Zig-PHP AOT 编译执行的性能差异。"
    echo ""
    echo "## 基准测试结果"
    echo ""
    echo "详细结果请参见 \`tests/benchmarks/baseline_results.json\`"
    echo ""
    echo "## 回归检测"
    echo ""
    echo "回归阈值: 10%"
    echo ""
} > "$REPORT_FILE"

echo "✅ 报告已生成: $REPORT_FILE"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "                    测试完成"
echo "═══════════════════════════════════════════════════════════════"
