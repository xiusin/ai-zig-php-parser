## 目标与范围
- **目标**：围绕现有 `src/aot`（IR 生成/优化/生成 Zig 并调用 `zig build-exe`）做体系化优化，使 **运行性能提升≥50%**、**内存占用降低≥25%**，并在 AOT 运行时实现 **内存效率提升≥30%**（以常驻/峰值与分配次数综合衡量）。
- **范围**：编译流程（Bytecode 预处理→IR→目标代码）、AOT runtime（`runtime_lib_template.zig`）、AOT 工具链参数（`native_linker.zig`）、性能测试与回归门禁（现有 perf-check/报告体系）。
- **约束**：保持 PHP 语义兼容与内存安全；所有优化必须可回退（编译开关/分阶段启用）。

## 编译流程优化设计
### 1) 字节码预处理（AOT 前置）
- **静态常量池冻结**：对字符串/数字/常量表达式做去重与 canonicalization，减少后续 IR 中重复字面量与分配。
- **CFG 预规整**：提前拆分/合并基本块（移除空块、规范化 fallthrough），降低 IR 优化 pass 的复杂度。
- **调用解析前置**：对可静态解析的函数/方法调用做解析（包含 builtin 识别与静态类/方法解析），为后续“直接调用/内联”提供确定性。
- **Profile 输入（可选）**：支持从解释器/BytecodeVM 导出 profile（热函数/热分支/类型分布），AOT 作为 PGO 输入（不依赖运行时采样，先做离线 profile）。

### 2) IR 优化（AOT IR 层）
- **pass 管线重排与固定点**：在结构性变换（Inlining/LICM/Unroll）后增加清理 pass（DCE、CFG simplify、phi 清理）并做迭代上限控制（对应 `src/aot/optimizer.zig`）。
- **全局值编号（GVN）/更强 CSE**：将当前 CSE 扩展到基本块间并结合常量传播，减少重复计算。
- **逃逸分析（Escape Analysis）与标量替换（SROA）**：
  - 对短生命周期对象（临时数组/字符串包装/小对象）在 IR 层判断是否逃逸，优先 **栈分配/寄存器标量化**。
  - 目标是减少 AOT runtime 的 `allocator.create` 与 RC 操作密度。
- **去装箱/装箱消除（Box/Unbox Elim）**：对 `Value.initInt/Float/Bool` 之后立刻 `asInt/asFloat/toBool` 的模式做消除，保持标量寄存器形态。
- **分支专门化与 guard**：基于类型/常量条件生成 fast path + deopt/slow path（AOT 使用“回退到 runtime 通用路径”而非解释器）。
- **内联策略（成本模型）**：
  - 引入基于指令数、分支数、分配次数、可能抛异常等维度的成本模型。
  - 对小 builtin wrapper、热函数、leaf 函数优先内联；对冷路径/异常路径抑制内联。

### 3) 目标代码生成（Zig 代码生成与链接）
- **寄存器生命周期/RC 精简**：
  - 在 codegen 阶段使用“是否可能持有堆对象”的数据流标记，生成更少的 `retain/release`（对立即数 value 完全消除）。
  - 引入“noexcept / may_raise”元信息，裁剪不必要的异常检查。
- **分支预测提示**：
  - 在异常慢路径、边界检查失败分支、rare error 分支插入 `@branchHint(.unlikely)`；在循环回边/热判断插入 `@branchHint(.likely)`。
- **结构化控制流优先**：
  - 对可识别的 for/while 模式优先生成结构化循环，减少状态机 dispatch（提升指令 cache 与分支预测）。
- **工具链参数与产物**：
  - AOT Release 系列启用 LTO、关闭 unwind/error tracing、omit frame pointer、按平台选择 `-mcpu`（native/基线）与 `-fsingle-threaded`（AOT 单线程运行时模式时）。
  - 输出可选的 `-femit-asm`/`-femit-llvm-ir` 用于汇编级对比与回归分析。

