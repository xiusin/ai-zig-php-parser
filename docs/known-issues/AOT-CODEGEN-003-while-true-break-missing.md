# while(true) 循环中 break 语句未生成问题

**问题 ID**: AOT-CODEGEN-003  
**优先级**: P0（高）  
**状态**: **CLOSED（2026-10-01 当前工作区树复测通过）** —— 原工单复现脚本（`test_while_simple.php` / `test_while_arr.php` / `rec_mini.php` 等）已在清理轮次中删除，故按本文 §复现代码 重建永久探针 `fuzzy_scripts_720/tmp/c003_while_true_break_tmp.php`（R1 原文复现 + R2/R3/R4 覆盖「影响范围」三类组合）。**实测**：四形 AOT 与 `/opt/homebrew/bin/php` 逐字节等值（`RUN_RC=0`，`VERDICT=SAME_AS_PHP`），读数见 §测试结果（2026-10-01 复测）。  
**发现日期**: 2026-08-22

---

## 问题描述

`generateWhileFromLabels` 在处理 `while(true)` 循环时，两个独立缺陷导致 `break` 语句未生成：

1. **`isLoopBreakTarget` 无 exit 块时无法识别 break 目标**：当 `while(true)` 无正式 exit 块（`exit_idx >= func.blocks.items.len`）时，`isLoopBreakTarget` 的条件 `exit_idx < func.blocks.items.len` 恒为 false，导致 br 到循环外的目标无法被识别为 break。

2. **then 块指向 exit 块时被 `processed` 跳过**：`generateWhileFromLabels` 在处理 body 块的 `cond_br` 时，exit 块被预标记为 `processed`（行 10543）。当 `cond_br` 的 then 块就是 exit 块本身时，`!processed.contains(ti)` 不满足，跳过 then 块处理，导致 break 语句从未生成。

## 复现代码

```php
<?php
class Test {
    private array $obj = [];
    private int $pos = 0;

    public function test(): array {
        $this->obj = [];
        $this->pos = 0;
        while (true) {
            if ($this->pos >= 2) break;
            $key = "key" . $this->pos;
            $val = $this->getValue();
            $this->obj[$key] = $val;
            $this->pos++;
        }
        return $this->obj;
    }

    private function getValue(): int {
        return 42;
    }
}

$t = new Test();
echo json_encode($t->test()) . "\n";
// 期望: {"key0":42,"key1":42}
// 实际（修复前）: 无限循环（break 未生成）
```

## 根本原因

### 原因 1: `isLoopBreakTarget` 越界检查

```zig
// 修复前：
fn isLoopBreakTarget(self: *Self, func: *const IR.Function, br_target: *const IR.BasicBlock) bool {
    if (self.current_loop_exit_block) |exit_idx| {
        // 当 exit_idx >= func.blocks.items.len 时，此条件恒为 false
        if (exit_idx < func.blocks.items.len and func.blocks.items[exit_idx] == br_target) return true;
    }
    // ...
    return false;
}
```

### 原因 2: exit 块预标记导致 then 块处理被跳过

```zig
// 行 10543-10544：exit 块被无条件预标记
if (exit_idx < func.blocks.items.len) {
    try processed.put(exit_idx, {});
}

// 行 10677：then 块处理被跳过（因为 then_bi == exit_idx 且 exit_idx 已被 processed）
} else if (!processed.contains(ti)) {
    // then 块的指令和终止符处理...
    // break 语句应在此处生成，但被跳过
}
```

## 修复方案

### 修复 1: `isLoopBreakTarget` 增加 while(true) 回退

```zig
fn isLoopBreakTarget(self: *Self, func: *const IR.Function, br_target: *const IR.BasicBlock) bool {
    if (self.current_loop_exit_block) |exit_idx| {
        if (exit_idx < func.blocks.items.len and func.blocks.items[exit_idx] == br_target) return true;
        // while(true) 无正式 exit 块时，非循环回边的 br 目标都是 break 目标
        if (exit_idx >= func.blocks.items.len) {
            if (self.current_loop_cond_block) |cond_idx| {
                if (cond_idx < func.blocks.items.len and func.blocks.items[cond_idx] != br_target) return true;
            } else {
                return true;
            }
        }
    }
    // ...
}
```

