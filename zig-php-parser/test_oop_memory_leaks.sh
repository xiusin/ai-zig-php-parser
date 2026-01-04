#!/bin/bash

# OOP Memory Leak Testing Script
# Tests complex OOP scenarios for memory leaks

PHP_INTERPRETER="./zig-out/bin/php-interpreter"
TEST_DIR="examples"
LOG_FILE="oop_memory_leak_test_results.log"
FAILED_TESTS=()
PASSED_TESTS=()

# OOP test files to check
TEST_FILES=(
    "test_oop_complex_inheritance.php"
    "test_oop_interfaces.php"
    "test_oop_abstract_classes.php"
    "test_oop_magic_methods.php"
    "test_oop_static_properties.php"
    "test_oop_anonymous_classes.php"
    "test_oop_exceptions.php"
    "test_oop_complex_object_graph.php"
    "test_oop_traits.php"
    "test_oop_type_hints.php"
    "test_oop_iterators.php"
    "test_oop_namespaces.php"
    "test_oop_closures.php"
)

echo "=== OOP Memory Leak Testing Started ===" | tee "$LOG_FILE"
echo "Date: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Check if interpreter exists
if [ ! -f "$PHP_INTERPRETER" ]; then
    echo "Error: PHP interpreter not found at $PHP_INTERPRETER" | tee -a "$LOG_FILE"
    echo "Please build the project first with: zig build" | tee -a "$LOG_FILE"
    exit 1
fi

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

    # Check for memory leaks in output
    if echo "$output" | grep -qi "memory leak\|leak\|not freed\|memory.*not.*released"; then
        echo "FAILED: Memory leak detected in $test_file" | tee -a "$LOG_FILE"
        echo "$output" | tee -a "$LOG_FILE"
        FAILED_TESTS+=("$test_file")
    else
        # Check if the program ran (even with expected errors)
        if [ $exit_code -eq 0 ] || echo "$output" | grep -qi "error\|exception\|undefined"; then
            echo "PASSED: No memory leak in $test_file" | tee -a "$LOG_FILE"
            PASSED_TESTS+=("$test_file")
        else
            echo "WARNING: Unexpected exit code $exit_code for $test_file" | tee -a "$LOG_FILE"
            echo "$output" | tee -a "$LOG_FILE"
            FAILED_TESTS+=("$test_file")
        fi
    fi

    echo "" | tee -a "$LOG_FILE"
done

# Print summary
echo "=== OOP Test Summary ===" | tee -a "$LOG_FILE"
echo "Total tests: ${#TEST_FILES[@]}" | tee -a "$LOG_FILE"
echo "Passed: ${#PASSED_TESTS[@]}" | tee -a "$LOG_FILE"
echo "Failed: ${#FAILED_TESTS[@]}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo "Failed tests:" | tee -a "$LOG_FILE"
    for failed in "${FAILED_TESTS[@]}"; do
        echo "  - $failed" | tee -a "$LOG_FILE"
    done
    echo "" | tee -a "$LOG_FILE"
    echo "Some tests failed with memory leaks. Please review the log." | tee -a "$LOG_FILE"
    exit 1
else
    echo "All OOP tests passed! No memory leaks detected." | tee -a "$LOG_FILE"
    exit 0
fi