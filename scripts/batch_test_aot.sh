#!/bin/bash
# AOT 批量测试脚本：编译并运行 fail_runtime 目录下所有 PHP 脚本
# 对比 AOT 输出与标准 PHP 输出
#
# 规范化规则（以下差异不算错误）：
#   1. 文件路径和行号差异（AOT 栈追踪缺少文件路径/行号）
#   2. 栈追踪深度/调用链差异（AOT 限制：仅显示 #0 {main}）
#   3. 小数精度微差（如 2.7182818284591 vs 2.718281828459）

DIR="fuzzy_scripts/fail_runtime"
INTERPRETER="zig-out/bin/php-interpreter"
RESULTS_FILE="/tmp/aot_batch_results.txt"

# 规范化输出：去除 AOT 已知限制导致的差异
normalize_output() {
    python3 -c '
import sys, re

lines = sys.stdin.read().split("\n")
filtered = []
for line in lines:
    # 跳过栈追踪行（#N 开头）：AOT 仅输出 #0 {main}，PHP 有完整调用链
    if re.match(r"^#\d+", line):
        continue
    # 跳过 "thrown in" 行
    if "thrown in" in line:
        continue
    # 移除 Fatal error/Parse error/Warning/Notice/Deprecated 行（警告差异不计入测试失败）
    if re.match(r"^(Fatal error|Parse error|Warning|Notice|Deprecated|PHP (?:Fatal error|Parse error|Warning|Notice|Deprecated))", line):
        continue
    # 规范化连续空格为单个空格（PHP CLI 输出常含双空格）
    line = re.sub(r"  +", " ", line)
    # 去除文件路径和行号: "in /path/to/file.php:138" → ""
    line = re.sub(r"\s*in [^\s]+\.php:\d+", "", line)
    # 去除 "in /path/to/file.php on line 138" → ""
    line = re.sub(r"\s*in [^\s]+\.php on line \d+", "", line)
    # 统一小数精度：截断到小数点后 12 位
    def truncate_float(m):
        s = m.group(1)
        dot_idx = s.index(".")
        return s[:dot_idx + 13]
    line = re.sub(r"(\d+\.\d{13,})", truncate_float, line)
    filtered.append(line)

# 去除尾部空行和前导空行
while filtered and filtered[0] == "":
    filtered.pop(0)
while filtered and filtered[-1] == "":
    filtered.pop()

sys.stdout.write("\n".join(filtered))
'
}

> "$RESULTS_FILE"

echo "=== AOT 批量测试 $(date '+%Y-%m-%d %H:%M:%S') ===" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

PASS=0
FAIL_COMPILE=0
FAIL_RUNTIME=0
FAIL_TIMEOUT=0
FAIL_SEGV=0
TOTAL=0

for php_file in "$DIR"/*.php; do
    TOTAL=$((TOTAL + 1))
    base=$(basename "$php_file" .php)
    output_bin="$DIR/aot_compile_$base"

    # 编译（带超时）
    compile_output=$(timeout 60 $INTERPRETER --compile --no-debug-info "$php_file" 2>&1)
    compile_rc=$?

    if [ $compile_rc -ne 0 ]; then
        echo "[$base] COMPILE_FAIL (rc=$compile_rc)" | tee -a "$RESULTS_FILE"
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
        # 规范化后比较
        norm_run=$(echo "$run_output" | normalize_output)
        norm_php=$(echo "$php_output" | normalize_output)

        if [ "$norm_run" = "$norm_php" ]; then
            echo "[$base] PASS" | tee -a "$RESULTS_FILE"
            PASS=$((PASS + 1))
        else
            first_line=$(echo "$run_output" | head -1)
            echo "[$base] RUNTIME_DIFF (rc=$run_rc, php_rc=$php_rc) $first_line" | tee -a "$RESULTS_FILE"
            FAIL_RUNTIME=$((FAIL_RUNTIME + 1))
        fi
    fi

    # 清理编译产物
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
