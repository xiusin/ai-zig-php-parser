# 交接文档：AST-Direct 标签驱动结构化代码生成（方案A）

> **日期**：2026-07-24  
> **会话**：Session #4  
> **状态**：进行中（AST-DIRECT 路径已修复并成功应用于 f026 全部函数，但生成的 Zig 代码存在编译错误尚未修复）  
> **核心文件**：`src/aot/native_linker.zig`

---

## 一、TL;DR（高层摘要）

本会话的核心任务是**修复 AST-Direct 标签驱动代码生成路径（`tryGenerateFromLabels`），使其真正被应用**。

之前的会话已搭建了 AST-Direct 的完整框架（`tryGenerateFromLabels` + 5 个递归生成函数），但该路径**始终失败并回退到状态机**。本会话定位并修复了导致失败的 3 个根因：

1. **`generateIfFromLabels` 的 `return_generated` 标志泄漏**：`if_then` 块内含 `ret` 终止符时设置 `return_generated = true`，返回主循环后立即退出，后续块全部未处理
2. **`generateForeachFromLabels` 硬性要求 `foreach_increment_` 和 `foreach_exit_` 块**：IR 生成器有时不生成这些块（增量逻辑内联到 body），导致查找失败
3. **`generateWhileFromLabels` 不处理循环体内的嵌套 if 块位于 `while_exit` 之后的情况**：IR 生成器先创建 while 所有块，再处理 body 内嵌套的 if，导致 if 块在 exit 之后

修复后，f026 的全部 14 个函数（含复杂嵌套循环/if 的 `LinkedList::pop`、`LinkedList::find`、`__main__`）全部通过 AST-DIRECT 路径。

**当前阻塞**：AST-DIRECT 成功后，生成的 Zig 代码缺少 fallback return 语句导致编译失败。已添加了 fallback return 逻辑，但最新修改尚未编译验证。

---

## 二、AST 转 Zig 的新逻辑方式：详细架构

### 2.1 核心原理

传统编译器后端从 IR（CFG）重建结构化代码，需要分析 br/cond_br 的连接关系，复杂且易错。

**新方案（方案A）的核心思路**：不从 br 连接关系重建控制流，而是**从 IR 块的标签名称重建控制流结构**。

#### 为什么这样做可行？

因为 `ir_generator.zig` 在创建 IR 块时使用了有规律的命名前缀：

| IR 生成器调用 | 标签前缀 | 对应 PHP 语法 |
|---|---|---|
| `createBlock("foreach_cond")` | `foreach_cond_N` | `foreach` 循环 |
| `createBlock("for_cond")` | `for_cond_N` | `for` 循环 |
| `createBlock("while_cond")` | `while_cond_N` | `while` 循环 |
| `createBlock("if_then")` | `if_then_N` | `if` 语句 |
| `createBlock("do_while_body")` | `do_while_body_N` | `do-while` 循环 |

标签后的数字 N 是全局递增的 `block_counter`。

#### 块在数组中的排列顺序

IR 生成器按 **AST 遍历顺序** 创建块。例如对于以下 PHP 代码：

```php
foreach ($arr as $v) {       // 创建 foreach_cond_0, foreach_body_1, foreach_cleanup_3
    if ($v > 0) {            // 创建 if_then_4, if_merge_5
        $list->push($v);
    }
}
echo "done";                 // 在 foreach_exit 块之后
```

块在 `func.blocks` 数组中的排列为：
```
entry → foreach_cond_0 → foreach_body_1 → foreach_cleanup_3 → foreach_exit_4 → if_then_5 → if_merge_6 → ...
```

**关键洞察**：块索引的顺序天然反映了 AST 的嵌套结构。通过递归处理块索引范围，可以天然支持任意深度嵌套。

### 2.2 三层调用架构

