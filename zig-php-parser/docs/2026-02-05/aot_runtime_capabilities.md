# AOT 运行时能力清单（当前实现）

本清单用于描述 AOT 产物“可用的运行时能力边界”，并作为差异测试用例挑选与 AOT 子集口径的依据。

## 运行时组成
- 模板运行时：`src/aot/runtime_lib_template.zig`
- 并发运行时：`src/aot/concurrency_runtime.zig`
- 链接器/代码生成：`src/aot/native_linker.zig`

## 已覆盖（高置信）
- **基础值类型**：整数/浮点/布尔/null/字符串（含引用计数）与常见转换 API（以模板实现为准）。
- **对象系统（基础）**：ClassMeta + PHPObject + 属性读写 + 方法分发表达（不等同解释器完整 class 系统）。
- **并发基础**：Scheduler + Channel（含 close/tryRecv/trySend/len/capacity/isClosed）+ Mutex/Atomic/RWLock/SharedData，以及 `go`（以模板注册的 builtin 函数形式暴露）。
- **select（最小版）**：全局 `select(cases, timeout_ms)` 与 `Zig\\Select::select()`（轮询 tryRecv/trySend + 超时）。
- **最小反射/查询**：`class_exists/method_exists/property_exists/get_class` 等模板函数。

## 部分覆盖（需要定义口径或补齐）
- **异常语义**：模板侧提供 set/get 异常状态，但与解释器异常对象/trace 语义不等价；需要明确对齐目标（至少类型/消息对齐）。
- **await 语义**：runtime 有 await_result 等接口片段，但 lowering 与代码生成未形成闭环。
- **I/O 能力**：AOT 侧未形成与解释器 builtin_io 同口径的完整集合；建议按最小可用集逐步补齐，并用差异测试驱动。

## 未覆盖（当前假设为 AOT 子集）
- **HTTP（Server/Client/Router）**：解释器内置类存在，AOT 侧尚无对应实现与编译期绑定路径。
- **动态扩展/插件系统**：解释器支持动态扩展生命周期；AOT 产物为静态链接，建议改为“编译期打包扩展”的模式。

## 测试建议
- `test/aot_diff`：用于“解释器 vs AOT 输出一致”的短用例集合（stdout 对齐优先）。
- `tests/aot_mrc`：用于更复杂的最小复现与后续回归。
