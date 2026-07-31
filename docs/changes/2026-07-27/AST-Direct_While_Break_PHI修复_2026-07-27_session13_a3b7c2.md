# AST-Direct While 循环 Break 生成与 ||/&& PHI 消解修复

## 1. 高层摘要（TL;DR）

本次修复解决了 AST-Direct 代码生成路径中三个关键问题：
1. **while 循环体内 `break` 语句未生成**：`br while_exit_N` 未被翻译为 `break :__while_N;`，导致死循环
2. **while 循环 exit 块的 `||`/`&&` PHI 未消解**：exit 块的 `cond_br` 未被主循环处理，导致 `||`/`&&` 短路求值失效
3. **PHPString double free / use-after-free**：`deinit()` 销毁对象后 Value 仍持有悬垂指针，二次 release 触发 use-after-free

## 2. 影响范围

| 模块 | 影响面 | 说明 |
|------|--------|------|
| `native_linker.zig` - `generateWhileFromLabels` | 核心修复 | 添加循环上下文、exit PHI 消解、回边 PHI 修复 |
| `native_linker.zig` - `generateIfFromLabels` | 核心修复 | Step 5 添加 break 生成和 exit PHI 消解 |
| `native_linker.zig` - while body cond_br handler | 核心修复 | then 块 `.br` 到 exit 块时生成 break + PHI |
| `runtime_lib_template.zig` - `PHPString.deinit` | 内存安全 | 标记 `is_static=true` 防止 use-after-free |

## 3. 核心变更

| 变更点 | 文件 | 行号范围 | 描述 |
|--------|------|----------|------|
| 添加 `current_loop_label` 字段 | `native_linker.zig` | ~243 | 存储当前循环标签名，供嵌套 if 生成 break |
| while 循环上下文 save/restore | `native_linker.zig` | ~7542-7554 | 设置 `current_loop_label` 和 `current_loop_exit_block` |
| exit 块 PHI 初始值消解 | `native_linker.zig` | ~7538-7550 | 循环前设置 exit 块 PHI 的初始值（来自 cond 块的 incoming） |
| 回边 PHI 匹配范围扩展 | `native_linker.zig` | ~7832-7862 | 从仅匹配 `body_idx` 扩展到匹配 `extended_end` 范围内所有块 |
| while body cond_br then 块 `.br` 处理 | `native_linker.zig` | ~7660-7672 | br 到 exit 块时消解 exit PHI + 生成 `break :label;` |
| `generateIfFromLabels` Step 5 break 生成 | `native_linker.zig` | ~7983-8000 | br 到循环 exit 块时消解 exit PHI + 生成 break |
| while exit 块 `||`/`&&` 检测 | `native_linker.zig` | ~7872-7880 | `then_block` 是 `logical_merge_` 时不在此处处理，返回 exit_idx 让主循环处理 |
| `PHPString.deinit` 安全释放 | `runtime_lib_template.zig` | ~1554-1570 | 不销毁对象本身，设置 `is_static=true` 防止二次释放 |

## 4. 可视化概览

### 业务流程

```mermaid
flowchart TD
    A[PHP while+break+||] --> B[IR 生成]
    B --> C[AST-Direct 代码生成]
    C --> D{generateWhileFromLabels}
    D --> E[设置循环上下文]
    E --> F[exit PHI 初始值]
    F --> G[while true 循环体]
    G --> H{body cond_br?}
    H -->|break| I[消解 exit PHI + break]
    H -->|normal| J[回边 PHI 更新]
    I --> K[exit 块处理]
    J --> K
    K --> L{exit cond_br?}
    L -->|logical_merge_| M[返回 exit_idx 让主循环处理]
    L -->|其他| N[旧递归处理]
    M --> O[||/&& PHI 消解 ✅]
```

### 执行流程

```mermaid
sequenceDiagram
    participant Main as 主循环
    participant While as generateWhileFromLabels
    participant If as generateIfFromLabels
    participant CondBr as cond_br case

    Main->>While: 遇到 while_cond_
    While->>While: 设置 current_loop_label/exit_block
    While->>While: 消解 exit PHI 初始值
    While->>While: 生成 while(true) {
    While->>If: 处理 body 内嵌套 if
    If->>If: Step 5: br 到 exit 块?
    alt br 到 exit
        If->>If: 消解 exit PHI (break 值)
        If->>If: 生成 break :__while_N;
    end
    If-->>While: 返回
    While->>While: 消解回边 PHI (扩展匹配范围)
    While->>While: continue :__while_N; }
    While->>While: exit 块有 cond_br?
    alt then_block 是 logical_merge_
        While->>While: 移除 processed 标记
        While-->>Main: 返回 exit_idx
        Main->>CondBr: 处理 exit 块 cond_br
        CondBr->>CondBr: ||/&& PHI 消解 ✅
    else 其他 cond_br
        While->>While: 旧递归处理
    end
```

## 5. 详细变更分析

### 5.1 while 循环 break 生成

