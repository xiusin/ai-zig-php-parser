# AOT 编译器体系化重构 Spec

## Why
当前 AOT 在“函数/内置函数解析、函数库扩展、业务封装”上缺少稳定抽象与可插拔边界，导致实现倾向于以字符串比对与分支堆叠来推进功能，扩展成本高且容易引入一致性问题。与此同时，AOT 性能未能优于解释器，说明在调用分发、运行时值表示、优化流水线与基准/回归体系上存在结构性缺口，需要一次体系化重构来恢复可持续开发的必要性。

## What Changes
- 建立清晰的“语言实现分层”：Frontend（解析/AST）→ Semantic（符号/绑定/类型）→ IR（SSA）→ Opt（优化管线）→ Backend（代码生成/链接）→ Runtime/Stdlib（运行时与函数库）
- 引入统一的 Function Registry（函数注册表）与 Builtin/Stdlib 模块化机制，替代各处散落的字符串比对、手写 if/else 分发、重复的 builtin 映射表
- 在 IR 中使用“函数 ID（或符号句柄）”表示已解析的调用点，编译期完成绑定；运行时仅保留可选的动态 fallback（变量函数、反射、callable）
- 统一 AOT 与解释器（或 VM）侧的内置函数元数据来源与调用约定，避免实现分叉与行为漂移
- 运行时库拆分为可维护的模块边界（Value/GC、Array、String、IO、Exception、Reflection、Json、Regex…），提供“扩展点”与测试基线
- 建立可重复的性能与回归体系：微基准（microbench）、宏基准（真实 workload）、性能预算与回归门禁（CI）
- 提供 AOT 业务封装层（Embedding API）：稳定的编译/缓存/运行接口、可配置沙箱能力与可观测性（日志、trace、profile）
- **BREAKING**：内部 API（builtin 分发、runtime_lib_template 组织方式、AOT 代码生成入口）将重构；对外 CLI/脚本行为目标保持兼容（除明确标记的动态/不可确定性特性）

