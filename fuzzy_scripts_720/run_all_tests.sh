#!/bin/bash
# fuzzy_scripts_720 全量 AOT 测试脚本 (v2)
# 改进: 精确排除模式 / 健壮归一化 / mv 替代 cp / 并行编译

set -uo pipefail

SCRIPT_DIR="/Users/tuoke/Desktop/ai-zig-php-parser"
FUZZY_DIR="$SCRIPT_DIR/fuzzy_scripts_720"
PASS_DIR="$FUZZY_DIR/pass"
FAIL_COMPILE_DIR="$FUZZY_DIR/fail_compile"
FAIL_RUNTIME_DIR="$FUZZY_DIR/fail_runtime"
INTERPRETER="$SCRIPT_DIR/zig-out/bin/php-interpreter"
TEMP_DIR="/tmp/aot_fuzzy_720_$$"
PROGRESS_FILE="$FUZZY_DIR/.test_progress"
REPORT_FILE="$FUZZY_DIR/full_report.md"
DETAIL_LOG="$FUZZY_DIR/test_detail.log"
FAILURES_TSV="$FUZZY_DIR/failures.tsv"

mkdir -p "$PASS_DIR" "$FAIL_COMPILE_DIR" "$FAIL_RUNTIME_DIR" "$TEMP_DIR"

# 超时设置
PHP_TIMEOUT=10
COMPILE_TIMEOUT=120
RUN_TIMEOUT=10

# 仅排除 AOT 明确不支持的特性（基于文件内容，非文件名）
# Fiber/协程/生成器/eval/swoole 为 AOT 排除项
should_exclude() {
    local f="$1"
    # 检查是否包含 AOT 排除项语法
    if grep -qE '\b(yield\b|Fiber|fiber\(|coroutine|swoole_|eval\s*\()' "$f" 2>/dev/null; then
        return 0  # 排除
    fi
    return 1  # 不排除
}

# 归一化输出：处理 AOT 与 PHP 的已知差异
# 1. 行尾空白去除
# 2. 行首缩进差异忽略（宪法: 打印输出缩进不一致不视为 BUG）
# 3. 浮点数末位精度差异忽略（宪法: 浮点数小数位数微差不视为错误）
# 4. microtime/时间戳精度差异忽略
# 5. 内存地址归一化
# 6. 临时路径归一化
# 7. 栈追踪行号/文件路径差异忽略
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

    # 跳过排除项
    if should_exclude "$script_path"; then
        echo "  [SKIP] $script_name (AOT excluded feature)"
        echo "SKIP|$script_name|excluded" >> "$FAILURES_TSV"
        echo "$script_name" >> "$PROGRESS_FILE"
        return 0
    fi

    # PHP 运行
    local php_output php_exit
    php_output=$(timeout "$PHP_TIMEOUT" php "$script_path" 2>&1)
    php_exit=$?
    if [ $php_exit -ne 0 ]; then
        echo "  [SKIP] $script_name (PHP error exit=$php_exit)"
        echo "SKIP|$script_name|PHP_error_exit=$php_exit" >> "$FAILURES_TSV"
        echo "$script_name" >> "$PROGRESS_FILE"
        return 0
    fi

    # AOT 编译
    local compile_output compile_exit
    compile_output=$(timeout "$COMPILE_TIMEOUT" "$INTERPRETER" --compile --output="$aot_binary" "$script_path" 2>&1)
    compile_exit=$?
    if [ $compile_exit -ne 0 ]; then
        echo "  [FAIL_COMPILE] $script_name"
        local err_summary
        err_summary=$(echo "$compile_output" | tail -5 | tr '\n' ' ' | head -c 200)
        echo "FAIL_COMPILE|$script_name|$err_summary" >> "$FAILURES_TSV"
        mv "$script_path" "$FAIL_COMPILE_DIR/" 2>/dev/null
        echo "$script_name" >> "$PROGRESS_FILE"
        rm -f "$aot_binary"
        return 1
    fi

    # AOT 运行
    local aot_output aot_exit
    aot_output=$(timeout "$RUN_TIMEOUT" "$aot_binary" 2>&1)
    aot_exit=$?
    rm -f "$aot_binary"

    if [ $aot_exit -ne 0 ]; then
        echo "  [FAIL_RUNTIME] $script_name (exit=$aot_exit)"
        local err_tail
        err_tail=$(echo "$aot_output" | tail -5 | tr '\n' ' ' | head -c 200)
        echo "FAIL_RUNTIME|$script_name|exit=$aot_exit|$err_tail" >> "$FAILURES_TSV"
        mv "$script_path" "$FAIL_RUNTIME_DIR/" 2>/dev/null
        echo "$script_name" >> "$PROGRESS_FILE"
        return 1
    fi

    # 比对（归一化后）
    local norm_php norm_aot
    norm_php=$(normalize_output <<< "$php_output")
    norm_aot=$(normalize_output <<< "$aot_output")

    if [ "$norm_php" == "$norm_aot" ]; then
        echo "  [PASS] $script_name"
        echo "PASS|$script_name" >> "$FAILURES_TSV"
        mv "$script_path" "$PASS_DIR/" 2>/dev/null
        echo "$script_name" >> "$PROGRESS_FILE"
        return 0
    else
        echo "  [FAIL_DIFF] $script_name"
        local php_head aot_head
        php_head=$(echo "$norm_php" | head -3 | tr '\n' '|')
        aot_head=$(echo "$norm_aot" | head -3 | tr '\n' '|')
        echo "FAIL_DIFF|$script_name|PHP:$php_head|AOT:$aot_head" >> "$FAILURES_TSV"
        mv "$script_path" "$FAIL_RUNTIME_DIR/" 2>/dev/null
        echo "$script_name" >> "$PROGRESS_FILE"
        return 1
    fi
}

