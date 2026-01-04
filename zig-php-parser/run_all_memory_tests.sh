#!/bin/bash

# Comprehensive memory leak test runner
# Runs both exception tests and OOP tests

echo "=========================================="
echo "  Comprehensive Memory Leak Testing"
echo "=========================================="
echo "Date: $(date '+%Y年%m月%d日 %H时%M分%S秒')"
echo ""

# Track results
TOTAL_PASSED=0
TOTAL_FAILED=0

# Run exception tests
echo "=== Phase 1: Exception Tests ==="
echo ""
./test_memory_leaks.sh > /tmp/exception_test_output.txt 2>&1
EXCEPTION_EXIT_CODE=$?

if [ $EXCEPTION_EXIT_CODE -eq 0 ]; then
    EXCEPTION_PASSED=$(grep "Passed:" /tmp/exception_test_output.txt | awk '{print $2}')
    EXCEPTION_FAILED=$(grep "Failed:" /tmp/exception_test_output.txt | awk '{print $2}')
    TOTAL_PASSED=$((TOTAL_PASSED + EXCEPTION_PASSED))
    TOTAL_FAILED=$((TOTAL_FAILED + EXCEPTION_FAILED))
    echo "Exception Tests: $EXCEPTION_PASSED passed, $EXCEPTION_FAILED failed"
else
    echo "Exception Tests: FAILED (exit code $EXCEPTION_EXIT_CODE)"
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi

echo ""

# Run OOP tests
echo "=== Phase 2: OOP Tests ==="
echo ""
./test_oop_memory_leaks.sh > /tmp/oop_test_output.txt 2>&1
OOP_EXIT_CODE=$?

if [ $OOP_EXIT_CODE -eq 0 ]; then
    OOP_PASSED=$(grep "Passed:" /tmp/oop_test_output.txt | awk '{print $2}')
    OOP_FAILED=$(grep "Failed:" /tmp/oop_test_output.txt | awk '{print $2}')
    TOTAL_PASSED=$((TOTAL_PASSED + OOP_PASSED))
    TOTAL_FAILED=$((TOTAL_FAILED + OOP_FAILED))
    echo "OOP Tests: $OOP_PASSED passed, $OOP_FAILED failed"
else
    echo "OOP Tests: FAILED (exit code $OOP_EXIT_CODE)"
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
fi

echo ""
echo "=========================================="
echo "  Overall Test Summary"
echo "=========================================="
echo "Total Tests Passed: $TOTAL_PASSED"
echo "Total Tests Failed: $TOTAL_FAILED"
echo ""

if [ $TOTAL_FAILED -eq 0 ]; then
    echo "✓ ALL TESTS PASSED - No memory leaks detected!"
    echo "The PHP interpreter is safe for production use."
else
    echo "✗ SOME TESTS FAILED - Memory leaks detected!"
    echo "Please review the test output logs for details."
fi

echo ""
echo "Detailed logs saved to:"
echo "  - memory_leak_test_results.log"
echo "  - oop_memory_leak_test_results.log"
echo ""

exit $TOTAL_FAILED