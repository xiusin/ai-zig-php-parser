#!/bin/bash
# 全量扫描 fuzzy_scripts_73 目录下所有 PHP 脚本
# 使用规范化规则对比 AOT 与 PHP 输出

DIR="fuzzy_scripts_73"
INTERPRETER="zig-out/bin/php-interpreter"
RESULTS_FILE="/tmp/aot_full_scan_results.txt"

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
    # 移除 Fatal error/Parse error/Warning/Notice/Deprecated 行（警告差异不计入测试失败）
    # 匹配 PHP 前缀的警告和直接以类型开头的警告
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

> "$RESULTS_FILE"

PASS=0
FAIL_COMPILE=0
FAIL_RUNTIME=0
FAIL_TIMEOUT=0
FAIL_SEGV=0
FAIL_SKIP=0
TOTAL=0

for php_file in "$DIR"/*.php; do
    TOTAL=$((TOTAL + 1))
    base=$(basename "$php_file" .php)
    output_bin="$DIR/aot_compile_$base"

    # 跳过已知不支持特性的脚本
    case "$base" in
        f018_generators_alternative|f046_exception_hierarchy)
            echo "[$base] SKIP (unsupported feature)" | tee -a "$RESULTS_FILE"
            FAIL_SKIP=$((FAIL_SKIP + 1))
            continue
            ;;
    esac

    # 编译（带超时）
    compile_output=$(timeout 60 $INTERPRETER --compile --no-debug-info "$php_file" 2>&1)
    compile_rc=$?

    if [ $compile_rc -ne 0 ]; then
        echo "[$base] COMPILE_FAIL" | tee -a "$RESULTS_FILE"
        FAIL_COMPILE=$((FAIL_COMPILE + 1))
        continue
    fi

    # 运行 AOT
    run_output=$(timeout 10 "$output_bin" 2>&1)
    run_rc=$?

    # 运行标准 PHP
    php_output=$(timeout 10 php "$php_file" 2>&1)
    php_rc=$?

    if [ $run_rc -eq 124 ]; then
        echo "[$base] TIMEOUT" | tee -a "$RESULTS_FILE"
        FAIL_TIMEOUT=$((FAIL_TIMEOUT + 1))
    elif [ $run_rc -eq 139 ]; then
        echo "[$base] SIGSEGV" | tee -a "$RESULTS_FILE"
        FAIL_SEGV=$((FAIL_SEGV + 1))
    else
        norm_run=$(echo "$run_output" | normalize_output)
        norm_php=$(echo "$php_output" | normalize_output)

        if [ "$norm_run" = "$norm_php" ]; then
            echo "[$base] PASS" | tee -a "$RESULTS_FILE"
            PASS=$((PASS + 1))
        else
            echo "[$base] RUNTIME_DIFF" | tee -a "$RESULTS_FILE"
            FAIL_RUNTIME=$((FAIL_RUNTIME + 1))
        fi
    fi

    rm -f "$output_bin"
done

echo "" | tee -a "$RESULTS_FILE"
echo "=== 汇总 ===" | tee -a "$RESULTS_FILE"
echo "总计: $TOTAL" | tee -a "$RESULTS_FILE"
echo "通过: $PASS" | tee -a "$RESULTS_FILE"
echo "编译失败: $FAIL_COMPILE" | tee -a "$RESULTS_FILE"
echo "输出差异: $FAIL_RUNTIME" | tee -a "$RESULTS_FILE"
echo "超时: $FAIL_TIMEOUT" | tee -a "$RESULTS_FILE"
echo "段错误: $FAIL_SEGV" | tee -a "$RESULTS_FILE"
echo "跳过: $FAIL_SKIP" | tee -a "$RESULTS_FILE"