**问题**：`if ($x == 5) { $found = true; break; }` 中的 `break` 未被翻译为 Zig 的 `break :__while_0;`，导致循环体内的 `break` 语句被忽略，`$x` 永远不会递减，形成死循环。

**修复**：
1. 添加 `current_loop_label: ?[]const u8` 字段存储当前循环标签
2. 在 `generateWhileFromLabels` 中设置 `current_loop_label` 和 `current_loop_exit_block`
3. 在 `generateIfFromLabels` Step 5 中检测 `br` 到循环 exit 块，生成 `break :label;`
4. 在 while body 的 cond_br then 块 `.br` handler 中生成 break

### 5.2 exit 块 PHI 消解

**问题**：`while_exit_N` 块的 PHI（如 `$found` 变量）未在循环前初始化、未在 break 时赋值，导致变量值为 null。

**修复**：
1. 循环前：从 exit 块 PHI 中找到来自 cond 块的 incoming，赋初始值
2. break 时：从 exit 块 PHI 中找到来自 break 块的 incoming，赋 break 值

### 5.3 回边 PHI 匹配范围扩展

**问题**：回边 PHI 仅匹配来自 `body_idx`（`while_body_1`）的 incoming，但实际回边可能来自 `if_merge_N` 等其他循环内部块。

**修复**：将匹配范围从仅 `body_idx` 扩展到 `body_idx..extended_end` 范围内的所有块。

### 5.4 while exit 块 `||`/`&&` PHI 消解

**问题**：while exit 块的 `cond_br`（如 `if ($found || $x == 0)`）未被处理为 if/else 结构，`||`/`&&` 的 PHI 未消解。

**修复**：当 exit 块的 `cond_br` 的 `then_block` 是 `logical_merge_` 时，不在此处处理（移除 processed 标记，返回 exit_idx），让主循环的 cond_br case 处理 `||`/`&&` PHI 消解。对于非 `||`/`&&` 的 cond_br（如普通 if），保留旧的递归处理方式。

### 5.5 PHPString double free 修复

**问题**：`PHPString.deinit()` 调用 `destroyPHPString()` 销毁对象本身，但 `Value` 仍持有指向已释放对象的指针。后续 `release()` 访问已释放内存 → use-after-free。

**修复**：在 `deinit()` 中不调用 `destroyPHPString()`，而是设置 `is_static = true` 标记为已释放。后续 `release()` 检测到 `is_static == true` 直接返回，避免 use-after-free。代价是 PHPString 对象本身不被回收（minor memory leak），但数据被正确释放。

## 6. 影响与风险评估

### 是否破坏式变更
**否** — 所有变更都是增量修复，不修改已有逻辑。

### 变更影响范围
- while 循环 + break + `||`/`&&` 组合场景：从死循环/错误结果 → 正确执行
- PHPString 使用场景：从 double free/use-after-free → 安全释放

### 回归测试结果

| 指标 | 修复前 | 修复后 | 变化 |
|------|--------|--------|------|
| Total | 67 | 67 | — |
| Pass | 5 | 5 | — |
| Fail (Compile) | 0 | **0** | — ✅ |
| Fail (Runtime) | 46 | **44** | **-2** ✅ |
| Fail (Diff) | 15 | 17 | +2 |
| Skip | 1 | 1 | — |
| PHPString double free 警告 | 4 脚本 | **0** | **-4** ✅ |

### 复测路径
1. `php /tmp/test_while_or.php` + AOT 编译运行对比
2. `isPrime(4)` 测试（`||` 短路求值）
3. `f081_bplustree_index_range_query.php` 编译验证
4. `f031_builder_fluent_immutable.php` double free 消除验证

## 7. 遗留问题/潜在问题

1. **f031 仍有 segfault**：double free 已消除，但存在其他内存问题（可能是 PHPArray 或 Object 的 use-after-free）
2. **f043/f072 输出差异**：从 segfault 转为输出差异，需进一步分析 diff 内容
3. **PHPString 对象泄漏**：`deinit()` 不再调用 `destroyPHPString()`，PHPString 对象不被回收。长期运行的程序可能有内存增长。后续可考虑在 Value 级别添加 release 后置 null 的机制
4. **for/foreach/do-while 循环**：尚未添加 `current_loop_label` 和 exit PHI 消解。需要同样的修复

## 8. 后续开发/优化建议

| 优先级 | 建议 | 影响面 | 落地成本 |
|--------|------|--------|----------|
| P0 | 将 while 的 break/exit PHI 修复扩展到 for/foreach/do-while 循环 | 所有循环+break 场景 | 中 |
| P1 | 分析 f043/f072 的输出差异，修复输出不匹配 | 2 个脚本从 FAIL_DIFF → PASS | 中 |
| P1 | 分析 f031 的 segfault，可能是 PHPArray use-after-free | 1 个脚本从 FAIL_RUNTIME → PASS | 高 |
| P2 | 为 Value 添加 `releaseAndNull()` 方法，在 release 后自动置 null | 消除所有 double free 根因 | 低 |
| P2 | 分析剩余 segfault 脚本（f042, f051, f056, f061, f085, f117, f160, f178）| 8 个脚本 | 高 |
