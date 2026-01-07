# Memory Leak Testing Tasks

## Overview

Implementation tasks for systematic memory leak detection and fixing in the PHP interpreter.

## Tasks

- [x] 1. Build and verify interpreter
  - Build with ReleaseFast optimization
  - Verify build succeeds without errors
  - _Requirements: All_

- [x] 2. Fix critical bug: Function parameter binding
  - **BUG FOUND**: Function/method parameters were not accessible in function body
  - **ROOT CAUSE**: Parser was stripping `$` prefix from parameter names, but variable lookups kept the `$` prefix
  - **FIX**: Modified `src/compiler/parser.zig` to keep `$` prefix in parameter names
  - **VERIFIED**: Functions, methods, and constructors now work correctly
  - _Requirements: All_

- [x] 3. Execute basic functionality tests
  - [x] 3.1 Run hello.php - PASSED
  - [x] 3.2 Run functions.php - PASSED
  - [x] 3.3 Run oop.php - PASSED
  - [x] 3.4 Run test_oop_complex_object_graph.php - PASSED
  - [x] 3.5 Run test_array_methods_complete.php - PASSED
  - [x] 3.6 Run test_string_methods_complete.php - PASSED
  - _Requirements: US-2, US-3_

- [ ] 4. Execute concurrency test suite
  - [ ] 4.1 Run test_concurrency_comprehensive.php
    - NOTE: Test hangs on reentrant mutex test (expected - mutex is non-reentrant)
    - Need to modify test or skip reentrant tests
    - _Requirements: US-1_

- [ ] 5. Execute remaining OOP tests
  - [ ] 5.1 test_oop_deep_inheritance.php - Missing uniqid() function
  - [ ] 5.2 test_oop_traits.php - Method call on non-object issue
  - [ ] 5.3 test_oop_closures.php - $this not captured in closures
  - _Requirements: US-2_

- [ ] 6. Execute file operations test suite
  - [x] 6.1 Run test_file_operations_comprehensive.php
    - Runs without crashes
    - Some boolean comparison issues in test assertions
    - _Requirements: US-4_

- [ ] 7. Run unit tests
  - Some tests fail with signal 11 (segfault)
  - 1320/1320 tests passed, but 6 test executables crashed
  - Need investigation
  - _Requirements: All_

## Completed Fixes

### Fix 1: Function Parameter Binding Bug
**File**: `src/compiler/parser.zig`
**Change**: Removed code that stripped `$` prefix from PHP-style parameter names
**Impact**: All functions, methods, and constructors now correctly bind parameters

## Known Issues

1. **Mutex reentrant locking**: The Mutex implementation doesn't support reentrant locking (deadlocks on second lock from same thread)
2. **Closure $this binding**: `$this` is not properly captured in closures
3. **Some unit tests crash**: 6 test executables crash with signal 11

## Notes

- Use ReleaseFast build to avoid Debug LLVM bug
- Monitor for both crashes and memory growth
- Document all findings for future reference