```
generateControlFlowStateMachine (入口，行 ~6900)
  │
  ├── [第1层] tryGenerateFromLabels (AST-Direct 路径)
  │     │  策略：从块标签重建控制流
  │     │  失败时自动回滚（截断已写入的代码）
  │     │
  │     ├── generateLabelDrivenBlockRange (递归遍历块范围)
  │     │     ├── generateForeachFromLabels (foreach 循环)
  │     │     ├── generateForFromLabels (for 循环)
  │     │     ├── generateWhileFromLabels (while 循环)
  │     │     ├── generateIfFromLabels (if/else 语句)
  │     │     └── generateDoWhileFromLabels (do-while 循环)
  │     │
  │     └── findBlockByLabelPrefix (辅助：按标签前缀查找块)
  │
  ├── [第2层] tryGenerateStructuredControlFlowNew (旧结构化路径，fallback)
  │
  └── [第3层] generateControlFlowStateMachine (状态机，最终 fallback)
```

### 2.3 入口逻辑（`generateControlFlowStateMachine` 内，行 ~6900）

```zig
// AST-direct 结构化代码生成（方案A）
if (!func.has_multi_level_break and !has_do_while and !has_switch and !has_match and !has_exception_handler) {
    // 保存当前代码长度，失败时回滚
    const code_len_before_ast = code.items.len;
    const saved_return_generated = self.return_generated;
    const saved_break_generated = self.break_generated;
    self.return_generated = false;
    self.break_generated = false;

    const ast_result = try self.tryGenerateFromLabels(&writer, func, cleanup_regs, alloca_regs);
    if (ast_result) {
        // 成功！如果没有生成 return 语句，添加 fallback return
        if (!self.return_generated) {
            try writer.writeAll("    return runtime.Value.initNull();\n");
        }
        return;  // 直接返回，不走后面的 fallback 路径
    }
    // 失败回滚：截断已写入的部分代码，重置标志
    code.shrinkRetainingCapacity(code_len_before_ast);
    self.return_generated = saved_return_generated;
    self.break_generated = saved_break_generated;
}
// ↓ 继续走 tryGenerateStructuredControlFlowNew → 状态机
```

**排除条件**：以下情况不走 AST-Direct 路径（直接走 fallback）：
- `has_multi_level_break` — 多层 break（需要 break 标签栈管理，暂不支持）
- `has_do_while` — do-while 循环
- `has_switch` / `has_match` — switch/match 语句
- `has_exception_handler` — try/catch 异常处理

### 2.4 `tryGenerateFromLabels`（行 ~5856）

```zig
fn tryGenerateFromLabels(self, writer, func, cleanup_regs, alloca_regs) !bool {
    // 1. 设置 alloca_regs 上下文
    // 2. 创建 processed HashMap（跟踪已处理的块索引）
    // 3. 创建 loop_label_counter（生成唯一循环标签名）
    // 4. 从块 0（entry）开始递归处理所有块
    try self.generateLabelDrivenBlockRange(writer, func, 0, func.blocks.items.len, ...);
    // 5. 检查是否所有块都已处理
    //    如果有未处理的块 → 返回 false（调用者会回滚）
    //    全部处理 → 返回 true
}
```

### 2.5 `generateLabelDrivenBlockRange`（行 ~5914）— 核心递归函数

```zig
fn generateLabelDrivenBlockRange(self, writer, func, start_idx, end_idx, ...) {
    var i = start_idx;
    while (i < end_idx) {
        if (self.return_generated or self.break_generated) return; // 不可达代码停止
        if (processed.contains(i)) { i += 1; continue; }

        const label = func.blocks.items[i].label;

        // 根据标签前缀分派到对应的生成器
        if (startsWith(label, "foreach_cond_")) → generateForeachFromLabels
        if (startsWith(label, "for_cond_"))      → generateForFromLabels
        if (startsWith(label, "while_cond_"))    → generateWhileFromLabels
        if (startsWith(label, "if_then_"))       → generateIfFromLabels
        if (startsWith(label, "do_while_body_")) → generateDoWhileFromLabels

        // 普通线性块：生成指令，处理终止符
        // ret → 生成 return + cleanup
        // br/cond_br → 只生成指令，不生成跳转（控制流由标签驱动）
    }
}
```

