# 交接文档：`while(true)+break` 出口 PHI 物化缺失修复（嵌套 foreach 阻断 f177 简况）— Session 2026-08-24

> 日期：2026-08-24 | 涉及文件：`src/aot/native_linker.zig`
> 变更标识：`while_true_break_exit_phi`（未提交工作区，叠加于既有工作区差异之上）
> 编译状态：✅ `zig build` 通过
> 上级交接链：`docs/changes/2026-08-24/handoff.md`（4d3a1f0，共享 merge 嵌套 if）
> 详情文档：`docs/changes/2026-08-24/while_true_break_exit_phi_821f0e3a.md`

---

## TL;DR

推进 f177 段错误（exit=137）最小化时下钻出**两个独立的 while+break 缺陷**，缺陷 A 已修复并零回归：

- **缺陷 A（已修复）**：`while(true){ $i++; if($i>=3) break; } echo "i=$i";` 的 AOT 输出 `i=0`（PHP 应为 `i=3`）。根因是 IR 将 `while(true)` 降级为 `while_cond_0`（body==cond）+ `while_exit_2`，出口 PHI `reg_14` 持冗余 incoming，`then_is_exit_break` 分支裸 `break` 未物化。**修复**：新增 `materializeExitPHIOnThenBreak`，break 前跳过 body 循环 PHI 陈旧值、物化最新计算值。
- **缺陷 B（P1 阻断项）**：嵌套 foreach 于 while(true) 内，while 回边/break 落在 `foreach_cleanup` 终止符，`generateForeachFromLabels` cleanup 对指向外层 while 的 `cond_br` 落入空分支 → 空 `if{}else{}` 永不 break → 死循环 OOM，阻断 f177 `dijkstra`。需跨循环上下文协调，本会话不盲目进行。

**成果**：`repro_w1` AOT===PHP（`i=3`）；标准 while 对照不受影响；全量回归 108 脚本 **Pass 49 与基线一致，零真回归**（f177 仍为缺陷 B 阻断）。

**详情**：`while_true_break_exit_phi_821f0e3a.md`
**上一轮**：`handoff.md`（4d3a1f0，共享 merge 嵌套 if，test_f067_min2 `!==` 归零）

---

## 后续建议（承接）

| 优先级 | 建议 | 影响面 | 落地成本 |
|--------|------|--------|---------|
| P1 | 攻嵌套 foreach 于 while(true)（缺陷 B）：`generateForeachFromLabels` cleanup 终止符委派给外层 while 的 break/回边，先行用 `repro_wbreak.php`/`repro_whiletrue_break.php` 最小验证 | AOT 运行稳定性（f177/f007/f025/f028/f038） | 高 |
| P1 | 为「while(true)+break 出口 PHI 物化」建立约束性单元测试，纳入自动回归 | 代码生成稳定性 | 小 |
| P1 | `test_f067_min2.php` 以 `test_` 前缀被自动回归循环（`f*.php`）排除，建议改名 `f067_min2` 纳入覆盖 | 回归覆盖 | 小 |
| P2 | 复核 `materializeExitPHIOnThenBreak` 在多携带变量、break 前无最新计算值场景的 incoming 选择 | 正确性 | 中 |

---

## 复测路径

```bash
cd /Users/wangjianjun/products/parser
env -u PKG_CONFIG_PATH zig build
T=$(mktemp -d)
# 缺陷A 最小复现
./zig-out/bin/php-interpreter --compile --output="$T/w1" fuzzy_scripts_720/tmp/repro_w1.php
diff <("$T/w1") <(php fuzzy_scripts_720/tmp/repro_w1.php)   # 期望无输出 (i=3)
# 标准 while 对照
./zig-out/bin/php-interpreter --compile --output="$T/w3" fuzzy_scripts_720/tmp/repro_w3.php
diff <("$T/w3") <(php fuzzy_scripts_720/tmp/repro_w3.php)   # 期望无输出 (i=3)
rm -rf "$T"
```

