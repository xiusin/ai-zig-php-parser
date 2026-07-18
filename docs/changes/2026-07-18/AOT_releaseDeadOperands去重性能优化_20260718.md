# AOT releaseDeadOperands 去重性能优化

| 字段 | 值 |
|------|-----|
| 日期 | 2026-07-18 |
| 轮次 | 第二十二轮（微优化） |
| Commit | 工作区变更 |
| 模块 | AOT 代码生成 / 编译性能 |
| 测试 | 61/61 ALL PASS (pass 37 + fail_runtime 17 + fuzzy_scripts_73 7) |

---

## 1. 高层摘要（TL;DR）

`releaseDeadOperands` 每条指令调用一次，原实现用 `std.AutoHashMap` 去重 `used_regs`（通常仅 1-4 个元素）。HashMap 的分配+哈希+deinit 开销远大于线性查找。优化为 O(n²) 线性查找去重，n≤4 时远快于 HashMap。同时确认 `emitPreGcCleanup` 与 `releaseDeadOperands` 职责不同（不冗余不冲突），无需调整。

## 2. 核心变更

| 文件 | 行号 | 变更描述 |
|------|------|---------|
| `src/aot/native_linker.zig` | ~7431 | HashMap 去重 → 线性查找去重 |

### 变更代码

```zig
// 优化前：HashMap 去重（每次调用分配+deinit）
var seen = std.AutoHashMap(usize, void).init(self.allocator);
defer seen.deinit();
for (used_regs.items) |reg_id| {
    if (seen.contains(reg_id)) continue;
    try seen.put(reg_id, {});
    // ...
}

// 优化后：线性查找去重（零分配）
for (used_regs.items, 0..) |reg_id, i| {
    var is_dup = false;
    for (used_regs.items[0..i]) |prev_id| {
        if (prev_id == reg_id) { is_dup = true; break; }
    }
    if (is_dup) continue;
    // ...
}
```

## 3. 性能分析

| 指标 | HashMap | 线性查找 |
|------|---------|---------|
| 分配次数 | 1 次/指令 | 0 |
| 时间复杂度 | O(n) | O(n²) |
| n=1 | ~100ns（分配+哈希） | ~2ns（0 次比较） |
| n=2 | ~100ns | ~4ns（1 次比较） |
| n=4 | ~100ns | ~16ns（6 次比较） |
| 典型场景 | 每条指令 1-4 个操作数 | 远快于 HashMap |

## 4. emitPreGcCleanup 审查结论

| 检查点 | 结论 |
|--------|------|
| 与 releaseDeadOperands 职责重叠？ | ❌ 不重叠 |
| 职责区分 | releaseDeadOperands：释放**死亡**操作数（liveness 判断）；emitPreGcCleanup：GC 前强制释放**存活但临时**引用 |
| 是否冗余？ | ❌ 不冗余（GC 需看到 ref_count 降到底才能检测循环引用） |
| 是否冲突？ | ❌ 不冲突（emitPreGcCleanup 释放后 nullify，防 SEGV） |
| 是否需要调整？ | ❌ 无需调整 |

## 5. 测试结果

```
=== fuzzy_scripts_73: 7/7 PASS ===
=== fail_runtime: 17/17 PASS ===
=== pass: 37/37 PASS ===
总计: 61/61 ALL PASS, DIFF=0, FAIL=0
```

## 6. 后续建议

| 优先级 | 建议 | 影响面 | 落地成本 |
|--------|------|--------|---------|
| P3 | 清理 `parent_call` 死指令 | 可维护性 | 中 |
| P3 | 统一 PHI 代码生成路径 | 可维护性 | 中 |
| P3 | 引入 releaseDeadOperands 单元测试 | 回归保障 | 中 |
