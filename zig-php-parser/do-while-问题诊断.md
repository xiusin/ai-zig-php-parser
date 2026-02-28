# do-while 循环问题诊断报告

## 问题描述
test_10.php 的 do-while 循环完全不执行，输出为空。

## 诊断过程

### 1. 检查 Parser ✅
- `src/compiler/parser.zig:945` - parseDoWhile 函数存在且正确
- `src/compiler/parser.zig:282` - parseStatement 正确调用 parseDoWhile
- `src/compiler/keyword_lookup.zig:9` - "do" 关键字已定义
- **结论**: Parser 正确解析 do-while 语句

### 2. 检查 AST ✅
- `src/compiler/ast.zig:150` - do_while_stmt 结构定义正确
- `src/compiler/token.zig:55` - k_do token 已定义
- **结论**: AST 结构完整

### 3. 检查 Tree-Walking VM ✅
- `src/runtime/vm.zig:6222` - eval switch 中有 do_while_stmt 分支
- `src/runtime/vm.zig:7967` - evaluateDoWhileStatement 函数已实现
- `src/runtime/vm.zig:4090` - nodeOrChildrenContainYield 支持 do_while
- **结论**: Tree-walking 解释器支持完整

### 4. 发现根本原因 ❌
- `src/main.zig:197` - **默认执行模式是 `.bytecode`**
- `src/bytecode/` - **字节码生成器未实现 do-while**
- **结论**: 默认使用字节码模式，但字节码不支持 do-while

## 验证

```bash
# 默认模式（bytecode）- 不工作
./zig-out/bin/php-interpreter test_10.php
# 输出: (空)

# Tree-walking 模式 - 应该工作
./zig-out/bin/php-interpreter --mode=tree test_10.php
# 输出: 01234
```

## 解决方案

### 方案 1: 添加字节码支持（推荐）
在 `src/bytecode/compiler.zig` 中添加 do-while 字节码生成：

```zig
fn compileDoWhileStmt(self: *Compiler, stmt: anytype) !void {
    const loop_start = self.currentOffset();
    
    // 编译循环体
    try self.compileStmt(stmt.body);
    
    // 编译条件
    try self.compileExpr(stmt.condition);
    
    // 条件为真则跳回开始
    try self.emitJumpIfTrue(loop_start);
}
```

### 方案 2: 修改默认模式
修改 `src/main.zig:197`:
```zig
var execution_mode: ExecutionMode = .tree_walking;  // 改为 tree
```

### 方案 3: 字节码降级到 tree-walking
在字节码编译器遇到不支持的语句时，自动降级到 tree-walking 模式。

## 影响范围

### 受影响的测试
- test_10: do-while 基础测试
- test_149: do-while 循环（可能）
- 其他使用 do-while 的测试

### 其他可能缺失的字节码支持
需要检查以下语句是否有字节码支持：
- switch 语句
- match 表达式
- try-catch-finally
- yield/generator

## 建议

1. **立即**: 添加字节码 do-while 支持（工作量：30分钟）
2. **短期**: 审计所有 AST 节点，确保字节码完整支持
3. **长期**: 添加自动测试，确保 tree-walking 和 bytecode 行为一致

## 时间线

- 2026-02-28 13:19 - 开始调查
- 2026-02-28 13:45 - 发现根本原因
- 预计修复时间: 30-60 分钟
