#!/bin/bash

# PHP Interpreter Compatibility Test Runner

set -e

INTERPRETER="./zig-out/bin/php-interpreter"
TEST_DIR="tests/compatibility"
PASSED=0
FAILED=0
TOTAL=0

echo "=== PHP Interpreter Compatibility Tests ==="
echo

# Check if interpreter exists
if [ ! -f "$INTERPRETER" ]; then
    echo "Error: Interpreter not found at $INTERPRETER"
    echo "Please run 'zig build' first"
    exit 1
fi

# Check if test directory exists
if [ ! -d "$TEST_DIR" ]; then
    echo "Error: Test directory not found at $TEST_DIR"
    exit 1
fi

# Function to run a single test
run_test() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .php)
    
    echo -n "Running $test_name... "
    TOTAL=$((TOTAL + 1))
    
    # Run test with a simple timeout mechanism using background process
    if "$INTERPRETER" "$test_file" > /tmp/test_output_$$ 2>&1; then
        echo "PASSED"
        PASSED=$((PASSED + 1))
    else
        echo "FAILED"
        FAILED=$((FAILED + 1))
        echo "  Error output:"
        cat /tmp/test_output_$$ | sed 's/^/    /'
        echo
    fi
    
    # Clean up temp file
    rm -f /tmp/test_output_$$
}

# Run all PHP test files
for test_file in "$TEST_DIR"/*.php; do
    if [ -f "$test_file" ]; then
        run_test "$test_file"
    fi
done

# Run example files as additional tests
echo
echo "=== Running Example Files ==="
echo

for example_file in examples/*.php; do
    if [ -f "$example_file" ]; then
        run_test "$example_file"
    fi
done

# Summary
echo
echo "=== Test Summary ==="
echo "Total tests: $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -eq 0 ]; then
    echo "All tests passed! ✅"
    exit 0
else
    echo "Some tests failed! ❌"
    exit 1
fi