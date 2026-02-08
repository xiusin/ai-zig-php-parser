## 目标与产出
- 形成一份“解释器语义口径”驱动的差异清单（可执行、可验证、可追踪）。
- 选定 AOT 的目标支持面：严格对齐解释器 / 明确子集（写入文档与测试约束）。
- 建立持续化差异测试：同一批 PHP 用例在解释器与 AOT 输出一致，失败可定位到 IR/运行时模板/链接器。

## 差异盘点（按模块拆分）
- **并发**：go 返回值、调度时机（解释器 run 末尾统一跑 vs AOT worker 并行）、Channel 阻塞/关闭语义、select/lock。
  - 入口：解释器 [vm.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/vm.zig)、[builtin_concurrency.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/builtin_concurrency.zig)；AOT [concurrency_runtime.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/concurrency_runtime.zig)、[runtime_lib_template.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/runtime_lib_template.zig)。
- **异常**：解释器完整异常对象/trace vs AOT 简化全局异常状态（throw/catch 语义是否等价、错误类型与消息对齐）。
  - 入口：解释器 [exceptions.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/exceptions.zig)；AOT [exception_handling.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/exception_handling.zig)、[runtime_lib_template.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/runtime_lib_template.zig)。
- **对象/反射**：解释器 Reflection 族能力 vs AOT 仅基础查询函数（class_exists/method_exists 等）。
  - 入口：解释器 [reflection.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/reflection.zig)；AOT [runtime_lib_template.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/runtime_lib_template.zig)。
- **I/O 与 HTTP**：解释器 builtin_io/builtin_http 完整；AOT 侧缺口与最小可用集定义。
  - 入口：解释器 [builtin_io.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/builtin_io.zig)、[builtin_http.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/builtin_http.zig)。
- **扩展系统**：解释器支持动态扩展与插件；AOT 静态链接下的可替代方案（编译期链接/生成绑定）。
  - 入口：[extension/api.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/extension/api.zig)、[plugin_system.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/plugin_system.zig)。
- **执行后端差异**：tree/bytecode/fast/auto 与 AOT 的覆盖边界、FastVM 对复杂类型回退策略。
  - 入口：[vm.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/vm.zig)、[fast_compiler.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/fast_compiler.zig)、[native_linker.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/native_linker.zig)。

## “语义基准”与优先级规则
- 以解释器（tree-walking）作为语义基准（oracle），AOT 对齐其可观测行为：输出、异常类型/消息、返回值、阻塞行为。
- 优先级：
  1) 会导致崩溃/内存问题/死锁的差异（P0）。
  2) 同一代码在两边输出不一致、但可稳定复现的差异（P0/P1）。
  3) 反射/HTTP/扩展等“功能缺失型”差异（P1/P2，需定义子集）。

## 实施路径（按层次落地）
- **层 1：差异测试框架扩展（先固化差异）**
  - 扩展 `test/aot_diff` 用例集合：每个用例只覆盖一个语义点（返回值/异常/阻塞/对象/IO）。
  - 建立“黑名单/已知差异”机制（文档 + runner 输出），避免 CI 被暂未实现的功能阻塞。
- **层 2：AOT 运行时模板补齐（快速提升覆盖）**
  - 把解释器 builtin 的“基础可移植子集”迁移/重实现到 `runtime_lib_template.zig`（字符串/数组/对象基础、部分 IO、基础异常）。
  - 并发：明确 Channel trySend/recv/close/select 的语义口径与阻塞策略（必要时提供 `await`/`join` 原语）。
- **层 3：IR/Lowering/Codegen 对齐（解决语法与控制流差异）**
  - 补齐 AST→IR 的缺失节点（尤其是 try/catch/throw、select、动态调用/可调用对象）。
  - 在 `native_linker.zig` 里把“运行时可用的 builtin”映射完整化（返回值、错误传播、资源释放）。
- **层 4：能力增强与可选项**
  - HTTP/网络：先定义 AOT 最小可用 API（例如 HttpClient GET/POST），再决定是否与解释器同名类对齐。
  - 扩展：设计 AOT 的“编译期扩展打包”方案（manifest + 绑定生成），不追求运行时动态加载。

## 交付物
- 差异矩阵（按模块 + 语义点 + 当前状态 + 负责人/文件入口 + 用例链接）。
- `test/aot_diff` 可持续增长的用例库（每个差异点至少 1 个用例）。
- AOT 运行时模板能力清单（支持/不支持/部分支持）与对应测试。

## 验证策略
- 以 `zig build test-aot-diff` 作为回归基线；新增用例必须在解释器与 AOT 两侧一致通过。
- 对潜在阻塞/并发用例增加超时保护（避免 CI 挂死）。
- 对异常相关用例同时校验：退出码、stderr 关键字、stack trace 片段（允许行号差异但要求类型/消息一致）。

## 需要你确认的决策点（不影响我继续推进盘点）
- AOT 是否目标“完全语义等价解释器”，还是允许一个明确的 AOT 子集（例如不支持运行时扩展/全量反射/复杂 HTTP 服务器）？
- 并发语义口径：解释器是否也要支持“脚本执行期间阻塞 recv”并与 AOT 对齐，还是规定并发只能在 go 任务内部阻塞？