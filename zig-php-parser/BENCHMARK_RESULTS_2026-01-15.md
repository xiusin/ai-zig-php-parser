# Performance Benchmark Results (2026-01-15)

## Test Environment
- Zig-PHP Interpreter: Tree-walking mode (default)
- PHP Version: 8.x
- Test: `tests/quick_benchmark.php`

## Results Comparison

| Benchmark | Zig-PHP (ms) | PHP 8 (ms) | Ratio | Zig-PHP ops/s | PHP 8 ops/s |
|-----------|-------------|-----------|-------|---------------|-------------|
| Int add | 193.4 | 1.8 | 107x | 516,940 | 56,337,193 |
| Int mul | 220.5 | 1.3 | 170x | 453,572 | 76,748,472 |
| Int cmp | 252.0 | 1.6 | 158x | 396,814 | 64,103,683 |
| Float add | 247.9 | 1.5 | 165x | 403,316 | 67,389,203 |
| Float mul | 390.5 | 1.2 | 325x | 256,103 | 81,096,365 |
| strlen | 988.5 | 1.3 | 760x | 101,168 | 77,030,376 |
| strpos | 995.4 | 2.1 | 474x | 100,457 | 46,795,760 |
| Array get | 342.4 | 1.7 | 201x | 292,036 | 59,730,903 |
| count | 941.6 | 2.6 | 362x | 106,201 | 38,476,323 |
| Prop get | 329.2 | 2.0 | 165x | 303,722 | 49,795,845 |
| Func call | 1737.8 | 2.6 | 668x | 57,546 | 39,060,384 |
| For loop | 4318.2 | 7.1 | 608x | 2,316 | 1,406,069 |
| Fib(15) | 13242.2 | 31.3 | 423x | 76 | 31,986 |
| **Total** | **24199.7** | **58.0** | **417x** | - | - |

## Analysis

### Current Performance Gap
- Average slowdown: ~417x compared to PHP 8
- Main bottlenecks:
  1. **Function calls** (668x slower) - CallFrame allocation overhead
  2. **Loops** (608x slower) - AST traversal overhead
  3. **String operations** (474-760x slower) - String allocation
  4. **Recursive calls** (423x slower) - Stack management

### Optimization Components Status

| Component | Status | Expected Improvement | Integrated |
|-----------|--------|---------------------|------------|
| FastVM (Bytecode) | ✅ Implemented | ~20x | ⚠️ Optional (--mode=fast) |
| NaN-boxing Value | ✅ Implemented | ~10x | ⚠️ Partial |
| SIMD String Ops | ✅ Implemented | ~3x | ✅ Yes |
| Shape System | ✅ Implemented | ~3x | ✅ Yes |
| Object Pool | ✅ Implemented | ~2x | ⚠️ Partial |
| CallFrame Pool | ✅ Implemented | ~2x | ✅ Yes |
| Generational GC | ✅ Implemented | ~2x | ⚠️ Optional |
| Adaptive GC | ✅ Implemented | ~1.5x | ✅ Yes (new) |

### Key Findings

1. **Tree-walking interpreter is the main bottleneck**
   - Each AST node requires function call overhead
   - No instruction caching or optimization

2. **FastVM not enabled by default**
   - FastVM provides bytecode execution
   - Currently requires `--mode=fast` flag
   - Limited feature support (numeric operations only)

3. **Memory allocation patterns**
   - Frequent small allocations for strings/arrays
   - Object Pool helps but not fully utilized

## Recommendations

### Short-term (Immediate Impact)
1. Enable FastVM for numeric-heavy workloads
2. Increase Object Pool usage in hot paths
3. Enable Generational GC for high-memory scenarios

### Medium-term (Significant Impact)
1. Expand FastVM to support more operations
2. Integrate NaN-boxing Value into main VM
3. Implement bytecode caching

### Long-term (Target: <50x slower)
1. Full bytecode compilation
2. JIT compilation for hot paths
3. Inline caching for all property access

## Test Commands

```bash
# Run Zig-PHP benchmark
./zig-out/bin/php-interpreter tests/quick_benchmark.php

# Run PHP 8 benchmark
php tests/quick_benchmark.php

# Run with FastVM (limited support)
./zig-out/bin/php-interpreter --mode=fast tests/quick_benchmark.php
```

## Conclusion

The Zig-PHP interpreter is currently ~417x slower than PHP 8 in tree-walking mode. 
The optimization components are implemented but not fully integrated into the main 
execution path. The primary bottleneck is the AST interpretation overhead, which 
can be addressed by enabling the FastVM bytecode execution mode.

Next steps:
1. Expand FastVM feature support
2. Make FastVM the default execution mode
3. Complete NaN-boxing Value integration
