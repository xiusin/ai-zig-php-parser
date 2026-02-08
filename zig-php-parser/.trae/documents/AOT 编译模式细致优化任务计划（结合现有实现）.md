## 目标对齐
- 以设计文档为准，将优化拆成“可回退的分阶段开关”，并以现有 perf-check/报告为门禁，最终达成：运行性能 ≥50%、内存占用 ≥25%、AOT runtime 内存效率 ≥30%。

## 现状基线（已实现能力盘点）
- **IR 优化管线已存在**：Mem2Reg/ConstProp/DCE/Inline/TypeSpec/CSE/StrengthReduction/LICM/Unroll，且支持 fixed-point 迭代与 pass 覆写入口（[optimizer.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/optimizer.zig)、[analysis.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/analysis.zig)、[compiler.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/compiler.zig)）。
- **AOT codegen 走 IR→Zig 转译**：RC/异常检查/cleanup/部分 branchHint 已插入（[native_linker.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/native_linker.zig)）。
- **AOT runtime 已有 stats + 部分池化 + RC+cycle collector**：string/array pool、static string pool、cycle roots（[runtime_lib_template.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/runtime_lib_template.zig)）。
- **工具链参数已有 LTO/strip/emit-asm/emit-llvm-***，缺 `-mcpu` 与 debug_info 映射（[native_linker.zig:invokeZigCompiler](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/native_linker.zig#L5854-L5979)）。

## 优化任务分解（按里程碑推进，保证可回退）

### M1：观测闭环与编译流水线精化（低风险，高收益）
1. **AOT 编译阶段耗时统计**：在 AOTCompiler 内记录 Bytecode→IR→IR Opt→Zig codegen→zig build-exe 各阶段耗时，并输出到报告/日志。
   - 目标文件：AOT 编译编排侧（[compiler.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/compiler.zig)）、链接侧（[native_linker.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/native_linker.zig)）。
2. **IR/ASM 导出统一入口**：把 emit-asm/emit-llvm-ir/emit-llvm-bc 的路径配置打通到 CLI（复用现有 `invokeZigCompiler` 支持），并在 perf-check 报告里记录产物路径。
3. **基准集补齐“编译指标”**：perf-check 增加编译耗时/产物体积/启动时间三项（先落地 compile-time + binary size）。

### M2：IR 优化增强（结构清理 + 更强的跨块消除）
1. **CFG 预规整/清理 pass**：在结构性变换（Inline/LICM/Unroll）后增加/强化 CFG simplify、phi 清理、unreachable 合并，减少后续 pass 工作量。
   - 落点：扩展 [optimizer.zig:IROptimizer.optimize](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/optimizer.zig#L290-L374) 的清理环节与迭代策略。
2. **更强的跨块 CSE/GVN（IR 层）**：在当前“哈希+dom 检查”的 CSE 基础上，补齐 value-numbering（至少覆盖纯表达式、可证明无副作用指令），并与 ConstProp 联动。
   - 约束：只对“无副作用、无异常”的指令启用（先用白名单）。
3. **内联成本模型（替代固定阈值）**：将“指令数/分支数/可能抛异常/分配密度”纳入成本，热路径优先。
   - 扩展点：现有 [runFunctionInlining](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/optimizer.zig#L2186)；新增配置项并接入 CLI 覆写。

### M3：AOT codegen 热路径整形（RC 精简 + noexcept 元信息 + 更精确 cleanup）
1. **确立 RC 所有权协议（先 correctness，后性能）**：统一 `store/val_assign/array_get/object_get` 等路径的“borrowed vs owned”语义，避免重复 release/retain 或漏 retain。
   - 重点核查点：
     - `store` 当前生成会先 `release(old)` 再 `val_assign`，需明确 `val_assign` 是否也做 RC（[native_linker.zig:store](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/native_linker.zig#L2337-L2367)）。
     - `array_get` 返回值是否需要 `retain`（[native_linker.zig:array_get](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/native_linker.zig#L3411-L3424)）。
2. **noexcept/may_raise 元信息贯通**：为 runtime API（builtin、数组/对象操作）标注“是否可能设置 exception”，codegen 仅对 may_raise 插入 `hasException()` 检查与 cleanup。
   - 落点：在 native_linker 指令 lowering 的 call/new_object/method_call 等处按元信息裁剪（参考现有 `@branchHint(.unlikely)` 异常分支点）。
3. **cleanup 精确化（按活跃寄存器集合）**：把当前“函数级保守 cleanup_registers”升级为“block/区域级已初始化寄存器集”，异常发生早期时减少无效 release。
   - 落点：`generateCleanupCode()` 与 `cleanup_registers` 的生成逻辑（[native_linker.zig:generateCleanupCode](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/native_linker.zig#L2263-L2275)）。
4. **branchHint 扩展与结构化循环优先**：对异常慢路径、边界检查失败等统一加 `.unlikely`；对 counted loop 回边加 `.likely`（先做 2-3 个最热模式）。

### M4：AOT runtime 内存体系（池化一致性 + arena + cycle collector 轻分代）
1. **池化一致性修复**：确保 string/array 的创建路径都走 pool（例如 `PHPString.concat` 当前绕过 pool 的点先修复），并新增 closure pool（高频对象）。
   - 落点：`PHPString.concat`（[runtime_lib_template.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/runtime_lib_template.zig#L890-L918)）、`PHPClosure` init/release（[runtime_lib_template.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/runtime_lib_template.zig#L1577-L1623)）。
2. **临时 arena allocator（只用于 bytes/临时 buffer）**：为 `Value.toString`、var_export、closure capture 构建等热点引入“函数级/请求级” arena，以减少 GPA 小分配与碎片。
   - 约束：arena 不承载带析构语义/RC 对象，避免泄漏与 UAF。
3. **cycle collector 触发自适应 + roots 分层**：对 `cycle_roots` 做轻量“年轻/老年代”分层与自适应阈值（根据分配率/roots 增长），降低一次性扫描成本。
4. **统计导出补齐**：补齐 closure、cycle_roots 规模、collect 次数/耗时、rehash 次数等，统一纳入 perf 报告。

## 工具链/构建参数优化（支撑性能目标）
- **补齐 `-mcpu` 支持**：新增配置支持 `native`/baseline 两档，便于在 CI 与本机对齐。
- **debug_info 映射**：将 `NativeLinkerConfig.debug_info` 实际映射到 zig build-exe 参数策略（与 strip 规则一致）。
- **额外参数透传**：允许追加 `extra_zig_flags`（用于试验 LTO/CPU/strip/emit 等矩阵）。

## 验证策略（每阶段都必须通过）
- 正确性：现有 `zig build test` + AOT 相关测试集 +（必要时）新增属性测试覆盖 RC 协议。
- 性能：扩展 perf-check 报告对齐“运行 + 内存 + 编译”三维；每个阶段都更新/比较基线并设门禁。
- 可回退：所有高风险优化（inline/escape/arena/cycle 分代）均以 feature flag 控制，默认灰度启用。

## 交付物
- 代码：`src/aot/*`（optimizer/codegen/linker/runtime 模板）与 perf/CI 报告链路增强。
- 文档：在设计文档旁补一份“实现与开关对照表 + 基准结果对比表”。