#!/bin/bash
# 全量 AOT 回归测试：覆盖所有 PHP 测试目录（并行优化版）
#
# 优化策略：
#   - 全部并行执行（AOT 编译器使用进程唯一临时目录，并行安全）
#   - 进度提示 [i/N] 格式，便于监控
#
# 用法：
#   timeout 1200 bash scripts/full_regression_test.sh
#   PARALLEL_JOBS=8 timeout 1200 bash scripts/full_regression_test.sh

set -u

INTERPRETER="zig-out/bin/php-interpreter"
RESULTS_FILE="/tmp/aot_full_regression.txt"
PARALLEL_JOBS=${PARALLEL_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)}
TMP_RESULTS="/tmp/aot_results_$$"

cleanup() {
    rm -rf "$TMP_RESULTS"
}
trap cleanup EXIT

normalize_output() {
    python3 -c '
import sys, re

lines = sys.stdin.read().split("\n")
filtered = []
for line in lines:
    if re.match(r"^#\d+", line):
        continue
    if "thrown in" in line:
        continue
    if re.match(r"^(Fatal error|Parse error|Warning|Notice|Deprecated|PHP (?:Fatal error|Parse error|Warning|Notice|Deprecated))", line):
        continue
    line = re.sub(r"  +", " ", line)
    line = re.sub(r"\s*in [^\s]+\.php:\d+", "", line)
    line = re.sub(r"\s*in [^\s]+\.php on line \d+", "", line)
    def truncate_float(m):
        s = m.group(1)
        dot_idx = s.index(".")
        return s[:dot_idx + 13]
    line = re.sub(r"(\d+\.\d{13,})", truncate_float, line)
    filtered.append(line)

while filtered and filtered[0] == "":
    filtered.pop(0)
while filtered and filtered[-1] == "":
    filtered.pop()

sys.stdout.write("\n".join(filtered))
'
}

# 测试单个 PHP 文件（编译加锁串行，运行并行）
test_single() {
    local php_file="$1"
    local base=$(basename "$php_file" .php)
    local dir=$(dirname "$php_file")
    local output_bin="$dir/aot_compile_$base"

    # 编译（并行安全，AOT 编译器使用进程唯一临时目录）
    local compile_output=$(timeout 60 $INTERPRETER --compile --no-debug-info "$php_file" 2>&1)
    local compile_rc=$?

    if [ $compile_rc -ne 0 ]; then
        echo "COMPILE_FAIL"
        return 1
    fi

    # 运行 AOT（不加锁，并行）
    local run_output=$(timeout 10 "$output_bin" 2>&1)
    local run_rc=$?

    # 运行标准 PHP
    local php_output=$(timeout 10 php "$php_file" 2>&1)

    if [ $run_rc -eq 124 ]; then
        rm -f "$output_bin"
        echo "TIMEOUT"
        return 1
    elif [ $run_rc -eq 139 ]; then
        rm -f "$output_bin"
        echo "SIGSEGV"
        return 1
    else
        local norm_run=$(echo "$run_output" | normalize_output)
        local norm_php=$(echo "$php_output" | normalize_output)

        if [ "$norm_run" = "$norm_php" ]; then
            rm -f "$output_bin"
            echo "PASS"
            return 0
        else
            # 重试一次：并行竞态可能导致 AOT 或 PHP 输出异常
            local retry_run=$(timeout 10 "$output_bin" 2>&1)
            local retry_php=$(timeout 10 php "$php_file" 2>&1)
            rm -f "$output_bin"

            local norm_retry_run=$(echo "$retry_run" | normalize_output)
            local norm_retry_php=$(echo "$retry_php" | normalize_output)

            if [ "$norm_retry_run" = "$norm_retry_php" ]; then
                echo "PASS"
                return 0
            else
                echo "RUNTIME_DIFF"
                return 1
            fi
        fi
    fi
}

