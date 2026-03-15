#!/bin/bash
# 模糊测试对比脚本：PHP原生 vs AOT执行结果对比

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUZZY_DIR="$SCRIPT_DIR/fuzzy_scripts"
REPORT_FILE="$SCRIPT_DIR/fuzzy_test_report.md"
PHP_BIN="/usr/local/bin/php"
AOT_BIN="$SCRIPT_DIR/zig-out/bin/php-interpreter"
PASSED_DIR="$FUZZY_DIR/passed"
FAILED_DIR="$FUZZY_DIR/failed"

# 创建目录
mkdir -p "$PASSED_DIR" "$FAILED_DIR"

# 初始化报告
echo "# AOT模糊测试报告" > "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 计数器
TOTAL=0
PASSED=0
FAILED=0

# 测试单个文件
test_file() {
    local file="$1"
    local basename=$(basename "$file")
    local php_output="$SCRIPT_DIR/.php_output.txt"
    local aot_output="$SCRIPT_DIR/.aot_output.txt"
    local aot_exe="${file%.php}"
    
    # 跳过生成器和随机数测试
    if grep -q "rand\|mt_rand\|random\|Generator" "$file" 2>/dev/null; then
        echo "  [SKIP] $basename (contains randomness)"
        return 0
    fi
    
    # PHP原生执行
    timeout 3 $PHP_BIN "$file" > "$php_output" 2>&1 || {
        local php_exit=$?
        if [ $php_exit -eq 124 ]; then
            echo "PHP timeout" > "$php_output"
        fi
    }
    
    # AOT编译
    if ! timeout 10 $AOT_BIN --compile --output "$aot_exe" "$file" 2>/dev/null; then
        echo "  [FAIL] $basename - AOT compilation failed"
        echo "| $basename | AOT compilation failed | - | - |" >> "$REPORT_FILE"
        cp "$file" "$FAILED_DIR/"
        FAILED=$((FAILED + 1))
        rm -f "$php_output" "$aot_output"
        return 1
    fi
    
    # AOT执行
    timeout 3 "$aot_exe" > "$aot_output" 2>&1 || {
        local aot_exit=$?
        if [ $aot_exit -eq 124 ]; then
            echo "AOT timeout" > "$aot_output"
        fi
    }
    
    # 对比输出
    if diff -q "$php_output" "$aot_output" > /dev/null 2>&1; then
        echo "  [PASS] $basename"
        mv "$file" "$PASSED_DIR/"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $basename - Output differs"
        echo "" >> "$REPORT_FILE"
        echo "## $basename" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "### PHP输出:" >> "$REPORT_FILE"
        echo "\`\`\`" >> "$REPORT_FILE"
        cat "$php_output" >> "$REPORT_FILE"
        echo "\`\`\`" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "### AOT输出:" >> "$REPORT_FILE"
        echo "\`\`\`" >> "$REPORT_FILE"
        cat "$aot_output" >> "$REPORT_FILE"
        echo "\`\`\`" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        cp "$file" "$FAILED_DIR/"
        FAILED=$((FAILED + 1))
    fi
    
    # 清理
    rm -f "$php_output" "$aot_output" "$aot_exe"
    
    return 0
}

# 主循环
echo "开始模糊测试对比..."
echo ""

for file in "$FUZZY_DIR"/test_*.php; do
    if [ -f "$file" ]; then
        TOTAL=$((TOTAL + 1))
        test_file "$file"
        
        # 每10个显示进度
        if [ $((TOTAL % 10)) -eq 0 ]; then
            echo ""
            echo "进度: $TOTAL 测试完成, $PASSED 通过, $FAILED 失败"
            echo ""
        fi
    fi
done

# 总结
echo "" >> "$REPORT_FILE"
echo "## 测试总结" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "- 总测试数: $TOTAL" >> "$REPORT_FILE"
echo "- 通过: $PASSED" >> "$REPORT_FILE"
echo "- 失败: $FAILED" >> "$REPORT_FILE"
echo "- 通过率: $(( PASSED * 100 / TOTAL ))%" >> "$REPORT_FILE"

echo ""
echo "========================================"
echo "测试完成!"
echo "总计: $TOTAL"
echo "通过: $PASSED"
echo "失败: $FAILED"
echo "报告: $REPORT_FILE"
echo "========================================"
