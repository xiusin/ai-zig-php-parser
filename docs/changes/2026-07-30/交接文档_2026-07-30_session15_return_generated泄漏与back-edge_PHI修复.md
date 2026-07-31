# 交接文档：Session 15 AST-Direct return_generated 泄漏与 for 循环 back-edge PHI 修复

**日期**：2026-07-30
**范围**：`src/aot/native_linker.zig` — AST-Direct 代码生成路径
**Session**：15
**前置**：Session 14（`docs/changes/2026-07-29/交接文档_2026-07-29_session14_AST-Direct_PHI消解与循环break修复.md`）

---

## 一、TL;DR

本轮修复了 AST-Direct 代码生成中两个核心缺陷，消除了 6 个超时脚本：

1. **`return_generated` 标志泄漏**：`generateForeachFromLabels` 和 `generateForFromLabels` 的 `cond_br` case 中，then 块的 `.ret` 终止符将 `return_generated` 设为 `true`，该标志泄漏到后续的 `generateLabelDrivenBlockRange` 调用，触发 early-exit 跳过 `if_merge_` 块（循环增量代码），导致迭代器永不前进 → 无限循环。`generateWhileFromLabels` 已有此 save/restore 模式，本轮将同样的修复应用到 foreach 和 for 循环生成器。

2. **for 循环 back-edge PHI 消解不完整**：`generateForFromLabels` 的回边 PHI 处理仅检查 `is_from_loop`/`is_from_body`，无法检测来自嵌套循环退出块（如 `for_exit_9`，其终止符为 `br for_cond_1`）的回边，导致循环计数器 PHI 未被消解 → 无限循环。

---

## 二、当前状态

### 2.1 回归测试统计

| 指标 | Session 14 交接时 | Session 15 当前 | 变化 |
|------|-------------------|-----------------|------|
| PASS | 12 | 13 | **+1** |
| FAIL_COMPILE | 2 | 2 | 0 |
| FAIL_RUNTIME | 37 | 31 | **-6** |
| FAIL_DIFF | 15 | 20 | +5 |
| SKIP | 1 | 1 | 0 |
| **超时脚本(exit=142)** | **23** | **17** | **-6** |
| **段错误(exit=139/133)** | **8** | **6** | **-2** |

> 回归报告来自 `fuzzy_scripts_720/regression_report.md`（2026-07-30 11:52:04 生成）。
>
> FAIL_DIFF 增加 5 个是正面信号：部分超时脚本现在能正常运行但输出有差异（从"无限循环"变为"输出不匹配"），这是实质性改善。

### 2.2 脚本级变化明细

| 脚本 | Session 14 交接时 | Session 15 当前 | 变化类型 |
|------|-------------------|-----------------|----------|
| f012 | FAIL_RUNTIME exit=124 | FAIL_DIFF | 超时→输出差异 |
| f016 | FAIL_RUNTIME exit=124 | FAIL_DIFF | 超时→输出差异 |
| f033 | FAIL_RUNTIME exit=137 | FAIL_RUNTIME exit=1 | 段错误→RuntimeError |
| **f036** | FAIL_RUNTIME exit=124 | **PASS** | **超时→通过** |
| f042 | FAIL_RUNTIME exit=139 | FAIL_DIFF | 段错误→输出差异 |
| **f057** | FAIL_DIFF | **PASS** | **输出差异→通过** |
| **f090** | FAIL_DIFF | **PASS** | **输出差异→通过** |
| f105 | FAIL_RUNTIME exit=124 | FAIL_DIFF | 超时→输出差异 |
| f110 | FAIL_RUNTIME exit=124 | FAIL_RUNTIME exit=139 | 超时→段错误 |
| f113 | FAIL_RUNTIME exit=124 | FAIL_RUNTIME exit=139 | 超时→段错误 |
| f178 | FAIL_RUNTIME exit=139 | FAIL_DIFF | 段错误→输出差异 |
| **f179** | - | **PASS** | **新增通过** |

---

## 三、已完成任务

### 3.1 `return_generated` 标志泄漏修复（核心修复 1）

**问题**：循环体内的 `if ($cond) { return ...; }` 模式生成的 IR 结构为：

