# Performance Benchmarks

This directory contains performance benchmarks for the PHP-Zig interpreter.

## Structure

- `benchmark_runner.zig` - Main Zig benchmark runner for internal components
- `php_benchmarks/` - PHP scripts for comparison with PHP 8.x
- `baseline_results.json` - Baseline results for regression testing

## Running Benchmarks

### Zig Component Benchmarks
```bash
zig build bench
```

### PHP Comparison Benchmarks
```bash
# Run with PHP-Zig interpreter
./zig-out/bin/php-interpreter tests/benchmarks/php_benchmarks/arithmetic.php

# Run with PHP 8.x for comparison
php tests/benchmarks/php_benchmarks/arithmetic.php
```

## Benchmark Categories

1. **Arithmetic Operations** - Basic math operations performance
2. **String Operations** - String manipulation and concatenation
3. **Array Operations** - Array creation, access, and manipulation
4. **Function Calls** - Function invocation overhead
5. **Object Operations** - Object creation and method calls
6. **Memory Management** - GC and memory allocation performance
7. **Bytecode VM** - Bytecode execution performance

## Baseline Comparison

The baseline results are stored in `baseline_results.json` and used for regression testing.
A benchmark is considered a regression if it's more than 10% slower than the baseline.
