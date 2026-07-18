# AOT 异常路径 cleanup 完整性修复

| 字段 | 值 |
|------|-----|
| 日期 | 2026-07-18 |
| 轮次 | 第二十三轮 |
| 模块 | AOT 代码生成 / 异常路径内存安全 |
| 测试 | 61/61 ALL PASS (pass 37 + fail_runtime 17 + fuzzy_scripts_73 7) |

---

## 1. 高层摘要（TL;DR）

发现异常路径（try-catch）内存泄漏：`cleanup_regs` 仅收集 7 种指令的 result（`new_object`/`const_string`/`concat`/`array_new`/`call`/`global_get`/`load`），遗漏了 `method_call`/`static_method_call`/`property_get`/`clone`/`cast`/`box`/`array_get`/`interpolate` 等产生堆值的指令。异常发生时这些寄存器不被 cleanup → 内存泄漏。修复：扩展 `cleanup_regs` 收集范围为所有 `php_value`/`php_object` result，同时在 `generateCleanupCodeExcept` 中补齐 `ref_ptr`/`this`/`ref_param_alloca` 跳过逻辑防止 double free。

## 2. 核心变更

| 文件 | 变更点 | 描述 |
|------|--------|------|
| `native_linker.zig` ~line 3944 | `cleanup_regs` 收集逻辑 | 白名单（7种指令）→ 所有 `php_value`/`php_object` result |
| `native_linker.zig` ~line 7510 | `generateCleanupCodeExcept` | 补齐 `ref_ptr`/`this`/`ref_param_alloca` 跳过 |

## 3. 安全保障

| 机制 | 说明 |
|------|------|
| `ref_ptr` 跳过 | PHI/select 合并引用参数，不拥有值 |
| `$this` 跳过 | 持有 ctx 借用引用，不可释放 |
| `ref_param_alloca` 跳过 | 引用参数的 alloca，由调用者管理 |
| `alloca` 跳过 | 局部变量，函数退出自动清理 |
| `catch_used` 跳过 | catch 块仍需使用的值 |
| `regMayHeap` 检查 | 非堆值（int/float/bool）不释放 |
| `release` null 安全 | null/基本类型值的 release 是 no-op |

## 4. 测试结果

```
=== fuzzy_scripts_73: 7/7 PASS ===
=== fail_runtime: 17/17 PASS ===
=== pass: 37/37 PASS ===
总计: 61/61 ALL PASS, DIFF=0, FAIL=0
```
