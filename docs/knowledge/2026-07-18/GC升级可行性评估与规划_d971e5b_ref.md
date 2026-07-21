# GC 升级可行性评估与规划

> 规划文档（非变更摘要）。评估 AOT 运行时由"引用计数 + cycle 检测"升级为"追踪式 GC（分代/压缩）"的可行性、方案、风险与里程碑。
>
> 关联知识：[docs/knowledge/2026-07-18/已知无引用代码参考索引_d971e5b.md](已知无引用代码参考索引_d971e5b.md)（`complete_gc`/`gc_roots`/`cow` 参考）

## 1. 高层摘要（TL;DR）

| 项 | 当前状态 | 建议方向 |
|---|---|---|
| GC 机制 | 引用计数 + Purple/Gray/Black/White 三色 cycle 检测（`runtime_lib_template.zig`） | **不建议升级**为追踪式 GC，原因见第 3 节 |
| 引用计数缺陷 | 循环引用依赖 cycle 检测，高并发场景下 cycle 检测延迟 | 分代 GC 可降低 cycle 检测频率，但 AOT 单线程暂无并发压力 |
| 参考实现 | `complete_gc.zig`（标记-清除-压缩）、`gc_roots.zig`（根集合）、`cow.zig`（原子 COW） | 技术成熟，但与 AOT 运行时模型存在**根本性差异**（见第 4 节） |

**核心结论**：AOT 单线程模型下，当前引用计数 + cycle 检测已是合理方案。升级为分代/压缩 GC 的**收益不明确，风险极高**，建议**暂缓升级**，优先完成 P0 数组 SIMD、P1 bcmath、P1 形状缓存等优化。

## 2. 需求与约束

### 2.1 当前 GC 需求（已满足）

| 需求 | 实现方式 | 状态 |
|---|---|---|
| 自动内存管理 | 引用计数（每个 PHPArray/Object/Closure/String 有 `ref_count`） | ✓ |
| 循环引用回收 | Purple/Gray/Black/White 三色 cycle 检测（`gcCollectCycles`） | ✓ |
| 增量收集 | GC_BATCH_SIZE=64 分批处理，避免长暂停 | ✓ |
| 写保护 | COW（`cloneShallow`/`cloneDeep`），值语义保证 | ✓ |

### 2.2 升级需求（待明确）

| 需求 | 来源 | 优先级 |
|---|---|---|
| 降低 cycle 检测开销 | 高并发场景下 cycle 检测延迟可能累积 | P1 |
| 减少内存碎片 | 引用计数释放后堆碎片化 | P2 |
| 根集合优化 | 全局变量、栈根扫描效率 | P2 |

### 2.3 约束

- **单线程模型**：AOT 产物为单线程可执行文件，无并发压力
- **PHP 语义**：值语义（COW）、对象引用共享、析构函数必须执行
- **现有 COW 实现高度耦合**：`runtime_lib_template.zig`（30K 行）中 `release`、`cloneShallow`、`gcBuffer` 已深度集成 cycle 检测
- **native_linker.zig 生成点耦合**：retain/release/COW 生成逻辑遍及 664KB 文件，任何 GC 策略变更需同步修改

## 3. 方案权衡

### 3.1 方案 A：升级为分代 GC（完整追踪式）

**技术来源**：`complete_gc.zig`（标记-清除-压缩）+ `gc_roots.zig`（根集合）

| 优点 | 缺点 |
|---|---|
| 减少内存碎片，支持堆压缩 | **AOT 单线程无高并发需求，收益不明确** |
| 降低 cycle 检测频率 | **根集合扫描需重构**（当前 cycle_roots 缓冲区 + 阈值触发，分代 GC 需全栈扫描） |
| 提升存活对象局部性 | **引用计数与追踪式 GC 不可兼容**，须完全替换 runtime_lib_template.zig |
|  | **破坏式变更**：native_linker.zig 所有 retain/release 生成逻辑需重写 |
|  | **风险极高**：COW 与追踪式 GC 的写屏障（write barrier）交互复杂，易引入 UAF |

**结论**：收益不明确，风险极高，**不推荐**。

### 3.2 方案 B：优化现有 cycle 检测（渐进式）

| 优化项 | 来源 | 落地成本 | 收益 |
|---|---|---|---|
| 动态调整阈值 | 参考优化策略 | 低 | 减少无效 cycle 收集 |
| 并行标记（未来多线程） | 参考 `parallel_gc` | 高 | 降低暂停时间 |
| 根集合增量扫描 | 参考 `gc_roots.zig` | 中 | 降低根扫描开销 |

**结论**：**推荐**，风险可控，收益可预期。

### 3.3 方案 C：暂缓 GC 升级，优先其他优化

| 优先级 | 优化项 | 收益 | 成本 |
|---|---|---|---|
| P0 | 数组 SIMD（`packed_array.zig` 参考路径） | 数组操作 2-5x 加速 | 中 |
| P1 | bcmath 扩展（`bigdecimal.zig` 参考） | 金融计算刚需 | 中 |
| P1 | 对象属性形状缓存（`shape.zig` 参考） | 属性访问 O(1) | 中 |
| P2 | 小整数缓存（`optimizations.zig` 参考） | 低成本高收益 | 低 |

**结论**：**强烈推荐**，GC 升级暂缓，聚焦高 ROI 优化。

## 4. 技术差异与耦合面分析

### 4.1 参考实现 vs AOT 运行时模型差异