### 修复 2: then 块指向 exit 块时直接生成 break

```zig
// 在 if 生成前预检测 then 块是否就是 exit 块
var then_is_exit_break = false;
if (then_bi) |ti| {
    if (exit_idx < func.blocks.items.len and ti == exit_idx) {
        then_is_exit_break = true;
    }
}

// 生成 if 块后，若 then_is_exit_break 则直接 break
if (then_is_exit_break) {
    try writer.print("{s}    break :{s};\n", .{ then_indent, label_name });
    self.break_generated = true;
}
```

### 修复 3: then 块 `.br` 处理增加 `isLoopBreakTarget` 回退

```zig
.br => |br_target| {
    if (exit_idx < func.blocks.items.len and br_target == exit_ptr) {
        // 正常 exit 块匹配 → break
    } else if (br_target == cond_block_ptr) {
        // 循环回边 → continue
    } else if (self.isLoopBreakTarget(func, br_target)) {
        // while(true) 无正式 exit 块时，br 到循环外块 → break
        try writer.print("{s}    break :{s};\n", .{ then_indent, label_name });
        self.break_generated = true;
    } else if (br_target != cond_block_ptr) {
        // 跟踪 merge 块
    }
},
```

## 影响范围

- `while(true)` + `break` 的 AOT 代码生成（此前会导致无限循环或输出 null）
- `while(true)` + `if/else` + `break`/`continue`/`throw` 的组合

## 测试结果

> 下表是**修复过程中某一时点**的中间读数（`test_while_*` / `f067_min*` 系列脚本后被清理轮次删除），三行 ❌ 据本文更新日志 2026-08-24 条记录「已于变更摘要中修复通过」，勿据此判缺陷仍在。当前树判定以下一节「2026-10-01 复测」为准。

| 测试文件 | PHP 输出 | AOT 输出（修复后） | 状态 |
|---------|---------|------------------|------|
| test_while_simple.php | `{"key0":42,"key1":42}` | `{"key0":42,"key1":42}` | ✅ |
| test_while_arr.php | `{"a":30,"b":40}` | `{"a":30,"b":40}` | ✅ |
| f067_min_match3.php | `{"a":30,"b":40}` | `{"a":30,"b":40}` | ✅ |
| f067_minimal3.php | `{"a":30,"b":40}` | `{"a":30,"b":40}` | ✅ |
| f067_minimal4.php | `{"a":30,"b":40}` | `{"a":null,"b":null}` | ❌ |
| f067_debug_route2.php | `{"a":30,"b":40}` | `{"a":null,"b":null}` | ❌ |
| f067_debug_char3.php | `{"a":30}` | `{"a":null}` | ❌ |

### 2026-10-01 当前树复测（永久探针 `fuzzy_scripts_720/tmp/c003_while_true_break_tmp.php`）

| 形 | 覆盖的「影响范围」 | PHP 8.5.8 真值 | AOT（`b21cdfd` 当前树） | 判定 |
|---|---|---|---|---|
| R1 | 工单原文复现：方法内 `while(true)` + `if (pos >= 2) break;` + 属性数组写入 | `R1 {"key0":42,"key1":42}` | 同 | ✅ 等值 |
| R2 | 循环携带变量 + 短路条件 + `continue` + 条件 `break` | `R2 iter=6 [10,30,50]` | 同 | ✅ 等值（修复 4/5 的回边 PHI 与短路链首条件边不回退） |
| R3 | `while(true)` + `throw`，外层 catch 后**同函数二次调用** | `R3 first=caught:stop@3 second=caught:stop@3 hits=6` | 同 | ✅ 等值（异常后状态污染形已根治） |
| R4 | `foreach` 驱动 + 内层 `while(true)` + `break`（与迭代器/臂内派发家族交叉） | `R4 ["1-1","2-1","2-2","3-1","3-2","3-3"] count=6` | 同 | ✅ 等值 |

