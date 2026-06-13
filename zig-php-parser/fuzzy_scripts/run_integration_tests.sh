#!/usr/bin/env bash
# ============================================================================
# zig-php-parser Integration Test Suite Runner
# ============================================================================
# Runs all fuzzy test PHP files in fuzzy_scripts/ directory through the
# php-interpreter and tracks pass/fail counts.
#
# Usage:
#   ./run_integration_tests.sh              # Run all tests in all modes
#   ./run_integration_tests.sh --mode safe  # Only ReleaseSafe mode
#   ./run_integration_tests.sh --mode fast  # Only ReleaseFast mode
#   ./run_integration_tests.sh --verbose    # Verbose output
#   ./run_integration_tests.sh --test <name> # Run single test file
#   ./run_integration_tests.sh --help       # Show help
# ============================================================================

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$SCRIPT_DIR"
BUILD_DIR="$PROJECT_DIR/zig-out"
INTERPRETER="$BUILD_DIR/bin/php-interpreter"
MANIFEST_FILE="$TEST_DIR/test_manifest.json"
REPORT_DIR="$TEST_DIR/reports"
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')
REPORT_FILE="$REPORT_DIR/integration_test_report_${TIMESTAMP}.txt"

# ============================================================================
# Color definitions
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ============================================================================
# Test tracking variables
# ============================================================================
declare -A TEST_RESULTS_SAFE   # filename -> "PASS"|"FAIL"|"TIMEOUT"|"BUILD_FAIL"
declare -A TEST_RESULTS_FAST
declare -A TEST_DURATIONS_SAFE
declare -A TEST_DURATIONS_FAST
declare -A TEST_DESCRIPTIONS

TOTAL_TESTS=0
PASS_COUNT_SAFE=0
FAIL_COUNT_SAFE=0
TIMEOUT_COUNT_SAFE=0
PASS_COUNT_FAST=0
FAIL_COUNT_FAST=0
TIMEOUT_COUNT_FAST=0
BUILD_SUCCESS_SAFE=false
BUILD_SUCCESS_FAST=false

# ============================================================================
# Test file list (ordered by test number)
# ============================================================================
ALL_TEST_FILES=(
    "test_001_variables.php"
    "test_003_type_juggling.php"
    "test_006_loops_for.php"
    "test_007_loops_while.php"
    "test_008_loops_foreach.php"
    "test_009_functions_basic.php"
    "test_010_closures.php"
    "test_012_arrays_basic.php"
    "test_018_magic_methods.php"
    "test_021_math_functions.php"
    "test_023_string_advanced.php"
    "test_029_callback.php"
    "test_030_variables_advanced.php"
    "test_033_namespaces.php"
    "test_047_readonly_props.php"
    "test_048_dnf_types.php"
    "test_049_type_system.php"
    "test_051_closures_advanced.php"
    "test_052_complex_expressions.php"
    "test_056_superglobals.php"
    "test_057_output_buffering.php"
    "test_063_sorting_algorithms.php"
    "test_064_string_manipulation.php"
    "test_065_array_walk.php"
    "test_068_misc_functions.php"
    "test_do_while_comprehensive.php"
    "test_runtime_functions.php"
)

# ============================================================================
# Options
# ============================================================================
RUN_SAFE=true
RUN_FAST=true
VERBOSE=false
SINGLE_TEST=""
TEST_TIMEOUT=60  # seconds per test

# ============================================================================
# Usage / Help
# ============================================================================
usage() {
    cat <<EOF
${BOLD}zig-php-parser Integration Test Runner${NC}

Usage: $0 [OPTIONS]

Options:
  --mode MODE     Test mode: safe, fast, all (default: all)
  --verbose       Enable verbose output
  --test NAME     Run only the specified test file (e.g. test_001_variables.php)
  --timeout SEC   Timeout per test in seconds (default: 60)
  --help          Show this help message

Examples:
  $0                          # Run all tests in all modes
  $0 --mode safe              # Run only ReleaseSafe tests
  $0 --test test_runtime_functions.php  # Run single test
  $0 --mode fast --verbose    # Verbose ReleaseFast tests
EOF
}

