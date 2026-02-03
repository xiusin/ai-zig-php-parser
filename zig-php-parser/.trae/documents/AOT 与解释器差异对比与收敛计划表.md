## 目标
- 以当前 AOT 路径（[native_linker.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/native_linker.zig)）为基准，不引入 LLVM，系统对比“解释器能力面”与“AOT 可编译子集”，输出可执行的收敛路线。

## 现状结论（只读对比摘要）
- AOT：IR → 生成 Zig 源码 → `zig build-exe` 生成原生可执行文件（转译式），运行时主要来自 `src/aot/runtime_lib_template.zig` 与 `src/aot/concurrency_runtime.zig`。核心边界在 builtin 覆盖、IR op 覆盖、以及 OOP wrapper（参数处理）等处。
- 解释器：`src/main.zig` 支持 tree/bytecode/fast/auto 多模式，runtime 体系完整（builtin 分发、IO/HTTP/JSON/Hash 等模块、PHP 8.5 特性模块），并有 bytecode/JIT 作为性能路径。

## 功能差异计划表（对比矩阵 + 动作）
| 功能域 | 解释器（现状） | AOT（native_linker 现状） | 主要缺口/风险 | 计划动作（不含LLVM） | 优先级 |
|---|---|---|---|---|---|
| 执行/产物形态 | 解释执行（二进制解释器） | 生成单个可执行文件 | AOT 依赖目标机有 zig；构建时临时目录清理策略 | 规范化 AOT 构建产物与缓存目录；补充可配置输出（bin/obj 预留） | P1 |
| IR op 覆盖 | Bytecode 指令集广，runtime 可兜底 | 未实现 op 走 warn/error（[handleUnsupportedOp](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/native_linker.zig#L105-L115)） | 兼容性断崖 | 建立“IR op 覆盖清单”与“未实现 op 的最小替代实现/显式错误”策略；输出覆盖率报告 | P1 |
| OOP：类/方法调用 | 支持较完整（runtime/bytecode） | 类≤64、方法≤16、method wrapper 忽略 args；构造函数仅取 2 参（[registerClassFunctions](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/native_linker.zig#L316-L395)） | AOT OOP 大量行为错误 | 重写 wrapper：统一走 `args: []PHPValue` 传参；支持任意参数数目、默认/可变参数最小语义；移除 64/16 硬上限或改动态容器 | P0 |
| builtin 覆盖 | `builtin_dispatch` 覆盖面很大（[builtin_dispatch.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/builtin_dispatch.zig)） | 白名单映射较小（[isBuiltinFunction/mapToRuntimeFunction](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/native_linker.zig#L506-L611)）+ AOT 模板 callable 表偏小（[lookupBuiltinFunction](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/runtime_lib_template.zig#L649-L675)） | AOT 可用子集过小 | 生成“builtin 名称对照表”：解释器 builtin → AOT 映射/实现状态；优先补齐 P0/P1 必需 builtin（输出/字符串/数组/类型/数学/时间/文件） | P0 |
| I/O / 文件 / 网络 | runtime 有 `builtin_io/builtin_http` 等集成 | AOT runtime 偏“零依赖最小集” | AOT 无法运行常见脚本 | 定义 AOT runtime 的“分层”策略：Core（零依赖）+ Optional（按平台链接 libc/系统 API）；先补 I/O 基础子集 | P1 |
| 正则/PCRE | 解释器侧已有 PCRE/扩展集成 | AOT 取决于 runtime template 是否实现/链接 | 兼容性缺口明显 | 建立可选特性开关：是否启用 PCRE（对齐 build.zig 的 pcre2 链接策略），并输出能力开关矩阵 | P2 |
| 异常/try-catch | 解释器运行时链路更完整 | AOT 依赖 IR lowering + runtime | 边界语义不一致 | 拉齐 AOT runtime 的异常对象/栈追踪接口，与解释器异常内建对齐；补关键测试用例 | P1 |
| 闭包/回调/高阶函数 | 解释器 builtin + runtime 支持较多 | AOT callable 查表有限 | array_map/array_reduce 等易缺失 | 扩充 AOT callable registry，统一从同一份 builtin 描述生成 | P1 |
| 并发/Channel | 解释器 runtime 有并发/async 模块 | AOT lowering 覆盖 mutex/go_spawn/channel/await，select 未实现（[TODO](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/native_linker.zig#L2569-L2627)） | 功能不对齐 | 明确 AOT 并发特性边界；补齐 select 或在 IR 层禁止生成 select，并给出诊断 | P2 |
| 调试/诊断 | 解释器 CLI/trace/调试体系更丰富 | AOT 主要依赖生成 Zig 代码可读性 | AOT 调试成本高 | 增加 AOT 的 `--dump-zig`/`--dump-ir` 以及源位置映射输出（不引入 LLVM） | P2 |

## 落地路线（按阶段交付）
### Phase 0：对齐基线与可观测性
- 产出 2 份自动生成报告：
  - IR op 覆盖矩阵（AOT 支持/不支持/降级策略）。
  - builtin 覆盖矩阵（解释器 builtin → AOT 映射/实现/缺失原因）。
- 为每个缺口绑定最小可复现脚本（PHP）与期望输出。

### Phase 1：P0 收敛（可用性拐点）
- 修复 AOT OOP wrapper：构造函数与普通方法支持完整参数数组，不再忽略 args；消除类/方法硬上限或提升为动态结构。
- 扩充 AOT builtin：优先补齐输出/字符串/数组/类型检查/数学/时间等“脚本生存必需集”。

### Phase 2：P1 收敛（兼容性/生态）
- I/O 子集：文件读写、基本目录操作；定义 Optional 依赖边界（是否链接 libc/系统库）。
- 异常/闭包：对齐解释器语义与常用 builtin（如 array_* 高阶）。

### Phase 3：P2 收敛（高级特性与边界清晰化）
- 并发 select 支持或显式禁止生成并提供诊断。
- 正则/PCRE 与其他扩展能力开关化；输出平台矩阵（macOS/Linux/Windows）。
- AOT 调试体验增强：dump、定位、错误提示统一。

## 验证与门禁（每阶段必做）
- 单元测试：新增覆盖率目标（AOT 新增模块 ≥90%）。
- 集成测试：每个新增 builtin/语义点必须有 PHP 脚本对照解释器输出。
- 性能基线：用现有 perf-check 体系对比解释器与 AOT 的关键脚本运行时（只看趋势/回归）。

## 风险与假设
- AOT runtime 走“可选依赖分层”时，需要明确哪些 builtin/特性允许依赖 libc/第三方库；否则会破坏“零依赖”目标。
- 解释器 builtin 全集很大，短期应以“脚本生存必需集 + 高频集”为收敛目标，避免无限扩张。

如果你确认这个计划，我将按 Phase 0 开始：先把 builtin 与 IR op 的对照矩阵做成可持续更新的清单（并把每项绑定到对应源码与测试用例）。