```bash
cd /Users/wangjianjun/products/parser
timeout 10 /opt/homebrew/bin/php fuzzy_scripts_720/tmp/c003_while_true_break_tmp.php
timeout 300 ./zig-out/bin/php-interpreter --compile --no-debug-info \
  --output=/tmp/aot_compile_c003_while_true_break_tmp fuzzy_scripts_720/tmp/c003_while_true_break_tmp.php
timeout 10 /tmp/aot_compile_c003_while_true_break_tmp   # RUN_RC=0，diff 与 PHP 逐字节等值
rm -f /tmp/aot_compile_c003_while_true_break_tmp        # 编译产物用完即删
```

## 修复 4（2026-08-24）: 循环回边 PHI 物化缺失导致循环局部变量不更新

### 独立缺陷

`generateWhileFromLabels` 生成循环体 `cond_br` 时，原先的“修复 2”在 `then_is_exit_break`（循环体内条件性 `if(...){ break }`）分支错误地执行 `self.break_generated = true;`。

```zig
// 错误代码（已被移除）：
if (then_is_exit_break) {
    try writer.print("{s}    break :{s};\n", .{ then_indent, label_name });
    self.break_generated = true;   // ← 条件性 break 也被标记为不可达
}
```

该标志被随后（行~10781）保存为 `saved_break_for_body_if`，并在 if/else 合并后（行~11325）恢复：

```zig
if (!self.break_generated) self.break_generated = saved_break_for_body_if; // 恢复为 true
```

由于 `break_generated == true`，循环体后段两处关键生成被门控跳过：

```zig
// 行~11381 循环回边 PHI 消解（被 !break_generated 门控）
if (!self.return_generated and !self.break_generated and !self.lastLineIsReturn(writer)) {
    // 应为 reg_60 = reg_39 等循环局部变量回写 —— 被跳过
}

// 行~11413 循环末 continue（被 !break_generated 门控）
if (!self.return_generated and !self.break_generated) {
    // continue :label —— 被跳过
}
```

### 根因

条件性 `break`（包裹在 `if(...)` 内）执行后，if 的 else/fall-through 路径仍然可达（循环可能再次迭代）。把 `break_generated` 置为 `true` 错误地表示“循环末端不可达”，从而抑制了：

1. 循环回边 PHI 物化——循环局部变量的 SSA 寄存器（如 `$iter` 对应 `reg_60`）在回边处永不写回 `reg_60 = reg_39`；
2. 循环末的 `continue :label`——但 `while(true)` 天然回绕，语义上仍成立，真正丢失的只有 PHI 回写。

结果：循环迭代变量在每次迭代都读取入口初值，循环体内 `echo` 等语句虽可执行但引用的迭代变量始终为初值。

### 修复

条件性 break 不应让循环末端不可达，移除置位：

```zig
if (then_is_exit_break) {
    try writer.print("{s}    break :{s};\n", .{ then_indent, label_name });
    // 不置 break_generated —— 条件性 break 之后回退路径仍可达
}
```

这样循环末端回边 PHI 消解（`reg_60 = reg_39`）与 `continue :label` 被正确生成，仅在真正的无条件 break/return（`.br`/`.ret` 终止符）时才被抑制。

### 验证

| 用例 | PHP | AOT（修复前） | AOT（修复后） |
|-----|-----|--------------|--------------|
| `rec_mini.php`（while + 短路条件 + 体 echo + 条件 break） | `iter=0 iter=1 int(30)` | `iter=0 iter=0 int(30)`（`$iter` 不递增） | `iter=0 iter=1 int(30)` ✅ |
| `f067_debug_pos2.php` | 循环体 echo 打印 `while iter=...` | 循环体 echo 完全未执行 | `while iter=0/1: ...` + `END pos=2 iter=2` ✅（与 PHP 一致，见修复 5） |

全量回归（114 个 pass 脚本，归一化比对）结论：**65 失败 == 65 基线失败，完全一致，无新增失败、无消失失败**。

## 修复 5（2026-08-24）: 短路条件链首条件失败边循环携带变量 PHI 未物化

### 独立缺陷

