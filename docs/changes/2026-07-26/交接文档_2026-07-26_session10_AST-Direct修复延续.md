# 交接文档：Session 8-10 AST-Direct 修复

**日期**：2026-07-26  
**范围**：`src/aot/native_linker.zig` — AST-Direct 代码生成路径  
**状态**：Session 8-9 修复保留，Session 10 回退

---

## 一、当前状态

| 指标 | 值 |
|------|-----|
| **FAIL_COMPILE** | **0** ✅ |
| FAIL_RUNTIME | 47 |
| FAIL_DIFF | 14 |
| PASS | 5 |
| SKIP | 1 |
| 总计 | 67 |

**FAIL_COMPILE 从 10 降至 0**（Session 8 修复），且无回归。

---

## 二、Session 8-9 修复内容（保留）

### 2.1 Release isAllocaReg 检查
- AST-Direct cleanup 的 `reg_N.release(...)` 添加 `isAllocaReg` 检查
- 对 `*Value` 指针生成 `reg_N.*.release(...)`
- 影响 ~25 处代码生成点

### 2.2 PHI 赋值 writePtrAwareAssign
- PHI 消解的 `reg_N = reg_M;` 替换为 `writePtrAwareAssign`
- 自动处理 4 种 alloca 组合
- 影响 ~11 处

### 2.3 While-Exit cond_br 处理
- `generateWhileFromLabels` exit 块添加 `.cond_br` case
- 递归处理 while 循环后的 if/逻辑条件块
- 修复 f081/f105

### 2.4 else 分支嵌套 cond_br 的 PHI 消解
- if/elseif 中 else 分支 PHI 的 incoming 来自嵌套 if 的 merge 块
- 扩展匹配：`is_not_then`（非 then 块即匹配）
- 修复 f032（TypeError: null given → FAIL_DIFF）

---

## 三、Session 10 尝试（已回退）

### 3.1 `||`/`&&` PHI 未消解

**问题**：`||`/`&&` 操作符生成的 `logical_rhs_`/`logical_merge_` 块未被 AST-Direct 识别为控制结构。PHI 在 merge 块中未消解，导致条件永远为 false。

**典型案例**（f027 isPrime）：
```php
if ($n % 2 === 0 || $n % 3 === 0) return false;  // 条件永远 false！
```

**修复尝试**：
1. 主循环添加 `logical_rhs_`/`logical_merge_` 识别
2. cond_br case 跳过 logical 目标
3. `generateIfFromLabels` 的 merge 搜索添加 `logical_merge_`
4. 控制结构检查添加 `logical_rhs_`

**结果**：
- `lcm` 函数修复成功（`lcm(4,6) = 12`）
- 但引入 f044 FAIL_COMPILE 回归（`coalesce_rhs_` 块被误处理）
- 净效果为 0（1 改善 + 1 回归）

**回退原因**：`logical_rhs_` 块的 `generateIfFromLabels` 处理范围可能包含 `coalesce_rhs_` 块但未正确处理。需要更精细的范围控制。

### 3.2 根因分析

`||`/`&&` 的 IR 结构：
```
[cond_br] → then=merge (left true) / else=logical_rhs (left false)
[logical_rhs] → cond_br → then=merge (right true) / else=merge (right false)
[logical_merge] → PHI
```

挑战：
1. `logical_rhs_` 块是 cond_br 的 **else_block**（非 then_block），`generateIfFromLabels` 需要取反条件
2. `logical_merge_` 可能在 `coalesce_rhs_` 块之后，`generateIfFromLabels` 范围包含 `coalesce_rhs_` 但不处理它
3. `break` 在 Zig switch case 中会退出 while 循环（不是只退出 switch）

---

## 四、后续建议

| 优先级 | 影响面 | 建议 |
|--------|--------|------|
| **P0** | 17+ 脚本 | 修复 `||`/`&&` PHI：需要为 `logical_rhs_` 块编写专用的 `generateLogicalExpr` 函数，不依赖 `generateIfFromLabels` |
| P0 | 47 脚本 | 排查 segfault/timeout 脚本 |
| P1 | 14 脚本 | 修复 FAIL_DIFF 输出差异 |
| P1 | 5 脚本 | 修复 PHPString double free |
| P2 | 全局 | 统一 AST-Direct cleanup release 为 helper 函数 |

### `||`/`&&` 修复方向

1. **专用生成函数**：为 `logical_rhs_`/`logical_merge_` 编写 `generateLogicalExpr`，不使用 `generateIfFromLabels`
2. **正确处理条件取反**：`logical_rhs_` 是 cond_br 的 else_block，条件需取反
3. **精确范围控制**：`generateLogicalExpr` 只处理 `logical_rhs_` 到 `logical_merge_` 之间的块，不跨越其他控制结构
4. **PHI 消解**：在 `logical_rhs_` 和 `logical_merge_` 的 then/else 分支中正确消解 PHI