# ============================================================================
# Parse arguments
# ============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                case "${2:-}" in
                    safe) RUN_FAST=false ;;
                    fast) RUN_SAFE=false ;;
                    all)  ;;
                    *) echo -e "${RED}Error: Invalid mode '$2'. Use: safe, fast, all${NC}"; exit 1 ;;
                esac
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --test)
                SINGLE_TEST="$2"
                shift 2
                ;;
            --timeout)
                TEST_TIMEOUT="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown option '$1'${NC}"
                usage
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# Utility functions
# ============================================================================
log_section() {
    echo ""
    echo -e "${BOLD}${BLUE}================================================================================${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}================================================================================${NC}"
    echo ""
}

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC}  $1"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_verbose() {
    if $VERBOSE; then
        echo -e "       $1"
    fi
}

# ============================================================================
# Build step
# ============================================================================
build_project() {
    local mode="$1"  # ReleaseSafe or ReleaseFast
    local mode_flag="-Doptimize=$mode"
    
    log_info "Building project with ${BOLD}$mode${NC} optimization..."
    
    cd "$PROJECT_DIR"
    
    local build_output
    build_output=$(zig build $mode_flag 2>&1)
    local build_ret=$?
    
    if $VERBOSE; then
        echo "$build_output" | tail -20
    fi
    
    if [[ $build_ret -ne 0 ]]; then
        log_fail "Build failed for $mode"
        if ! $VERBOSE; then
            echo "$build_output" | tail -10
        fi
        return 1
    fi
    
    # Verify interpreter exists
    if [[ ! -f "$INTERPRETER" ]]; then
        log_fail "Interpreter binary not found at: $INTERPRETER"
        return 1
    fi
    
    log_success "Build successful: $INTERPRETER"
    return 0
}

# ============================================================================
# Run a single test
# ============================================================================
run_single_test() {
    local test_file="$1"
    local mode="$2"  # safe or fast
    local test_path="$TEST_DIR/$test_file"
    
    if [[ ! -f "$test_path" ]]; then
        log_fail "Test file not found: $test_file"
        return 2
    fi
    
    log_verbose "  Running: $test_file"
    
    # Execute with timeout
    local start_time
    start_time=$(date +%s.%N)
    
    local output
    local exit_code=0
    
    if timeout "$TEST_TIMEOUT" "$INTERPRETER" "$test_path" > /tmp/zig_php_test_output_$$.txt 2>&1; then
        exit_code=$?
    else
        exit_code=$?
    fi
    
    local end_time
    end_time=$(date +%s.%N)
    
    local duration
    duration=$(printf "%.2f" "$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")")
    
    # Determine result
    if [[ $exit_code -eq 124 ]]; then
        # timeout command returns 124 on timeout
        if $VERBOSE; then
            cat /tmp/zig_php_test_output_$$.txt
        fi
        rm -f /tmp/zig_php_test_output_$$.txt
        return 124
    elif [[ $exit_code -ne 0 ]]; then
        if $VERBOSE; then
            cat /tmp/zig_php_test_output_$$.txt
        fi
        rm -f /tmp/zig_php_test_output_$$.txt
        return 1
    fi
    
    # Check output for FAIL indicators if the test has self-checking
    if grep -q "^FAIL:" /tmp/zig_php_test_output_$$.txt 2>/dev/null; then
        if $VERBOSE; then
            cat /tmp/zig_php_test_output_$$.txt
        fi
        rm -f /tmp/zig_php_test_output_$$.txt
        return 1
    fi
    
    if $VERBOSE; then
        cat /tmp/zig_php_test_output_$$.txt
    fi
    
    rm -f /tmp/zig_php_test_output_$$.txt
    return 0
}

