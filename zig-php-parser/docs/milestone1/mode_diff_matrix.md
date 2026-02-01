# 执行模式差异矩阵（解释器 Tree/Bytecode/Fast 与 AOT）

## 单一真实源（功能点枚举）
- 功能点以 AST tag 为主索引，来源：[ast.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/compiler/ast.zig#L20-L115)

## 覆盖抽取口径（可复验）
- Tree-walking：`VM.eval` 的 `switch(ast_node.tag)`： [vm.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/runtime/vm.zig#L5587-L6191)
- Bytecode：`BytecodeGenerator.visitNode` 的 `switch(node.tag)`： [generator.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/bytecode/generator.zig#L303-L342)
- FastVM：`FastCompiler.compileNode` 的 `switch(node.tag)`： [fast_compiler.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/runtime/fast_compiler.zig#L132-L161)
- AOT（IR 生成）：`IRGenerator.generateStatement/generateExpression` 的 `switch(node.tag)`： [ir_generator.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/aot/ir_generator.zig#L671-L712) 与 [ir_generator.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/aot/ir_generator.zig#L1836-L1961)
- AOT（后端覆盖）：以 `IR.Instruction.Op` 与 `NativeLinker.generateInstruction` 的 `switch(inst.op)` 对照： [ir.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/aot/ir.zig) 与 [native_linker.zig](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/src/aot/native_linker.zig#L3545-L4073)

## 关键差异（P0）
| 差异点 | Tree | Bytecode | Fast | AOT | 影响面 | 备注 |
|---|---|---|---|---|---|---|
| 未覆盖节点处理方式 | 抛 Unsupported（显式失败） | `else => {}` 静默跳过 | `else` 静默跳过 | `else => const_null` 回退 | 差异矩阵可信度/一致性 | Bytecode/Fast 的“静默缺口”会导致“看似能跑但语义缺失” |
| `auto` 模式行为 | N/A | N/A | N/A | N/A | 模式选择 | 当前 `auto` 恒等 tree（`shouldUseBytecode=false`） |
| AOT 后端实现路径 | N/A | N/A | N/A | IR→Zig→zig build-exe | 性能/可控性 | LLVM codegen 现为 stub，需在后续里程碑补齐 |

## 差异矩阵文件
- 全量矩阵： [diff_matrix.xlsx](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/artifacts/diff_matrix.xlsx)
- 可审阅/可 diff： [diff_matrix.csv](file:///Users/xiusin/Desktop/zig-php/zig-php-parser/artifacts/diff_matrix.csv)
