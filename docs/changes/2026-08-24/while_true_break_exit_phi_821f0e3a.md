# 交接文档：`while(true)+break` 出口 PHI 物化缺失修复（嵌套 foreach 阻断 f177 简况）— Session 2026-08-24

> 日期：2026-08-24 | 涉及文件：`src/aot/native_linker.zig`
> 变更标识：`while_true_break_exit_phi`（未提交工作区，叠加于既有工作区差异之上）
> 编译状态：✅ `zig build` 通过
> 上级交接链：`docs/changes/2026-08-24/handoff.md`（4d3a1f0 会话，共享 merge 嵌套 if）

---

## 1. 高层摘要（TL;DR）

在推进 f177 段错误（exit=137）最小化时，下钻出**两个独立的 while+break 缺陷**，其中一个已修复并零回归：

### 缺陷 A（本会话已修复）：`while(true)+break` 出口 PHI 未物化
- **表现**：`while(true){ $i++; if($i>=3) break; } echo "i=$i";` 的 AOT 输出 `i=0`（PHP 应为 `i=3`）。
- **根因**：IR 将 `while(true)` 降级为 `while_cond_0`（体+条件合并，body==cond）+ `while_exit_2`。出口 PHI `reg_14` 持**冗余 incoming** `[reg_13(循环PHI旧值), reg_4(最新计算值)]`（均来自 while_cond_0）。`generateWhileFromLabels` 的 `then_is_exit_break` 分支（body 终止符 cond_br 的 then 直接指向 exit）**裸 `break :label` 未物化出口 PHI**，`reg_14` 停留在循环前的 0。
- **修复**：新增 `materializeExitPHIOnThenBreak` 辅助函数，break 前跳过「body 块内的循环 PHI 结果」（陈旧值），物化「body 内最新计算值」到出口 PHI（`reg_14 = reg_4`）。若变量在 body 未变更（仅有 PHI 结果 incoming）则回退到首个来自 body 的 incoming。
- **验证**：`repro_w1` AOT===PHP（`i=3`）；全量回归 108 脚本 **Pass 49 与基线一致，零真回归**。

### 缺陷 B（嵌套 foreach 于 while(true) 内，阻断 f177，记为 P1 后续）
- **表现**：`dijkstra()` 的 `while(true){ $i++; foreach($dist as $v=>$d){...} if($minVertex===null) break; ... }` 仍 exit=137 死循环。
- **根因**：while 的真实回边/break 落在嵌套 `foreach_cleanup_6` 的终止符（`br ge(reg_6,3), while_exit_2, while_cond_0`）。`generateForeachFromLabels` 的 cleanup 终止符处理（line ~9540-9562）只处理 `.ret`，对指向**外层 while** 的 `cond_br` 落入空分支 → 生成 `if(reg_27.toBool()){}else{}` **全空** → 永不 break → 死循环 OOM。
- **评估**：需 `generateForeachFromLabels` 识别 cleanup 终止符指向外层 while 的 exit/cond 并按 while 语义委派（物化外层 while exit PHI + 回边写回），涉及跨循环上下文协调（`generateForeachFromLabels` 覆盖了 `current_loop_label/exit/cond`），为高风险结构性重构，尚未找到最小可验证切入路径。**本会话不盲目进行，记为 P1。**

---

## 2. 交接链路

```
docs/changes/2026-08-24/handoff.md (4d3a1f0, 共享 merge 嵌套 if)
  └─ 本轮(while_true_break_exit_phi): 推进 f177 段错误最小化
      ├─ ✅ 缺陷A: while(true)+break 出口 PHI 未物化(materializeExitPHIOnThenBreak) → repro_w1 归零, 零回归
      └─ ✅ 缺陷B记录: 嵌套foreach于while(true) → while回边/break落在foreach_cleanup终止符, 空分支死循环(阻断f177, P1)
```

---

## 3. 核心变更

### 3.1 新增 `materializeExitPHIOnThenBreak`（紧邻 `generateExitPHIAssignments` 之后）

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

### 3.2 `then_is_exit_break` 分支 break 前调用物化

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

### 3.3 修复后生成的 Zig 结构（`w1`）

```zig
__while_0: while (true) {
    reg_4 = try runtime.php_increment(reg_13);   // $i++
    ...
    reg_7 = try runtime.php_ge(reg_4, reg_6);    // $i >= 3
    if (reg_7.toBool()) {
        reg_14 = reg_4;                          // ← 新增：出口 PHI 物化 $i=当前值
        _ = reg_14.retain();
        break :__while_0;                        // ← break 前已物化
    }
    reg_13 = reg_4;                              // 回边写回
    _ = reg_13.retain();
    continue :__while_0;
}
... echo i=reg_14 ...                            // 现为 3
```

