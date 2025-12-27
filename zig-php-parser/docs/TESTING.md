# Testing Guide

## Overview

The PHP interpreter uses a comprehensive testing strategy combining unit tests, property-based tests, integration tests, and compatibility tests to ensure correctness and reliability.

## Test Categories

### 1. Unit Tests

Located in `src/test_*.zig` files, these test individual components in isolation.

**Running Unit Tests:**
```bash
zig build test
```

**Test Files:**
- `test_enhanced_types.zig` - Type system tests
- `test_gc.zig` - Garbage collection tests
- `test_enhanced_functions.zig` - Function system tests
- `test_enhanced_parser.zig` - Parser tests
- `test_error_handling.zig` - Exception handling tests
- `test_object_integration.zig` - Object system integration
- `test_object_system.zig` - Object-oriented features
- `test_reflection.zig` - Reflection API tests
- `test_attribute_system.zig` - Attribute system tests

### 2. Property-Based Tests

These tests verify universal properties that should hold for all valid inputs.

**Example Property Test:**
```zig
test "String concatenation preserves UTF-8 encoding" {
    // Property: For any two valid UTF-8 strings, concatenation produces valid UTF-8
    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();
    
    for (0..100) |_| {
        const str1 = generateRandomUTF8String(random, allocator);
        const str2 = generateRandomUTF8String(random, allocator);
        
        const result = try str1.concat(str2);
        try expect(isValidUTF8(result.data));
        
        str1.deinit(allocator);
        str2.deinit(allocator);
        result.deinit(allocator);
    }
}
```

**Key Properties Tested:**
- Type conversion consistency
- Memory safety (no leaks, no double-free)
- Garbage collection correctness
- Function call semantics
- Object lifecycle management
- Error handling completeness

### 3. Integration Tests

Test complete PHP script execution end-to-end.

**Running Integration Tests:**
```bash
zig build test-compat
```

**Test Structure:**
```
tests/compatibility/
├── basic_types.php      # Basic data type operations
├── operators.php        # All PHP operators
├── control_flow.php     # If, loops, switch statements
├── functions.php        # Function definitions and calls
└── classes.php          # Object-oriented features
```

### 4. Compatibility Tests

Verify PHP specification compliance using the test runner:

```bash
./run_compatibility_tests.sh
```

**Test Coverage:**
- PHP 8.5 language features
- Standard library functions
- Error handling behavior
- Type coercion rules
- Object-oriented semantics

## Writing Tests

### Unit Test Guidelines

1. **Test Structure:**
```zig
test "descriptive test name" {
    const allocator = std.testing.allocator;
    
    // Setup
    var vm = try VM.init(allocator);
    defer vm.deinit();
    
    // Test action
    const result = try vm.someOperation();
    
    // Assertions
    try std.testing.expect(result.tag == .integer);
    try std.testing.expectEqual(@as(i64, 42), result.data.integer);
}
```

2. **Memory Management:**
   - Always use `std.testing.allocator`
   - Properly clean up allocated resources
   - Check for memory leaks

3. **Error Testing:**
```zig
test "error handling" {
    const allocator = std.testing.allocator;
    var vm = try VM.init(allocator);
    defer vm.deinit();
    
    // Test that invalid operation throws expected error
    try std.testing.expectError(error.TypeError, vm.invalidOperation());
}
```

### Property-Based Test Guidelines

1. **Property Definition:**
   - Start with "For any..." or "For all..."
   - Define clear invariants
   - Use appropriate generators

2. **Generator Functions:**
```zig
fn generateRandomValue(random: std.rand.Random, allocator: Allocator) !Value {
    const value_type = random.enumValue(Value.Tag);
    return switch (value_type) {
        .integer => Value{ .tag = .integer, .data = .{ .integer = random.int(i64) } },
        .string => try generateRandomString(random, allocator),
        // ... other types
    };
}
```

3. **Iteration Count:**
   - Minimum 100 iterations for property tests
   - More iterations for critical properties
   - Use deterministic seeds for reproducibility

### Integration Test Guidelines

