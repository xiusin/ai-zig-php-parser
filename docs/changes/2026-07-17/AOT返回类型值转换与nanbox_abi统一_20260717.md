# AOT 返回类型值转换与 nanbox_abi 统一 变更摘要

> 日期：2026-07-17
> 轮次：第十二轮
> 全量测试：pass 37/37 + fail_runtime 17/17 + fuzzy_scripts_73 7/7 = 61/61 ALL PASS, DIFF=0

---

## 1. TL;DR

本轮完成两项后续建议并评估第三项：
1. **P3: 返回类型声明的值转换**：全链路修改 AST → parser → IR generator → native_linker，函数返回值按声明的标量类型做弱类型转换
2. **P2: nanbox_abi 常量冲突统一**：`shared/nanbox_abi.zig` 的 `TYPE_REF` 从 `0x0003...` 改为 `0x0002...`（与 aot 版一致），补全 `TYPE_BIGINT` 和 `TYPE_RESOURCE`
3. **P3: GC 完整循环检测**：已评估并回退——SEGV 根因是 AOT 生成的 retain/release 不完全精确，MarkGray 递减后 ref_count 误判为 0 导致提前释放

## 2. 影响范围

| 模块 | 影响面 | 风险等级 |
|------|--------|----------|
| AST `function_decl` 节点 | 全局函数返回类型解析 | 低 |
| parser `parseFunction` | 全局函数返回类型存储 | 低 |
| IR generator | `func.php_return_type`/`php_return_nullable` 填充 | 低 |
| native_linker return 生成 | 所有函数返回路径的值转换 | 中（已回归验证） |
| shared/nanbox_abi.zig | 解释器 nanbox 常量 | 低（值改名，不影响逻辑） |

## 3. 核心变更

| 文件 | 变更点 | 说明 |
|------|--------|------|
| `ast.zig` | `function_decl` 新增 `return_type: ?Index` | AST 节点存储返回类型 |
| `parser.zig` | `parseFunction` 存储返回类型 | 不再丢弃 `: type` 声明 |
| `ir.zig` | `IR.Function` 新增 `php_return_type`/`php_return_nullable` | 与 `return_type: Type`（IR 类型推断用）区分 |
| `ir_generator.zig` | `generateFunctionDecl`/`generateMethodDecl` 提取返回类型 | 全局函数和方法均填充 `func.php_return_type` |
| `native_linker.zig` | 新增 `writeReturnStmt`/`generateReturnStr` | 所有返回点统一使用辅助方法 |
| `native_linker.zig` | 返回点替换为 `writeReturnStmt` | 10+ 处 return 生成点改为带弱类型转换 |
| `shared/nanbox_abi.zig` | `TYPE_REF` 值修正 + 补全常量 | 消除与 aot 版的冲突 |

## 4. 详细变更分析

### 4.1 返回类型值转换全链路

**AST 层**：`function_decl` 节点新增 `return_type: ?Index = null` 字段

**Parser 层**：`parseFunction` 将 `parseType()` 结果存入 `return_type_idx` 而非丢弃

**IR 层**：`IR.Function` 新增 `php_return_type: ?[]const u8` 和 `php_return_nullable: bool`（与已有 `return_type: Type` 区分，后者用于 IR 类型推断）

**IR Generator 层**：
- `generateFunctionDecl`：从 `func_data.return_type` 提取返回类型，填充 `func.php_return_type`
- `generateMethodDecl`：从 `method_data.return_type` 提取返回类型，同时填充 `func.php_return_type`

**Native Linker 层**：
- `generateFunction`：设置 `self.current_return_type`/`current_return_nullable`
- 新增 `writeReturnStmt(writer, reg_id, is_alloca, indent)` 方法：有返回类型时生成 `php_coerce_value` 调用
- 新增 `generateReturnStr(reg_id, is_alloca, indent)` 方法：返回字符串版本（用于 `allocPrint+appendSlice` 路径）
- 10+ 处 return 生成点替换为 `writeReturnStmt`/`generateReturnStr`

**生成代码模式**：
```zig
// 有返回类型声明时：
return if (true and reg_0.isNull()) reg_0
     else runtime.php_coerce_value(reg_0, "int", runtime.runtime_allocator);
// 无返回类型声明时：
return reg_0;
```

### 4.2 nanbox_abi 常量统一

**冲突**：
- `shared/nanbox_abi.zig`: `TYPE_REF = 0x0003000000000000`
- `aot/nanbox_abi.zig`: `TYPE_BIGINT = 0x0003000000000000`

**修复**：将 shared 版与 aot 版统一：
```
TYPE_REF:      0x0002800000000000 (从 0x0003 改为 0x0002)
TYPE_BIGINT:   0x0003000000000000 (新增)
TYPE_RESOURCE: 0x0003800000000000 (新增)
```

### 4.3 GC 完整循环检测评估

**尝试**：将保守策略替换为 MarkGray → Scan → CollectWhite 三阶段完整算法

**结果**：SEGV (exit 139)

**根因分析**：AOT 生成的代码中，部分栈变量赋值路径未调用 `retain()`：
1. 对象赋值给局部变量时，某些代码路径只做 `reg_X = reg_Y`（值拷贝）而不 `retain`
2. MarkGray 递减内部引用后，这些对象的 ref_count 误判为 0
3. CollectWhite 阶段释放仍在栈上使用的对象 → SEGV

**结论**：完整循环检测算法本身正确，但需要先修复所有 retain/release 不精确问题。已回退到保守策略。

## 5. 影响与风险评估

- **破坏式变更**：否
- **需要特别注意的点**：
  - `function_decl` AST 节点新增字段，旧代码使用默认值 `null` 兼容
  - `IR.Function.php_return_type` 与 `return_type` 是不同字段（PHP 字符串 vs IR 类型枚举）
  - nanbox_abi `TYPE_REF` 值变更影响解释器模式，但解释器通过常量名引用不依赖具体值
- **复测路径**：`batch_test_pass.sh` + `batch_test_aot.sh` + `full_scan_aot.sh`

## 6. 后续开发建议

| 优先级 | 建议 | 影响面 | 落地成本 |
|--------|------|--------|----------|
| P3 | 修复 AOT retain/release 不精确 → 启用 GC 完整循环检测 | 内存泄漏修复 | 高（需审查所有对象赋值路径） |
| P2 | 系统死代码清理（rt_*.zig + runtime/） | 可维护性 | 低（零风险） |
| P3 | 返回类型声明的类型检查（TypeError 异常） | 类型安全完整性 | 中 |