`while (cond1 && cond2 …)` 短路链中，循环**经首条件失败边退出**时，循环携带局部变量（`$iter`）最终值未物化。

### 根因

`generateExitPHIAssignments` 的携带值回退只扫描 `current_loop_cond_block`（短路链最终决策块 `logical_merge_4`，仅含合并的布尔 PHI `reg_25`），而循环携带寄存器 `reg_91`（`$iter` 的 Sync/PHI result）定义在条件起始块 `while_cond_0`（首条件 break 生成处）。回退无匹配 → 首条件失败边不生成 `reg_92 = reg_91` → 退出时读到回边残留旧值（`iter=1` 而非 `2`）。

### 修复

回退候选由“仅决策块”扩为“源块（break 生成处）优先 → 决策块次之”，在源块找其 PHI result 作为 exit PHI 的 incoming 值：

```zig
var candidates: [2]usize = undefined; var cand_len: usize = 0;
candidates[cand_len] = source_idx; cand_len += 1;   // ① 源块，持有循环携带 PHI
if (self.current_loop_cond_block) |cb| { if (cb != source_idx) { candidates[cand_len] = cb; cand_len += 1; } }
outer: for (candidates[0..cand_len]) |cand| {
    if (cand >= func.blocks.items.len) continue;
    for (func.blocks.items[cand].instructions.items) |phi_inst| {
        if (phi_inst.op == .phi) if (phi_inst.result) |cr| {
            for (inst.op.phi.incoming) |incoming| {
                if (incoming.value.id == cr.id) {
                    try self.writePtrAwareAssign(writer, indent, result_reg.id, cr.id);
                    resolved = true; break :outer;
                }
            }
        };
    }
}
```

### 验证

`f067_debug_pos2.php` 现在 **PASS**（循环体 echo 字符串完整渲染 + `END iter=2` 正确）。全量 114 脚本 Pass 50（基线 49，`f067_debug_pos2` FAIL_DIFF→PASS），**零真回归**。变更见 `docs/changes/2026-08-24/loop_cond_chain_phi_fallback_d7a2bd6f.md`。

---

## 修复 6（2026-08-24 记录 / 2026-09-20 落地）: while_body_ 作循环头时 then/else 臂未识别 → 整个循环被压平

### 缺陷

IR 生成器对某些 `while(true)` 省略 `while_cond_` 块，直接以 `while_body_N` 作循环头（如 f067 `JsonParser::parseArray`，body 以 array.push 起始的形态）。generic cond_br 处理器的 then/else「循环控制结构」识别列表只含 `while_cond_/for_cond_/foreach_cond_/do_while_body_`，`while_body_` 漏项 → 循环头块被当普通块内联 → **while 循环整体压平为直线代码**：逗号分支 `pos++; continue;` 的 continue 丢失，落入后续 `]` 检查与无条件 throw。

症状：`{"a":[1]}` 通过、`{"a":[1,2]}` 报 `Expected ',' or ','`；`parse('[1,2]')` 停在 pos=3（第二元素从未解析）；异常后同函数重入时外层驱动 foreach 静默早退。

### 修复

`generateLabelDrivenBlockRange` generic cond_br 的 then（@~7641）与 else（@~8413）派发列表各补一行 `while_body_` 前缀识别，命中即递归 `generateLabelDrivenBlockRange` → 由 @6981 的 while_body_ 入口 → `generateWhileFromLabels` 正常生成 `__while_N: while(true)` + continue/break。

### 验证

探针 6 例（`{"a":[1]}`、`{"a":[1,2]}`、`[1,2]`、`[1]`、`{"a":{"b":[1,2]}}`、`{"b":2,"a":[1,2]}`）AOT 与 PHP 全 MATCH；`f067_min_repro` MATCH；f097/f113 保持逐字节一致。

### 未关闭的 f067 后续缺陷（2026-09-20 定性）→ ✅ 已全部闭环（2026-09-21）

