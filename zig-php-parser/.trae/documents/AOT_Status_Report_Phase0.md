# AOT 差异对比与收敛计划报告 (Phase 0)

**生成日期**: 2026-02-03
**状态**: Phase 0 完成

## 1. 核心发现：编译流程断裂

在尝试执行 Phase 0 验证时，发现 AOT 编译流程存在严重的路径依赖问题：

1.  **LLVM 强依赖**: `src/aot/compiler.zig` 目前硬编码调用 `src/aot/codegen.zig` 进行代码生成。
2.  **Codegen 损坏**: `src/aot/codegen.zig` 依赖 LLVM C API，这违反了“不引入 LLVM”的项目目标。目前已将其 Stub 化以通过编译。
3.  **Native Linker 未启用**: 虽然 `src/aot/native_linker.zig` 旨在实现无 LLVM 的转译（IR -> Zig -> Exe），但在 `compiler.zig` 中并未正确接管代码生成阶段。

**结论**: Phase 1 的首要任务不仅仅是补齐 Builtin，而是**重构 `compiler.zig` 以完全切换到 `native_linker.zig` 路径**。

## 2. IR Op 覆盖率 (62.35%)

共 85 个 IR Op，已实现 53 个。

| 状态 | 数量 | 主要缺失类别 |
|---|---|---|
| ✅ 已实现 | 53 | 算术运算, 比较运算, 流程控制, 基础内存操作 |
| ❌ 缺失 | 32 | 对象操作 (`clone`, `instanceof`), 闭包 (`closure_*`), 类型检查 (`type_check`), 位运算 (`bit_*`) |

**高优先级缺失 (P0/P1):**
- `type_check`, `get_type` (类型系统基础)
- `closure_new`, `closure_bind` (函数式特性)
- `bit_not`, `bit_or`, `bit_xor` (基础运算)

## 3. Builtin 覆盖率 (32.13%)

共 305 个解释器 Builtin，AOT 仅声明支持 98 个。

**P0 级严重缺失:**
- `json_encode` / `json_decode` (数据交换核心)
- `file_*` 系列 (部分缺失)
- `str_*` 系列 (部分缺失)

## 4. 验证脚本与复现

已创建验证脚本 `tests/aot_verification/json_test.php`:

```php
<?php
$data = ["a" => 1, "b" => 2];
$json = json_encode($data);
echo "Encoded: " . $json . "\n";
$decoded = json_decode($json, true);
echo "Decoded: " . $decoded["a"] . "\n";
```

**当前运行结果**:
```
error: code generation failed: LLVMUnavailable
```
(由于 `codegen.zig` 被 Stub 化，且 `compiler.zig` 仍尝试调用它)

## 5. 下一步行动建议 (Phase 1)

1.  **重构 AOT Pipeline**: 修改 `src/aot/compiler.zig`，移除 `codegen.zig` 依赖，完全委托给 `native_linker.zig` 处理 `generateCode` 阶段。
2.  **实现 `NativeLinker.generateModule`**: 确保 `native_linker.zig` 能够接收 IR Module 并生成 Zig 源码。
3.  **补齐 P0 Builtins**: 在 `native_linker.zig` 中注册 `json_*` 等核心函数。

