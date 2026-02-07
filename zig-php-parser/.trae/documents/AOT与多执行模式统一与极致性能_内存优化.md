## 现状差异梳理（已定位到源码）
- **解释器执行模式**：tree_walking / bytecode / fast / auto 在 [vm.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/vm.zig#L132-L141)；其中 fast 目前只稳定覆盖数值类型，复杂类型转换直接回 null（功能差距大），见 [vm.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/vm.zig#L5211-L5225)。auto 现在启发式返回 false，等价 tree_walking。
- **AOT 运行时真实来源**：并非仓库内固定 runtime_lib，而是编译期把 [runtime_lib_template.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/runtime_lib_template.zig) 复制到临时目录改名链接；同时复制 concurrency + array_ops_shared，见 [native_linker.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/native_linker.zig#L5617-L5674)。
- **语法模式差异**：解释器支持 `// @syntax: go` 指令检测与混用校验（见 [main.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/main.zig#L294-L329)、[vm.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/vm.zig#L7843-L7876)），AOT 当前仅依赖编译选项映射，不做指令检测。
- **JIT 体系分裂**：`--jit` 实际接到 bytecode 内嵌 JIT（[bytecode/vm.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/bytecode/vm.zig#L4723-L4766)），而更完善的 fallback/统计在另一套 `src/jit/*`（[jit/fallback.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/jit/fallback.zig#L362-L438)）并未默认接入。
- **数组/字符串底层差异巨大**：解释器的 `PHPArray` 有 packed/mixed 双模式自动转换（[types.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/types.zig#L187-L293)），AOT 模板目前是较简化的 hash-map 为主结构；解释器有 fast_runtime/fast_value/fast_pool/fast_string 可用（如 [fast_runtime.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/fast_runtime.zig)），AOT 模板暂未利用。
- **AOT 模板存在内存安全隐患（必须优先修）**：`PHPString.initStatic()` 返回局部变量地址（UB），并在对象魔术方法调用路径直接使用（[runtime_lib_template.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/runtime_lib_template.zig#L145-L156)、[runtime_lib_template.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/runtime_lib_template.zig#L3608-L3619)）。
- **循环引用回收差异**：解释器有 `gc.Box` 的循环检测/颜色算法（[gc.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/gc.zig#L15-L114)），AOT 模板主要是手写引用计数，实际“cycle detection”并未落地到类型层。

## 统一目标（功能+性能+内存）
- **单一语义源**：tree_walking 作为 oracle，但让 bytecode/fast/AOT 尽可能复用同一份“核心语义实现”（数组、字符串、比较、类型转换、callable 调用、异常/错误）。
- **单一内建注册表**：把 builtin 名称、签名（是否需要 allocator、变参是否 slice 打包）、以及 AOT/解释器/JIT 的映射统一成一份表，避免漂移。
- **极致内存/性能**：在不牺牲正确性的前提下，减少分配、减少哈希查找、减少 retain/release 次数，提升数据局部性与分支预测命中。

## 实施计划（按优先级分阶段落地）
### Phase 0：安全与基线（必须先做）
- 修复 AOT `PHPString.initStatic` 的生命周期：改为“全局字符串驻留池/静态常量表”或“runtime init 时一次性分配并标记 static”，保证指针稳定且可在 deinit 统一释放。
- 给 AOT 增加循环引用处理：最小可行方案是移植解释器 `gc.Box` 的紫/灰/黑/白算法到 AOT 模板中（至少覆盖 PHPArray/PHPObject/PHPClosure），并设定阈值触发/或在 `deinitRuntime` 强制 sweep。
- 建立可重复的性能与内存基线：复用现有性能回归检查与 AOT benchmark 框架（[aot_benchmark.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/benchmark/aot_benchmark.zig)），新增若干 microbench（数组 push/pop/shift/unshift、sort/ksort、字符串 concat/trim、callable invoke、方法分发）。

### Phase 1：运行时核心结构统一（收益最大）
- **AOT 引入 packed/mixed 数组**：把解释器 `PHPArray` 的 packed/mixed 设计抽象为“无 VM 依赖的共享模块”，AOT template 与解释器 types 同时复用；保证顺序语义、next_index 语义一致。
- **AOT 引入字符串驻留与短字符串优化**：借鉴 [fast_string.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/runtime/fast_string.zig) 的 SSO+intern，至少对：数组键、函数名、方法名、常量字符串做 intern；减少 allocator 压力和字符串比较成本。
- **统一 Value 表示/转换策略**：解释器 fast_value 与 AOT Value 都是 NaN-boxing，但标签方案不同；抽象成一份“Value ABI 规范”或提供转换层，让 bytecode/fast/AOT 能共享更多 builtin 实现而不是互相转换丢信息。

### Phase 2：编译器/分发层极致优化（减少哈希与 retain）
- **AOT builtin 直连**：编译期能确定的 builtin 直接生成对 runtime 函数指针/符号的调用，绕过按名字查 `StringHashMap`。
- **Callable/方法分发 inline cache**：对 `call_user_func`、对象 `callMethod`、`__call` 路径加“最近一次解析缓存”（按 interned name + class meta 指针）减少字符串哈希。
- **retain/release 逃逸分析**：在 AOT lowering 做“局部临时值不逃逸”判定，省掉成对 retain/release；对 array_map/filter/reduce 这类高阶函数尤其显著。

### Phase 3：解释器模式统一与 JIT 收敛
- **auto 模式启发式落地**：根据 AST/IR 特征（循环、函数调用密度、数组操作密度）选择 bytecode 或 fast；失败路径保留 tree_walking。
- **JIT 体系收敛**：二选一：
  - 方案 A：把 `src/jit/fallback.zig` 的统计/策略接入 bytecode 内嵌 JIT，形成统一 `--jit` 行为（含失败原因分类与阈值策略）。
  - 方案 B：让 `--jit` 切换到 `src/jit/*` 这套编译器，bytecode 内嵌 JIT 退为实验/删除。

### Phase 4：全链路验证与回归门禁
- 扩充差异矩阵到“符号级别”：从解释器 builtin_* 与 AOT runtime template 生成一张可自动更新的差异表，并把 P0/P1 用例沉淀到 tests/aot_mrc。
- 在 CI/本地 test step 中：同时跑功能测试 + 性能回归阈值；对 AOT 可执行体大小、启动时间、常见脚本吞吐做门禁。

## 交付物
- 一张“tree/bytecode/fast/AOT/JIT”能力矩阵 + 每个差异点的源码落点。
- 一套共享 runtime-core（数组/字符串/Value/GC）模块或代码生成方案，AOT 与解释器复用。
- 一组微基准 + 回归阈值报告，能量化每次优化收益。

如果你确认该计划，我会先从 Phase 0 的 **AOT initStatic UB 修复 + 循环引用回收最小可行实现 + microbench 基线** 开始落地，因为这是后续极致优化的安全前提。