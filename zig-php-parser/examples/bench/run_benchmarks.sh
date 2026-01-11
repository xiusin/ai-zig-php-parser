#!/bin/bash
#
# 性能测试运行脚本
# 运行 PHP 原生和 Zig-PHP 解释器的性能对比测试
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHP_INTERPRETER="${1:-$SCRIPT_DIR/../../zig-out/bin/php-interpreter}"
OUTPUT_DIR="$SCRIPT_DIR"

echo "================================================="
echo "  性能测试套件"
echo "================================================="
echo ""
echo "Zig-PHP 解释器: $PHP_INTERPRETER"

# 检查解释器是否存在
if [ ! -f "$PHP_INTERPRETER" ]; then
    echo "错误: 找不到解释器 $PHP_INTERPRETER"
    echo "请先运行: zig build"
    exit 1
fi

echo ""
echo "步骤 1: 运行 PHP 原生性能测试..."
echo "-------------------------------------------"
php "$SCRIPT_DIR/benchmark_php.php"

echo ""
echo "步骤 2: 运行 Zig-PHP 性能测试..."
echo "-------------------------------------------"
php "$SCRIPT_DIR/benchmark_zig.php" "$PHP_INTERPRETER"

echo ""
echo "================================================="
echo "  测试完成！"
echo "================================================="
echo ""
echo "生成的报告:"
echo "  - $OUTPUT_DIR/benchmark_$(date +%Y-%m-%d).md"
echo "  - $OUTPUT_DIR/comparison_report_$(date +%Y-%m-%d).md"
echo ""