# 收集所有待测文件
ALL_FILES=()
for DIR in "fuzzy_scripts/pass" "fuzzy_scripts/fail_runtime" "fuzzy_scripts_73" "fuzzy_scripts_715/pass" "fuzzy_scripts_715/fail_runtime"; do
    for php_file in "$DIR"/*.php; do
        [ -f "$php_file" ] && ALL_FILES+=("$php_file")
    done
done
# 根目录唯一脚本（排除重复和 ob）
for php_file in fuzzy_scripts/test_ref_capture_repro.php fuzzy_scripts/test_ref_dump.php fuzzy_scripts/test_ref_simple2.php; do
    [ -f "$php_file" ] && ALL_FILES+=("$php_file")
done

TOTAL=${#ALL_FILES[@]}
rm -rf "$TMP_RESULTS"
mkdir -p "$TMP_RESULTS"

> "$RESULTS_FILE"

echo "=== 全量 AOT 回归测试 $(date '+%Y-%m-%d %H:%M:%S') ===" | tee -a "$RESULTS_FILE"
echo "并行度: $PARALLEL_JOBS  总脚本数: $TOTAL" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

# 并行执行（编译加锁串行，运行并行）
for i in "${!ALL_FILES[@]}"; do
    php_file="${ALL_FILES[$i]}"
    base=$(basename "$php_file")
    (
        result=$(test_single "$php_file")
        echo "$result" > "$TMP_RESULTS/result_$i.txt"
        echo "[$((i + 1))/$TOTAL] $base → $result" >&2
    ) &
    # 控制并行度
    if (( (i + 1) % PARALLEL_JOBS == 0 )); then wait; fi
done
wait

# 串行重跑非 PASS 项：消除并行竞态导致的误报
RETRY_COUNT=0
for i in "${!ALL_FILES[@]}"; do
    result=$(cat "$TMP_RESULTS/result_$i.txt" 2>/dev/null || echo "UNKNOWN")
    if [ "$result" != "PASS" ]; then
        php_file="${ALL_FILES[$i]}"
        base=$(basename "$php_file")
        retry_result=$(test_single "$php_file")
        if [ "$retry_result" != "$result" ]; then
            echo "$retry_result" > "$TMP_RESULTS/result_$i.txt"
            echo "  [RETRY] $base: $result → $retry_result" >&2
            RETRY_COUNT=$((RETRY_COUNT + 1))
        fi
    fi
done
if [ $RETRY_COUNT -gt 0 ]; then
    echo "串行重跑修正: $RETRY_COUNT 项" | tee -a "$RESULTS_FILE"
fi

# 汇总
TOTAL_PASS=0
TOTAL_FAIL_COMPILE=0
TOTAL_FAIL_RUNTIME=0
TOTAL_FAIL_TIMEOUT=0
TOTAL_FAIL_SEGV=0
FAILED_FILES=""

for i in "${!ALL_FILES[@]}"; do
    php_file="${ALL_FILES[$i]}"
    base=$(basename "$php_file")
    result=$(cat "$TMP_RESULTS/result_$i.txt" 2>/dev/null || echo "UNKNOWN")
    echo "  [$base] $result" | tee -a "$RESULTS_FILE"
    case $result in
        PASS) TOTAL_PASS=$((TOTAL_PASS + 1)) ;;
        COMPILE_FAIL) TOTAL_FAIL_COMPILE=$((TOTAL_FAIL_COMPILE + 1)); FAILED_FILES="$FAILED_FILES\n  COMPILE_FAIL: $php_file" ;;
        RUNTIME_DIFF) TOTAL_FAIL_RUNTIME=$((TOTAL_FAIL_RUNTIME + 1)); FAILED_FILES="$FAILED_FILES\n  RUNTIME_DIFF: $php_file" ;;
        TIMEOUT) TOTAL_FAIL_TIMEOUT=$((TOTAL_FAIL_TIMEOUT + 1)); FAILED_FILES="$FAILED_FILES\n  TIMEOUT: $php_file" ;;
        SIGSEGV) TOTAL_FAIL_SEGV=$((TOTAL_FAIL_SEGV + 1)); FAILED_FILES="$FAILED_FILES\n  SIGSEGV: $php_file" ;;
    esac
done

echo "" | tee -a "$RESULTS_FILE"
echo "=== 汇总 ===" | tee -a "$RESULTS_FILE"
echo "总计: $TOTAL" | tee -a "$RESULTS_FILE"
echo "通过: $TOTAL_PASS" | tee -a "$RESULTS_FILE"
echo "编译失败: $TOTAL_FAIL_COMPILE" | tee -a "$RESULTS_FILE"
echo "输出差异: $TOTAL_FAIL_RUNTIME" | tee -a "$RESULTS_FILE"
echo "超时: $TOTAL_FAIL_TIMEOUT" | tee -a "$RESULTS_FILE"
echo "段错误: $TOTAL_FAIL_SEGV" | tee -a "$RESULTS_FILE"

if [ -n "$FAILED_FILES" ]; then
    echo "" | tee -a "$RESULTS_FILE"
    echo "=== 失败文件 ===" | tee -a "$RESULTS_FILE"
    echo -e "$FAILED_FILES" | tee -a "$RESULTS_FILE"
fi
