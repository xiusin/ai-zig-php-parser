## 目标
- 在不破坏 PHP 语义的前提下，优先落地“收益最大、风险可控”的经典 AOT 优化：RC（retain/release）优化、SCCP（稀疏条件常量传播）、内存/别名模型收敛或补强。
- 让 AOT 输出在真实 workload 上能用 flamegraph/pprof 明确观察到：RC 次数下降、不可达分支消失、生成代码体积与 runtime 调用减少。

## P0：RC（retain/release）优化
- **IR 侧规则设计**
  - 建立“值生命周期/最后使用点”的局部分析（以 SSA use-def 为基础，block 内先做，再扩展到 CFG）。
  - 先做低风险规则：
    - 同一 block 内 `retain(x)` 后在无逃逸/无别名写入前出现 `release(x)`：消除配对。
    - 连续重复 `retain(x)` 或 `release(x)`：合并/去重。
    - `release(x)` 下沉到最后一次 use（release sinking，限定在同一 block 内）。
  - 逐步扩展：跨 block 的“支配/后支配”近似（仅对无异常/无早退路径启用）。
- **实现位置**
  - 在 [optimizer.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/optimizer.zig) 增加 `runRCEllision()`（并接入迭代 pipeline），并在寄存器使用/副作用判断里标注 `.retain/.release` 的 effect。
- **验证**
  - 新增 AOT 单测覆盖：多次 retain/release、分支合流、循环内临时值。
  - 运行解释器 vs AOT 差分（已有 test-aot-diff）确保语义一致。

## P0：SCCP + 更强不可达删除
- **算法落地**
  - 为 SSA 寄存器引入 lattice（Unknown / Const / Overdefined）与 CFG 可达性队列。
  - 处理核心指令：const、phi、select、比较、逻辑短路、简单算术（仅在操作数为 Const 时折叠）。
  - 对可达性驱动：当分支条件变为 Const bool，剪掉不可达 successor。
- **集成点**
  - 在现有 constant propagation 之前/之后插入 SCCP（通常 SCCP → CFG cleanup → DCE 效果最佳）。
  - 扩展 [CFG cleanup](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/optimizer.zig#L2246-L2390) 的不可达块删除与 phi 精简。
- **验证**
  - 新增脚本/用例：类型检查+分支、恒真/恒假条件、短路逻辑，确保 AOT 输出与解释器一致。

## P0：内存/别名模型（为 CSE/Load 正确性“立规矩”）
- **先做安全收敛（短期）**
  - 将 `load` 从 CSE 的可 hash 表达式集合里剔除，避免跨 `store/call` 的潜在错误复用。
- **再做正确扩展（中期可选）**
  - 引入最小 memory versioning：
    - 每个 block/或线性扫描维护 `mem_version`；遇到可能写内存的 op（store/array_set/object_set/可能逃逸 call）递增。
    - `load` 的 CSE key 携带 version，保证合法性。
- **验证**
  - 增加针对 array/object property 的读写序列测试，确保优化前后行为一致。

## P1：去虚化/直接调用（面向 PHP 动态成本）
- 利用 type_specialization 结果：当接收者 class 与 method 在编译期可确定时，将 method_call 降为 direct call（或单态 inline cache）。
- 对 `Instruction.call` 的已知 user func/builtin，绕过 runtime registry 查找，直接生成 Zig 调用。

## 指标与回归门禁
- **新增可度量指标**：
  - IR 级：retain/release 数量、不可达块数量、phi 数量、call_indirect 数量。
  - Runtime 级：可选在 debug 模式输出计数器（不在 release 默认启用）。
- **回归门禁**：
  - `zig build test`、`zig build test-aot`、`zig build test-aot-diff`。
  - 对选定 benchmark 脚本跑 perf-check（已有框架），并用 flamegraph/pprof 对比热点变化。

## 交付物
- optimizer 新增/调整 pass：RCEllision、SCCP，以及 CSE 的 load 安全修正（或 memory versioning）。
- 新增/扩展 AOT 单测与差分测试用例。
- 文档补充：AOT_OPTIMIZER_IMPLEMENTATION.md 增补新 pass 与正确性约束，给出常见回退开关与诊断方式。