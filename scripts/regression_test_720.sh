#!/bin/bash
# fuzzy_scripts_720/pass/ 回归测试脚本 (macOS 兼容版)
# 验证之前通过的脚本在最新修改后仍然 100% 通过

set -uo pipefail

SCRIPT_DIR="/Users/wangjianjun/products/parser"
FUZZY_DIR="$SCRIPT_DIR/fuzzy_scripts_720"
PASS_DIR="$FUZZY_DIR/pass"
INTERPRETER="$SCRIPT_DIR/zig-out/bin/php-interpreter"
TEMP_DIR="/tmp/aot_regression_$$"
REPORT_FILE="$FUZZY_DIR/regression_report.md"
FAIL_LOG="$FUZZY_DIR/regression_failures.tsv"

mkdir -p "$TEMP_DIR"

# macOS 兼容的 timeout 实现
run_with_timeout() {
    local timeout_sec=$1
    shift
    # 在后台运行命令
    "$@" &
    local pid=$!
    # 等待指定秒数
    local elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        elapsed=$((elapsed + 1))
        if [ "$elapsed" -ge "$timeout_sec" ]; then
            kill -9 "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            return 124  # timeout exit code
        fi
    done
    wait "$pid"
    return $?
}

# 带超时的命令，捕获输出到变量
run_capture_timeout() {
    local timeout_sec=$1
    local result_var=$2
    local exit_var=$3
    shift 3
    local tmp_out="$TEMP_DIR/capture_$$"
    
    "$@" >"$tmp_out" 2>&1 &
    local pid=$!
    local elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        elapsed=$((elapsed + 1))
        if [ "$elapsed" -ge "$timeout_sec" ]; then
            kill -9 "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            eval "$result_var=\$(cat '$tmp_out')"
            eval "$exit_var=124"
            rm -f "$tmp_out"
            return 0
        fi
    done
    wait "$pid"
    local rc=$?
    eval "$result_var=\$(cat '$tmp_out')"
    eval "$exit_var=$rc"
    rm -f "$tmp_out"
    return 0
}

# 超时设置
PHP_TIMEOUT=10
COMPILE_TIMEOUT=120
RUN_TIMEOUT=10

# 排除 AOT 不支持的特性
should_exclude() {
    local f="$1"
    if grep -qE '\b(yield\b|Fiber|fiber\(|coroutine|swoole_|eval\s*\()' "$f" 2>/dev/null; then
        return 0  # 排除
    fi
    return 1  # 不排除
}

# 归一化输出
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

PASS_CNT=0
FAIL_COMPILE_CNT=0
FAIL_RUNTIME_CNT=0
FAIL_DIFF_CNT=0
SKIP_CNT=0
TOTAL=0

> "$FAIL_LOG"

for script in "$PASS_DIR"/*.php; do
    [ -f "$script" ] || continue
    script_name=$(basename "$script")
    base_name="${script_name%.php}"
    aot_binary="$TEMP_DIR/aot_compile_${base_name}"
    TOTAL=$((TOTAL + 1))

    echo -n "[$TOTAL] $script_name ... "

    # 跳过排除项
    if should_exclude "$script"; then
        echo "SKIP (AOT excluded)"
        echo "SKIP|$script_name|excluded" >> "$FAIL_LOG"
        SKIP_CNT=$((SKIP_CNT + 1))
        continue
    fi

    # PHP 运行
    run_capture_timeout "$PHP_TIMEOUT" php_output php_exit php "$script"
    if [ "$php_exit" -ne 0 ]; then
        echo "SKIP (PHP error exit=$php_exit)"
        echo "SKIP|$script_name|PHP_error_exit=$php_exit" >> "$FAIL_LOG"
        SKIP_CNT=$((SKIP_CNT + 1))
        continue
    fi

    # AOT 编译
    run_capture_timeout "$COMPILE_TIMEOUT" compile_output compile_exit "$INTERPRETER" --compile --output="$aot_binary" "$script"
    if [ "$compile_exit" -ne 0 ]; then
        echo "FAIL_COMPILE"
        err_summary=$(echo "$compile_output" | tail -5 | tr '\n' ' ' | head -c 200)
        echo "FAIL_COMPILE|$script_name|$err_summary" >> "$FAIL_LOG"
        FAIL_COMPILE_CNT=$((FAIL_COMPILE_CNT + 1))
        rm -f "$aot_binary"
        continue
    fi

    # AOT 运行
    run_capture_timeout "$RUN_TIMEOUT" aot_output aot_exit "$aot_binary"
    rm -f "$aot_binary"

    if [ "$aot_exit" -ne 0 ]; then
        echo "FAIL_RUNTIME (exit=$aot_exit)"
        err_tail=$(echo "$aot_output" | tail -5 | tr '\n' ' ' | head -c 200)
        echo "FAIL_RUNTIME|$script_name|exit=$aot_exit|$err_tail" >> "$FAIL_LOG"
        FAIL_RUNTIME_CNT=$((FAIL_RUNTIME_CNT + 1))
        continue
    fi

    # 比对（归一化后）
    norm_php=$(normalize_output <<< "$php_output")
    norm_aot=$(normalize_output <<< "$aot_output")

    if [ "$norm_php" == "$norm_aot" ]; then
        echo "PASS"
        PASS_CNT=$((PASS_CNT + 1))
    else
        echo "FAIL_DIFF"
        php_head=$(echo "$norm_php" | head -3 | tr '\n' '|')
        aot_head=$(echo "$norm_aot" | head -3 | tr '\n' '|')
        echo "FAIL_DIFF|$script_name|PHP:$php_head|AOT:$aot_head" >> "$FAIL_LOG"
        FAIL_DIFF_CNT=$((FAIL_DIFF_CNT + 1))
    fi
done

echo ""
echo "=========================================="
echo "回归测试结果:"
echo "  TOTAL:        $TOTAL"
echo "  PASS:         $PASS_CNT"
echo "  FAIL_COMPILE: $FAIL_COMPILE_CNT"
echo "  FAIL_RUNTIME: $FAIL_RUNTIME_CNT"
echo "  FAIL_DIFF:    $FAIL_DIFF_CNT"
echo "  SKIP:         $SKIP_CNT"
echo "=========================================="

# 生成报告
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
    echo "| Total | $TOTAL |"
    echo "| Pass | $PASS_CNT |"
    echo "| Fail (Compile) | $FAIL_COMPILE_CNT |"
    echo "| Fail (Runtime) | $FAIL_RUNTIME_CNT |"
    echo "| Fail (Diff) | $FAIL_DIFF_CNT |"
    echo "| Skip | $SKIP_CNT |"
    echo ""

    if [ -s "$FAIL_LOG" ]; then
        echo "## 失败明细"
        echo ""
        echo "| 脚本 | 类型 | 详情 |"
        echo "|------|------|------|"
        while IFS='|' read -r type name detail; do
            detail_short=$(echo "$detail" | head -c 150)
            echo "| $name | $type | $detail_short |"
        done < "$FAIL_LOG"
    else
        echo "## 无失败 ✅"
    fi
} > "$REPORT_FILE"

echo "报告已生成: $REPORT_FILE"
rm -rf "$TEMP_DIR"
