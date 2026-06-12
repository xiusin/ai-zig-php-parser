# PHP Interpreter Architecture

## Overview

This document describes the internal architecture of the PHP 8.5 interpreter implemented in Zig. The interpreter follows a traditional design with lexical analysis, parsing, and execution phases, enhanced with modern features like garbage collection and reflection.

## High-Level Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   PHP Source    │───▶│     Lexer       │───▶│     Parser      │
│     Code        │    │   (Tokenizer)   │    │   (AST Builder) │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Execution     │◀───│  Virtual Machine │◀───│  Abstract       │
│    Result       │    │      (VM)       │    │ Syntax Tree     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                    ┌─────────────────────────┐
                    │    Runtime System       │
                    │  ┌─────────────────┐    │
                    │  │  Type System    │    │
                    │  ├─────────────────┤    │
                    │  │ Garbage Collector│    │
                    │  ├─────────────────┤    │
                    │  │ Standard Library │    │
                    │  ├─────────────────┤    │
                    │  │ Error Handling  │    │
                    │  ├─────────────────┤    │
                    │  │ Reflection API  │    │
                    │  └─────────────────┘    │
                    └─────────────────────────┘
```

## Core Components

### 1. Lexical Analysis (`src/compiler/lexer.zig`)

The lexer converts PHP source code into a stream of tokens.

**Key Features:**
- UTF-8 string handling
- PHP-specific token recognition (variables, operators, keywords)
- Error recovery for malformed input
- Position tracking for error reporting

**Token Types:**
```zig
pub const TokenType = enum {
    // Literals
    integer,
    float,
    string,
    
    // Identifiers and variables
    identifier,
    variable,
    
    // Keywords
    k_if, k_else, k_while, k_for, k_function, k_class,
    k_public, k_private, k_protected, k_static,
    k_try, k_catch, k_finally, k_throw,
    
    // Operators
    plus, minus, multiply, divide, modulo,
    assign, plus_assign, minus_assign,
    equal, not_equal, less_than, greater_than,
    
    // Delimiters
    semicolon, comma, dot,
    l_paren, r_paren, l_brace, r_brace, l_bracket, r_bracket,
    
    // Special
    eof, invalid,
};
```

### 2. Syntax Analysis (`src/compiler/parser.zig`)

The parser builds an Abstract Syntax Tree (AST) from the token stream.

**Key Features:**
- Recursive descent parsing
- Operator precedence handling
- Error recovery and reporting
- Support for all PHP 8.5 syntax constructs

**AST Node Types:**
```zig
pub const NodeType = enum {
    // Expressions
    literal,
    variable,
    binary_op,
    unary_op,
    function_call,
    method_call,
    property_access,
    array_access,
    
    // Statements
    expression_stmt,
    assignment,
    if_stmt,
    while_stmt,
    for_stmt,
    foreach_stmt,
    function_decl,
    class_decl,
    try_stmt,
    
    // PHP 8.5 features
    pipe_expr,
    clone_with,
    attribute,
};
```

### 3. Virtual Machine (`src/runtime/vm.zig`)

The VM executes the AST using a tree-walking interpreter approach.

**Key Components:**
- **Environment Stack**: Manages variable scopes
- **Call Stack**: Tracks function calls and returns
- **Exception Handling**: Manages try-catch-finally blocks
- **Performance Monitoring**: Tracks execution statistics

**Execution Flow:**
```zig
pub fn eval(self: *VM, node: *ast.Node) !Value {
    switch (node.tag) {
        .literal => return self.evalLiteral(node),
        .variable => return self.evalVariable(node),
        .binary_op => return self.evalBinaryOp(node),
        .function_call => return self.evalFunctionCall(node),
        .assignment => return self.evalAssignment(node),
        // ... other node types
    }
}
```

### 4. Type System (`src/runtime/types.zig`)

Implements PHP's dynamic type system with automatic conversions.

**Value Representation:**
```zig
pub const Value = struct {
    tag: Tag,
    data: Data,
    
    pub const Tag = enum {
        null, boolean, integer, float, string,
        array, object, resource, builtin_function,
        user_function, closure,
    };
    
    pub const Data = union {
        null: void,
        boolean: bool,
        integer: i64,
        float: f64,
        string: *gc.Box(*PHPString),
        array: *gc.Box(*PHPArray),
        object: *gc.Box(*PHPObject),
        // ... other types
    };
};
```

**Type Conversion Matrix:**
- Automatic conversions follow PHP semantics
- Explicit type checking for strict mode
- Support for type hints and return type declarations

### 5. Garbage Collection (`src/runtime/gc.zig`)

Implements a hybrid garbage collection strategy.

**Collection Strategy:**
1. **Reference Counting**: Immediate cleanup for most objects
2. **Cycle Detection**: Periodic cleanup of circular references
3. **Generational Collection**: Separate young and old object spaces

**GC Box Structure:**
```zig
pub fn Box(comptime T: type) type {
    return struct {
        ref_count: u32,
        gc_info: GCInfo,
        data: T,
        
        pub const GCInfo = packed struct {
            color: Color = .white,
            buffered: bool = false,
            
            pub const Color = enum(u2) {
                white = 0,  // Not visited
                gray = 1,   // Visited, children not processed
                black = 2,  // Visited, children processed
                purple = 3, // Possible cycle root
            };
        };
    };
}
```

### 6. Standard Library (`src/runtime/stdlib.zig`)

Provides PHP's built-in functions organized by category.

**Function Categories:**
- **Array Functions**: `array_map`, `array_filter`, `array_reduce`, etc.
- **String Functions**: `strlen`, `substr`, `str_replace`, etc.
- **Math Functions**: `abs`, `round`, `sqrt`, `pow`, etc.
- **Date/Time Functions**: `date`, `time`, `strtotime`, etc.
- **File Functions**: `file_get_contents`, `file_put_contents`, etc.
- **JSON Functions**: `json_encode`, `json_decode`
- **Hash Functions**: `md5`, `sha1`, `hash`, etc.

**Function Registration:**
```zig
pub const BuiltinFunction = struct {
    name: []const u8,
    min_args: u8,
    max_args: u8,
    handler: *const fn(*VM, []const Value) anyerror!Value,
};