---

## 4. 回归概览

| 范围 | 结果 |
|------|------|
| 首要目标 | `repro_w1`（`while(true){$i++;if($i>=3)break;}`）：AOT `i=3` 与真实 PHP 一致（修复前 `i=0`） |
| 标准 while 对照（`repro_w3`） | `while($i<3){$i++;}` AOT `i=3` 仍正确，未受影响 |
| 全量 pass（108 脚本） | **Pass 49，FAIL_RUNTIME 20，FAIL_DIFF 35，SKIP 4；与基线完全一致，零真回归** |
| 嵌套 foreach 阻断项 | f177 仍 FAIL_RUNTIME(137)，为缺陷 B（嵌套 foreach），本修复不覆盖 |

---

## 5. 详细变更分析

| 端/层 | 模块 | 变更点 |
|-------|------|--------|
| 代码生成 | `native_linker.zig` | 新增 `materializeExitPHIOnThenBreak`（物化 while(true)+break 的出口 PHI，跳过 body 循环 PHI 陈旧值） |
| 代码生成 | `native_linker.zig` `generateWhileFromLabels` | `then_is_exit_break` 分支 break 前调用该辅助函数 |

涉及文件：
- `src/aot/native_linker.zig`

---

## 6. 影响与风险评估

- **是否破坏式变更**：否。仅在 `then_is_exit_break`（body==cond 的 while(true)，body 终止符 cond_br 的 then 直接指向 exit）路径新增物化；此前该路径裸 `break` 未物化，`reg_14` 恒为循环前初始化值（读陈旧/未初始化）。不触及标准 while（body 有独立块，出口读循环 PHI `reg_12`）、for/foreach 路径。
- **变更影响范围**：仅「while(true) 且循环体在 cond 块内、以条件性 break 直接指向 exit」的代码生成。
- **需要特别注意**：`materializeExitPHIOnThenBreak` 依赖「body 内循环 PHI result = 陈旧值」的判定排除集。对多携带变量 loop，各出口 PHI 的陈旧 incoming 恰好是对应循环 PHI result，可正确跳过；若未来 IR 对某变量生成无最新计算值（仅 PHI result incoming）则回退到首个 body incoming（此时携带寄存器本身即当前值，正确）。
- **复测路径**：
  ```bash
  cd /Users/wangjianjun/products/parser
  env -u PKG_CONFIG_PATH zig build
  T=$(mktemp -d)
  ./zig-out/bin/php-interpreter --compile --output="$T/w1" fuzzy_scripts_720/tmp/repro_w1.php
  diff <("$T/w1") <(php fuzzy_scripts_720/tmp/repro_w1.php)   # 期望无输出
  rm -rf "$T"
  ```

---

## 7. 遗留问题 / 潜在问题

- **缺陷 B（高危，P1）**：嵌套 foreach 于 while(true) 内，while 回边/break 落在 foreach_cleanup 终止符 → 空分支死循环。阻断 f177 `dijkstra`、f007/f025/f028/f038 等多脚本。修复方向：`generateForeachFromLabels` cleanup 终止符对指向外层 while 的 `cond_br` 委派处理（需协调 `saved_loop_label`/`saved_exit_block`/`saved_cond_block` 外层上下文，物化外层 while exit PHI + 回边写回）。属跨循环结构性重构，未在上文捕获。
- `repro_w1.php`/`repro_wbreak.php` 等验证脚本位于 `fuzzy_scripts_720/tmp/`，验证后可清理（但 `*.php` 受保护铁律，保留）。

---

## 8. 后续开发 / 优化建议

| 优先级 | 建议 | 影响面 | 落地成本 |
|--------|------|--------|---------|
| P1 | 攻嵌套 foreach 于 while(true)（缺陷 B）：`generateForeachFromLabels` cleanup 终止符委派给外层 while 的 break/回边，先行用 `repro_wbreak.php`/`repro_whiletrue_break.php` 最小验证 | AOT 运行稳定性（f177/f007/f025/f028/f038） | 高 |
| P1 | 为「while(true)+break 出口 PHI 物化」建立约束性单元测试，纳入自动回归 | 代码生成稳定性 | 小 |
| P2 | 复核 `materializeExitPHIOnThenBreak` 在多携带变量、break 前无最新计算值场景的 incoming 选择 | 正确性 | 中 |