# 初始化进度文件（首次运行）
if [ ! -f "$PROGRESS_FILE" ]; then
    > "$PROGRESS_FILE"
fi

# 统计根目录待测脚本数
TOTAL_REMAIN=$(ls -1 "$FUZZY_DIR"/f*.php 2>/dev/null | wc -l | tr -d ' ')

echo "=========================================="
echo "AOT Fuzzy Test 720 v2 - $(date '+%Y-%m-%d %H:%M:%S')"
echo "待测脚本: $TOTAL_REMAIN"
echo "=========================================="

PASS_CNT=0
FAIL_CNT=0
SKIP_CNT=0
IDX=0

for script in "$FUZZY_DIR"/f*.php; do
    [ -f "$script" ] || continue
    script_name=$(basename "$script")

    # 断点续跑
    if grep -qxF "$script_name" "$PROGRESS_FILE" 2>/dev/null; then
        continue
    fi

    IDX=$((IDX + 1))
    echo "[$IDX/$TOTAL_REMAIN] >>> $script_name"

    run_test "$script"
    rc=$?
    if [ $rc -eq 0 ]; then
        PASS_CNT=$((PASS_CNT + 1))
    else
        FAIL_CNT=$((FAIL_CNT + 1))
    fi
done

# 统计已处理总数
PROG_COUNT=$(wc -l < "$PROGRESS_FILE" 2>/dev/null | tr -d ' ')

# 目录统计
PASS_DIR_CNT=$(ls -1 "$PASS_DIR"/*.php 2>/dev/null | wc -l | tr -d ' ')
FC_DIR_CNT=$(ls -1 "$FAIL_COMPILE_DIR"/*.php 2>/dev/null | wc -l | tr -d ' ')
FR_DIR_CNT=$(ls -1 "$FAIL_RUNTIME_DIR"/*.php 2>/dev/null | wc -l | tr -d ' ')
REMAIN_CNT=$(ls -1 "$FUZZY_DIR"/f*.php 2>/dev/null | wc -l | tr -d ' ')

echo ""
echo "=========================================="
echo "本次: PASS=$PASS_CNT FAIL=$FAIL_CNT"
echo "累计已测: $PROG_COUNT"
echo "目录统计: pass=$PASS_DIR_CNT fail_compile=$FC_DIR_CNT fail_runtime=$FR_DIR_CNT 根目录剩余=$REMAIN_CNT"
echo "=========================================="

# 生成报告
{
    echo "# fuzzy_scripts_720 全量测试报告 v2"
    echo ""
    echo "测试时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "## 统计"
    echo ""
    echo "| 类别 | 数量 |"
    echo "|------|------|"
    echo "| Pass | $PASS_DIR_CNT |"
    echo "| Fail (Compile) | $FC_DIR_CNT |"
    echo "| Fail (Runtime/Diff) | $FR_DIR_CNT |"
    echo "| 根目录待测 | $REMAIN_CNT |"
    echo "| 累计已测 | $PROG_COUNT |"
    echo ""
    echo "## 失败明细"
    echo ""
    if [ -f "$FAILURES_TSV" ]; then
        echo "| 脚本 | 类型 | 详情 |"
        echo "|------|------|------|"
        while IFS='|' read -r type name detail; do
            # 截断过长的详情
            detail_short=$(echo "$detail" | head -c 150)
            echo "| $name | $type | $detail_short |"
        done < "$FAILURES_TSV"
    fi
} > "$REPORT_FILE"

echo "报告已生成: $REPORT_FILE"
rm -rf "$TEMP_DIR"