pub fn registerFunction(stdlib: *StandardLibrary, name: []const u8, func: *const BuiltinFunction) !void {
    try stdlib.functions.put(name, func);
}
```

### 7. Object System

Implements PHP's object-oriented features.

**Class Structure:**
```zig
pub const PHPClass = struct {
    name: *PHPString,
    parent: ?*PHPClass,
    interfaces: []const *PHPInterface,
    traits: []const *PHPTrait,
    
    properties: std.StringHashMap(Property),
    methods: std.StringHashMap(Method),
    constants: std.StringHashMap(Value),
    
    modifiers: ClassModifiers,
    attributes: []const Attribute,
};
```

**Inheritance Chain:**
- Single inheritance with `extends`
- Multiple interface implementation
- Trait composition with conflict resolution
- Method overriding with visibility rules

### 8. Error Handling (`src/runtime/exceptions.zig`)

Comprehensive error handling system.

**Exception Hierarchy:**
```
Throwable
├── Error
│   ├── ParseError
│   ├── TypeError
│   └── ArgumentCountError
└── Exception
    ├── RuntimeException
    ├── InvalidArgumentException
    └── [User-defined exceptions]
```

**Exception Context:**
```zig
pub const ExceptionContext = struct {
    exception: *PHPException,
    catch_blocks: []const CatchBlock,
    finally_block: ?*ast.Node,
    stack_trace: []const StackFrame,
};
```

### 9. Reflection System (`src/runtime/reflection.zig`)

Runtime introspection capabilities.

**Reflection Classes:**
- `ReflectionClass`: Class metadata and manipulation
- `ReflectionMethod`: Method information and invocation
- `ReflectionProperty`: Property access and modification
- `ReflectionFunction`: Function metadata
- `ReflectionParameter`: Parameter information

**Usage Example:**
```zig
const reflection_class = try ReflectionClass.init(allocator, some_class);
const methods = try reflection_class.getMethods();
for (methods) |method| {
    const result = try method.invoke(object_instance, args);
}
```

## Memory Management

### Allocation Strategy

1. **Small Objects**: Pool allocation for frequently used small objects
2. **Large Objects**: Direct allocation with tracking
3. **String Interning**: Shared storage for identical strings
4. **Array Optimization**: Specialized storage for different array types

### Garbage Collection Phases

1. **Mark Phase**: Identify reachable objects from roots
2. **Sweep Phase**: Deallocate unreachable objects
3. **Compact Phase**: Reduce memory fragmentation (optional)

### Memory Layout

```
┌─────────────────────────────────────────────────────────────┐
│                    Heap Memory Layout                        │
├─────────────────┬─────────────────┬─────────────────────────┤
│   Young Gen     │    Old Gen      │      Large Objects      │
│  (New objects)  │ (Long-lived)    │    (Arrays, Strings)    │
├─────────────────┼─────────────────┼─────────────────────────┤
│ Fast allocation │ Infrequent GC   │   Direct allocation     │
│ Frequent GC     │ Mark & Sweep    │   Reference counted     │
└─────────────────┴─────────────────┴─────────────────────────┘
```

## Performance Optimizations

### 1. Inline Caching

Cache method lookups and property access for faster repeated operations.

### 2. String Interning

Share memory for identical string literals and frequently used strings.

### 3. Array Specialization

Use different internal representations based on array usage patterns:
- Dense integer-indexed arrays
- Sparse associative arrays
- Mixed arrays with optimization hints

### 4. Function Call Optimization

- Direct calls for built-in functions
- Cached lookups for user functions
- Tail call optimization where possible

### 5. Memory Pool Management

- Pre-allocated pools for common object sizes
- Reduced allocation overhead
- Better cache locality

## Extensibility

### Adding New Built-in Functions

1. Define function signature in appropriate category
2. Implement handler function
3. Register in standard library initialization
4. Add tests for new functionality

### Adding New Language Features

1. Extend lexer for new tokens
2. Update parser for new syntax
3. Add AST node types
4. Implement evaluation in VM
5. Update type system if needed

### Custom Extensions

The architecture supports loadable extensions through:
- Function registration API
- Class registration system
- Custom type definitions
- Hook system for lifecycle events

## Testing Strategy

### Unit Tests
- Component isolation testing
- Mock dependencies where appropriate
- Edge case coverage

### Property-Based Tests
- Correctness properties verification
- Random input generation
- Invariant checking

### Integration Tests
- End-to-end PHP script execution
- Cross-component interaction testing
- Performance regression detection

### Compatibility Tests
- PHP specification compliance
- Standard library behavior matching
- Error handling consistency

## Future Enhancements

### Planned Features
1. **JIT Compilation**: Hot path optimization
2. **Async/Await**: Coroutine support
3. **FFI**: Foreign function interface
4. **Debugger**: Interactive debugging support
5. **Profiler**: Performance analysis tools

### Performance Improvements
1. **Better GC**: Concurrent garbage collection
2. **SIMD**: Vectorized operations for arrays
3. **Cache Optimization**: Better memory layout
4. **Compilation**: Bytecode intermediate representation

This architecture provides a solid foundation for a complete PHP interpreter while maintaining extensibility and performance.