2026-09-21 干净二进制复测：`f067_json_parser_schema_path_diff` 与 `f067_min_repro` 在 68 脚本回归中双双 PASS（逐字节一致），三个残留探针（`f067_num_probe`、`f067_or_hop`、`f067_nested_if`）MATCH，`f067_or_hop2` 数值一致（仅 PHP 解释器 "Uninitialized string offset" 警告行为差异，非 AOT 缺陷）。判定以下 (a)(b)(c) 已随 f095 两段修复（退出边 PHI 物化 + 臂内循环派发）及 f113 系列修复一并根治：

1. ~~`parseNumber` 科学计数法 `1e5`~~ ✅ 已闭环；
2. ~~`getPath` 输出值为空~~ ✅ 已闭环；
3. ~~throw 被 catch 后同函数二次调用状态污染~~ ✅ 已闭环。

## 修复 7（2026-09-21）: if 臂尾 br→循环头未派发致循环逃逸 if 外（臂逃逸/UAF 家族）+ f033 地形门控

### 缺陷 A：臂逃逸循环 → use-after-free（f095/b18c，段错误根因）

`if_merge_`+cond_br 处理器（`generateLabelDrivenBlockRange` @~7100 特殊路径）的 then 块终止符 `.br` 分支原为空操作。当 if 体内嵌 foreach/for/while（then 臂尾 br 指向循环头块）且循环头块**不在臂线性范围**（IR 乱序布局）时，线性行走只把臂内指令发射进 if 体，循环本体留在 if 闭合之后的顶层——每次父迭代无条件进入循环头，读到上一轮已 `php_array_iter_free` 的陈旧迭代器 alloca（Debug 存活、ReleaseFast SIGSEGV，f095 最小复现 `b18c_tmp.php` 需两个相邻 if 各带嵌套 foreach 才触发）。

**修复**：`.br` 分支识别循环头标签前缀（`foreach_cond_/for_cond_/while_cond_/while_body_/do_while_body_`），在 then 缩进内就地派发 `generateForeach/For/WhileFromLabels`（与 `generateIfFromLabels` 的 f067 臂内派发同源），配 `defer_loop_fallthrough=true` 防止循环生成器抢先消费本 if 共享 merge，出口即 merge 时经 `materializeBrTargetMergePhis` 物化 exit→else 边 PHI。

### 缺陷 B：抢先派发吞并按序共享 merge → f033 回归（地形门控）

臂内派发引入 f033 `StateMachine::transition` 回归（`if(isset($guards[$k])){foreach…} 尾部; return true`：Transition 返回 NULL、状态不推进）。两例块几何完全同构（`nti < nei < hi < end`），差异在 **merge 块自身的终止符**：

| | merge@nei 终止符 | else 抬升行走 | 正确策略 |
|---|---|---|---|
| f033 | `.ret`（`return true`） | 止于 return，外层主行走在 if 闭合后正确派发 foreach，并以 defer=false 就地消费 merge 补发 then 路径尾部拷贝（HEAD 旧行为） | **禁止派发** |
| f095/b18c | `.cond_br`/`.br`（路径继续） | `[nei,end)` 连带吞掉排在 merge 之后的 then 臂 foreach 块，循环被发射进 false 臂（f095 症状：`used['diff']` 丢失 → dce 7≠6、`diff=const(-7)` 被误删） | **必须抢先派发** |

**修复门控**（native_linker.zig @~7290）：

```zig
const ah_merge_stop_after = /* nei 在界内且其 terminator 为 .ret/.throw */;
const ah_merge_in_terrain = nested_else_idx != null and
    nested_else_idx.? > nti and nested_else_idx.? < end_idx and
    nested_else_idx.? < hi and ah_merge_stop_after;
// !ah_in_arm_range and !ah_merge_in_terrain and !is_outer_back_edge and !processed.contains(hi) 才派发
```

### 验证（2026-09-21，干净二进制）

f033 / b18c / f095 / f067（含 min_repro）逐字节一致；68 脚本回归 **61 PASS**，零新增失败，f113、f067 转 PASS；残留失败仅为基线固有（f004 SKIP、f163 FAIL_DIFF、exit=124 超时组 f007/f038/f124/f161/f178）。

### 失败尝试（勿重试）