# ============================================================================
# Run all tests for a given mode
# ============================================================================
run_test_suite() {
    local mode="$1"        # safe or fast
    local mode_label="$2"  # ReleaseSafe or ReleaseFast
    
    local -n pass_count
    local -n fail_count
    local -n timeout_count
    local -n results_map
    local -n durations_map
    
    if [[ "$mode" == "safe" ]]; then
        pass_count=PASS_COUNT_SAFE
        fail_count=FAIL_COUNT_SAFE
        timeout_count=TIMEOUT_COUNT_SAFE
        results_map=TEST_RESULTS_SAFE
        durations_map=TEST_DURATIONS_SAFE
    else
        pass_count=PASS_COUNT_FAST
        fail_count=FAIL_COUNT_FAST
        timeout_count=TIMEOUT_COUNT_FAST
        results_map=TEST_RESULTS_FAST
        durations_map=TEST_DURATIONS_FAST
    fi
    
    log_section "Running Tests: $mode_label"
    
    local start_time
    start_time=$(date +%s)
    
    local test_files=()
    if [[ -n "$SINGLE_TEST" ]]; then
        test_files=("$SINGLE_TEST")
    else
        test_files=("${ALL_TEST_FILES[@]}")
    fi
    
    local test_index=0
    local test_total=${#test_files[@]}
    
    for test_file in "${test_files[@]}"; do
        test_index=$((test_index + 1))
        
        printf "  ${CYAN}[%3d/%3d]${NC} %-45s " "$test_index" "$test_total" "$test_file"
        
        local test_start
        test_start=$(date +%s.%N)
        
        local result_code=0
        run_single_test "$test_file" "$mode" || result_code=$?
        
        local test_end
        test_end=$(date +%s.%N)
        local duration
        duration=$(printf "%.2f" "$(echo "$test_end - $test_start" | bc -l 2>/dev/null || echo "0")")
        durations_map["$test_file"]="$duration"
        
        case $result_code in
            0)
                echo -e "${GREEN}PASS${NC} (${duration}s)"
                pass_count=$((pass_count + 1))
                results_map["$test_file"]="PASS"
                ;;
            124)
                echo -e "${YELLOW}TIMEOUT${NC} (${duration}s)"
                timeout_count=$((timeout_count + 1))
                results_map["$test_file"]="TIMEOUT"
                ;;
            *)
                echo -e "${RED}FAIL${NC} (${duration}s)"
                fail_count=$((fail_count + 1))
                results_map["$test_file"]="FAIL"
                ;;
        esac
    done
    
    local end_time
    end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    log_info "$mode_label suite completed in ${total_duration}s"
    echo ""
}

