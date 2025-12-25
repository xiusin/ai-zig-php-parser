# PHP 8.5 Parser (Zig Implementation) TODO List

## 🎯 Project Overview
An industry-expert level PHP 8.5 parser implemented in Zig, focused on high performance, residency in memory, and modern language features. It utilizes Data-Oriented Design (DOD) with an index-based AST and SIMD-accelerated lexing.

---

## ✅ Current Progress (v0.8.5-integrated)

### Core Architecture
- [x] **Index-based AST**: Nodes use `u32` indices instead of pointers for memory efficiency.
- [x] **Persistent Context**: `PHPContext` manages `ArenaAllocator` and `StringPool`.
- [x] **String Interning**: Deduplication of identifiers (class names, variables) into `u32` IDs.
- [x] **Memory Management**: O(1) reset capability via `ArenaAllocator.reset(.retain_capacity)`.

### Lexer & Tokens
- [x] **Full Token Set**: Comprehensive mapping of PHP 8.5 keywords and operators.
- [x] **SIMD Optimization**: `@Vector` accelerated whitespace skipping (16-byte chunks).
- [x] **Stateful Lexing**: Support for script mode, string literals, and initial HTML mode.
- [x] **Heredoc/Nowdoc**: Preliminary support for boundary detection.

### Parser Features
- [x] **Pratt Parsing**: Operator precedence-based expression parsing.
- [x] **PHP 8.x Features**:
    - [x] **Attributes**: `#[Attribute]` parsing and attachment.
    - [x] **Property Hooks**: `get` and `set` syntax (PHP 8.4).
    - [x] **Constructor Promotion**: Visibility modifiers in parameters.
    - [x] **Match Expressions**: Complete parsing of arms and conditions.
    - [x] **Variadic/Unpacking**: `...$params` support in declarations and calls.
- [x] **High-Order Syntax**:
    - [x] **Closures**: `function() use($var)` variable capture.
    - [x] **Anonymous Classes**: `new class extends Base { ... }`.
    - [x] **Arrow Functions**: `fn() => expr`.
- [x] **Advanced Controls**: `go` keyword for coroutines, `namespace`, `use`, `global`, `static`, `const`.

### Reflection & Semantics
- [x] **Name Resolution**: FQCN resolution based on current namespace and imports.
- [x] **Symbol Indexing**: `ReflectionManager` for indexing classes, interfaces, traits, and enums.
- [x] **Error Recovery**: Panic mode implementation with `synchronize()` points.

---

## 🚀 Future Development Tasks

### Phase A: Lexer & Literal Depth (High Priority)
- [ ] **Advanced Interpolation**: Implement full parsing of `"{$obj->prop}"` and `"${var}"` within double quotes and Heredoc.
- [ ] **Heredoc Label Validation**: Ensure ending labels strictly match opening labels in `Lexer`.
- [ ] **Property Hook Refinement**: Support modifiers like `final get` or `abstract set` in `parsePropertyHook`.

### Phase B: Parser Detail & Robustness (Medium Priority)
- [ ] **Full Type System**: Support Union Types (`int|string`) and Intersection Types (`A&B`) in all type hints.
- [ ] **Constant Evaluation**: Implement a simple interpreter for constant folding (e.g., `const A = 1 << 2`).
- [ ] **Position Tracking**: Update `Lexer` to track line and column numbers; update `Error` struct to report them.

### Phase C: Semantic & Reflection Enhancement (Medium Priority)
- [ ] **Trait Mixin Expansion**: Implement `linkTraits` in `ReflectionManager` to copy methods from Traits to Classes.
- [ ] **Inheritance Chain Mapping**: Support recursive resolution of parent classes and implemented interfaces.
- [ ] **Built-in Symbol Injection**: Pre-populate the reflection index with PHP's internal functions and classes.

### Phase D: Performance & Integration (Optimization)
- [ ] **SIMD Identifier Scanning**: Use `@Vector` to validate identifier characters (A-Z, 0-9, _) in bulk.
- [ ] **Small String Optimization (SSO)**: Store short strings (< 8 chars) directly in the ID space to avoid hash map lookups.
- [ ] **Extended C API**: Export the AST traversal and Reflection queries via C ABI for external embedding.

---

## 🛠 Instructions for Future Agents
1. **Data-Oriented Design**: Never use pointers in AST nodes. Always store child indices (`Node.Index`).
2. **Memory Ownership**: All temporary allocations during a parse must go through `context.arena`.
3. **No Deletion**: Improve existing logic but do not remove keywords or high-order features (like `go` or `property hooks`).
4. **Test First**: Add new PHP snippets to `src/main.zig` and verify node counts after every parser change.
