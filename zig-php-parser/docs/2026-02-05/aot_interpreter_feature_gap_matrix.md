# 解释器 vs AOT 功能差异矩阵（开发用）

本文件用于追踪“解释器（tree-walking 作为 oracle）”与 AOT 产物的可观测行为差异，并为每个差异点绑定：
- 语义口径（以解释器为准，或明确 AOT 子集）
- 落点（IR / lowering / runtime template / 链接器 / builtin）
- 用例（`test/aot_diff/*.php` 或 `tests/aot_mrc/*`）
- 优先级（P0/P1/P2）

## 口径
- **解释器 oracle**：以 `src/runtime/vm.zig` 的 tree-walking 行为为准。
- **差异测试**：默认对比 stdout；stderr/异常对齐另行标注。
- **阻塞行为**：任何可能导致测试挂死的语义点必须提供超时保护与可复现最小用例。

## 差异矩阵

| 模块 | 语义点 | 解释器 | AOT 当前 | 缺口落点 | 优先级 | 用例/说明 |
|---|---|---|---|---|---|---|
| 并发 | `go` 调度时机 | 主脚本结束后 `runCoroutines()` 再跑 | worker 线程并行执行（全局 scheduler） | 语义层决定（VM 调度 vs AOT runtime） | P0 | 阻塞 recv 的语义需要统一，否则会出现解释器死锁/行为不一致 |
| 并发 | `Channel.recv()` on close | close 且空返回 `null` | 需要映射 `ChannelClosed -> null` | AOT runtime template 封装层 | P0 | `test/aot_diff/channel_recv_closed.php` |
| 并发 | `Channel.trySend()` 语义 | 非阻塞（trySend，满则 false） | 非阻塞（trySend，满则 false） | 无（已对齐） | P2 | `test/aot_diff/channel_try.php` |
| 并发 | `Mutex/Atomic/RWLock/SharedData` | 内置类 + 方法分发 | 模板注册类 + 方法分发 | 无（已对齐最小集） | P2 | `test/aot_diff/*_basic.php` |
| 并发 | `select`（函数级） | `select(cases, timeout)` 可用 | `select(cases, timeout)`/`Zig\\Select::select` 可用 | 无（已对齐） | P2 | `test/aot_diff/select_basic.php` |
| 并发 | `select_`（IR op） | 不依赖 | 未实现（若未来引入 select lowering） | IR/lowering | P2 | 仅当 IR 增加 select 指令时需要 |
| 异常 | `try/catch/throw` | 完整异常对象与 trace | 模板侧为简化异常状态 | AST→IR、lowering、runtime template | P0 | 需要“类型/消息”一致性用例；trace 可允许差异 |
| 对象/反射 | Reflection API | 相对完整（ReflectionClass 等） | 仅基础查询函数（class_exists 等） | AOT runtime template 补齐或定义子集 | P1 | 先定义 AOT 最小反射能力清单 |
| I/O | 文件/路径/句柄 | builtin_io 覆盖面大 | AOT 侧缺口较多（以模板实现为准） | AOT runtime template + native_linker 映射 | P1 | 先选取最小可用集（read/write/stat） |
| HTTP | HttpServer/Client/Router | 有内置类并与 VM 资源清理集成 | AOT 未覆盖 | AOT runtime template + 编译期绑定 | P2 | 建议先做 HttpClient 子集，server 后置 |
| 扩展 | 动态扩展/插件 | 支持（extension/api + plugin_system） | 静态产物天然受限 | AOT 编译期打包方案 | P2 | 设计“编译期扩展 manifest + 绑定生成” |
| 执行后端 | FastVM 复杂类型 | 部分复杂类型回落为 null | AOT 不相关 | fast_vm 值桥接限制 | P2 | 作为解释器内部差异矩阵的一部分维护 |

## 关键入口（定位用）
- CLI/模式选择：`src/main.zig`
- 解释器 tree-walking：`src/runtime/vm.zig`
- AOT 编译主链路：`src/aot/compiler.zig` → `src/aot/ir_generator.zig` → `src/aot/native_linker.zig`
- AOT 运行时模板：`src/aot/runtime_lib_template.zig`
