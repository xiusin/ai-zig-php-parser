#!/bin/bash
# AOT 测试套件采集运行器：收集失败类型与内存统计，不在发现问题时直接修复

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../.."
SUITE_DIR="$SCRIPT_DIR/suite"
COMPILER="$PROJECT_ROOT/zig-out/bin/php-interpreter"
TIMEOUT="$SCRIPT_DIR/timeout.sh"

COMPILE_TIMEOUT=${COMPILE_TIMEOUT:-12}
RUN_TIMEOUT=${RUN_TIMEOUT:-4}
MAX_TESTS=${MAX_TESTS:-20}

REPORT_DIR="$PROJECT_ROOT/.zigphp_aot_reports"
TS="$(date +%Y%m%d_%H%M%S)"
REPORT_FILE="$REPORT_DIR/suite_collect_${TS}.md"
DATA_FILE="$REPORT_DIR/suite_collect_${TS}.tsv"

mkdir -p "$REPORT_DIR"

echo "# AOT Suite 采集报告" > "$REPORT_FILE"
echo "- 时间: $(date '+%F %T')" >> "$REPORT_FILE"
echo "- Suite: $SUITE_DIR" >> "$REPORT_FILE"
echo "- 编译器: $COMPILER" >> "$REPORT_FILE"
echo "- 编译超时: ${COMPILE_TIMEOUT}s" >> "$REPORT_FILE"
echo "- 运行超时: ${RUN_TIMEOUT}s" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo -e "name\tcompile_ok\trun_ok\tphp_exit\taot_exit\toutput_match\tstatus\talloc_stats\texpected\tactual" > "$DATA_FILE"

passed=0
failed=0
total=0

total_seen=0

status_pass=0
status_php_timeout=0
status_compile_fail=0
status_exe_missing=0
status_runtime_timeout=0
status_output_mismatch=0

rm -rf "$PROJECT_ROOT/.zigphp_aot_build" || true

run_capture() {
    local timeout_secs="$1"
    shift

    set +e
    local out
    out=$("$TIMEOUT" "$timeout_secs" "$@" 2>&1)
    local code=$?
    set -e

    printf "%s\n" "$out"
    return $code
}

tsv_escape() {
    local s="$1"
    s=${s//$'\t'/\\t}
    s=${s//$'\r'/\\r}
    s=${s//$'\n'/\\n}
    printf "%s" "$s"
}

for test_file in "$SUITE_DIR"/*.php; do
    if [ ! -f "$test_file" ]; then
        continue
    fi

    total_seen=$((total_seen + 1))
    if [ $total_seen -gt $MAX_TESTS ]; then
        break
    fi

    test_name=$(basename "$test_file" .php)
    total=$((total + 1))

    echo "[$total/$MAX_TESTS] $test_name" 1>&2

    # 1) PHP 期望输出
    expected_raw=""
    php_exit=0
    expected_raw=$(run_capture "$RUN_TIMEOUT" php "$test_file")
    php_exit=$?
    if [ $php_exit -ne 0 ]; then
        status="PHP_TIMEOUT"
        status_php_timeout=$((status_php_timeout + 1))
        echo -e "${test_name}\t0\t0\t${php_exit}\t-\t0\t${status}\t-\t-\t-" >> "$DATA_FILE"
        failed=$((failed + 1))
        continue
    fi
    expected=$(tsv_escape "$expected_raw")

    # 2) AOT 编译
    compile_ok=0
    if run_capture "$COMPILE_TIMEOUT" "$COMPILER" --compile "$test_file" > /dev/null; then
        compile_ok=1
    else
        compile_ok=0
        status="AOT_COMPILE_FAIL"
        status_compile_fail=$((status_compile_fail + 1))
        echo -e "${test_name}\t${compile_ok}\t0\t${php_exit}\t-\t0\t${status}\t-\t${expected}\t-" >> "$DATA_FILE"
        failed=$((failed + 1))
        continue
    fi

    exe_name="$PROJECT_ROOT/$test_name"
    if [ ! -f "$exe_name" ]; then
        status="AOT_EXE_MISSING"
        status_exe_missing=$((status_exe_missing + 1))
        echo -e "${test_name}\t${compile_ok}\t0\t${php_exit}\t-\t0\t${status}\t-\t${expected}\t-" >> "$DATA_FILE"
        failed=$((failed + 1))
        continue
    fi

    # 3) AOT 运行（开启 alloc stats 输出）
    actual_raw=""
    aot_exit=0
    run_ok=0

    set +e
    actual_raw=$(ZIGPHP_ALLOC_STATS=1 run_capture "$RUN_TIMEOUT" "$exe_name")
    aot_exit=$?
    set -e

    if [ $aot_exit -eq 0 ]; then
        run_ok=1
    else
        run_ok=0
        status="AOT_RUNTIME_TIMEOUT"
        status_runtime_timeout=$((status_runtime_timeout + 1))
        echo -e "${test_name}\t${compile_ok}\t${run_ok}\t${php_exit}\t${aot_exit}\t0\t${status}\t-\t${expected}\t-" >> "$DATA_FILE"
        rm -f "$exe_name" || true
        failed=$((failed + 1))
        continue
    fi

    alloc_stats_raw=$(echo "$actual_raw" | grep '^ALLOC_STATS ' || true)
    actual_out_raw=$(echo "$actual_raw" | grep -v '^ALLOC_STATS ' || true)

    alloc_stats=$(tsv_escape "$alloc_stats_raw")
    actual=$(tsv_escape "$actual_out_raw")

    # 4) 输出对比
    if [ "$expected" = "$actual" ] && [ $php_exit -eq $aot_exit ]; then
        output_match=1
        status="PASS"
        passed=$((passed + 1))
        status_pass=$((status_pass + 1))
    else
        output_match=0
        status="OUTPUT_MISMATCH"
        failed=$((failed + 1))
        status_output_mismatch=$((status_output_mismatch + 1))
    fi

    echo -e "${test_name}\t${compile_ok}\t${run_ok}\t${php_exit}\t${aot_exit}\t${output_match}\t${status}\t${alloc_stats}\t${expected}\t${actual}" >> "$DATA_FILE"

    rm -f "$exe_name" || true
done

echo "## 总览" >> "$REPORT_FILE"
echo "- 通过: $passed" >> "$REPORT_FILE"
echo "- 失败: $failed" >> "$REPORT_FILE"
echo "- 总计: $total" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "## 状态统计" >> "$REPORT_FILE"
echo "- PASS: $status_pass" >> "$REPORT_FILE"
echo "- PHP_TIMEOUT: $status_php_timeout" >> "$REPORT_FILE"
echo "- AOT_COMPILE_FAIL: $status_compile_fail" >> "$REPORT_FILE"
echo "- AOT_EXE_MISSING: $status_exe_missing" >> "$REPORT_FILE"
echo "- AOT_RUNTIME_TIMEOUT: $status_runtime_timeout" >> "$REPORT_FILE"
echo "- OUTPUT_MISMATCH: $status_output_mismatch" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "## 失败明细（来自 TSV）" >> "$REPORT_FILE"
echo "- TSV: $DATA_FILE" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "报告已生成: $REPORT_FILE"