在派发点用 `generateLabelDrivenBlockRange(nei, end_idx)` 直接向 then 臂补发 merge 内容拷贝：f095 死循环（补发范围连带外层循环 latch）、f033 尾部双重执行（`state=paid` 出现在 no-tracking 路径）。拷贝的唯一正确来源是主行走的 FE-CONS 就地消费（defer=false 语境）。

## 修复 8（2026-09-21）: merge 块边物化双缺口 —— GIFL Step-10 回边丢失（f163）+ 循环生成器 false 边直落缺省（f044）

### 缺陷 A：`generateIfFromLabels` Step 10 消费 merge 后丢失「.br → 更早共享 merge」边（f163）

f163 `EventStore::replay` 中 `if ($snapshot) { …array_slice(…) } else { …??[] }` 两臂各以 `.br` 汇入更早的共享 merge 块；GIFL Step 10 就地消费该 merge（置 `processed`）后，本块终止符 `.br` 到更早 merge 的边只剩「PHI handled in terminator」占位注释，外层行走再也见不到这条边 → 目标 merge phi 读上一轮陈旧寄存器（`$events` 跨分支污染）。

**修复**（Step 10 `.br` case，@~15960）：按边物化，门控三条件——

```zig
if (!is_loop_head_target and br_t.index < merge_block.index) {
    try self.materializeBrTargetMergePhis(writer, merge_block, br_t, indent);
}
```

- 回边/横向汇入（目标块 index **更早**）：外边无人按边补写，必须在此物化；
- 前向目标：由后续顺序行走正常消费该边，不发以免冲写；
- 循环头目标：latch 自带回边物化，跳过。

### 缺陷 B：循环生成器 `nested_then_br_to_else` 处理器只物化 then 边、缺 false 边直落（f044）

f044 行 99 `$rules['type'] ?? 'any'`：`??` 三元 PHI 的 **false/直落边 incoming 来自 cond 源块（else_blk）**。foreach/for/while 生成器的 `nested_then_br_to_else` 分支发射形态为 `if (cond) { then 指令 + then 边 PHI 拷贝 }` 后接 merge 延续——**从不调和 cond 源块进入的 false 边** → `reg_82` 跨迭代携带陈旧值。此前 f044「侥幸通过」是两条错误边互相抵消的假象（stale-false coincidence）；缺陷 A 落地后该行必须真修。

**修复**：在 5 个 `if (nested_then_br_to_else) {` 站点（foreach/for/while 臂，@~11033/@~11265/@~13239/@~14447/@~14629 区域），then 臂内容之后、闭合 `{s}}}` 之前补发 false 边拷贝，复用既有右括号闭合 else——

```zig
if (nested_else_idx) |nei_fe| {
    const m_fe = func.blocks.items[nei_fe];
    var fe_emitted = false;
    for (m_fe.instructions.items) |pi_fe| {
        if (pi_fe.op != .phi) continue;
        if (pi_fe.result) |r_fe| {
            for (pi_fe.op.phi.incoming) |inc_fe| {
                if (inc_fe.block == else_blk or
                    std.mem.eql(u8, inc_fe.block.label, else_blk.label))
                {
                    if (!fe_emitted) {
                        try writer.print("{s}}} else {{\n", .{then_indent});
                        fe_emitted = true;
                    }
                    try self.writePtrAwareAssign(writer, ntbe_indent, r_fe.id, inc_fe.value.id);
                    break;
                }
            }
        }
    }
}
```

无命中 PHI 时保持单臂直落形态（不发空 else）。第 6 个候选站点（@~12996「方案 C：嵌套 merge 已被外层 if 认领」变体）内部结构不同，未打点，保持原行为。

### 定位手段备忘

第二处错误边由 `writePtrAwareAssign` 内临时栈探针（`std.debug.captureCurrentStackTrace` + `dumpStackTrace`，ReleaseSafe 可用）精确钉到 `generateForeachFromLabels` @11097 —— 静态猜点两次落空后唯一有效手段，探针已于提交前全部移除。

### 失败尝试（勿重试）

v3 方案：GIFL 维护 `active_gifl_merges` 栈 + `on_active_merge` 按激活 merge 判定补写 —— f044 通过但 f163 回归（栈门控无法区分前向消费边），已整体回滚，最终采用 v2 回边 index 门控 + 缺陷 B 真修。