### 2.6 各控制流生成器的详细逻辑

#### 2.6.1 `generateForeachFromLabels`（行 ~6048）

**IR 块结构**：
```
foreach_cond_N     - 条件检查（iter_valid → cond_br）
foreach_body_N+1   - 循环体
foreach_increment_  - 迭代器递增（可选，可能不存在）
foreach_cleanup_    - 迭代器清理
foreach_exit_       - 循环出口（可选，可能不存在）
```

**生成逻辑**：
1. 查找 body/increment/cleanup/exit 块（increment 和 exit 是可选的）
2. 生成 cond 块指令
3. 生成 `__foreach_N: while (true) {` 带标签循环
4. 生成条件判断：`if (!(iter_valid)) break :__foreach_N;`
5. 生成 body 块指令 + 递归处理嵌套控制流
6. 生成 increment 块指令（如果存在）
7. 生成 `continue :__foreach_N;` + `}`
8. 生成 cleanup 块指令
9. 生成 exit 块指令（如果存在）

**本会话修复点**：
- `increment_idx` 改为可选（`?usize`），不存在时用 `cond_idx` 作为 `next_after_body`
- `exit_idx` 改为可选，不存在时返回 `cleanup_idx + 1`
- body 的 br 终止符判断也适配了可选块

#### 2.6.2 `generateForFromLabels`（行 ~6221）

**IR 块结构**：
```
for_cond_N  - 条件检查
for_body_N+1 - 循环体
for_loop_N+K - 增量表达式（可能不存在，用 body_idx 代替）
for_exit_N+K+1 - 循环出口
```

**生成逻辑**：与 foreach 类似，但条件直接放在 `while (cond)` 中，不需要 `if/break` 模式。

#### 2.6.3 `generateWhileFromLabels`（行 ~6373）

**IR 块结构**：
```
while_cond_N   - 条件检查
while_body_N+1 - 循环体
while_exit_N+K  - 循环出口
```

**生成逻辑**：
1. 生成 cond 块指令
2. 生成 `__while_N: while (cond) {` 或 `while (true) {`
3. 生成 body 块指令
4. 处理 body 终止符
5. 递归处理 body 和 exit 之间的嵌套控制流
6. 生成 `continue :__while_N;` + `}`
7. 生成 exit 块指令

**本会话修复点（关键）**：当 body 有 `cond_br` 终止符（嵌套 if）时，if 块可能在 `while_exit` 之后。原因是 IR 生成器先创建 while 的 cond/body/exit 块，再处理 body 内嵌套的 if。修复方案：
- 扩展递归范围 `extended_end` 到最后一个分支回 cond 块的块（循环回边）
- 提前标记 exit 块为已处理，避免递归调用错误处理它

```zig
.cond_br => {
    // 搜索 exit 之后的块，找到最后一个 br 回 cond 块的块（循环回边）
    const cond_block_ptr = func.blocks.items[cond_idx];
    var last_back_edge: usize = exit_idx;
    for (exit_idx + 1..end_idx) |i| {
        const block = func.blocks.items[i];
        if (block.terminator) |t| {
            if (t == .br and t.br == cond_block_ptr) {
                last_back_edge = i;
            }
        }
    }
    extended_end = last_back_edge + 1;
},
```

#### 2.6.4 `generateIfFromLabels`（行 ~6522）— 本会话修复最重的函数

**IR 块结构**：
```
[cond_block]     - 条件块（有 cond_br → if_then, if_merge/else）
if_then_N        - then 分支
if_else_N+K      - else 分支（可选）
if_merge_N+K+1   - 合并块
```

**旧代码的 3 个 Bug**：

1. **指令顺序错误**：先标记 then 块为已处理并生成指令，再向前搜索条件块。条件块的指令被生成在 then 块指令之后，导致 Zig 代码逻辑错误。

2. **`return_generated` 标志泄漏**：then 块内有 `ret` 终止符时设置 `return_generated = true`，函数返回后主循环立即退出，后续块全部未处理。

