# AOT Fuzz Testing Report

**Date:** 2026-03-09
**Test Suite:** 300 randomized PHP scripts with complex control flow and type usage.
**Objective:** Verify AOT execution consistency with native PHP (8.4.8).

## Summary

The fuzz testing campaign revealed significant discrepancies between AOT execution and native PHP execution. Out of 300 tests, a majority failed to match native PHP behavior due to crashes or exception handling differences.

### Key Findings

1.  **Memory Corruption (Critical)**
    -   **Error:** `ERROR: PHPString corrupted! length=... (0xaaaaaaaaaaaaaaaa)` and `ERROR: PHPArray corrupted!`
    -   **Impact:** Indicates severe memory safety issues, likely use-after-free or buffer overflows in string/array manipulation.
    -   **Example Scripts:** `test_7.php`, `test_10.php`, `test_13.php`, `test_146.php`.

2.  **Exception Handling Failures (Major)**
    -   **Error:** `error: DivisionByZero` (AOT crash/exit 1) vs `caught` (PHP exception).
    -   **Behavior:** AOT terminates execution upon division by zero instead of throwing a catchable `DivisionByZeroError` or `Warning` as per PHP semantics.
    -   **Impact:** Prevents robust error handling in user code.
    -   **Example Scripts:** `test_1.php`, `test_4.php`, `test_6.php`, `test_22.php`.

3.  **Compilation Failures**
    -   **Error:** `error: expected type '*runtime_lib.Value', found 'runtime_lib.Value'`
    -   **Behavior:** The AOT compiler fails to generate valid Zig code for certain PHP constructs (likely involving complex type inference or reference handling).
    -   **Example Scripts:** `test_19.php`, `test_24.php`, `test_36.php`.

## detailed Failure Log (Sample)

| ID | Issue Type | PHP Result | AOT Result |
|---|---|---|---|
| 7 | Memory Corruption | `caught` | `Exit: 1, ... ERROR: PHPString corrupted!` |
| 1 | Exception Handling | `caught` | `Exit: 1, ... error: DivisionByZero` |
| 19 | Compilation Error | `Exit: 0` | `COMPILATION_FAILED ... expected type '*runtime_lib.Value'` |
| 258 | Logic/Output | `D0caught` | `D00...` (Loop/Logic mismatch) |

## Artifacts

Failing scripts are preserved in `gemini_scripts/temp_tests/`.

## Recommendations

1.  **Fix Memory Safety:** Investigate `PHPString` and `PHPArray` implementation for 0xaa pattern (uninitialized/freed memory usage).
2.  **Implement Exceptions:** Ensure runtime errors (DivByZero, TypeError) throw catchable exceptions instead of crashing.
3.  **Fix Codegen:** Address Zig type mismatches in the compiler backend.