| 维度 | `complete_gc.zig` / `gc_roots.zig` | AOT `runtime_lib_template.zig` |
|---|---|---|
| **GC 模型** | 追踪式（标记-清除-压缩） | 引用计数 + cycle 检测 |
| **根集合** | 栈/全局/寄存器/跨代引用（全扫描） | cycle_roots 缓冲区（增量） |
| **堆管理** | 分代（young/old），对象代际 | 无代际，统一堆（分配器自由管理） |
| **写屏障** | `writeBarrier` 记录跨代引用（`remembered_set`） | 无写屏障，COW 手动 clone |
| **对象生命周期** | 标记阶段决定存活 | 引用计数归零即释放（非 buffer 情况） |
| **并发模型** | 单线程（@thread-safety ISOLATED） | 单线程（同） |
| **类型系统** | `types.Value`（独立表示） | `nanbox_abi`（NaN boxing） |

**关键冲突**：
- 根集合扫描方式不同（全扫描 vs 增量缓冲）
- 堆压缩需要对象移动，而 `nanbox_abi` 中 Value 包含直接指针，移动对象需更新所有引用，**破坏值语义**
- `gc_roots.zig` 依赖 `generational_gc.zig.GCObjectHeader`，AOT 运行时无此头结构

### 4.2 耦合面：native_linker.zig

| 生成点 | 行数（估算） | GC 策略变更影响 |
|---|---|---|
| `generateRetain` | 150 | 需改为 GC 标记/保护 |
| `generateRelease` | 200 | 需改为 GC 取消保护 |
| `writeCOWArrayModify` | 50 | 需与写屏障协同（追踪式 GC） |
| `cloneShallow`/`cloneDeep` 生成 | 30 | 深拷贝与浅拷贝语义在追踪式 GC 下需重新定义 |
| `gcBuffer*` 调用（如数组释放时） | 100 | 需替换为根集合添加/移除 |

**总计影响范围**：约 530 行直接 GC 生成逻辑，但受影响的上下文超过 2000 行（需同步更新 retain/release 调用点）。

### 4.3 耦合面：runtime_lib_template.zig

| 模块 | 行数 | GC 策略变更影响 |
|---|---|---|
| `gcBuffer*` / `gcMaybeCollect` / `gcCollectCycles` | 300+ | 需完全替换为 GC collect/mark/sweep |
| `release`（Array/Object/Closure） | 200+ | 引用计数递减逻辑改为 GC 取消保护 |
| `retain`（Array/Object/Closure） | 50 | 增加引用计数改为 GC 保护 |
| `cloneShallow`/`cloneDeep` | 150 | COW 与写屏障交互 |
| `val_assign` | 100 | COW 检查逻辑需适配 GC |

**总计影响范围**：约 800 行核心 GC 逻辑，但引用计数嵌入整个运行时（PHPArray/Object/Closure/String 所有方法），间接影响 30K+ 行。

## 5. 风险评估

| 风险项 | 概率 | 影响 | 缓解措施 |
|---|---|---|---|
| **内存安全破坏**（UAF/Double Free） | 高 | 致命 | 完整的 `zig build test` + 模糊测试覆盖 |
| **PHP 语义违背**（析构函数未执行） | 中 | 严重 | 析构函数执行测试集 |
| **性能回退**（GC 暂停时间不可控） | 中 | 中 | 基准测试对比 |
| **COW 与写屏障交互冲突** | 高 | 严重 | 详细设计评审，隔离测试 |
| **native_linker.zig 生成逻辑错误** | 中 | 致命 | 逐步迁移，保留回退方案 |

## 6. 里程碑（若执行方案 A）

| 阶段 | 里程碑 | 验收标准 | 工时（预估） |
|---|---|---|---|
| **P0** | 设计评审与原型验证 | 设计文档通过评审，原型跑通 `zig build test` | 1 周 |
| **P1** | 堆替换（保留引用计数接口） | 堆压缩功能验证，所有测试通过 | 2 周 |
| **P2** | 根集合重构（全栈扫描） | 根扫描覆盖所有全局变量/栈根 | 1 周 |
| **P3** | native_linker.zig retain/release 迁移 | 所有生成点验证，benchmark 无回退 | 3 周 |
| **P4** | COW 与写屏障集成 | COW 测试集全通过，无内存泄漏 | 2 周 |
| **P5** | 性能调优与压力测试 | fuzzy_scripts_73 全通过，benchmark 提升 ≥10% | 2 周 |
| **P6** | 文档与交接 | 完整变更摘要 + 维护手册 | 1 周 |

**总计**：12 周（3 个月），高风险，建议**暂缓**。

## 7. 推荐行动

| 优先级 | 行动 | 理由 |
|---|---|---|
| **P0** | 暂缓 GC 升级，保留 cycle 检测优化空间 | 收益不明确，风险极高 |
| **P0** | 推进数组 SIMD（参考 `packed_array.zig`） | 收益明确（2-5x），风险可控 |
| **P1** | 推进 bcmath 扩展（参考 `bigdecimal.zig`） | 金融计算刚需 |
| **P1** | 推进对象属性形状缓存（参考 `shape.zig`） | 属性访问 O(1) |
| **P2** | 优化 cycle 检测阈值（动态调整） | 低成本，低风险 |
| **P2** | 引入小整数缓存（参考 `optimizations.zig`） | 低成本高收益 |

## 8. 附录：参考实现关键符号

| 文件 | 关键 pub 符号 | 可借鉴点 |
|---|---|---|
| `complete_gc.zig` | `CompleteGC`、`Heap`、`GCStats`、`collect()`/`markPhase()`/`sweepPhase()`/`compactPhase()` | 标记-清除-压缩流程、暂停时间预算（`pause_budget_ns`） |
| `gc_roots.zig` | `RootSet`、`RootType`、`iterateRoots()` | 根集合分类（栈/全局/寄存器/跨代） |
| `cow.zig` | `COWWrapper(T)`、`COWState`、`copyOnWrite()` | 原子引用计数、三态（exclusive/shared/immutable）COW |