# ============================================================================
# Generate test report
# ============================================================================
generate_report() {
    mkdir -p "$REPORT_DIR"
    
    log_section "Generating Test Report"
    
    {
        echo "================================================================================"
        echo "  zig-php-parser Integration Test Report"
        echo "  Generated: $(date)"
        echo "  Project:   $PROJECT_DIR"
        echo "================================================================================"
        echo ""
        
        # --- ReleaseSafe Summary ---
        if $RUN_SAFE; then
            echo "=== ReleaseSafe Results =========================================="
            echo ""
            if $BUILD_SUCCESS_SAFE; then
                local safe_total=$((PASS_COUNT_SAFE + FAIL_COUNT_SAFE + TIMEOUT_COUNT_SAFE))
                local safe_pass_rate=0
                if [[ $safe_total -gt 0 ]]; then
                    safe_pass_rate=$(echo "scale=1; $PASS_COUNT_SAFE * 100 / $safe_total" | bc -l 2>/dev/null || echo "0")
                fi
                echo "  Build:        SUCCESS"
                echo "  Total Tests:  $safe_total"
                echo "  Passed:       $PASS_COUNT_SAFE"
                echo "  Failed:       $FAIL_COUNT_SAFE"
                echo "  Timeouts:     $TIMEOUT_COUNT_SAFE"
                echo "  Pass Rate:    ${safe_pass_rate}%"
                echo ""
                
                # Per-test details
                echo "  Test Details:"
                echo "  ------------"
                for test_file in "${ALL_TEST_FILES[@]}"; do
                    if [[ -n "${TEST_RESULTS_SAFE[$test_file]+x}" ]]; then
                        local result="${TEST_RESULTS_SAFE[$test_file]}"
                        local dur="${TEST_DURATIONS_SAFE[$test_file]}"
                        local marker=""
                        case "$result" in
                            PASS)    marker="✓" ;;
                            FAIL)    marker="✗" ;;
                            TIMEOUT) marker="⏱" ;;
                            *)       marker="?" ;;
                        esac
                        printf "    %s %-45s %-8s  %ss\n" "$marker" "$test_file" "$result" "$dur"
                    fi
                done
            else
                echo "  Build: FAILED - tests not run"
            fi
            echo ""
        fi
        
        # --- ReleaseFast Summary ---
        if $RUN_FAST; then
            echo "=== ReleaseFast Results =========================================="
            echo ""
            if $BUILD_SUCCESS_FAST; then
                local fast_total=$((PASS_COUNT_FAST + FAIL_COUNT_FAST + TIMEOUT_COUNT_FAST))
                local fast_pass_rate=0
                if [[ $fast_total -gt 0 ]]; then
                    fast_pass_rate=$(echo "scale=1; $PASS_COUNT_FAST * 100 / $fast_total" | bc -l 2>/dev/null || echo "0")
                fi
                echo "  Build:        SUCCESS"
                echo "  Total Tests:  $fast_total"
                echo "  Passed:       $PASS_COUNT_FAST"
                echo "  Failed:       $FAIL_COUNT_FAST"
                echo "  Timeouts:     $TIMEOUT_COUNT_FAST"
                echo "  Pass Rate:    ${fast_pass_rate}%"
                echo ""
                
                # Per-test details
                echo "  Test Details:"
                echo "  ------------"
                for test_file in "${ALL_TEST_FILES[@]}"; do
                    if [[ -n "${TEST_RESULTS_FAST[$test_file]+x}" ]]; then
                        local result="${TEST_RESULTS_FAST[$test_file]}"
                        local dur="${TEST_DURATIONS_FAST[$test_file]}"
                        local marker=""
                        case "$result" in
                            PASS)    marker="✓" ;;
                            FAIL)    marker="✗" ;;
                            TIMEOUT) marker="⏱" ;;
                            *)       marker="?" ;;
                        esac
                        printf "    %s %-45s %-8s  %ss\n" "$marker" "$test_file" "$result" "$dur"
                    fi
                done
            else
                echo "  Build: FAILED - tests not run"
            fi
            echo ""
        fi
        
        # --- Cross-mode comparison ---
        if $RUN_SAFE && $RUN_FAST && $BUILD_SUCCESS_SAFE && $BUILD_SUCCESS_FAST; then
            echo "=== Mode Comparison =============================================="
            echo ""
            printf "  %-45s %-10s %-10s\n" "Test File" "Safe" "Fast"
            printf "  %-45s %-10s %-10s\n" "$(printf '%.0s-' {1..45})" "$(printf '%.0s-' {1..10})" "$(printf '%.0s-' {1..10})"
            for test_file in "${ALL_TEST_FILES[@]}"; do
                local safe_r="${TEST_RESULTS_SAFE[$test_file]:-N/A}"
                local fast_r="${TEST_RESULTS_FAST[$test_file]:-N/A}"
                printf "  %-45s %-10s %-10s\n" "$test_file" "$safe_r" "$fast_r"
            done
            echo ""
        fi
        
        echo "================================================================================"
        echo "  Report saved to: $REPORT_FILE"
        echo "================================================================================"
        
    } | tee "$REPORT_FILE"
}