1. **PHP Test Structure:**
```php
<?php
// Test description and purpose

// Setup
$test_data = setupTestData();

// Execute operations
$result = performOperations($test_data);

// Assertions using assert()
assert($result === $expected_value);
assert(count($array) === $expected_count);

echo "Test passed!\n";
?>
```

2. **Test Categories:**
   - Basic language features
   - Standard library functions
   - Error conditions
   - Edge cases
   - Performance characteristics

## Test Data Generation

### Random Data Generators

```zig
pub const TestGenerators = struct {
    pub fn generateRandomString(random: std.rand.Random, allocator: Allocator) !*PHPString {
        const length = random.uintLessThan(usize, 100);
        const bytes = try allocator.alloc(u8, length);
        defer allocator.free(bytes);
        
        for (bytes) |*byte| {
            byte.* = random.intRangeAtMost(u8, 32, 126); // Printable ASCII
        }
        
        return PHPString.init(allocator, bytes);
    }
    
    pub fn generateRandomArray(random: std.rand.Random, allocator: Allocator) !*PHPArray {
        const array = try PHPArray.init(allocator);
        const length = random.uintLessThan(usize, 50);
        
        for (0..length) |i| {
            const value = try generateRandomValue(random, allocator);
            try array.set(.{ .integer = @intCast(i) }, value);
        }
        
        return array;
    }
};
```

### Edge Case Testing

Important edge cases to test:
- Empty strings and arrays
- Maximum and minimum integer values
- Special float values (NaN, infinity)
- Null values in various contexts
- Deeply nested structures
- Large data sets
- Unicode edge cases

## Performance Testing

### Benchmark Tests

```bash
# Run performance benchmarks
zig build bench

# Run specific benchmark
./zig-out/bin/php-interpreter benchmark.php
```

### Memory Leak Detection

```bash
# Check for memory leaks
zig build leak-check

# Run with detailed memory tracking
valgrind --tool=memcheck --leak-check=full ./zig-out/bin/php-interpreter test.php
```

### Performance Regression Testing

Track key performance metrics:
- Function call overhead
- Object creation time
- Array operation speed
- String manipulation performance
- Garbage collection pause times

## Continuous Integration

### Automated Testing

The CI pipeline runs:
1. All unit tests
2. Property-based tests with extended iterations
3. Integration tests
4. Compatibility tests
5. Memory leak detection
6. Performance regression checks

### Test Coverage

Target coverage metrics:
- Line coverage: >90%
- Branch coverage: >85%
- Function coverage: >95%
- Property coverage: 100% (all defined properties tested)

### Quality Gates

Tests must pass these criteria:
- Zero test failures
- No memory leaks detected
- No performance regressions >10%
- All property tests pass with 1000+ iterations
- Compatibility tests match PHP behavior

## Debugging Test Failures

### Common Issues

1. **Memory Leaks:**
   - Check for missing `deinit()` calls
   - Verify proper cleanup in error paths
   - Use `std.testing.allocator` for leak detection

2. **Flaky Tests:**
   - Use deterministic random seeds
   - Avoid timing-dependent assertions
   - Properly initialize all variables

3. **Property Test Failures:**
   - Examine the failing counterexample
   - Verify generator correctness
   - Check property definition accuracy

### Debugging Tools

```zig
// Enable debug output in tests
const debug = @import("std").debug;

test "debug example" {
    debug.print("Debug value: {}\n", .{some_value});
    
    // Use breakpoints in debugger-friendly builds
    if (builtin.mode == .Debug) {
        @breakpoint();
    }
}
```

## Test Maintenance

### Adding New Tests

1. Identify the component or feature to test
2. Choose appropriate test type (unit/property/integration)
3. Write test following guidelines
4. Verify test passes and fails appropriately
5. Add to CI pipeline if needed

### Updating Existing Tests

1. Maintain backward compatibility when possible
2. Update test data generators for new features
3. Extend property tests for new invariants
4. Keep integration tests current with language changes

### Test Documentation

Document tests with:
- Purpose and scope
- Expected behavior
- Known limitations
- Maintenance notes

This comprehensive testing strategy ensures the PHP interpreter maintains high quality and reliability while supporting rapid development and feature additions.