## Impact
- Affected specs: 语言分层架构、函数解析/绑定模型、标准库扩展机制、AOT 代码生成模型、运行时模块边界、性能与回归基线
- Affected code:
  - AOT：src/aot/compiler.zig、src/aot/ir_generator.zig、src/aot/native_linker.zig、src/aot/type_inference.zig、src/aot/runtime_lib_template.zig
  - Runtime/VM：src/runtime/builtin_dispatch.zig、src/runtime/stdlib.zig、src/runtime/vm.zig（以及相关 core/* 模块）
  - Benchmark：src/benchmark/*（aot_benchmark.zig、microbench_suite.zig 等）
  - 测试与脚本：run_fuzzy_test.py、run_basic_tests.py、tests/basic/*

## 现状诊断（基于代码现象）
- builtin/stdlib 分发存在“多套机制并存”的风险：运行时侧已有 builtin 直分发的设计（例如基于枚举/完美哈希的方向），AOT 侧又维护另一套 builtin 映射与特殊规则，容易出现行为漂移与重复维护成本
- runtime_lib_template 过度聚合：Value/GC/Stdlib/Json/IO/Exception 等长期堆叠在单文件，导致模块边界不清、初始化顺序隐性、局部优化困难
- AOT 代码生成与运行时耦合过深：大量“为了某个 builtin/调用形态而做的特殊分支”容易积累为不可维护的条件分发
- 可重复性能与一致性缺少门禁：当出现 AOT 不如解释器、或修复引入回归时，难以快速定位“是分发开销、值模型、还是优化缺失”

## 核心问题清单
- 可扩展性：新增/替换函数库需要修改核心编译器/代码生成器，缺少模块化扩展点
- 可维护性：调用分发逻辑分散，出现大量“局部特判”，难以形成统一规则与复用
- 正确性漂移：AOT/VM/解释器各自实现 builtin 元数据与默认参数规则，容易产生 PHP 语义不一致
- 性能结构性短板：
  - 热路径仍存在字符串处理/动态分发（或无法内联的调用）
  - Value 统一动态表示导致无法有效做类型专门化与内联
  - retain/release 与临时分配密集导致 AOT 运行时仍像“解释器式动态系统”
  - 缺少系统性优化管线与基准门禁，导致性能问题难以及时被量化与治理

## 目标架构细节
### 分层与职责
- Frontend：词法/语法/AST 构建，提供稳定 AST 数据结构
- Semantic：符号解析（变量/函数/类/方法）、作用域、引用参数信息、可解析调用点绑定
- IR：SSA IR，要求调用点显式区分：
  - ResolvedCall(FunctionId, args…)
  - DynamicCall(name/value/callable, args…)
- Opt：可插拔 pass 管线（顺序可配置），至少支持：常量传播、DCE、builtin 内联、逃逸/分配统计
- Backend：将 IR 降到 Zig/LLVM 目标，要求 ResolvedCall 走“无字符串、可内联”的分发
- Runtime/Stdlib：以模块提供实现，模块通过 Registry 注册元数据与函数实现

### Function Registry 关键抽象（建议接口）
- FunctionId：稳定的 u16/u32 ID（按模块/域分段便于裁剪）
- FunctionMeta：
  - name、arity（min/max）、variadic
  - ref_params（引用参数 index 列表）
  - needs_allocator / may_throw / is_pure（用于优化）
  - category（array/string/json/… 便于 feature flags）
- FunctionImpl：统一调用约定（Value 数组输入 + allocator + ctx），由 wrapper 负责默认参数补齐与类型适配
- ModuleRegistration：模块提供 `register(registry)`，集中注册 FunctionMeta + FunctionImpl

### 调用解析策略
- 编译期绑定（ResolvedCall）：
  - 直接函数名调用（非变量函数名）
  - 明确 builtin/stdlib 名称
  - 可静态确定的 `ClassName::method`（在 class registry 完备时）
- 动态 fallback（DynamicCall）：
  - `$fn()`、`call_user_func($x)`、反射调用等
  - 动态路径仍可通过 runtime name→id 查找走 Registry，但不承诺零开销

## 迁移路线（分阶段）
- Phase 0（规划与基线）：固化现状审计、定义目标接口、建立基准与一致性门禁
- Phase 1（单一真相）：抽出 Registry 元数据源，AOT/VM 两侧都只读这一份
- Phase 2（AOT 绑定）：IR 中引入 ResolvedCall(FunctionId)，并完成代码生成改造
- Phase 3（VM 绑定）：VM/解释器侧同样以 FunctionId 分发替代名称分发
- Phase 4（模块化 runtime）：拆分 runtime_lib_template，模块自注册并支持 feature flags
- Phase 5（性能治理）：以基准驱动迭代（优先减少分配、提升内联、引入有限类型专门化）

## 性能规划（可衡量目标）
- 基准体系：
  - microbench：builtin call、数组 push/pop、字符串搜索、json encode/decode、类型转换
  - macrobench：3 个代表性脚本（业务/框架/算法）
- 目标与策略：
  - 优先让 ResolvedCall 在 Zig 编译器可内联（switch-on-id + 小 wrapper）
  - 为 Value/GC 引入“减少临时对象”的策略（逃逸统计、池化、避免不必要 retain/release）
  - 将非确定性输出脚本从“正确性对比”中剥离或归一化，避免伪回归噪音
  - 在确认热点后再引入更激进的类型专门化/内联缓存等优化，避免过早复杂化

## ADDED Requirements
### Requirement: 分层架构与依赖方向
系统 SHALL 将语言实现拆分为明确分层，并保证依赖方向单向（高层依赖低层抽象接口，而非直接依赖实现细节）。

#### Scenario: 构建时依赖约束
- **WHEN** 新增一个标准库函数实现
- **THEN** 开发者只需在 stdlib 模块中注册元数据与实现，不需要修改 AOT 代码生成器或 VM 的分发逻辑

### Requirement: Function Registry（统一函数注册表）
系统 SHALL 提供统一的函数注册表，支持：
- 通过函数名解析到稳定的 FunctionId
- 记录签名元数据（参数个数/必需参数、是否可变参数、引用参数位置、是否可能抛异常、是否需要 allocator 等）
- 生成高性能分发（编译期 StaticStringMap / 完美哈希 / switch-on-id），避免热路径字符串比较

#### Scenario: 内置函数调用
- **WHEN** 代码中调用 `array_search($needle, $haystack)` 或其它 builtin
- **THEN** 语义分析阶段将调用点绑定到对应 FunctionId，AOT/VM 统一通过 FunctionId 分发到实现

### Requirement: 扩展机制（Stdlib 模块化）
系统 SHALL 支持以模块形式扩展函数库（新增/替换 builtin），并支持按能力开关构建（feature flags），以便裁剪 runtime 体积与降低冷启动成本。

#### Scenario: 业务封装新增函数
- **WHEN** 业务方新增 `biz_hash_id()` 之类函数
- **THEN** 只需实现一个模块并注册，不需要修改核心编译器代码

### Requirement: 性能与回归门禁
系统 SHALL 提供基准集合与回归机制，至少覆盖：
- 调用分发开销（builtin/用户函数/闭包/callable）
- 值转换与 JSON/数组/字符串热点路径
- AOT 相对解释器的端到端速度比（定义一组代表性脚本）

#### Scenario: 性能回归阻断
- **WHEN** 引入改动导致关键基准（例如 builtin 调用、数组 push/pop、字符串搜索）退化超过预算阈值
- **THEN** CI 将标记失败并输出对比报告

## MODIFIED Requirements
### Requirement: 现有 AOT 编译与运行流程
系统 SHALL 在保持现有 CLI 与主要脚本行为兼容的前提下，将“函数解析/分发/标准库”迁移到 Function Registry 体系；旧的字符串判断分发仅保留为动态 fallback（变量函数、反射等）且不作为主要路径。

## REMOVED Requirements
### Requirement: 热路径基于字符串的多分支分发
**Reason**: 字符串比对 + if/else 链在可维护性、可扩展性与性能上均不可持续，且易造成 AOT/VM 行为漂移。
**Migration**: 所有 builtin/stdlib 调用点迁移为 FunctionId 分发；仅动态特性保留 runtime 级别 name→id 查找。