---

## 1. 核心变更

### 1.1 新增 `materializeExitPHIOnThenBreak`（紧邻 `generateExitPHIAssignments` 之后）

```zig
fn materializeExitPHIOnThenBreak(
    self: *Self,
    writer: anytype,
    func: *const IR.Function,
    exit_idx: usize,
    body_idx: usize,
    indent: []const u8,
) !void {
    if (exit_idx >= func.blocks.items.len) return;
    const exit_block = func.blocks.items[exit_idx];
    const body_blk = func.blocks.items[body_idx];
    // 收集 body 块内 PHI 结果 id（循环携带变量寄存器），作为陈旧 incoming 排除集
    var body_phi_results = std.AutoHashMap(usize, void).init(self.allocator);
    defer body_phi_results.deinit();
    for (body_blk.instructions.items) |inst| {
        if (inst.op == .phi) if (inst.result) |r| try body_phi_results.put(r.id, {});
    }
    for (exit_block.instructions.items) |phi_inst| {
        if (phi_inst.op != .phi) continue;
        if (phi_inst.result) |result| {
            var chosen_opt: ?usize = null;
            for (phi_inst.op.phi.incoming) |incoming| {
                if (incoming.block == body_blk or
                    std.mem.eql(u8, incoming.block.label, body_blk.label))
                {
                    if (!body_phi_results.contains(incoming.value.id)) {
                        chosen_opt = incoming.value.id;
                        break;
                    }
                }
            }
            if (chosen_opt == null) {
                for (phi_inst.op.phi.incoming) |incoming| {
                    if (incoming.block == body_blk or
                        std.mem.eql(u8, incoming.block.label, body_blk.label))
                    { chosen_opt = incoming.value.id; break; }
                }
            }
            if (chosen_opt) |cid| {
                try self.writePtrAwareAssign(writer, indent, result.id, cid);
            }
        }
    }
}
```

### 1.2 `then_is_exit_break` 分支 break 前调用物化

```zig
if (then_is_exit_break) {
    // 条件性 break 指向 exit 块（body==cond 的 while(true)）：
    // break 前物化 exit 块的循环携带变量 PHI，否则 exit 读到 null/陈旧值。
    if (exit_idx < func.blocks.items.len and exit_idx != cond_idx) {
        try self.materializeExitPHIOnThenBreak(writer, func, exit_idx, body_idx, then_indent);
    }
    try writer.print("{s}    break :{s};\n", .{ then_indent, label_name });
}
```

---

## 2. 回归概览

| 范围 | 结果 |
|------|------|
| 首要目标 | `repro_w1`（`while(true){$i++;if($i>=3)break;}`）：AOT `i=3` 与真实 PHP 一致（修复前 `i=0`） |
| 标准 while 对照（`repro_w3`） | `while($i<3){$i++;}` AOT `i=3` 仍正确，未受影响 |
| 全量 pass（108 脚本） | **Pass 49，FAIL_RUNTIME 20，FAIL_DIFF 35，SKIP 4；与基线一致，零真回归** |
| 嵌套 foreach 阻断项 | f177 仍 FAIL_RUNTIME(137)，为缺陷 B（嵌套 foreach），本修复不覆盖 |

---

## 3. 遗留与后续建议

| 优先级 | 建议 | 影响面 | 落地成本 |
|--------|------|--------|---------|
| P1 | 攻嵌套 foreach 于 while(true)（缺陷 B）：`generateForeachFromLabels` cleanup 终止符委派给外层 while 的 break/回边 | AOT 运行稳定性（f177/f007/f025/f028/f038） | 高 |
| P1 | 为「while(true)+break 出口 PHI 物化」建立约束性单元测试 | 回归稳定性 | 小 |
| P2 | 复核多携带变量、break 前无最新计算值场景的 incoming 选择 | 正确性 | 中 |