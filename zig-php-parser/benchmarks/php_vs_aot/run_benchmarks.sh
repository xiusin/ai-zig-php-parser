#!/usr/bin/env bash
#
# PHP vs AOT Benchmark Runner
# Runs all PHP benchmarks and optionally AOT-compiled versions,
# producing a CSV comparison report.
#
# Usage:
#   ./run_benchmarks.sh                    # Run PHP benchmarks only
#   ./run_benchmarks.sh --aot <aot_dir>   # Run PHP + AOT benchmarks
#   ./run_benchmarks.sh --quick            # Use reduced iterations for quick testing
#   ./run_benchmarks.sh --output <file>    # Specify custom output CSV path
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$SCRIPT_DIR"
RESULTS_DIR="$SCRIPT_DIR/results"
PHP_BIN="${PHP_BIN:-php}"
OUTPUT_CSV="${RESULTS_DIR}/benchmark_results.csv"
BASELINE_CSV="${RESULTS_DIR}/baseline.csv"
MODE="php"        # "php" or "both"
QUICK_MODE=false

# Benchmark files in execution order
BENCHMARKS=(
    "bench_sum"
    "bench_fibonacci"
    "bench_fibonacci_iter"
    "bench_string_concat"
    "bench_string_replace"
    "bench_string_search"
    "bench_array_push"
    "bench_array_access"
    "bench_array_filter"
    "bench_quicksort"
    "bench_math"
    "bench_oop"
    "bench_nested_loop"
    "bench_if_else"
    "bench_recursion"
    "bench_hashmap"
    "bench_json_encode"
    "bench_json_decode"
    "bench_preg_match"
    "bench_closure"
    "bench_range"
    "bench_string_builder"
    "bench_multi_array"
    "bench_type_juggling"
    "bench_include"
    "bench_switch"
    "bench_ternary"
    "bench_global"
    "bench_string_length"
    "bench_bubble_sort"
)

# Reduced iterations for quick mode (1/10 of default)
declare -A QUICK_ITERS=(
    ["bench_sum"]=1000000
    ["bench_fibonacci"]=30
    ["bench_fibonacci_iter"]=30
    ["bench_string_concat"]=1000
    ["bench_string_replace"]=1000
    ["bench_string_search"]=1000
    ["bench_array_push"]=10000
    ["bench_array_access"]=10000
    ["bench_array_filter"]=1000
    ["bench_quicksort"]=1000
    ["bench_math"]=1000000
    ["bench_oop"]=100000
    ["bench_nested_loop"]=10
    ["bench_if_else"]=1000000
    ["bench_recursion"]=10
    ["bench_hashmap"]=10000
    ["bench_json_encode"]=100
    ["bench_json_decode"]=100
    ["bench_preg_match"]=10000
    ["bench_closure"]=100000
    ["bench_range"]=10000
    ["bench_string_builder"]=10000
    ["bench_multi_array"]=1000
    ["bench_type_juggling"]=1000000
    ["bench_include"]=100
    ["bench_switch"]=100000
    ["bench_ternary"]=1000000
    ["bench_global"]=1000000
    ["bench_string_length"]=1000000
    ["bench_bubble_sort"]=500
)

# Parse command line arguments
AOT_DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --aot)
            MODE="both"
            AOT_DIR="$2"
            shift 2
            ;;
        --quick)
            QUICK_MODE=true
            shift
            ;;
        --output)
            OUTPUT_CSV="$2"
            shift 2
            ;;
        --php-bin)
            PHP_BIN="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--aot <dir>] [--quick] [--output <file>] [--php-bin <path>]"
            exit 1
            ;;
    esac
done

# Create results directory
mkdir -p "$RESULTS_DIR"

# Detect CPU and system info for the report
CPU_INFO="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")"
PHP_VERSION="$("$PHP_BIN" -v 2>/dev/null | head -1 || echo "Unknown")"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

echo "============================================"
echo "  PHP vs AOT Benchmark Suite"
echo "============================================"
echo "Date:       $TIMESTAMP"
echo "PHP:        $PHP_VERSION"
echo "CPU:        $CPU_INFO"
echo "Mode:       $MODE"
echo "Quick mode: $QUICK_MODE"
echo "============================================"
echo ""

# Write CSV header
if [ "$MODE" = "both" ]; then
    echo "benchmark,php_time_sec,php_iterations,aot_time_sec,aot_iterations,speedup" > "$OUTPUT_CSV"
else
    echo "benchmark,php_time_sec,php_iterations" > "$OUTPUT_CSV"
fi

