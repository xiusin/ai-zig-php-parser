#!/bin/bash
# i64 快速路径覆盖率汇总报告
# 用法: ZIGPHP_AOT_STATS=1 scripts/aot_coverage_report.sh [目录]
#
# 编译所有 PHP 测试脚本，收集 ZIGPHP_AOT_STATS 输出，生成覆盖率汇总

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="${1:-fuzzy_scripts/pass}"
STATS_FILE="/tmp/aot_stats_$$.txt"

echo "=== AOT i64 快速路径覆盖率报告 ==="
echo "目标目录: $TARGET_DIR"
echo ""

# 收集所有 PHP 文件
PHP_FILES=$(find "$SCRIPT_DIR/$TARGET_DIR" -name '*.php' -type f 2>/dev/null | sort)
TOTAL=0
COMPILED=0
FOR_ACTIVE=0
FOR_INACTIVE=0
WHILE_ACTIVE=0
WHILE_INACTIVE=0
TOTAL_KNOWN_REGS=0

for php_file in $PHP_FILES; do
    TOTAL=$((TOTAL + 1))
    # 编译并收集 stats
    STATS=$(ZIGPHP_AOT_STATS=1 timeout 30 "$SCRIPT_DIR/zig-out/bin/php-interpreter" --compile --no-debug-info "$php_file" 2>&1 || true)
    echo "$STATS" | grep '\[AOT-STATS\]' >> "$STATS_FILE" 2>/dev/null || true
    
    # 清理编译产物
    basename_noext=$(basename "$php_file" .php)
    rm -f "$SCRIPT_DIR/$TARGET_DIR/aot_compile_${basename_noext}" 2>/dev/null || true
    rm -f "$php_file"/*.aot_compile_* 2>/dev/null || true
done

# 汇总统计
if [ -f "$STATS_FILE" ]; then
    FOR_LINES=$(grep 'for_loop' "$STATS_FILE" 2>/dev/null || true)
    WHILE_LINES=$(grep 'while_loop' "$STATS_FILE" 2>/dev/null || true)
    
    FOR_TOTAL=$(echo "$FOR_LINES" | grep -c 'for_loop' || true)
    FOR_ACT=$(echo "$FOR_LINES" | grep 'active=true' | wc -l || true)
    FOR_INACT=$(echo "$FOR_LINES" | grep 'active=false' | wc -l || true)
    
    WHILE_TOTAL=$(echo "$WHILE_LINES" | grep -c 'while_loop' || true)
    WHILE_ACT=$(echo "$WHILE_LINES" | grep 'active=true' | wc -l || true)
    WHILE_INACT=$(echo "$WHILE_LINES" | grep 'active=false' | wc -l || true)
    
    echo "--- for 循环 ---"
    echo "  总数: $FOR_TOTAL"
    echo "  激活: $FOR_ACT"
    echo "  未激活: $FOR_INACT"
    if [ "$FOR_TOTAL" -gt 0 ]; then
        echo "  覆盖率: $(echo "scale=1; $FOR_ACT * 100 / $FOR_TOTAL" | bc)%"
    fi
    echo ""
    echo "--- while 循环 ---"
    echo "  总数: $WHILE_TOTAL"
    echo "  激活: $WHILE_ACT"
    echo "  未激活: $WHILE_INACT"
    if [ "$WHILE_TOTAL" -gt 0 ]; then
        echo "  覆盖率: $(echo "scale=1; $WHILE_ACT * 100 / $WHILE_TOTAL" | bc)%"
    fi
    echo ""
    echo "--- 详细 (前20条) ---"
    head -20 "$STATS_FILE"
else
    echo "未收集到任何统计信息"
fi

rm -f "$STATS_FILE"