```
foreach_body_3:
  br reg, foreach_cleanup_5, if_merge_8   ← cond_br

foreach_cleanup_5:                        ← then 块（break/return 路径）
  ret reg_50                              ← 设置 return_generated = true

if_merge_8:                               ← else 块（继续循环路径）
  ... 循环增量计算 ...
  br foreach_cond_2                       ← 回边
```

`return_generated = true` 泄漏后，`generateLabelDrivenBlockRange` 的 early-exit 逻辑（第 6284 行 `if (self.return_generated or self.break_generated) { ... return; }`）会跳过 `if_merge_8` 块，导致循环增量代码缺失 → 无限循环。

**修复方案**：在 `generateForeachFromLabels` 和 `generateForFromLabels` 的 `cond_br` case 中添加 `return_generated` 的 save/restore：

```zig
// 在 cond_br case 的 then 块处理前保存
const saved_cond_br_rg = self.return_generated;
self.return_generated = false;

// ... 处理 then/else 块（可能设置 return_generated = true）...

// 在回边处理前恢复
self.return_generated = saved_cond_br_rg;
```

**修改位置**：
- `generateForeachFromLabels`：~7150-7154（save）和 ~7395-7397（restore）
- `generateForFromLabels`：~7978-7982（save）和 ~8180-8182（restore）

**验证效果**：f036（Strategy + Dynamic Pricing）从无限循环修复为完全通过。

### 3.2 for 循环 back-edge PHI 消解修复（核心修复 2）

**问题**：`generateForFromLabels` 的回边 PHI 处理（~8248-8266）仅检查 `is_from_loop`（来自 `loop_idx` 块）和 `is_from_body`（来自 `body_idx` 块），无法检测来自嵌套循环退出块的回边。

**根因分析**（以 f016 `BloomFilter::hashes` 为例）：

```
for_cond_1:                              ← 外层循环条件
  PHI reg_46 = [reg_6, entry], [reg_44, for_exit_9]
  br reg_11, for_body_2, for_exit_4

for_body_2:                              ← 外层循环体
  ... 字符串拼接 ...
  br for_cond_6                          ← 进入内层循环

for_cond_6:                              ← 内层循环条件
  ...
for_body_7:                              ← 内层循环体
  ...
  br for_cond_6

for_exit_9:                              ← 内层循环退出 = 外层循环回边源
  array.push ...
  reg_44 = php_increment(reg_46)
  br for_cond_1                          ← 回边到外层循环
```

`for_exit_9` 是回边源（`br for_cond_1`），但它既不是 `loop_idx` 也不是 `body_idx`，原代码无法识别它为回边，导致 `PHI reg_46 = reg_44` 未被消解 → 循环计数器永不更新 → 无限循环。

**修复方案**：扩展回边检测逻辑，检查 incoming.block 是否有 `br`/`cond_br` 到 cond 或 loop 块：

```zig
const is_from_back_edge = blk: {
    if (is_from_loop or is_from_body) break :blk true;
    // 排除循环入口块（cond_idx 之前的块）
    if (incoming_blk_idx <= cond_idx) break :blk false;
    // 检查 incoming.block 是否有 br/cond_br 到 cond 或 loop
    if (incoming.block.terminator) |bt| {
        if (bt == .br and (bt.br == cond_ptr or bt.br == loop_ptr)) break :blk true;
        if (bt == .cond_br and (...)) break :blk true;
    }
    break :blk false;
};
if (is_from_back_edge) {
    try self.writePtrAwareAssign(writer, body_indent, result.id, incoming.value.id);
    break;
}
```

**修改位置**：`generateForFromLabels` ~8253-8280

**验证效果**：f016（Hash Table + Bloom Filter）从无限循环修复为有输出（FAIL_DIFF，输出差异需进一步排查）。

### 3.3 回归测试验证

执行了完整回归测试（`bash fuzzy_scripts_720/run_regression.sh`），67 个脚本全部测试完成，结果记录于 `fuzzy_scripts_720/regression_report.md`。

---

## 四、进行中/未完成任务

### 4.1 剩余超时脚本（P0，17 个）

以下脚本仍然超时（exit=142），需要进一步分析：

