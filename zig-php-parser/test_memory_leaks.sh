#!/bin/bash

# Memory leak testing script for PHP interpreter
# Tests various exception scenarios to detect memory leaks

PHP_INTERPRETER="./zig-out/bin/php-interpreter"
TEST_DIR="examples"
LOG_FILE="memory_leak_test_results.log"
DEBUG_ERRORS_FILE="exception_debug_errors.log"
FAILED_TESTS=()
PASSED_TESTS=()
DEBUG_ERRORS=()

# Test files to check
TEST_FILES=(
    "test_undefined_variable_in_array.php"
    "test_undefined_function_call.php"
    "test_undefined_method_call.php"
    "test_undefined_property_access.php"
    "test_undefined_class.php"
    "test_undefined_variable_in_function_arg.php"
    "test_undefined_variable_in_string_concat.php"
    "test_undefined_variable_in_arithmetic.php"
    "test_undefined_variable_in_array_access.php"
    "test_undefined_variable_in_if_condition.php"
    "test_undefined_variable_in_foreach.php"
    "test_undefined_variable_in_assignment.php"
    "test_call_user_func_with_undefined.php"
    "test_call_user_func_array_with_undefined.php"
    "test_undefined_variable_in_echo.php"
    "test_undefined_variable_in_class_property.php"
    "test_undefined_variable_in_return.php"
    "test_undefined_variable_in_while.php"
    "test_undefined_variable_in_for.php"
    "test_line_numbers.php"
    "dynamic_features.php"
    "test_parent_simple.php"
    "test_multiple_undefined_in_array.php"
    "test_undefined_in_nested_array.php"
    "test_undefined_in_closure.php"
    "test_undefined_in_static_method.php"
    "test_undefined_in_static_property.php"
    "test_undefined_in_try_catch.php"
    "test_undefined_in_ternary.php"
    "test_undefined_in_coalesce.php"
    "test_undefined_in_spaceship.php"
    "test_undefined_in_switch.php"
    "test_undefined_in_match.php"
    "test_undefined_in_array_map.php"
    "test_undefined_in_array_filter.php"
    "test_undefined_in_array_reduce.php"
    "test_undefined_in_recursive_function.php"
    "test_undefined_in_chained_method_call.php"
    "test_undefined_in_complex_expression.php"
    "test_undefined_in_multiple_closures.php"
    "test_undefined_in_class_inheritance.php"
    "test_undefined_in_interface.php"
    "test_undefined_in_array_merge.php"
    "test_undefined_in_array_keys.php"
    "test_undefined_in_array_values.php"
    "test_undefined_in_array_walk.php"
)

echo "=== Memory Leak Testing Started ===" | tee "$LOG_FILE"
echo "Date: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Check if interpreter exists
if [ ! -f "$PHP_INTERPRETER" ]; then
    echo "Error: PHP interpreter not found at $PHP_INTERPRETER" | tee -a "$LOG_FILE"
    echo "Please build the project first with: zig build" | tee -a "$LOG_FILE"
    exit 1
fi

# Clear previous debug errors file
> "$DEBUG_ERRORS_FILE"

# Run each test
for test_file in "${TEST_FILES[@]}"; do
    test_path="$TEST_DIR/$test_file"

    if [ ! -f "$test_path" ]; then
        echo "SKIP: $test_file not found" | tee -a "$LOG_FILE"
        continue
    fi

    echo "Testing: $test_file" | tee -a "$LOG_FILE"

    # Run the test and capture output
    output=$("$PHP_INTERPRETER" "$test_path" 2>&1)
    exit_code=$?

    # Check for DEBUG errors
    debug_errors=$(echo "$output" | grep -c "^DEBUG:")
    if [ "$debug_errors" -gt 0 ]; then
        echo "  ⚠️  Found $debug_errors DEBUG error(s) in $test_file" | tee -a "$LOG_FILE"
        echo "$output" | grep "^DEBUG:" | tee -a "$DEBUG_ERRORS_FILE"
        DEBUG_ERRORS+=("$test_file($debug_errors errors)")
    fi

    # Check for memory leaks in output
    # Look for patterns that indicate memory leaks
    if echo "$output" | grep -qi "memory leak\|leak\|not freed\|memory.*not.*released"; then
        echo "  ✗ FAILED: Memory leak detected in $test_file" | tee -a "$LOG_FILE"
        echo "$output" | tee -a "$LOG_FILE"
        FAILED_TESTS+=("$test_file")
    else
        # Check if the program ran (even with expected errors)
        if [ $exit_code -eq 0 ] || echo "$output" | grep -qi "error\|exception\|undefined"; then
            echo "  ✓ PASSED: No memory leak in $test_file" | tee -a "$LOG_FILE"
            PASSED_TESTS+=("$test_file")
        else
            echo "  ⚠️  WARNING: Unexpected exit code $exit_code for $test_file" | tee -a "$LOG_FILE"
            echo "$output" | tee -a "$LOG_FILE"
            FAILED_TESTS+=("$test_file")
        fi
    fi

    echo "" | tee -a "$LOG_FILE"
done

# Print summary
echo "=== Test Summary ===" | tee -a "$LOG_FILE"
echo "Total tests: ${#TEST_FILES[@]}" | tee -a "$LOG_FILE"
echo "Passed: ${#PASSED_TESTS[@]}" | tee -a "$LOG_FILE"
echo "Failed: ${#FAILED_TESTS[@]}" | tee -a "$LOG_FILE"
echo "DEBUG errors: ${#DEBUG_ERRORS[@]}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo "Failed tests:" | tee -a "$LOG_FILE"
    for failed in "${FAILED_TESTS[@]}"; do
        echo "  - $failed" | tee -a "$LOG_FILE"
    done
    echo "" | tee -a "$LOG_FILE"
    echo "Some tests failed with memory leaks. Please review the log." | tee -a "$LOG_FILE"
fi

if [ ${#DEBUG_ERRORS[@]} -gt 0 ]; then
    echo "Tests with DEBUG errors:" | tee -a "$LOG_FILE"
    for debug_err in "${DEBUG_ERRORS[@]}"; do
        echo "  - $debug_err" | tee -a "$LOG_FILE"
    done
    echo "" | tee -a "$LOG_FILE"
    echo "DEBUG errors saved to: $DEBUG_ERRORS_FILE" | tee -a "$LOG_FILE"
    echo "These may indicate unimplemented features or syntax issues." | tee -a "$LOG_FILE"
fi

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    exit 1
else
    echo "All tests passed! No memory leaks detected." | tee -a "$LOG_FILE"
    if [ ${#DEBUG_ERRORS[@]} -eq 0 ]; then
        echo "No DEBUG errors found." | tee -a "$LOG_FILE"
    fi
    exit 0
fi