3. **条件块查找不完整**：只查找紧邻 then 之前的块，如果前一个块不是 `cond_br`（可能是 entry 或其他线性块），条件就丢失了。特别是当 if 嵌套在 while body 中时，`if_then` 块可能在 `while_exit` 之后，前一个块是 `while_exit` 而不是 `cond_br` 块。

**新代码的 10 步流程**：

```
Step 1: 查找条件块
  - 先检查紧邻 then_idx 之前的块
  - 如果前一个块有 cond_br，提取条件寄存器
  - 如果前一个块没有 cond_br，全局搜索找到 cond_br.then_block == then_block 的块
  - 如果前一个块未被处理，生成其指令

Step 2: 生成 if 语句
  if (cond) {

Step 3: 保存 return_generated 和 break_generated（关键修复！）
  saved_return = self.return_generated
  saved_break = self.break_generated
  self.return_generated = false
  self.break_generated = false

Step 4: 生成 then 块指令

Step 5: 处理 then 块终止符
  - br → merge: 正常流程
  - ret → 生成 return + cleanup，设置 return_generated = true
  - cond_br → 标记有嵌套 if（由 Step 6 递归处理）

Step 6: 递归处理 then 块之后的嵌套控制流
  generateLabelDrivenBlockRange(then_idx + 1, else_idx orelse merge_idx)

Step 7: 生成 else 块（如果存在）
  } else {
  生成 else 块指令 + 递归处理嵌套控制流

Step 8: 关闭 if
  }

Step 9: 恢复标志（关键修复！）
  self.return_generated = saved_return
  self.break_generated = saved_break
  // then/else 内部的 return 不影响 merge 及后续代码

Step 10: 生成 merge 块指令 + 处理终止符
```

**为什么保存/恢复标志是正确的？**

在 PHP 语义中：
```php
if ($cond) {
    return 1;  // then 分支的 return 只在条件成立时执行
}
// 这里的代码在条件不成立时会执行
echo "after if";  // 必须生成！
```

如果 `return_generated` 不恢复，`echo "after if"` 会被跳过，导致 `if_merge` 块的指令不被生成。

#### 2.6.5 `generateDoWhileFromLabels`（行 ~6722）

**IR 块结构**：
```
do_while_body_N  - 循环体
do_while_cond_N+K - 条件检查
do_while_exit_N+K+1 - 循环出口
```

**生成逻辑**：
```zig
__do_while_N: while (true) {
    // body 指令
    // 嵌套控制流
    // cond 指令
    if (!(cond)) break :__do_while_N;
    continue :__do_while_N;
}
// exit 指令
```

### 2.7 辅助函数

#### `findBlockByLabelPrefix`（行 ~6825）
```zig
fn findBlockByLabelPrefix(self, func, start_idx, end_idx, prefix) ?usize {
    // 在 [start_idx, end_idx) 范围内查找第一个标签以 prefix 开头的块
}
```

#### `extractLabelCounter`（行 ~6816）
```zig
fn extractLabelCounter(self, label, prefix) u32 {
    // 从标签 "foreach_cond_3" 提取数字 3
}
```

---

## 三、本会话的具体修改清单

### 3.1 `generateForeachFromLabels` 修复

| 修改点 | 旧行为 | 新行为 |
|---|---|---|
| `increment_idx` 查找 | `orelse return end_idx`（必须存在） | 改为 `?usize`（可选） |
| `exit_idx` 查找 | `orelse return end_idx`（必须存在） | 改为 `?usize`（可选） |
| `cleanup_idx` 搜索起点 | `increment_idx + 1` | `if (increment_idx) inc_idx+1 else body_idx+1` |
| body 的 br 判断 | 硬编码 `increment_idx` | 使用 `next_after_body = increment_idx orelse cond_idx` |
| 返回值 | `exit_idx + 1` | `if (exit_idx) ei+1 else cleanup_idx+1` |

### 3.2 `generateIfFromLabels` 修复