## 内存管理优化方案（AOT runtime 专项）
### 1) 内存池与分配策略
- **分层内存池**：
  - 小对象池（固定大小 class：Value box、PHPString header、数组桶、对象属性表节点等）。
  - 线程/函数级 arena（生命周期绑定函数/请求），用于临时对象与短命 buffer；退出点统一回收。
- **按类型的专用 allocator**：字符串、数组、对象分开统计与调参，避免不同粒度对象造成碎片。
- **零拷贝/复用 buffer**：常见操作（concat、sprintf、json 编码）使用可增长 buffer 并复用 capacity。

### 2) 对象生命周期分析与“早释放/免分配”
- **编译期生命周期标注**：IR 中对临时对象、不会逃逸对象打标，生成代码走 arena / stack。
- **引用计数操作削减**：
  - 对“立即数 Value”彻底不做 RC；
  - 对“仅在块内流转且不逃逸”的 heap value 在块内做 RC 归并（批量 retain/release 或直接移动语义）。

### 3) GC/循环引用改进
- **分代/增量 cycle collector（AOT 专用配置）**：
  - 以现有 cycle roots 为基础，引入代际阈值与增量处理，降低一次性扫描成本。
  - 增强 write barrier（跨代引用记录）用于更精准的回收范围。
- **可观测性**：为 AOT runtime 增加 GC/分配统计导出（不影响 ReleaseFast：用编译开关控制）。
- **验收口径（内存提升≥30%）**：以“峰值 RSS、总分配字节、GC 暂停时间、cycle roots 扫描次数”四项综合判定。

## 编译器性能优化技术落地清单
- **热点识别与内联**：离线 profile → inliner 成本模型 → 内联后做 DCE/CFG simplify。
- **循环优化**：LICM、强度削减、循环展开（含展开阈值与代码膨胀预算）、循环版型识别（counted loop、range loop）。
- **常量折叠/传播**：跨块传播、条件常量化后触发 block 删除。
- **死代码消除**：结构性变换后强制清理；包括 unreachable blocks、无用 phi、无用临时。
- **调用优化**：
  - builtin 直连（避免字符串哈希/动态分派）；
  - 纯函数（noexcept/无副作用）可做 CSE 与代码移动。

## 可靠性保障机制（错误处理/异常/降级）
- **诊断分层**：前端（语法/语义）→ IR（验证/一致性）→ codegen（未实现 lowering）→ 链接（zig build-exe 输出收敛）。
- **异常捕获策略**：
  - 明确哪些 runtime API 可能设置 exception；基于元信息裁剪检查但保持语义正确。
  - 生成代码中统一异常出口（cleanup + handler 跳转 / 返回 RuntimeError）。
- **降级策略**：
  - AOT 优化失败/不安全时回退到较保守的 pass 组合（关闭 unroll/inline/escape）。
  - 运行期遇到 deopt 条件（类型变化/guard 失败）回退到 runtime 通用路径（保持正确性）。
- **边界条件**：大递归/大数组/极端字符串长度/溢出/NaN-box 边界均有专项测试与断言（Debug）以及 Release 的健壮处理。

## 里程碑与验收（不含具体日历排期）
- **M1：编译流水线与观测闭环**
  - 交付：AOT 编译各阶段耗时统计、IR/ASM 导出、perf 基线冻结。
  - 验收：可稳定重现“同源码同参数”产物与性能报告。
- **M2：IR 优化增强（DCE/CFG/GVN/内联成本模型）**
  - 交付：新增/重排 pass 与回退开关；语义保持测试通过。
  - 验收：AOT 运行速度提升可测（≥20% 阶段性目标），无回归。
- **M3：内存体系（池化/arena/逃逸分析）**
  - 交付：AOT runtime 内存池、arena、逃逸分析驱动的栈/arena 分配。
  - 验收：内存效率提升≥30%（按前述口径）。
- **M4：汇编层热路径整形（branch hints/RC 削减/结构化循环）**
  - 交付：生成代码的热路径更少分支/更少调用；可对比 asm。
  - 验收：综合性能提升≥50%、内存占用降低≥25%。