| 脚本 | 超时前的输出 | 可能根因 |
|------|-------------|----------|
| f024 | Permission Matrix 无限输出 "Alice (admin)/article:" | 嵌套 foreach 的 break/continue 处理问题 |
| f025 | "Round-trip OK: false" 后卡在 RLE | 待分析 |
| f028 | "Trying to access array offset on null" 后卡住 | array_fill 初始化问题导致 null 访问 + 循环 |
| f038 | 文件系统树遍历后卡住 | 待分析 |
| f061 | "Trying to access array offset on null" 后卡住 | 同 f028 |
| f065 | CRC32 计算后卡住 | 待分析 |
| f081 | B+Tree 操作后卡住 | 待分析 |
| f095 | "Dead Code Elimination" 后卡住 | 待分析 |
| f097 | TF-IDF 循环输出 "php:" | 嵌套循环增量缺失 |
| f102 | "Generational GC" 后卡住 | 待分析 |
| f104 | "Entity States" 后卡住 | 待分析 |
| f119 | "debug: 1 #" 循环输出 | 嵌套循环增量缺失 |
| f135 | "Modular Exponentiation" 后卡住 | 待分析 |
| f161 | "Generated CSV:" 后卡住 | 待分析 |
| f171 | DFA 匹配后卡住 | 待分析 |
| f175 | "QuickSort:" 后卡住 | 待分析 |
| f176 | "Young adult: Y" 后卡住 | 待分析 |

**排查方向**：
1. 优先检查 `generateBrToMergeCondBr`（~7570-7765）中是否有 `return_generated` 泄漏
2. 检查 `generateLabelDrivenBlockRange` 的 `cond_br` case（~6384-6500）中 then/else 块的 `.ret` 处理是否保存/恢复了 `return_generated`
3. 检查 `generateIfFromLabels`（~8531+）中嵌套控制流的 `return_generated` 传播

### 4.2 段错误脚本（P1，6 个）

| 脚本 | exit code | 可能根因 |
|------|-----------|----------|
| f027 | 139 | "Undefined variable $primes" — 变量未初始化（PHI 消解问题） |
| f042 | 139 | 差异从段错误变为 FAIL_DIFF（部分修复） |
| f051 | 139 | Validator 循环后段错误 |
| f056 | 139 | OR-Set 操作后段错误 |
| f110 | 139 | 文件系统遍历后段错误（从超时变为段错误） |
| f113 | 139 | ConsistentHash 后段错误（从超时变为段错误） |
| f177 | 139 | Graph DFS/BFS 后段错误 |

### 4.3 FAIL_DIFF 输出差异脚本（P1，20 个）

| 脚本 | 差异类型 |
|------|----------|
| f006 | Observer 事件输出差异 |
| f009 | Decorator Chain 输出差异 |
| f012 | JSON Tree 输出差异（从超时修复） |
| f016 | Hash Table 输出差异（从超时修复） |
| f031 | Builder 输出差异 |
| f034 | Template Method JSON 输出差异 |
| f042 | Array Functions 输出差异（从段错误修复） |
| f044 | JSON DeepOps 输出差异 |
| f066 | Hamming Code 输出差异 |
| f070 | Event Sourcing 输出差异 |
| f072 | Type Inference 输出差异 |
| f080 | DB Transaction 输出差异（coalesce `??` PHI 问题） |
| f105 | DB Index 输出差异（从超时修复） |
| f117 | Search Engine 输出差异 |
| f134 | EventSourcing 输出差异 |
| f151 | Type System 输出差异 |
| f163 | Event Bus 输出差异 |
| f164 | Plugin System 输出差异 |
| f173 | Concurrency 输出差异 |
| f178 | Matrix 输出差异（从段错误修复） |

### 4.4 FAIL_COMPILE 脚本（P2，2 个）

| 脚本 | 错误 |
|------|------|
| f087 | Zig 编译失败，2 errors |
| f160 | Zig 编译失败，2 errors |

---

## 五、已知问题

### 5.1 early-exit 问题（P0，继承自 Session 12，部分修复）

**根因**：`generateLabelDrivenBlockRange` 第 6284 行：
```zig
if (self.return_generated or self.break_generated) {
    for (i..end_idx) |j| {
        try processed.put(j, {});  // ← 标记所有剩余块为已处理
    }
    return;
}
```