| 修改点 | 旧行为 | 新行为 |
|---|---|---|
| 条件块查找 | 向前搜索直到 processed 或 cond_br | 只看前一个块 + 全局搜索 cond_br.then_block 匹配 |
| 指令顺序 | 先生成 then 指令，再向前搜索条件块 | 先生成条件块指令，再生成 if 语句，再生成 then 指令 |
| `return_generated` | 不保存/恢复，then 内的 return 泄漏到外层 | 进入 then/else 前保存，退出 if 后恢复 |
| `break_generated` | 不保存/恢复 | 进入 then/else 前保存，退出 if 后恢复 |

### 3.3 `generateWhileFromLabels` 修复

| 修改点 | 旧行为 | 新行为 |
|---|---|---|
| body 有 cond_br 时 | 递归范围只到 `exit_idx` | 扩展到 `extended_end`（最后一个 br 回 cond 的块 + 1） |
| exit 块处理 | 递归后标记 processed | 递归前提前标记 processed |

### 3.4 `tryGenerateFromLabels` 修复

| 修改点 | 旧行为 | 新行为 |
|---|---|---|
| `return_generated` | `defer` 恢复旧值 | 不保存/恢复，让调用者根据返回值判断 |
| 调用处 fallback | 成功后直接 return | 成功后检查 `return_generated`，如为 false 添加 `return runtime.Value.initNull();` |

---

## 四、验证结果

### 4.1 f026 脚本测试（修复前 → 修复后）

```
修复前：
  [AST-DIRECT] FAILED for func 'LinkedList::pop' (8 blocks, unprocessed: 3[if_then_2] 4[if_merge_3] 5[while_cond_4] 6[while_body_5] 7[while_exit_6] ...)
  [AST-DIRECT] FAILED for func 'LinkedList::shift' (5 blocks, unprocessed: 3[if_then_2] 4[if_merge_3])
  [AST-DIRECT] FAILED for func 'LinkedList::find' (6 blocks, unprocessed: 4[if_then_3] 5[if_merge_4])
  [AST-DIRECT] FAILED for func '__main__' (13 blocks, unprocessed: 1[foreach_cond_0] 2[foreach_body_1] 3[foreach_cleanup_3] 4[foreach_cond_5] 5[foreach_body_6] ...)

修复后：
  [AST-DIRECT] SUCCESS for func 'LinkedListNode::__construct' (4 blocks)
  [AST-DIRECT] SUCCESS for func 'LinkedList::push' (4 blocks)
  [AST-DIRECT] SUCCESS for func 'LinkedList::unshift' (3 blocks)
  [AST-DIRECT] SUCCESS for func 'LinkedList::pop' (8 blocks)        ← 修复！
  [AST-DIRECT] SUCCESS for func 'LinkedList::shift' (5 blocks)       ← 修复！
  [AST-DIRECT] SUCCESS for func 'LinkedList::toArray' (4 blocks)
  [AST-DIRECT] SUCCESS for func 'LinkedList::reverse' (4 blocks)
  [AST-DIRECT] SUCCESS for func 'LinkedList::find' (6 blocks)        ← 修复！
  [AST-DIRECT] SUCCESS for func 'Stack::peek' (3 blocks)
  [AST-DIRECT] SUCCESS for func 'Queue::front' (3 blocks)
  [AST-DIRECT] SUCCESS for func 'RingBuffer::push' (3 blocks)
  [AST-DIRECT] SUCCESS for func 'RingBuffer::pop' (3 blocks)
  [AST-DIRECT] SUCCESS for func 'RingBuffer::toArray' (4 blocks)
  [AST-DIRECT] SUCCESS for func '__main__' (13 blocks)              ← 修复！
```

### 4.2 当前阻塞问题

AST-DIRECT 路径成功后，生成的 Zig 代码出现编译错误：
```
main.zig:7321:107: error: function with non-void return type 'anyerror!runtime_lib.Value' implicitly returns
```

原因：`__main__` 函数末尾没有 return 语句。已添加 fallback return 逻辑（行 ~6911），但最新修改尚未编译验证。

---

## 五、待办事项

### 5.1 紧急（必须完成）