## 开关对照（当前实现）
### CLI（zig-php）
- 编译入口：`--compile <file.php>`
- 产物路径：`--output=<file>`
- 目标平台：`--target=<triple>`（可用 `--list-targets` 查看）
- 编译优化：`--optimize=debug|release-safe|release-fast|release-small`
- 静态链接：`--static`（macOS 会自动忽略静态链接策略）
- IR/AST/代码导出：`--dump-ir`、`--emit-ir[=<file>]`、`--dump-ast`、`--dump-zig`、`--dump-zig-path=<file>`
- 产物分析导出：`--emit-asm[=<file>]`、`--emit-llvm-ir[=<file>]`、`--emit-llvm-bc[=<file>]`
- 关闭默认行为：`--no-static`、`--no-debug-info`、`--no-link`（`--no-link` 会自动输出 Zig 源码）
- 工具链透传：
  - `--mcpu=<cpu>` → 透传到 `zig build-exe -mcpu=<cpu>`（例如 `native`）
  - `--zig-flag=<flag>` → 透传任意 Zig 参数（可重复；按出现顺序追加）
- 编译观测：`--timing`、`--timing-json=<file>`
- IR 校验与降级：`--verify-ir`、`--no-opt-fallback`
- Pass 覆盖：`--aot-disable-pass=<p>`、`--aot-enable-pass=<p>`、`--aot-inline-threshold=<n>`、`--aot-unroll-factor=<n>`、`--aot-max-iterations=<n>`

### perf-check（回归门禁）
- 维度：运行耗时（time）+ 分配统计（memory）+ 编译流水线耗时（compile pipeline）
- 运行耗时：基于 `BenchmarkResult.avg_time_ns` 与基线对比（默认阈值 5%）
- 内存：基于 `aot_runtime.getAllocStats()`（总分配字节/次数、峰值 live bytes/allocs、对象计数等）与基线对比（默认阈值 1%）
- 编译：新增 `aot_compile_pipeline` 基准，执行 AOT pipeline 并跳过最终链接（用于避免把 `zig build-exe` 的平台波动计入编译维度）

## 性能基准测试方案
- **指标**：
  - 编译：AOT 总耗时、各 pass 耗时、产物体积、启动时间。
  - 运行：总耗时、热点函数耗时、分支预测失败率（可选：perf）、指令数/IPC（可选）。
  - 内存：峰值 RSS、总分配字节、分配次数、GC 暂停与次数。
- **用例集**：
  - 微基准：字符串（concat/strpos/json）、数组（map/filter/reduce）、数学（abs/sqrt）、对象（property/method call）。
  - 宏基准：模拟 Web 请求处理、模板渲染、JSON API、并发/IO（若 AOT runtime 支持）。
- **报告产物**：CI 自动生成“优化前/后”对比表、回归阈值报警（>5%）。

## 风险评估与回滚方案
- **风险**：代码膨胀（unroll/inline）、逃逸分析误判导致语义/生命周期问题、平台差异（macOS unwind/链接）、性能假象（基准噪声）。
- **控制**：
  - 所有优化 pass 与 codegen 策略都有 feature flag；默认灰度启用。
  - 引入 IR 验证器（每次 pass 后校验 CFG/SSA/引用计数不变量）。
  - 基准波动控制：固定 CPU 亲和/重复运行/置信区间。
- **回滚**：
  - 一键回退到“保守 AOT 配置”（关闭高风险 pass/flags）；
  - 保留旧管线入口与生成方式，确保可逆。

## 最终交付物清单
- 优化设计文档（AOT 专项）：编译流程、IR/Codegen、内存/GC、可靠性、测试与回滚。
- 实现代码：`src/aot/*` 与 AOT runtime 相关模块变更（含开关）。
- 测试报告：正确性（单测/属性测）、性能（perf-check 报告）、内存（对比报告）。
- 性能对比分析报告：关键基准项提升来源拆解（pass/flags/runtime 贡献）。
