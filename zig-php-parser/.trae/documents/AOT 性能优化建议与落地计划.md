## 现状与主要瓶颈
- 编译期热点更集中在“IR 生成/优化/生成 Zig 源码”而不是运行期：当前有两个典型 O(n²)/高频分配点会直接拖慢 `aot_compile_pipeline`。
- 运行期（runtime）优化已经在进行，但编译期的少数结构性问题能先拿到更高的确定性收益。

## 优先级建议（先 P0，再 P1）
### P0-1：修复 IRGenerator entry block 头插导致的 O(n²)
- 问题：每次 alloca 都 `insert(..., 0, inst)`，变量/临时越多越慢。
- 位置：[ir_generator.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/ir_generator.zig#L363-L379)
- 方案：收集 entry allocas（append）→ 在函数结束/进入 codegen 前一次性拼到 entry block 前部（或一次 insertSlice）。

### P0-2：native_linker 生成 Zig 源码改为 writer 直写，消灭 per-instruction allocPrint
- 问题：大量 `allocPrint` + `appendSlice` + `free`，指令数上来后分配/拷贝成为主耗时。
- 位置示例：[native_linker.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/native_linker.zig#L4180-L4222)
- 方案：把字符串拼接改为 `writer.print/writeAll`；参数列表直接在 writer 中输出分隔符，避免中间 buffer。

## P1（第二波收益）
### P1-1：optimizer 中 HashMap/临时结构复用（保留容量）
- 问题：每函数 init/deinit `AutoHashMap`，小函数很多时 allocator 压力大。
- 位置：[optimizer.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/optimizer.zig#L2898-L2904)
- 方案：移动到 pass 级字段并 `clearRetainingCapacity()`，或用 `AutoHashMapUnmanaged` + 统一 arena。

### P1-2：补齐 optimizer 的“深拷贝 TODO”，避免后续被迫的防御性复制
- 位置：[optimizer.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/aot/optimizer.zig#L2837-L2868)
- 方案：统一在 clone/remap 层完成深拷贝规则，减少隐性额外分配与潜在别名问题。

## P2（基准稳定性/可解释性）
- 优化 microbench 计时噪声（极短函数时 `nanoTimestamp`/间接调用开销会掩盖收益）。
- 位置：[microbench_suite.zig](file:///Users/tuoke/Desktop/ai-zig-php-parser/zig-php-parser/src/benchmark/microbench_suite.zig#L61-L76)
- 方案：可选把回调改为 comptime 可内联形式，或自适应迭代到目标时间窗口。

## 验证与交付
- 在修改后跑：`zig build test`、`zig build perf-check`，重点观察 `aot_compile_pipeline` 的 avg_time_ns 与 stddev。
- 若收益显著且波动降低，再决定是否更新 `.perf_baselines`（建议仅在 CI/稳定机上更新）。

## 我将按此顺序落地（无需你额外确认细节）
1) 先实现 P0-1、P0-2（编译期确定性加速）。
2) 再做 P1-1、P1-2（进一步降分配/提升稳定性）。
3) 最后看是否需要 P2（提升基准可信度）。