# ============================================================================
# Print final summary to console
# ============================================================================
print_summary() {
    echo ""
    echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║                    INTEGRATION TEST SUMMARY                     ║${NC}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local overall_exit_code=0
    
    if $RUN_SAFE; then
        echo -e "${BOLD}ReleaseSafe:${NC}"
        if $BUILD_SUCCESS_SAFE; then
            local s_total=$((PASS_COUNT_SAFE + FAIL_COUNT_SAFE + TIMEOUT_COUNT_SAFE))
            echo -e "  ${GREEN}Passed:${NC}   $PASS_COUNT_SAFE/$s_total"
            if [[ $FAIL_COUNT_SAFE -gt 0 ]]; then
                echo -e "  ${RED}Failed:${NC}   $FAIL_COUNT_SAFE/$s_total"
                overall_exit_code=1
            fi
            if [[ $TIMEOUT_COUNT_SAFE -gt 0 ]]; then
                echo -e "  ${YELLOW}Timeout:${NC}  $TIMEOUT_COUNT_SAFE/$s_total"
                overall_exit_code=1
            fi
        else
            echo -e "  ${RED}Build failed${NC}"
            overall_exit_code=1
        fi
        echo ""
    fi
    
    if $RUN_FAST; then
        echo -e "${BOLD}ReleaseFast:${NC}"
        if $BUILD_SUCCESS_FAST; then
            local f_total=$((PASS_COUNT_FAST + FAIL_COUNT_FAST + TIMEOUT_COUNT_FAST))
            echo -e "  ${GREEN}Passed:${NC}   $PASS_COUNT_FAST/$f_total"
            if [[ $FAIL_COUNT_FAST -gt 0 ]]; then
                echo -e "  ${RED}Failed:${NC}   $FAIL_COUNT_FAST/$f_total"
                overall_exit_code=1
            fi
            if [[ $TIMEOUT_COUNT_FAST -gt 0 ]]; then
                echo -e "  ${YELLOW}Timeout:${NC}  $TIMEOUT_COUNT_FAST/$f_total"
                overall_exit_code=1
            fi
        else
            echo -e "  ${RED}Build failed${NC}"
            overall_exit_code=1
        fi
        echo ""
    fi
    
    echo -e "Report: ${BOLD}$REPORT_FILE${NC}"
    echo ""
    
    return $overall_exit_code
}

# ============================================================================
# Main
# ============================================================================
main() {
    parse_args "$@"
    
    echo ""
    echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║          zig-php-parser Integration Test Suite Runner           ║${NC}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Project:      ${PROJECT_DIR}"
    echo -e "Test files:   ${#ALL_TEST_FILES[@]}"
    echo -e "Modes:        $($RUN_SAFE && echo -n 'ReleaseSafe ')$($RUN_FAST && echo -n 'ReleaseFast')"
    echo -e "Verbose:      $VERBOSE"
    echo -e "Timeout:      ${TEST_TIMEOUT}s per test"
    if [[ -n "$SINGLE_TEST" ]]; then
        echo -e "Single test:  $SINGLE_TEST"
    fi
    echo ""
    
    # Verify we are in the right place
    if [[ ! -f "$PROJECT_DIR/build.zig" ]]; then
        log_fail "Not in project root. build.zig not found at $PROJECT_DIR"
        exit 1
    fi
    
    # Track if any mode was run
    local any_mode_run=false
    
    # Run ReleaseSafe tests
    if $RUN_SAFE; then
        any_mode_run=true
        if build_project "ReleaseSafe"; then
            BUILD_SUCCESS_SAFE=true
            run_test_suite "safe" "ReleaseSafe"
        else
            BUILD_SUCCESS_SAFE=false
        fi
    fi
    
    # Run ReleaseFast tests
    if $RUN_FAST; then
        any_mode_run=true
        if build_project "ReleaseFast"; then
            BUILD_SUCCESS_FAST=true
            run_test_suite "fast" "ReleaseFast"
        else
            BUILD_SUCCESS_FAST=false
        fi
    fi
    
    if ! $any_mode_run; then
        log_warn "No test modes selected. Nothing to do."
        exit 0
    fi
    
    # Generate report
    generate_report
    
    # Print summary
    print_summary
    local final_exit_code=$?
    
    # Clean up
    rm -f /tmp/zig_php_test_output_$$.txt
    
    exit $final_exit_code
}

main "$@"