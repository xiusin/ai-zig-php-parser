# Requirements Document

## Introduction

本文档定义了Zig-PHP解释器性能优化项目的需求规格。当前Zig实现的PHP解释器与原生PHP相比存在约2-4个数量级的性能差距（100-10000倍慢），本项目旨在通过系统性优化将性能差距缩小到1个数量级以内（10倍以内）。

## Glossary

- **Tree_Walking_Interpreter**: 树遍历解释器，直接遍历AST执行代码的解释方式
- **Bytecode_VM**: 字节码虚拟机，将AST编译为字节码后执行的解释方式
- **Value**: 运行时值类型，使用NaN-boxing或tagged union表示PHP值
- **GC**: 垃圾回收器，负责自动内存管理
- **Inline_Cache**: 内联缓存，用于加速属性访问和方法调用
- **String_Interning**: 字符串驻留，相同字符串共享存储以减少内存分配
- **Arena_Allocator**: 区域分配器，批量分配内存并一次性释放
- **NaN_Boxing**: 一种将多种类型编码到64位浮点数中的技术
- **Dispatch_Table**: 分发表，使用函数指针数组替代switch语句的优化技术
- **Type_Specialization**: 类型特化，根据运行时类型生成优化代码路径

## Requirements

### Requirement 1: Value表示优化

**User Story:** As a developer, I want the interpreter to use an efficient value representation, so that basic operations have minimal overhead.

#### Acceptance Criteria

1. THE Value_System SHALL use NaN-boxing to encode integers, floats, booleans, and null in a single 64-bit word without heap allocation
2. WHEN a Value is created for primitive types (int, float, bool, null) THEN the Value_System SHALL NOT perform any heap allocation
3. THE Value_System SHALL provide O(1) type checking through bit manipulation instead of tagged union switch
4. WHEN comparing two Values THEN the Value_System SHALL use direct bit comparison for primitive types
5. THE Value_System SHALL maintain reference counting only for heap-allocated types (string, array, object)

### Requirement 2: 内存分配优化

**User Story:** As a developer, I want the interpreter to minimize memory allocations, so that execution is not bottlenecked by allocator overhead.

#### Acceptance Criteria

1. THE Memory_Manager SHALL use arena allocation for AST nodes and temporary values within a single execution context
2. WHEN executing a function THEN the Memory_Manager SHALL use stack allocation for local variables instead of heap allocation
3. THE Memory_Manager SHALL implement object pooling for frequently allocated types (PHPString, PHPArray, CallFrame)
4. WHEN a string literal is encountered THEN the String_Interner SHALL return a cached reference if the string already exists
5. THE Memory_Manager SHALL batch deallocations to reduce allocator call frequency
6. WHEN the GC runs THEN the GC SHALL complete minor collections within 1ms for typical workloads

### Requirement 3: 执行循环优化

**User Story:** As a developer, I want the interpreter's main execution loop to be highly optimized, so that instruction dispatch overhead is minimized.

#### Acceptance Criteria

1. THE Bytecode_VM SHALL use computed goto (dispatch table) instead of switch statement for instruction dispatch
2. WHEN executing arithmetic operations on integers THEN the Bytecode_VM SHALL use specialized integer instructions without type checking
3. THE Bytecode_VM SHALL inline common instruction sequences (load-add-store, compare-branch)
4. WHEN a loop is detected THEN the Bytecode_VM SHALL mark it as a hot path for potential optimization
5. THE Bytecode_VM SHALL prefetch the next instruction during current instruction execution
6. THE Bytecode_VM SHALL use a register-based design for the top 8 stack slots to reduce memory access

### Requirement 4: 函数调用优化

**User Story:** As a developer, I want function calls to be fast, so that PHP code with many function calls performs well.

#### Acceptance Criteria

1. WHEN calling a builtin function THEN the VM SHALL use direct function pointer invocation without hash table lookup
2. THE VM SHALL cache resolved function references after first lookup
3. WHEN a function is called with known argument types THEN the VM SHALL skip type validation
4. THE VM SHALL reuse CallFrame objects from a pool instead of allocating new ones
5. WHEN a function returns THEN the VM SHALL use tail call optimization where applicable
6. THE VM SHALL inline small functions (< 10 instructions) at the bytecode level

### Requirement 5: 属性和方法访问优化

**User Story:** As a developer, I want property and method access to be fast, so that OOP code performs well.

#### Acceptance Criteria