### 验证（2026-09-21）

- f044：修复二进制 3 次独立编译运行均与 `/opt/homebrew/bin/php` 输出**逐字节一致**（两条边均真实物化，消除侥幸抵消）；
- f163：与 ground truth 逐字节一致（FAIL_DIFF → PASS，PASS 组唯一残留清零）；
- 68 脚本全量回归（2026-09-21 17:08）：**62 PASS / 0 FAIL_COMPILE / 5 FAIL_RUNTIME（exit=124 基线组 f007/f038/f124/f161/f178）/ 0 FAIL_DIFF / 1 SKIP（f004）** —— 零新增失败，FAIL_DIFF 组清零；详见 `docs/changes/2026-09-21/f163f044_merge边物化双缺口修复_2026-09-21_908a3a0.md`。

## 遗留问题

### 遗留 1: ~~复杂 echo 字符串内容为空（`f067_debug_pos2.php`）~~ ✅ 已修复（修复 5）

~~相同测试中循环体 echo：~~
```php
echo "  while iter=$iter: pos=" . $this->pos . " ... ctype=" . (ctype_digit(...) ? "1" : "0") . " ...\n";
```
~~行~6189 concat 前有 `// PHI: reg_92 (handled in terminator)`，PHI 未物化导致 `reg_92` 为空，整个字符串坍缩为仅 `\n`。为独立缺陷（PHI 物化→三元表达式内字符串拼接），非本次 while+break PHI 修复范围。~~

已于 2026-08-24（修复 5）解决：短路链首条件失败边循环携带变量 PHI 物化缺失，`f067_debug_pos2.php` 已从 FAIL_DIFF 转为 PASS。

### 遗留 2: ~~早期 3 个 null 测试~~ ✅ 已闭环（依据 2026-08-24 更新日志 + 2026-09-21 干净二进制复测 + 当前回归台账）

3 个测试曾输出 null，疑似 `parseObject` 中 `return $obj` 在 while 循环内部直接执行时（而非 break 后执行），`$obj` 的值未被正确传播。可能原因：

1. **PHI 消解问题**：`return $obj` 使用的 `reg_59` 可能引用了错误的 PHI incoming 值
2. **变量生命周期**：`$obj`（`reg_7` 指针）在循环迭代中被释放或覆盖
3. **关联已知问题 AOT-PHI-001**：嵌套 if 语句的 PHI 节点赋值问题可能导致 `$obj` 值丢失

**闭环依据（2026-10-01 核对）**：更新日志 2026-08-24 条记录三例「已于变更摘要中修复通过」；2026-09-21 干净二进制复测判定 f067 三个后续残留缺陷（1e5 / getPath / post-catch）随修复 7 全部闭环；当前回归失败台账 `fuzzy_scripts_720/regression_failures.tsv` **只余 `SKIP|f004_oop_deep_inheritance_magic.php` 一行，无任何 f067 条目**；本轮 R1–R4 复测再补一层直接证据（R3 即「异常后同函数二次调用」形）。上面三条猜测保留为**历史取证线索**，不再是待办。

## 相关代码

> 下列为 **2026-10-01 实测锚点**（`src/aot/native_linker.zig`，当前 32296 行）。本文修复 1–8 中写的 `:881 / :892 / :10341 / :10543 / :10617 / :10744 / :11381 / :11413 / :15960` 等行号对应**当时的文件形态**，已随后续修复整体下移，仅作历史线索读，勿按图索骥。

