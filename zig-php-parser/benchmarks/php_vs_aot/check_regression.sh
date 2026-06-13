#!/usr/bin/env bash
#
# Performance Regression Check Script
# Compares current benchmark results against a baseline and flags regressions > 20%.
#
# Usage:
#   ./check_regression.sh [baseline_csv] [current_csv]
#
# If no arguments are provided, it uses:
#   - baseline: results/baseline.csv
#   - current:  results/benchmark_results.csv
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
BASELINE="${1:-$RESULTS_DIR/baseline.csv}"
CURRENT="${2:-$RESULTS_DIR/benchmark_results.csv}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

REGRESSION_THRESHOLD=20  # percentage

echo "============================================"
echo "  Performance Regression Check"
echo "============================================"
echo "Baseline: $BASELINE"
echo "Current:  $CURRENT"
echo "Threshold: ${REGRESSION_THRESHOLD}%"
echo "============================================"
echo ""

if [ ! -f "$BASELINE" ]; then
    echo -e "${RED}ERROR: Baseline file not found: $BASELINE${NC}"
    echo "Run the benchmark suite first to generate a baseline."
    exit 1
fi

if [ ! -f "$CURRENT" ]; then
    echo -e "${RED}ERROR: Current results file not found: $CURRENT${NC}"
    echo "Run the benchmark suite first to generate current results."
    exit 1
fi

# Read baseline into an associative array
declare -A baseline_times
declare -A baseline_iters

while IFS=',' read -r bench time iters _; do
    # Skip header
    if [ "$bench" = "benchmark" ]; then
        continue
    fi
    baseline_times["$bench"]="$time"
    baseline_iters["$bench"]="$iters"
done < "$BASELINE"

# Read current into an associative array
declare -A current_times
declare -A current_iters

while IFS=',' read -r bench time iters _; do
    if [ "$bench" = "benchmark" ]; then
        continue
    fi
    current_times["$bench"]="$time"
    current_iters["$bench"]="$iters"
done < "$CURRENT"

# Compare
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0

printf "%-30s %12s %12s %10s %s\n" "Benchmark" "Baseline(s)" "Current(s)" "Change%" "Status"
printf "%-30s %12s %12s %10s %s\n" "------------------------------" "------------" "------------" "----------" "------"

for bench in "${!current_times[@]}"; do
    curr_time="${current_times[$bench]}"
    base_time="${baseline_times[$bench]:-}"
    curr_iter="${current_iters[$bench]}"
    base_iter="${baseline_iters[$bench]:-}"

    # Skip if no baseline entry (new benchmark)
    if [ -z "$base_time" ]; then
        printf "%-30s %12s %12s %10s %s\n" "$bench" "N/A" "${curr_time}s" "NEW" "${YELLOW}SKIP${NC}"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    # Skip if baseline or current had errors
    if [ "$base_time" = "ERROR" ] || [ "$curr_time" = "ERROR" ]; then
        printf "%-30s %12s %12s %10s %s\n" "$bench" "$base_time" "$curr_time" "ERROR" "${RED}SKIP${NC}"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    # Calculate percentage change
    # change% = (current - baseline) / baseline * 100
    # Positive = slower (regression), Negative = faster (improvement)
    change=$(echo "scale=2; ($curr_time - $base_time) / $base_time * 100" | bc 2>/dev/null || echo "0")

    # Determine status
    if echo "$change >= $REGRESSION_THRESHOLD" | bc -l 2>/dev/null | grep -q 1; then
        # Regression (slower by >= threshold)
        printf "%-30s %12s %12s %+9.1f%% %s\n" "$bench" "${base_time}s" "${curr_time}s" "$change" "${RED}FAIL${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    elif echo "$change <= -$REGRESSION_THRESHOLD" | bc -l 2>/dev/null | grep -q 1; then
        # Significant improvement (faster by >= threshold)
        printf "%-30s %12s %12s %+9.1f%% %s\n" "$bench" "${base_time}s" "${curr_time}s" "$change" "${GREEN}IMPROVED${NC}"
        PASS_COUNT=$((PASS_COUNT + 1))
    elif echo "$change > 0" | bc -l 2>/dev/null | grep -q 1; then
        # Slight slowdown (less than threshold)
        printf "%-30s %12s %12s %+9.1f%% %s\n" "$bench" "${base_time}s" "${curr_time}s" "$change" "${YELLOW}WARN${NC}"
        WARN_COUNT=$((WARN_COUNT + 1))
    else
        # No regression
        printf "%-30s %12s %12s %+9.1f%% %s\n" "$bench" "${base_time}s" "${curr_time}s" "$change" "${GREEN}PASS${NC}"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
done

# Check for benchmarks in baseline but not in current
for bench in "${!baseline_times[@]}"; do
    if [ -z "${current_times[$bench]:-}" ]; then
        printf "%-30s %12s %12s %10s %s\n" "$bench" "${baseline_times[$bench]}s" "MISSING" "-" "${RED}MISSING${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
echo "============================================"
echo "  Summary"
echo "============================================"
echo -e "  ${GREEN}PASS:${NC}     $PASS_COUNT"
echo -e "  ${YELLOW}WARN:${NC}     $WARN_COUNT"
echo -e "  ${RED}FAIL:${NC}     $FAIL_COUNT"
echo -e "  SKIP:     $SKIP_COUNT"
echo "============================================"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo ""
    echo -e "${RED}REGRESSION DETECTED: $FAIL_COUNT benchmark(s) degraded by >= ${REGRESSION_THRESHOLD}%${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}No significant regressions detected (threshold: ${REGRESSION_THRESHOLD}%)${NC}"
    exit 0
fi