| # | 任务 | 详情 |
|---|---|---|
| 1 | **编译验证最新修改** | 执行 `zig build`，修复 `tryGenerateFromLabels` 中 `return_generated` 不保存/恢复后可能导致的编译错误 |
| 2 | **验证 f026 AOT 产物正确性** | 编译 f026 后运行 `./aot_compile_f026_linkedlist_stack_queue_deque`，对比 PHP 输出 |
| 3 | **清理调试 print** | 移除 `tryGenerateFromLabels` 中的 `std.debug.print("[AST-DIRECT] ...")` 调试输出 |
| 4 | **全量回归测试** | 对 `fuzzy_scripts_720/pass/` 全部 67 个脚本运行回归测试，确认无回退 |

### 5.2 后续优化

| # | 任务 | 详情 |
|---|---|---|
| 5 | **扩展 AST-DIRECT 支持范围** | 当前排除了 `has_do_while`、`has_multi_level_break` 等，逐步支持这些特性 |
| 6 | **修复 f091/f071 预存问题** | `f091_os_scheduler_banker_algorithm.php` 和 `f071_compression_huffman_rle_lz77.php` 存在 typed property 运行时错误 |
| 7 | **性能基准测试** | 对比 AST-DIRECT 路径与状态机路径的性能 |

---

## 六、关键代码位置索引

| 函数 | 文件 | 行号 | 说明 |
|---|---|---|---|
| `tryGenerateFromLabels` | `native_linker.zig` | ~5856 | AST-Direct 入口 |
| `generateLabelDrivenBlockRange` | `native_linker.zig` | ~5914 | 核心递归遍历 |
| `generateForeachFromLabels` | `native_linker.zig` | ~6048 | foreach 生成 |
| `generateForFromLabels` | `native_linker.zig` | ~6221 | for 生成 |
| `generateWhileFromLabels` | `native_linker.zig` | ~6373 | while 生成 |
| `generateIfFromLabels` | `native_linker.zig` | ~6522 | if/else 生成 |
| `generateDoWhileFromLabels` | `native_linker.zig` | ~6722 | do-while 生成 |
| `findBlockByLabelPrefix` | `native_linker.zig` | ~6825 | 辅助：按标签查找块 |
| AST-Direct 调用处 | `native_linker.zig` | ~6900 | `generateControlFlowStateMachine` 内 |
| IR 块创建 | `ir_generator.zig` | ~521 | `createBlock(prefix)` |
| foreach IR 生成 | `ir_generator.zig` | ~2895 | 创建 foreach_cond/body/increment/cleanup/exit |

---

## 七、IR 块标签命名约定（来自 `ir_generator.zig`）

| PHP 语法 | IR 生成器创建的块 | 标签前缀 |
|---|---|---|
| `if/else` | `if_then`, `if_else`(可选), `if_merge` | `if_then_N`, `if_else_N`, `if_merge_N` |
| `while` | `while_cond`, `while_body`, `while_exit` | `while_cond_N`, `while_body_N`, `while_exit_N` |
| `for` | `for_init`(可选), `for_cond`, `for_body`, `for_loop`, `for_exit` | `for_cond_N`, `for_body_N`, `for_loop_N`, `for_exit_N` |
| `foreach` | `foreach_cond`, `foreach_body`, `foreach_increment`(可选), `foreach_cleanup`, `foreach_exit`(可选) | `foreach_cond_N`, `foreach_body_N`, `foreach_increment_N`, `foreach_cleanup_N`, `foreach_exit_N` |
| `do-while` | `do_while_body`, `do_while_cond`, `do_while_exit` | `do_while_body_N`, `do_while_cond_N`, `do_while_exit_N` |
| `switch` | `switch.case`, `switch.default`, `switch.merge` | `switch.case.N`, `switch.default_N`, `switch.merge_N` |
| `try/catch` | `try_body`, `catch`, `finally`(可选), `try_exit` | `try_body_N`, `catch_N`, `finally_N`, `try_exit_N` |

**重要**：标签后的数字 N 是全局递增的 `block_counter`，不是函数内的局部编号。