1. THE VM SHALL use inline caching for property access with shape-based invalidation
2. WHEN accessing a property on an object THEN the VM SHALL use offset-based access if the object shape is cached
3. THE VM SHALL cache method lookups with class hierarchy invalidation
4. WHEN calling a method THEN the VM SHALL use monomorphic dispatch for single-class call sites
5. THE VM SHALL use polymorphic inline caches for call sites with 2-4 receiver types
6. IF a call site becomes megamorphic (>4 types) THEN the VM SHALL fall back to hash table lookup

### Requirement 6: 数组操作优化

**User Story:** As a developer, I want array operations to be fast, so that PHP code using arrays performs well.

#### Acceptance Criteria

1. THE PHPArray SHALL use a specialized representation for sequential integer-keyed arrays (packed arrays)
2. WHEN iterating over a packed array THEN the Iterator SHALL use direct index access without hash lookup
3. THE PHPArray SHALL use small-object optimization for arrays with ≤8 elements
4. WHEN searching in an array THEN the Array_Functions SHALL use SIMD instructions for integer arrays
5. THE PHPArray SHALL support copy-on-write semantics to avoid unnecessary copying
6. WHEN merging arrays THEN the Array_Functions SHALL pre-allocate the result array to avoid resizing

### Requirement 7: 字符串操作优化

**User Story:** As a developer, I want string operations to be fast, so that PHP code with string manipulation performs well.

#### Acceptance Criteria

1. THE PHPString SHALL use small-string optimization for strings ≤23 bytes
2. WHEN concatenating strings THEN the String_Builder SHALL use rope data structure for deferred concatenation
3. THE String_Functions SHALL use SIMD instructions for strlen, strcmp, and strstr operations
4. WHEN a string is used as a hash key THEN the PHPString SHALL cache its hash value
5. THE String_Interner SHALL use a lock-free concurrent hash table for multi-threaded scenarios
6. WHEN parsing string literals THEN the Parser SHALL directly intern constant strings

### Requirement 8: 字节码编译优化

**User Story:** As a developer, I want the bytecode compiler to generate efficient code, so that the VM executes fewer instructions.

#### Acceptance Criteria

1. THE Bytecode_Compiler SHALL perform constant folding for arithmetic expressions with literal operands
2. THE Bytecode_Compiler SHALL eliminate dead code that cannot be reached
3. WHEN a variable is assigned and immediately used THEN the Bytecode_Compiler SHALL use register allocation
4. THE Bytecode_Compiler SHALL perform common subexpression elimination within basic blocks
5. THE Bytecode_Compiler SHALL generate specialized instructions for common patterns (++$i, $a[$i])
6. THE Bytecode_Compiler SHALL inline constant array and string literals into the bytecode

### Requirement 9: 解析器优化

**User Story:** As a developer, I want the parser to be fast, so that script startup time is minimized.

#### Acceptance Criteria

1. THE Lexer SHALL use SIMD instructions for whitespace skipping and identifier scanning
2. THE Parser SHALL use a perfect hash table for keyword lookup
3. WHEN parsing a file THEN the Parser SHALL use memory-mapped I/O for large files
4. THE Parser SHALL generate AST nodes using arena allocation
5. THE Parser SHALL support incremental parsing for IDE integration
6. WHEN the same file is parsed multiple times THEN the Parser SHALL cache the AST

### Requirement 10: 垃圾回收优化

**User Story:** As a developer, I want garbage collection to have minimal impact on execution, so that the interpreter maintains consistent performance.

#### Acceptance Criteria

1. THE GC SHALL use generational collection with a nursery for short-lived objects
2. WHEN collecting the nursery THEN the GC SHALL complete within 1ms for typical workloads
3. THE GC SHALL use incremental marking to avoid long pauses
4. THE GC SHALL use write barriers only for cross-generational references
5. WHEN an object survives multiple collections THEN the GC SHALL promote it to the old generation
6. THE GC SHALL support concurrent sweeping to overlap with mutator execution

### Requirement 11: 基准测试和验证

**User Story:** As a developer, I want comprehensive benchmarks, so that I can measure and verify performance improvements.

#### Acceptance Criteria

1. THE Benchmark_Suite SHALL include micro-benchmarks for each optimization target
2. THE Benchmark_Suite SHALL include macro-benchmarks representing real PHP workloads
3. WHEN running benchmarks THEN the Benchmark_Suite SHALL report operations per second and memory usage
4. THE Benchmark_Suite SHALL compare results against native PHP 8.x
5. THE Benchmark_Suite SHALL detect performance regressions in CI
6. THE Benchmark_Suite SHALL generate detailed profiling reports for hotspot analysis
