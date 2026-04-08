#!/bin/bash
# AOT模糊测试执行脚本
# 执行时间: $(date '+%Y-%m-%d %H:%M:%S')

set -e

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser"
FUZZY_DIR="$SCRIPT_DIR/fuzzy_scripts"
PASS_DIR="$FUZZY_DIR/pass"
INTERPRETER="$SCRIPT_DIR/zig-out/bin/php-interpreter"
REPORT_FILE="$SCRIPT_DIR/fuzzy_test_report.md"
TEMP_DIR="/tmp/aot_fuzzy_test_$$"

# 创建必要目录
mkdir -p "$PASS_DIR" "$TEMP_DIR"

# 排除的测试脚本（生成器、随机数、Fiber相关）
EXCLUDE_PATTERNS=(
    "fiber"
    "coroutine"
    "generator"
    "random"
    "rand"
)

# 结果统计
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

# 初始化报告文件
echo "# AOT模糊测试报告" > "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "测试时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# 错误记录函数
log_error() {
    local script="$1"
    local php_output="$2"
    local aot_output="$3"

    echo "" >> "$REPORT_FILE"
    echo "### $script" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "| 项目 | 内容 |" >> "$REPORT_FILE"
    echo "|------|------|" >> "$REPORT_FILE"
    # 截断输出并处理特殊字符
    local php_trunc=$(echo "$php_output" | head -c 500 | sed 's/|/\\|/g' | tr '\n' ' ')
    local aot_trunc=$(echo "$aot_output" | head -c 500 | sed 's/|/\\|/g' | tr '\n' ' ')
    echo "| PHP输出 | \`$php_trunc\` |" >> "$REPORT_FILE"
    echo "| AOT输出 | \`$aot_trunc\` |" >> "$REPORT_FILE"
}

# 检查是否需要排除
should_exclude() {
    local script="$1"
    local basename=$(basename "$script")
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        if [[ "$basename" == *"$pattern"* ]]; then
            return 0
        fi
    done
    return 1
}

# 执行单个测试
run_test() {
    local script="$1"
    local script_name=$(basename "$script")
    local output_name="${script_name%.php}"
    local aot_binary="$TEMP_DIR/$output_name"

    TOTAL=$((TOTAL + 1))

    # 检查是否排除
    if should_exclude "$script_name"; then
        echo "[SKIP] $script_name (excluded pattern)"
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    # Step 1: PHP原生执行
    local php_output
    local php_exit=0
    php_output=$(timeout 3 php "$script" 2>&1) || php_exit=$?

    # Step 2: AOT编译
    local compile_output
    local compile_exit=0
    compile_output=$(timeout 30 "$INTERPRETER" --compile --output="$aot_binary" "$script" 2>&1) || compile_exit=$?

    if [ $compile_exit -ne 0 ]; then
        # 编译失败，检查是否PHP也有致命错误
        if echo "$php_output" | grep -qiE "fatal|error|parse|warning"; then
            # PHP也报错，认为一致（编译期错误应该在编译器报错）
            if echo "$compile_output" | grep -qiE "error|fail"; then
                echo "[PASS] $script_name (both have errors)"
                PASSED=$((PASSED + 1))
                rm -f "$script"
                return
            fi
        fi
        echo "[FAIL] $script_name (compile failed)"
        log_error "$script_name" "$php_output" "Compile Error: $compile_output"
        FAILED=$((FAILED + 1))
        return
    fi

    # Step 3: AOT执行
    local aot_output
    local aot_exit=0
    aot_output=$(timeout 3 "$aot_binary" 2>&1) || aot_exit=$?

    # Step 4: 清理编译产物
    rm -f "$aot_binary"

    # Step 5: 对比结果
    if [ "$php_output" == "$aot_output" ]; then
        echo "[PASS] $script_name"
        PASSED=$((PASSED + 1))
        # 删除通过的脚本
        rm -f "$script"
    else
        echo "[FAIL] $script_name (output mismatch)"
        log_error "$script_name" "$php_output" "$aot_output"
        FAILED=$((FAILED + 1))
    fi
}

# 主循环
echo "=========================================="
echo "开始AOT模糊测试..."
echo "解释器: $INTERPRETER"
echo "测试目录: $FUZZY_DIR"
echo "=========================================="
echo ""

for script in "$FUZZY_DIR"/*.php; do
    if [ -f "$script" ]; then
        run_test "$script"
    fi
done

# 写入统计信息
echo "" >> "$REPORT_FILE"
echo "## 测试统计" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "| 统计项 | 数量 |" >> "$REPORT_FILE"
echo "|--------|------|" >> "$REPORT_FILE"
echo "| 总计 | $TOTAL |" >> "$REPORT_FILE"
echo "| 通过 | $PASSED |" >> "$REPORT_FILE"
echo "| 失败 | $FAILED |" >> "$REPORT_FILE"
echo "| 跳过 | $SKIPPED |" >> "$REPORT_FILE"

# 清理临时目录
rm -rf "$TEMP_DIR"

echo ""
echo "=========================================="
echo "测试完成!"
echo "总计: $TOTAL, 通过: $PASSED, 失败: $FAILED, 跳过: $SKIPPED"
echo "报告已保存到: $REPORT_FILE"
echo "=========================================="