---

## 八、`return_generated` 和 `break_generated` 标志的语义

| 标志 | 含义 | 设置时机 | 恢复时机 |
|---|---|---|---|
| `return_generated` | 已生成 return 语句，后续代码不可达 | 块终止符为 `ret` 时 | `generateIfFromLabels` 在退出 if 前恢复（then/else 内的 return 不影响 merge） |
| `break_generated` | 已生成 break 语句，后续代码不可达 | 循环体内 br 到 exit 块时 | 循环生成器用 `defer` 恢复；`generateIfFromLabels` 在退出 if 前恢复 |

**关键规则**：
- `return_generated` 在 if 的 then/else 分支内设置后，**必须在退出 if 前恢复**，否则 merge 块及后续代码不会被生成
- `break_generated` 在循环体内设置后，**必须在退出循环前恢复**，否则循环后的代码不会被生成
- `tryGenerateFromLabels` 不再 `defer` 恢复 `return_generated`，改为让调用者检查该标志决定是否添加 fallback return

---

## 九、回退机制

AST-Direct 路径的回退机制设计：

```
generateControlFlowStateMachine
  │
  ├── 保存 code.items.len（当前代码长度）
  ├── 保存 return_generated / break_generated
  ├── 调用 tryGenerateFromLabels
  │     ├── 成功 → 检查 return_generated，添加 fallback return → 返回
  │     └── 失败 → 返回 false
  │
  ├── [失败] 截断代码：code.shrinkRetainingCapacity(code_len_before_ast)
  ├── [失败] 恢复标志
  │
  └── 继续走 tryGenerateStructuredControlFlowNew → 状态机
```

这确保了 AST-Direct 路径失败时不会影响已有的 fallback 路径。

---

## 十、已知问题与潜在风险

### 10.1 当前未验证的问题

1. **fallback return 可能与末尾已有的 return 冲突**：如果 AST-DIRECT 成功且函数末尾已有 return，`return_generated` 应为 true，不会添加 fallback。但如果 `return_generated` 标志管理有误，可能导致重复 return。

2. **`generateForFromLabels` 未修复 while 的同类问题**：for 循环也可能有嵌套 if 在 exit 之后的情况，当前 for 生成器没有扩展 `extended_end` 逻辑。

3. **`generateForeachFromLabels` 未修复 while 的同类问题**：foreach 循环也可能有嵌套 if 在 cleanup/exit 之后的情况。

4. **多个 if 嵌套在同一个循环体内**：当前 `extended_end` 只找最后一个 `br` 回 cond 的块，但如果循环体内有多个嵌套 if，中间可能有多个回边块。

### 10.2 回退安全性

AST-DIRECT 路径失败时通过 `code.shrinkRetainingCapacity` 截断已写入的代码，确保回退安全。但如果截断点不精确（如 `code_len_before_ast` 记录的时机不对），可能导致后续 fallback 路径生成错误的代码。

---

## 十一、后续开发建议

| 优先级 | 建议 | 影响面 | 落地成本 |
|---|---|---|---|
| P0 | 编译验证最新修改，修复 fallback return 问题 | 全部 AST-DIRECT 路径 | 低 |
| P0 | 清理 `[AST-DIRECT]` 调试 print | 代码整洁 | 低 |
| P0 | 全量回归测试（67 个 pass 脚本） | 确认无回退 | 中 |
| P1 | 将 `generateWhileFromLabels` 的 `extended_end` 逻辑同步到 `generateForFromLabels` 和 `generateForeachFromLabels` | for/foreach 的嵌套 if | 中 |
| P1 | 修复 f091/f071 typed property 运行时错误 | 2 个 fail_compile 脚本 | 中 |
| P2 | 扩展 AST-DIRECT 支持 do-while | 增加覆盖范围 | 中 |
| P2 | 扩展 AST-DIRECT 支持 multi-level break | 增加覆盖范围 | 高 |
| P2 | 性能基准测试：AST-DIRECT vs 状态机 | 性能评估 | 低 |