**当前状态**：本轮修复了 `generateForeachFromLabels` 和 `generateForFromLabels` 的 `cond_br` case 中的泄漏，但以下位置仍可能存在泄漏：
- `generateBrToMergeCondBr`（~7570-7765）：then 块和 else 块的 `.ret` 处理设置 `return_generated = true` 后未恢复
- `generateLabelDrivenBlockRange` 的 `cond_br` case（~6384-6500）：then/else 块的 `.ret` 处理
- `generateIfFromLabels`（~8531+）：嵌套控制流的 return 传播

**影响**：17 个超时脚本可能部分由此导致。

### 5.2 f024 Permission Matrix 无限输出（P0，新发现）

**现象**：f024 的 Permission Matrix 部分无限输出 "Alice (admin)/article:Alice (admin)/article:..."。

**初步分析**：可能是嵌套 foreach 循环中，内层 foreach 的 break 处理不正确，导致内层循环不终止，外层循环的 `printf` 被反复执行。需要 dump IR 分析 `Role::check` 和 `RBACManager::check` 的嵌套 foreach 结构。

### 5.3 f080 coalesce `??` PHI 消解（P1，继承自 Session 14）

**现象**：`waitForLock(): Argument #1 ($waiter) must be of type int, null given`

**根因**：coalesce `??` 运算符的 PHI 在合并点未正确消解，`$waiter` 变量为 null。

### 5.4 f027 变量未初始化（P1，继承自 Session 14）

**现象**：`Undefined variable $primes`

**根因**：`$primes` 变量的 PHI 在某条路径上未被消解。

### 5.5 PHPString double free（P1，5 脚本，继承自 Session 12）

- 脚本：f025/f031/f072/f119/f160
- 根因：release 后 alloca 中的值变悬垂引用

---

## 六、变更文件列表

| 文件 | 变更类型 | 行数变化 | 说明 |
|------|----------|----------|------|
| `src/aot/native_linker.zig` | 修改 | +48 行 / -12 行 | return_generated save/restore + for back-edge PHI 扩展 |

### 核心变更明细

| 变更点 | 函数 | 行号范围 | 说明 |
|--------|------|----------|------|
| foreach save return_generated | `generateForeachFromLabels` | ~7150-7154 | 新增：在 cond_br case 的 then 块处理前保存 return_generated |
| foreach restore return_generated | `generateForeachFromLabels` | ~7395-7397 | 新增：在回边处理前恢复 return_generated |
| for save return_generated | `generateForFromLabels` | ~7978-7982 | 新增：同上 |
| for restore return_generated | `generateForFromLabels` | ~8180-8182 | 新增：同上 |
| for back-edge PHI 扩展 | `generateForFromLabels` | ~8253-8280 | 修改：扩展回边检测逻辑，支持非 loop/body 块的回边 |

---

## 七、关键代码位置参考

| 功能 | 文件 | 行号范围 | 说明 |
|------|------|----------|------|
| `return_generated` early-exit | native_linker.zig | ~6284 | early-exit 逻辑（泄漏的放大器） |
| `generateForeachFromLabels` cond_br | native_linker.zig | ~7116-7417 | foreach 循环 cond_br case（本轮修复） |
| `generateForFromLabels` cond_br | native_linker.zig | ~7946-8213 | for 循环 cond_br case（本轮修复） |
| `generateForFromLabels` back-edge PHI | native_linker.zig | ~8248-8266 | for 循环回边 PHI（本轮修复） |
| `generateWhileFromLabels` cond_br | native_linker.zig | ~8482-8706 | while 循环 cond_br case（已有 save/restore，参考模板） |
| `generateWhileFromLabels` back-edge PHI | native_linker.zig | ~8766-8794 | while 循环回边 PHI（已有 comprehensive 检测，参考模板） |
| `generateForeachFromLabels` back-edge PHI | native_linker.zig | ~7434-7483 | foreach 回边 PHI（已有 comprehensive 检测） |
| `generateBrToMergeCondBr` | native_linker.zig | ~7570-7765 | br → cond_br 链处理（**待检查 return_generated 泄漏**） |
| `generateLabelDrivenBlockRange` cond_br | native_linker.zig | ~6384-6500 | 主循环 cond_br case（**待检查 return_generated 泄漏**） |
| `generateIfFromLabels` | native_linker.zig | ~8531+ | if/else 结构化生成（**待检查 return_generated 传播**） |
| `writePtrAwareAssign` | native_linker.zig | ~604-630 | PHI 赋值辅助函数 |

