# Zig-PHP Language Server Protocol (LSP) Implementation Plan

## Overview
This document tracks the development of the LSP for the Zig-PHP language. The goal is to provide editor features (diagnostics, definition lookup) by reusing the existing compiler frontend (`src/compiler`) with minimal changes to the core codebase.

## Status Legend
- [ ] Not Started
- [~] In Progress
- [x] Completed

## Roadmap

### Phase 1: Infrastructure & Build System
- [ ] **1.1 Project Structure**: Create `tool/lsp` directory and initial `main.zig`.
- [ ] **1.2 Build Configuration**: Update `build.zig` to expose compiler internals as a module and define the `zig-php-lsp` executable.
- [ ] **1.3 JSON-RPC Core**: Implement the basic LSP protocol loop (Content-Length header parsing, JSON serialization/deserialization).
- [ ] **1.4 Handshake**: Implement `initialize` and `initialized` handlers to allow editors (VS Code, Cursor) to connect.

### Phase 2: Diagnostics (Linting)
- [ ] **2.1 Document Synchronization**: Handle `textDocument/didOpen` and `textDocument/didChange` to keep in-memory file consistency.
- [ ] **2.2 Compiler Integration**: Integrate `PHPContext` and `Parser` into the LSP loop.
- [ ] **2.3 Error Reporting**: Convert `PHPContext.errors` into LSP `Diagnostic` objects and send `textDocument/publishDiagnostics`.

### Phase 3: Basic Language Features
- [ ] **3.1 Go to Definition**: Implement `textDocument/definition` by traversing the AST or using `PHPContext` symbol tables.
- [ ] **3.2 Hover Information**: Implement `textDocument/hover` to show type info or comments (if available in AST).

## Technical Notes
- **Communication**: Stdin/Stdout.
- **Concurrency**: Basic single-threaded event loop initially.
- **Memory Management**: Use `ArenaAllocator` per request or per document revision to manage AST memory.
