# AST-Direct 类型安全与控制流修复 Session 8-9

**日期**：2026-07-26  
**范围**：`src/aot/native_linker.zig` — AST-Direct 代码生成路径  
**目标**：消除全部 FAIL_COMPILE，修复 PHI 消解和 while-exit 控制流缺陷

---

## 一、TL;DR

两轮修复共修改 `native_linker.zig` 约 55 处代码生成点，涵盖三类系统性缺陷：

1. **Release 未检查 isAllocaReg**（5 脚本）：AST-Direct cleanup 直接生成 `reg_N.release(...)` 未区分 `*Value` 指针类型
2. **PHI 赋值未使用 writePtrAwareAssign**（2 脚本）：PHI 消解直接生成 `reg_N = reg_M;` 未区分 alloca 指针
3. **While-exit cond_br 未处理**（2 脚本）：`generateWhileFromLabels` 的 exit 块只处理 `.ret`，忽略 `.cond_br`
4. **else 分支嵌套 cond_br 时 PHI 未消解**（1 脚本修复）：if/elseif 结构中 else 分支的 PHI incoming 来自嵌套 if 的 merge 块而非 else 块本身

### 回归测试结果

| 类别 | 修复前 | Session 8 后 | Session 9 后 | 总变化 |
|------|--------|-------------|-------------|--------|
| PASS | 5 | 5 | 5 | 0 |
| **FAIL_COMPILE** | **10** | **0** | **0** | **-10** ✅ |
| FAIL_RUNTIME | 39 | 48 | 47 | +8 |
| FAIL_DIFF | 12 | 13 | 14 | +2 |
| SKIP | 1 | 1 | 1 | 0 |

**关键成就**：
- **FAIL_COMPILE 从 10 降至 0**（Session 8）
- f032 TypeError 已修复（Session 9），从 FAIL_RUNTIME 转为 FAIL_DIFF（仅差 2 行 rate limit 状态）
- 0 回归（已通过的 5 个脚本仍通过）

---

## 二、核心变更分析

### 2.1 Release isAllocaReg 检查（Session 8）

**问题**：AST-Direct cleanup 在 ret/throw 前生成 `reg_N.release(...)`，但 `reg_N` 可能是 `*Value` 指针。

**修复**：添加 `isAllocaReg` 检查：
```zig
// alloca 指针：reg_N.*.release(...)
// 非 alloca：reg_N.release(...)
```

**影响范围**：4 种缩进模式，~25 处代码生成点。

### 2.2 PHI 赋值 writePtrAwareAssign（Session 8）

**问题**：AST-Direct PHI 消解直接生成 `reg_N = reg_M;`，当 `reg_M` 是 `*Value` 时类型不匹配。

**修复**：替换为已有的 `writePtrAwareAssign` 函数，自动处理 4 种 alloca 组合。

### 2.3 While-Exit cond_br 处理（Session 8）

**问题**：`generateWhileFromLabels` 的 exit 块处理只处理 `.ret`，忽略 `.cond_br`。

**典型案例**（f081）：
```
[3] while_exit_2 → cond_br → if_then_5 / if_merge_6  ← exit 块有 if 条件
[6] if_then_5 → br → if_merge_6                       ← 未处理！
```

**修复**：添加 `.cond_br` case，递归调用 `generateLabelDrivenBlockRange` 处理后续块。

### 2.4 else 分支嵌套 cond_br 的 PHI 消解（Session 9）

**问题**：if/elseif 结构中，else 分支包含嵌套 if，PHI 的 incoming 来自嵌套 if 的 merge 块而非 else 块本身。

**典型案例**（f032 ValidationHandler::handle）：
```php
if (empty($data)) { ... } elseif (!isset($data['email'])) { ... }
return parent::handle($request);  // $request 为 null！
```

**根因**：`generateIfFromLabels` 和 cond_br case 的 else PHI 检查 `incoming2.block == else_block`，但 incoming 实际来自嵌套 if 的 merge 块。

**修复**：扩展匹配范围，检查 `is_not_then`（incoming 非 then 块即匹配）：
```zig
const is_else_block = incoming2.block == cond_br_data.else_block or ...;
const is_not_then = incoming2.block != cond_br_data.then_block and ...;
if (is_else_block or is_not_then) { ... }
```

**影响位置**：
1. `generateLabelDrivenBlockRange` 的 cond_br case（~line 6387）
2. `generateIfFromLabels` 的 else PHI（~line 8008）

---

## 三、影响与风险评估

### 3.1 是否破坏式变更

**否**。所有修改都是在原有逻辑基础上添加新处理路径或替换为已有函数。

### 3.2 需要注意的点

1. **`is_not_then` 匹配范围较广**：理论上可能匹配到不该匹配的 incoming。但实践验证（67 脚本回归测试）无回归。
2. **f080/f085 仍有 TypeError**：这些脚本的 IR 结构与 f032 不同，else 分支的嵌套结构更复杂，需要进一步排查。
3. **FAIL_RUNTIME 增加**：9 个脚本从 FAIL_COMPILE 转为 FAIL_RUNTIME（编译通过但运行时崩溃），需要后续排查。

---

## 四、后续开发/优化建议

| 优先级 | 影响面 | 落地成本 | 建议 |
|--------|--------|----------|------|
| P0 | 47 脚本 | 高 | 修复 FAIL_RUNTIME：优先排查 segfault 脚本（f031/f042/f043/f051/f056/f061/f072/f117/f178） |
| P0 | 2 脚本 | 低 | 修复 f080/f085 的 TypeError：排查不同 IR 结构下 else PHI 未消解的根因 |
| P1 | 14 脚本 | 中 | 修复 FAIL_DIFF：比对 PHP 和 AOT 输出差异 |
| P1 | 5 脚本 | 中 | 修复 PHPString double free（f025/f031/f072/f119/f160） |
| P2 | 全局 | 中 | 统一 AST-Direct cleanup release 为 helper 函数，减少重复代码 |
| P2 | 全局 | 中 | 为 else PHI 消解添加更精确的 incoming 匹配（基于 dominator tree） |