---

## 八、调试方法参考

### 8.1 编译并 dump IR + Zig 代码

```bash
# 编译 AOT 并 dump IR 和 Zig 代码
./zig-out/bin/php-interpreter --compile --dump-ir --dump-zig-path=/tmp/dump.zig \
  fuzzy_scripts_720/pass/fXXX.php --output=/tmp/aot_compile_fXXX 2>/tmp/ir.txt

# 运行 AOT 二进制（10 秒超时）
perl -e 'alarm 10; exec @ARGV' /tmp/aot_compile_fXXX
```

### 8.2 运行回归测试

```bash
bash fuzzy_scripts_720/run_regression.sh
```

### 8.3 分析超时脚本

1. 用 `perl -e 'alarm 5; exec @ARGV'` 运行，查看输出卡在哪里
2. Dump IR 找到卡住的函数
3. Dump Zig 代码检查循环增量代码是否缺失
4. 在 IR 中搜索 `return_generated` 可能泄漏的路径（then 块有 `.ret` 终止符）

### 8.4 分析 back-edge PHI 问题

1. 在 IR 中找到循环条件块的 PHI 指令
2. 检查 PHI 的 incoming 值来自哪些块
3. 确认这些块是否被 back-edge 检测逻辑覆盖
4. 对比 `generateWhileFromLabels`（~8766）的 comprehensive 检测逻辑

---

## 九、后续优化建议

| 优先级 | 影响面 | 落地成本 | 建议 |
|--------|--------|----------|------|
| **P0** | 17 脚本 | 中 | 分析剩余超时脚本：检查 `generateBrToMergeCondBr` 和 `generateLabelDrivenBlockRange` cond_br case 中的 `return_generated` 泄漏。优先排查 f024（无限输出）、f097/f119（循环输出模式） |
| **P0** | 1 脚本(f024) | 中 | 分析 Permission Matrix 无限输出：dump IR 检查 `Role::check` 和 `RBACManager::check` 的嵌套 foreach 结构 |
| **P1** | 6 脚本 | 中 | 修复段错误脚本（f027/f051/f056/f110/f113/f177）：优先检查 use-after-free 和 PHI 消解问题 |
| **P1** | 20 脚本 | 高 | 修复 FAIL_DIFF 输出差异：逐脚本对比 PHP 和 AOT 输出，定位 PHI 消解或逻辑差异。优先处理从超时/段错误转变为 FAIL_DIFF 的脚本（f012/f016/f042/f105/f178），这些已有部分输出，修复成本低 |
| **P1** | 1 脚本(f080) | 中 | 修复 coalesce `??` PHI 消解：`??` 的隐式 if/else 合并点 PHI 未正确赋值 |
| **P2** | 全局 | 低 | 统一 `return_generated` save/restore 模式：抽取为辅助函数 `withSavedReturnGenerated`，减少重复代码 |
| **P2** | 2 脚本 | 中 | 修复 FAIL_COMPILE 脚本（f087/f160）：分析 Zig 编译错误 |
| **P2** | 全局 | 高 | 重构 `generateLabelDrivenBlockRange` 的 early-exit 逻辑：改为基于块可达性分析而非标志位，从根本上消除泄漏问题 |

---

## 十、注意事项

1. **编译已验证**：`zig build` 通过，无编译错误
2. **回归测试已完成**：67 个脚本全部测试，结果记录于 `fuzzy_scripts_720/regression_report.md`
3. **临时文件已清理**：`/tmp/aot_compile_*`、`/tmp/f0*_dump*.zig`、`/tmp/f0*_ir.txt` 等临时产物已删除
4. **变更摘要已生成**：`docs/changes/2026-07-30/AST-Direct_return_generated泄漏与back-edge_PHI修复_2026-07-30_session15_a1b2c3.md`
5. **PHP 原始脚本未修改**：所有修改仅在 `src/aot/native_linker.zig`
6. **`generateWhileFromLabels` 是参考模板**：它已有完整的 `return_generated` save/restore 和 back-edge PHI comprehensive 检测，后续修复 foreach/for 循环时应参考其实现
7. **Session 14 交接文档中的 P0 问题**（f057 执行路径不完整）已在本轮修复中解决（f057 从 FAIL_DIFF 变为 PASS）