run_php_benchmark() {
    local bench="$1"
    local bench_file="$BENCH_DIR/${bench}.php"

    if [ ! -f "$bench_file" ]; then
        echo "WARNING: Benchmark file not found: $bench_file" >&2
        echo "ERROR"
        return 1
    fi

    # Build command with optional quick-mode iterations
    local cmd="$PHP_BIN $bench_file"
    if $QUICK_MODE && [ -n "${QUICK_ITERS[$bench]:-}" ]; then
        cmd="$PHP_BIN $bench_file ${QUICK_ITERS[$bench]}"
    fi

    # Run benchmark and capture output
    local output
    output="$($cmd 2>&1)" || {
        echo "WARNING: Benchmark $bench failed: $output" >&2
        echo "ERROR"
        return 1
    }

    echo "$output"
}

run_aot_benchmark() {
    local bench="$1"
    local aot_bin="$AOT_DIR/${bench}"

    if [ ! -f "$aot_bin" ] && [ ! -f "${aot_bin}.out" ]; then
        # Try common extensions
        for ext in "" ".out" ".exe" ".bin"; do
            if [ -f "${aot_bin}${ext}" ]; then
                aot_bin="${aot_bin}${ext}"
                break
            fi
        done
    fi

    if [ ! -f "$aot_bin" ] || [ ! -x "$aot_bin" ]; then
        echo "N/A"
        return 0
    fi

    local iters_arg=""
    if $QUICK_MODE && [ -n "${QUICK_ITERS[$bench]:-}" ]; then
        iters_arg=" ${QUICK_ITERS[$bench]}"
    fi

    local output
    output="$("$aot_bin" $iters_arg 2>&1)" || {
        echo "N/A"
        return 0
    }

    echo "$output"
}

parse_time() {
    # Parse the "time=X.XXXXXX seconds" from benchmark output
    local output="$1"
    echo "$output" | grep -oP 'time=\K[0-9.]+' | head -1
}

parse_iterations() {
    # Parse the "iterations=X" from benchmark output
    local output="$1"
    echo "$output" | grep -oP 'iterations=\K[0-9]+' | head -1
}

# Run all benchmarks
TOTAL=0
PASSED=0
FAILED=0

for bench in "${BENCHMARKS[@]}"; do
    TOTAL=$((TOTAL + 1))
    printf "[%2d/%2d] %-30s ... " "$TOTAL" "${#BENCHMARKS[@]}" "$bench"

    # Run PHP benchmark
    php_output="$(run_php_benchmark "$bench")"
    if [ "$php_output" = "ERROR" ]; then
        echo "PHP: FAILED"
        FAILED=$((FAILED + 1))
        echo "$bench,ERROR,-" >> "$OUTPUT_CSV"
        continue
    fi

    php_time="$(parse_time "$php_output")"
    php_iters="$(parse_iterations "$php_output")"

    if [ "$MODE" = "both" ]; then
        # Run AOT benchmark
        aot_output="$(run_aot_benchmark "$bench")"
        if [ "$aot_output" = "N/A" ]; then
            echo "PHP: ${php_time}s (AOT: N/A)"
            echo "$bench,$php_time,$php_iters,N/A,-,-" >> "$OUTPUT_CSV"
        else
            aot_time="$(parse_time "$aot_output")"
            aot_iters="$(parse_iterations "$aot_output")"
            speedup="$(echo "scale=2; $php_time / $aot_time" | bc 2>/dev/null || echo "N/A")"
            echo "PHP: ${php_time}s  AOT: ${aot_time}s  Speedup: ${speedup}x"
            echo "$bench,$php_time,$php_iters,$aot_time,$aot_iters,$speedup" >> "$OUTPUT_CSV"
        fi
    else
        echo "${php_time}s"
        echo "$bench,$php_time,$php_iters" >> "$OUTPUT_CSV"
    fi

    PASSED=$((PASSED + 1))
done

echo ""
echo "============================================"
echo "  Results: $PASSED/$TOTAL passed"
echo "  CSV:     $OUTPUT_CSV"
echo "============================================"

# Save as baseline if it doesn't exist
if [ ! -f "$BASELINE_CSV" ]; then
    cp "$OUTPUT_CSV" "$BASELINE_CSV"
    echo "Baseline saved to: $BASELINE_CSV"
fi

# Generate comparison report if baseline exists and this isn't the baseline itself
if [ -f "$BASELINE_CSV" ] && [ "$OUTPUT_CSV" != "$BASELINE_CSV" ]; then
    echo ""
    echo "--- Comparison with Baseline ---"
    "$SCRIPT_DIR/check_regression.sh" "$BASELINE_CSV" "$OUTPUT_CSV"
fi