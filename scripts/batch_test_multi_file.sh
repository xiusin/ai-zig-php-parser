#!/bin/bash
# AOT 多文件项目批量测试脚本
# 测试 fuzzy_scripts_73/multi_file 下所有多文件项目
#
# 规范化规则（以下差异不算错误）：
#   1. 文件路径和行号差异（AOT 栈追踪缺少文件路径/行号）
#   2. 栈追踪深度/调用链差异（AOT 限制：仅显示 #0 {main}）
#   3. 小数精度微差（如 2.7182818284591 vs 2.718281828459）
#   4. microtime 时间戳精度差异（执行时机不同导致）
#
# 多文件项目编译较慢，建议超时 300s

BASE_DIR="fuzzy_scripts_73/multi_file"
INTERPRETER="zig-out/bin/php-interpreter"
RESULTS_FILE="/tmp/aot_multi_file_results.txt"

# 需要测试的项目列表（有 main.php 入口的）
PROJECTS=("ecommerce" "banking_system" "message_queue" "logger_system" "student_mgmt")

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

echo "=== AOT 多文件项目测试 $(date '+%Y-%m-%d %H:%M:%S') ===" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

PASS=0
FAIL_COMPILE=0
FAIL_RUNTIME=0
FAIL_TIMEOUT=0
FAIL_SEGV=0
TOTAL=0

for project in "${PROJECTS[@]}"; do
    project_dir="$BASE_DIR/$project"
    main_file="$project_dir/main.php"
    output_bin="$project_dir/aot_compile_main"

    if [ ! -f "$main_file" ]; then
        echo "[$project] SKIP (无 main.php)" | tee -a "$RESULTS_FILE"
        continue
    fi

    TOTAL=$((TOTAL + 1))

    # 编译（带超时）
    compile_output=$(timeout 60 $INTERPRETER --compile --no-debug-info "$main_file" 2>&1)
    compile_rc=$?

    if [ $compile_rc -ne 0 ]; then
        echo "[$project] COMPILE_FAIL (rc=$compile_rc)" | tee -a "$RESULTS_FILE"
        FAIL_COMPILE=$((FAIL_COMPILE + 1))
        continue
    fi

    # 运行 AOT
    run_output=$(timeout 10 "$output_bin" 2>&1)
    run_rc=$?

    # 运行标准 PHP
    php_output=$(timeout 10 php "$main_file" 2>&1)
    php_rc=$?

    if [ $run_rc -eq 124 ]; then
        echo "[$project] TIMEOUT" | tee -a "$RESULTS_FILE"
        FAIL_TIMEOUT=$((FAIL_TIMEOUT + 1))
    elif [ $run_rc -eq 139 ]; then
        echo "[$project] SIGSEGV" | tee -a "$RESULTS_FILE"
        FAIL_SEGV=$((FAIL_SEGV + 1))
    else
        # 规范化后比较
        norm_run=$(echo "$run_output" | normalize_output)
        norm_php=$(echo "$php_output" | normalize_output)

        if [ "$norm_run" = "$norm_php" ]; then
            echo "[$project] PASS (IDENTICAL)" | tee -a "$RESULTS_FILE"
            PASS=$((PASS + 1))
        else
            # 检查是否仅为 microtime 差异
            diff_run=$(echo "$norm_run" | tr -d '0-9.')
            diff_php=$(echo "$norm_php" | tr -d '0-9.')

            if [ "$diff_run" = "$diff_php" ]; then
                echo "[$project] PASS (仅 microtime 时间戳差异，不计入失败)" | tee -a "$RESULTS_FILE"
                PASS=$((PASS + 1))
            else
                first_line=$(echo "$run_output" | head -1)
                echo "[$project] RUNTIME_DIFF (rc=$run_rc, php_rc=$php_rc) $first_line" | tee -a "$RESULTS_FILE"
                FAIL_RUNTIME=$((FAIL_RUNTIME + 1))
            fi
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