| 锚点 | 当前行 | 作用 |
|---|---|---|
| `isLoopBreakTarget` | :901 | break 边判定（修复 1 的 `while(true)` 无 exit 块回退在此） |
| `isLoopContinueTarget` | :924 | 成对谓词（CODEGEN-005 RC-1 新增） |
| `writeBrInLoopContext` | :935 | `.br` 型 break 边发射（修复 3 的回退入口） |
| `generateLabelDrivenBlockRange` | :7174 | 公共范围行走；generic `cond_br` 的 then/else 循环头识别（修复 6 补 `while_body_`）、`if_merge_`+`cond_br` 处理器（修复 7/8） |
| `generateExitPHIAssignments` | :10663 | 退出边 PHI 物化（修复 5 的「源块优先 → 决策块次之」候选在此） |
| `materializeBrTargetMergePhis` | :10796 | 按边物化（修复 8 缺陷 A 的回边 index 门控调用它） |
| `generateWhileFromLabels` | :14630 | while 生成器主体 |
| ↳ exit 块预标记 | :14878 | 修复 2 描述的「预标记导致 then 被跳过」的现状位置 |
| ↳ `then_is_exit_break` 判定与发 break | :15032–15050 | 修复 2 + 修复 4（**不置** `break_generated`） |
| ↳ then 块 `.br` 的 `isLoopBreakTarget` 回退 | :15204 | 修复 3 |
| ↳ 臂内嵌循环头派发（RC-3） | :15209–15291 | CODEGEN-005 RC-3，与本工单修复 7 的臂内派发同源 |

## 关联已知问题

- **AOT-PHI-001**: 循环中嵌套 if 语句的 PHI 节点赋值问题 —— **已于 2026-08-26 修复**，此处仅作当年 `$obj` 丢失的取证线索保留（见 §遗留 2 闭环依据）
- **AOT-CODEGEN-002**: 结构化控制流生成器的 continue 插入问题 — 相关的循环控制流生成 bug
- **AOT-CODEGEN-005**: 同族的「if 臂内嵌循环 / 臂尾 break」发射家族。**本工单修复 7 的臂内派发与它的 RC-1/RC-2/RC-3 同源**；该工单 CLOSED，但 2026-10-01 新登记的 **RC-4 候选**（同臂内、内层循环之后的裸 `break` 未发射）仍 ⏳ 待裁决 ⇒ 本工单的 `while(true)` 判定不受影响，R1–R4 均为等值实测

---

**更新日志**:
- 2026-10-01: **状态 部分修复 → CLOSED**。原复现脚本已在清理轮次删除，按 §复现代码 重建永久探针 `fuzzy_scripts_720/tmp/c003_while_true_break_tmp.php`（R1 原文复现 + R2 携带变量/continue + R3 throw 后同函数二次调用 + R4 foreach 驱动内层 while），当前树（`b21cdfd`）实测四形与 PHP **逐字节等值**、`RUN_RC=0`；同轮把 §相关代码 的 2026-08 历史行号换成实测锚点表、关闭 §遗留 2、补 §关联 的 CODEGEN-005（RC-4 候选仍待裁决）交叉引用
- 2026-09-21: 新增修复 8（GIFL Step-10 `.br`→更早 merge 回边按边物化根治 f163 + 循环生成器 `nested_then_br_to_else` false 边直落补发根治 f044 行99 `??`；f044 侥幸抵消假象消除，两文件逐字节一致）
- 2026-09-21: 新增修复 7（if 臂尾 br→循环头臂内派发根治 f095/b18c 臂逃逸 UAF + f033 地形门控防抢先派发吞并按序共享 merge）；f067 三个后续残留缺陷（1e5/getPath/post-catch）判定随本轮修复全部闭环，探针复测通过
- 2026-09-20: 新增修复 6（while_body_ 循环头 then/else 识别补全，f067 数组循环压平根治）；记录 f067 后续三缺陷（1e5 数字解析、getPath 空值、异常后状态污染）
- 2026-08-22: 初始创建，修复 break 语句未生成的两个根因，3 个测试仍有遗留问题
- 2026-08-24: 新增修复 4（循环回边 PHI 物化缺失），修复 2 的 `break_generated = true` 置位被识别为缺陷并移除；`f067_minimal4/route2/char3` 已于变更摘要中修复通过，新增 114 脚本全量回归（65=65 无新增）
- 2026-08-24（续）: 新增修复 5（短路链首条件失败边循环携带变量 PHI 物化），遗留 1 关闭，`f067_debug_pos2.php` FAIL_DIFF→PASS；全量 114 脚本 Pass 50、零真回归
