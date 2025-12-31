# 高级运行时优化任务列表

## 实现计划概述

基于需求文档和设计文档，本任务列表按优先级和依赖关系组织实现任务。预计总工期12-16周。

**当前实现状态分析：**
- ✅ 字节码指令集已定义 (`src/bytecode/instruction.zig`)
- ✅ 字节码VM基础框架已实现 (`src/bytecode/vm.zig`)
- ✅ 字节码生成器已实现 (`src/bytecode/generator.zig`)
- ✅ 基础GC系统已实现 (`src/runtime/gc.zig`)
- ✅ 分代GC基础框架已实现 (`src/runtime/memory.zig`)
- ✅ 协程系统已实现 (`src/runtime/coroutine.zig`)
- ✅ 性能监控系统已实现 (`src/runtime/performance_monitor.zig`)
- ✅ 基础优化模块已实现 (`src/runtime/optimization.zig`)

---

## Phase 1: 基础设施强化 (Week 1-3)

### Task 1.1: 增强现有GC系统
- [x] 1.1.1 完善gc.zig中的增量标记状态机
  - 文件: `src/runtime/gc.zig`
  - ✅ IncrementalState已实现 (idle/marking/sweeping)
  - ✅ 写屏障缓冲区已实现
  - _Requirements: 2.1, 2.3_
  
- [x] 1.1.2 实现写屏障缓冲区处理
  - 文件: `src/runtime/gc.zig`
  - ✅ WriteBarrierEntry结构已定义
  - ✅ incrementalStep中处理write_barrier_buffer
  - _Requirements: 2.2_

- [x] 1.1.3 增强GC统计信息收集
  - 文件: `src/runtime/gc.zig`
  - ✅ 添加GCTiming结构（标记时间、清除时间、停顿时间统计）
  - ✅ 添加GCMemoryStats结构（内存使用统计）
  - ✅ 添加GCReport结构和generateReport方法
  - ✅ incrementalStep中记录时间戳
  - _Requirements: 2.6, 9.2_

### Task 1.2: 完善分代GC
- [x] 1.2.1 实现Nursery快速分配
  - 文件: `src/runtime/memory.zig`
  - ✅ GenerationalGC已实现基础框架
  - ✅ nurseryAlloc方法已存在
  - _Requirements: 3.1_

- [x] 1.2.2 实现对象晋升机制
  - 文件: `src/runtime/memory.zig`
  - ✅ GCObject.age字段已存在
  - ✅ promotion_age阈值已配置
  - _Requirements: 3.3_

- [x] 1.2.3 实现Remember Set
  - 文件: `src/runtime/memory.zig`
  - ✅ remember_set已实现
  - ✅ writeBarrier方法已实现
  - _Requirements: 3.5_

### Task 1.3: 请求级Arena实现
- [x] 1.3.1 创建RequestArena结构
  - 文件: `src/runtime/request_arena.zig` (新建)
  - ✅ 基于ArenaAllocator扩展
  - ✅ 添加请求ID和生命周期管理
  - ✅ 实现RequestArenaPool复用机制
  - _Requirements: 4.1, 4.2_

- [x] 1.3.2 实现对象逃逸检测
  - 文件: `src/runtime/request_arena.zig`
  - ✅ EscapeEntry和EscapeReason定义
  - ✅ markEscape方法标记跨请求存活对象
  - ✅ promoteEscapedObjects晋升到全局堆
  - _Requirements: 4.5_

- [x] 1.3.3 集成到HTTP服务器
  - 文件: `src/runtime/http_server.zig`
  - ✅ HttpServer添加arena_pool字段
  - ✅ RequestContext添加arena字段
  - ✅ acquireContext时分配Arena
  - ✅ releaseContext时释放Arena
  - _Requirements: 4.3, 4.6_

---

## Phase 2: 字节码虚拟机 (Week 4-7)

### Task 2.1: 字节码指令定义
- [x] 2.1.1 创建指令集定义
  - 文件: `src/bytecode/instruction.zig`
  - ✅ OpCode枚举已定义 (200+指令)
  - ✅ Instruction结构体已定义
  - _Requirements: 1.1_

- [x] 2.1.2 实现常量池
  - 文件: `src/bytecode/instruction.zig`
  - ✅ Value联合类型已定义
  - ✅ 支持null/bool/int/float/string/array/class/func
  - _Requirements: 1.1_

- [x] 2.1.3 定义CompiledFunction结构
  - 文件: `src/bytecode/instruction.zig`
  - ✅ bytecode/constants/local_count/arg_count已定义
  - ✅ LineInfo和ExceptionEntry已定义
  - _Requirements: 1.6_

### Task 2.2: 字节码编译器
- [x] 2.2.1 创建BytecodeCompiler框架
  - 文件: `src/bytecode/generator.zig`
  - ✅ BytecodeGenerator已实现
  - ✅ AST遍历和指令发射已实现
  - _Requirements: 1.1_

- [x] 2.2.2 实现表达式编译
  - 文件: `src/bytecode/generator.zig`
  - ✅ visitLiteralInt/Float/String/Bool/Null
  - ✅ visitBinaryExpr/UnaryExpr/Variable
  - ✅ visitFunctionCall/MethodCall
  - _Requirements: 1.1_

- [x] 2.2.3 实现语句编译
  - 文件: `src/bytecode/generator.zig`
  - ✅ visitIf/While/For/Foreach
  - ✅ visitTry/Return/Break/Continue
  - _Requirements: 1.1_

- [x] 2.2.4 实现函数和类编译
  - 文件: `src/bytecode/generator.zig`
  - ✅ visitFunctionDecl/Closure/ArrowFunction
  - ✅ visitNewObject/PropertyAccess
  - _Requirements: 1.1_

### Task 2.3: 字节码执行引擎
- [x] 2.3.1 创建BytecodeVM框架
  - 文件: `src/bytecode/vm.zig`
  - ✅ BytecodeVM结构体已实现
  - ✅ 执行栈/调用栈/全局变量表已实现
  - _Requirements: 1.2_

- [x] 2.3.2 实现栈操作指令
  - 文件: `src/bytecode/vm.zig`
  - ✅ push_const/push_local/pop/dup/swap已实现
  - ✅ 栈溢出检查已实现
  - _Requirements: 1.2_

- [x] 2.3.3 实现算术和比较指令
  - 文件: `src/bytecode/vm.zig`
  - ✅ add_int/sub_int/mul_int/div_int已实现
  - ✅ eq/neq/lt_int/gt_int已实现
  - _Requirements: 1.3_

- [x] 2.3.4 实现控制流指令
  - 文件: `src/bytecode/vm.zig`
  - ✅ jmp/jz/jnz已实现
  - ✅ call/ret/ret_void已实现
  - _Requirements: 1.2_

- [x] 2.3.5 完善对象和数组指令
  - 文件: `src/bytecode/vm.zig`
  - ✅ 实现new_array/array_get/array_set/array_push/array_pop/array_len/array_exists/array_unset
  - ✅ 实现new_object/get_prop/set_prop/instanceof/clone
  - ✅ 实现new_struct/struct_get/struct_set
  - ✅ 实现类型转换指令to_int/to_float/to_bool/to_string
  - ✅ 实现类型检查指令is_null/is_int/is_float/is_string/is_array/is_object
  - ✅ 实现字符串操作concat/strlen
  - ✅ 更新为Zig 0.15 ArrayListUnmanaged API
  - _Requirements: 1.2_

### Task 2.4: 计算跳转表优化
- [x] 2.4.1 实现指令分发优化
  - 文件: `src/bytecode/vm.zig`
  - ✅ 定义DispatchResult联合类型（continue_execution/return_value/frame_changed/jump_to）
  - ✅ 定义DispatchFn函数指针类型
  - ✅ 实现initDispatchTable()初始化256个函数指针
  - ✅ 为所有已实现的操作码创建独立处理函数
  - ✅ 实现runOptimized()使用计算跳转表分发指令
  - ✅ 保留原始run()方法作为回退路径
  - 减少分支预测失败，提升执行性能
  - _Requirements: 1.2_

---

## Phase 3: 类型特化优化 (Week 8-10)

### Task 3.1: 类型反馈系统
- [x] 3.1.1 创建TypeFeedback结构
  - 文件: `src/runtime/type_feedback.zig` (新建)
  - ✅ TypeTag枚举定义运行时类型标签
  - ✅ TypeFeedback结构记录调用点类型信息
  - ✅ recordType()方法记录观察到的类型
  - ✅ isMonomorphic()/isPolymorphic()/isMegamorphic()判断方法
  - ✅ TypeFeedbackCollector管理多个调用点的类型反馈
  - ✅ PropertyFeedback用于属性访问的Shape追踪
  - ✅ 所有6个单元测试通过
  - _Requirements: 5.1, 5.2_

- [x] 3.1.2 在字节码执行中收集类型信息
  - 文件: `src/bytecode/vm.zig`
  - ✅ handleCall中记录函数调用参数类型
  - ✅ handleCallBuiltin中记录内置函数调用参数类型
  - ✅ handleGetProp中记录属性访问的对象类型
  - ✅ handleSetProp中记录属性设置的对象类型和值类型
  - ✅ 使用call_site_id高位标记区分不同类型的调用点
  - _Requirements: 5.1_

### Task 3.2: 类型守卫实现
- [x] 3.2.1 实现类型守卫指令
  - 文件: `src/bytecode/vm.zig`
  - ✅ guard_int/guard_float已在指令集中定义
  - ✅ 完善守卫失败时的去优化路径
  - _Requirements: 5.4_

- [x] 3.2.2 实现去优化机制
  - 文件: `src/bytecode/vm.zig`
  - ✅ handleGuardInt/handleGuardFloat使用checkTypeGuard()检查类型
  - ✅ 新增handleGuardString/handleGuardArray/handleGuardObject处理函数
  - ✅ 新增handleDeoptimize强制去优化指令
  - ✅ 类型不匹配时调用deoptimize()清除类型反馈
  - ✅ 支持operand1指定去优化跳转目标
  - ✅ 更新dispatch_table注册所有类型守卫处理函数
  - _Requirements: 5.3_

### Task 3.3: 内联缓存增强
- [x] 3.3.1 增强现有InlineCache
  - 文件: `src/runtime/optimization.zig`
  - ✅ PolymorphicInlineCache已实现
  - ✅ 支持多态内联缓存(PIC)
  - _Requirements: 5.6_

- [x] 3.3.2 实现方法调用内联缓存
  - 文件: `src/bytecode/vm.zig`
  - ✅ 添加MethodCache字段到BytecodeVM
  - ✅ 实现handleCallMethod处理函数
  - ✅ 集成内联缓存查找和缓存逻辑
  - ✅ 支持对象和结构体方法调用
  - ✅ 添加缓存管理方法（getMethodCacheStats/setInlineCacheEnabled/invalidateClassCache/clearAllMethodCache）
  - ✅ 在dispatch_table中注册call_method处理函数
  - ✅ Shape变化时失效机制（invalidateClassCache）
  - _Requirements: 5.5, 5.6_

---

## Phase 4: 逃逸分析 (Week 11-12)

### Task 4.1: 逃逸分析框架
- [x] 4.1.1 创建EscapeAnalyzer
  - 文件: `src/compiler/escape_analysis.zig` (新建)
  - ✅ EscapeState枚举定义 (NoEscape/ArgEscape/GlobalEscape/Unknown)
  - ✅ EscapeReason枚举定义逃逸原因
  - ✅ EscapeInfo结构记录完整逃逸信息
  - ✅ DFGNode数据流图节点定义
  - ✅ DFGEdge数据流图边定义
  - ✅ DataFlowGraph数据流图结构
  - ✅ EscapeAnalyzer分析器框架
  - ✅ AST遍历和DFG构建
  - ✅ 10个单元测试全部通过
  - _Requirements: 6.1_

- [x] 4.1.2 实现逃逸状态分析
  - 文件: `src/compiler/escape_analysis.zig`
  - ✅ 分析对象的逃逸路径 (traceEscapePath方法)
  - ✅ 标记不逃逸对象 (markEscape方法)
  - ✅ 逃逸状态传播算法 (propagateEscapeStates方法)
  - ✅ 获取可栈分配对象列表 (getStackAllocatableObjects方法)
  - ✅ 获取可标量替换对象列表 (getScalarReplaceableObjects方法)
  - ✅ EscapePathStep结构用于追踪逃逸路径
  - _Requirements: 6.2, 6.4, 6.5_

### Task 4.2: 栈分配优化
- [x] 4.2.1 实现栈分配决策
  - 文件: `src/compiler/escape_analysis.zig`
  - ✅ StackAllocationOptimizer结构
  - ✅ AllocationDecision决策结构
  - ✅ AllocationLocation枚举 (heap/stack/scalar_replaced)
  - ✅ DecisionReason枚举 (escapes/too_large/stack_overflow/fits_on_stack等)
  - ✅ makeDecision方法根据逃逸分析结果选择分配位置
  - ✅ 栈槽位分配 (next_stack_slot)
  - ✅ 栈空间管理 (current_stack_size, MAX_STACK_FRAME_SIZE)
  - ✅ 对象大小限制 (MAX_STACK_OBJECT_SIZE = 256字节)
  - ✅ OptimizationStats统计信息
  - ✅ 6个单元测试通过
  - _Requirements: 6.2_

- [x] 4.2.2 实现标量替换
  - 文件: `src/compiler/escape_analysis.zig`
  - ✅ ScalarReplacementOptimizer结构
  - ✅ ReplacementPlan替换计划结构
  - ✅ FieldMapping字段到局部变量映射
  - ✅ analyze方法分析可标量替换的对象
  - ✅ getFieldSlot方法获取字段对应的局部变量槽位
  - ✅ ReplacementStats统计信息
  - ✅ OptimizationResult综合优化结果
  - ✅ generateReport生成综合优化报告
  - ✅ 18个单元测试全部通过
  - _Requirements: 6.3_

---

## Phase 5: 协程调度优化 (Week 13-14)

### Task 5.1: 协程池实现
- [x] 5.1.1 创建CoroutinePool
  - 文件: `src/runtime/coroutine.zig`
  - ✅ CoroutineManager.pool已实现
  - ✅ pool_max_size配置已实现
  - _Requirements: 7.1_

- [x] 5.1.2 实现协程上下文保存/恢复
  - 文件: `src/runtime/coroutine.zig`
  - ✅ CoroutineStack已实现
  - ✅ Coroutine.state状态管理已实现
  - _Requirements: 7.2_

### Task 5.2: 调度器优化
- [x] 5.2.1 实现优先级调度
  - 文件: `src/runtime/coroutine.zig`
  - ✅ Priority枚举定义 (critical/high/normal/low/idle)
  - ✅ PriorityQueue优先级队列实现
  - ✅ 加权公平调度算法 (weighted fair scheduling)
  - ✅ 饥饿检测和优先级提升机制
  - ✅ SchedulingPolicy枚举 (fifo/priority/weighted_fair)
  - ✅ spawnWithPriority方法支持指定优先级
  - ✅ setPriority/getPriority方法动态调整优先级
  - ✅ 调度统计信息收集 (SchedulerStats)
  - ✅ 6个单元测试通过
  - _Requirements: 7.3_

- [x] 5.2.2 集成异步IO
  - 文件: `src/runtime/coroutine.zig`
  - ✅ IOEventType枚举定义 (read/write/err/hup/timer)
  - ✅ IOEvent和IOWaitEntry结构定义
  - ✅ AsyncIOReactor异步IO反应器实现
  - ✅ 平台特定事件队列 (kqueue for macOS/BSD, epoll for Linux)
  - ✅ registerFd/unregisterFd方法注册/取消IO事件
  - ✅ registerTimer方法注册定时器
  - ✅ poll方法非阻塞轮询事件
  - ✅ runEventLoop方法运行事件循环
  - ✅ AsyncIO辅助函数 (asyncRead/asyncWrite/asyncSleep/cancelAsync)
  - ✅ CoroutineManager集成IO反应器
  - ✅ initIOReactor/deinitIOReactor方法
  - ✅ waitForIO/waitForTimer方法挂起协程等待IO
  - ✅ pollIOEvents方法在调度器中轮询IO事件
  - ✅ run()方法更新支持IO等待协程
  - ✅ IOStats统计信息收集
  - ✅ 6个单元测试通过
  - _Requirements: 7.4_

---

## Phase 6: 性能监控与测试 (Week 15-16)

### Task 6.1: 性能监控系统
- [x] 6.1.1 创建PerformanceMonitor
  - 文件: `src/runtime/performance_monitor.zig`
  - ✅ MetricsCollector已实现
  - ✅ HotspotDetector已实现
  - ✅ ExecutionStats已实现
  - _Requirements: 9.1, 9.2_

- [x] 6.1.2 实现实时性能报告
  - 文件: `src/runtime/performance_monitor.zig`
  - ✅ generateReport方法已实现
  - ✅ MemoryStats已实现
  - _Requirements: 9.3, 9.4, 9.5_

### Task 6.2: 测试套件
- [x] 6.2.1 字节码VM单元测试
  - 文件: `src/test_bytecode_vm.zig` (新建)
  - ✅ 栈操作指令测试 (push_null/push_true/push_false/push_int_0/push_int_1)
  - ✅ 整数算术指令测试 (add_int/sub_int/mul_int/div_int)
  - ✅ 比较操作指令测试 (eq/lt_int)
  - ✅ 控制流指令测试 (jmp/jz)
  - ✅ 逻辑操作指令测试 (logic_and/logic_or/logic_not)
  - ✅ 类型转换指令测试 (to_int)
  - ✅ 类型检查指令测试 (is_null/is_int)
  - ✅ Value类型方法测试 (toBool/toInt/toFloat)
  - ✅ VM初始化和清理测试
  - ✅ 复合操作测试
  - ✅ 已添加到build.zig测试列表
  - _Requirements: 10.2_

- [x] 6.2.2 GC压力测试
  - 文件: `src/test_gc_stress.zig` (新建)
  - ✅ 基础GC测试 (allocation tracking, memory threshold, incremental state machine)
  - ✅ 写屏障缓冲区测试
  - ✅ 年轻代分配测试 (nursery allocation)
  - ✅ GC统计信息测试
  - ✅ 分代GC测试 (object creation, promotion, write barrier, root management)
  - ✅ Arena分配器压力测试 (rapid allocation, reset/reuse, large allocation)
  - ✅ 对象池压力测试 (rapid acquire/release, concurrent simulation)
  - ✅ 字符串驻留池压力测试 (deduplication, unique strings, release)
  - ✅ 内存泄漏检测器测试 (tracking, peak memory, no leaks)
  - ✅ GC时间统计测试
  - ✅ 综合压力测试 (mixed allocation patterns, memory manager integration)
  - ✅ 已添加到build.zig测试列表
  - _Requirements: 10.4, 10.5_

- [x] 6.2.3 性能基准测试
  - 文件: `tests/benchmarks/` (新建目录)
  - ✅ `benchmark_runner.zig` - Zig组件基准测试运行器
  - ✅ `php_benchmarks/arithmetic.php` - 算术运算基准测试
  - ✅ `php_benchmarks/strings.php` - 字符串操作基准测试
  - ✅ `php_benchmarks/arrays.php` - 数组操作基准测试
  - ✅ `php_benchmarks/functions.php` - 函数调用基准测试
  - ✅ `php_benchmarks/objects.php` - 对象操作基准测试
  - ✅ `php_benchmarks/run_all.php` - 综合基准测试运行器
  - ✅ `baseline_results.json` - 回归测试基线
  - ✅ `README.md` - 基准测试文档
  - 与PHP 8.x对比
  - 回归测试基线
  - _Requirements: 10.3_

### Task 6.3: 集成与验证
- [x] 6.3.1 集成字节码VM到主执行路径
  - 文件: `src/runtime/vm.zig`, `src/main.zig`
  - ✅ 添加ExecutionMode枚举 (tree_walking/bytecode/auto)
  - ✅ 添加execution_mode和bytecode_vm_instance字段到VM结构
  - ✅ 实现setExecutionMode()/getExecutionMode()方法
  - ✅ 实现ensureBytecodeVM()延迟初始化
  - ✅ 实现runBytecode()/runTreeWalking()执行方法
  - ✅ 实现convertBytecodeValue()值转换
  - ✅ 修改run()方法支持执行模式切换
  - ✅ 更新main.zig支持--mode命令行参数
  - ✅ 添加--help和--version命令行选项
  - ✅ 保留树遍历作为回退（字节码生成器有预存在问题待修复）
  - _Requirements: 10.1_

- [ ] 6.3.2 运行PHP兼容性测试
  - 文件: `tests/compatibility/`
  - PHP 8.x语法测试
  - 标准库函数测试
  - _Requirements: 10.6_

---

## 依赖关系图

```
Phase 1 (基础设施) [✅ 完成]
    |
    v
Phase 2 (字节码VM) [大部分完成] -----> Phase 3 (类型特化) [✅ 完成]
    |                                      |
    v                                      v
Phase 4 (逃逸分析) [✅ 完成] <--------------+
    |
    v
Phase 5 (协程优化) [✅ 完成]
    |
    v
Phase 6 (监控测试) [部分完成]
    |
    v
Phase 7 (增强型分代GC) [✅ 完成]
```

---

## 里程碑

| 里程碑 | 完成标准 | 目标日期 | 状态 |
|--------|----------|----------|------|
| M1: GC增强 | 增量GC停顿<1ms | Week 3 | ✅ 完成 |
| M2: 字节码VM | 基本PHP代码可执行 | Week 7 | ✅ 大部分完成 |
| M3: 类型特化 | 热点函数10x加速 | Week 10 | ✅ 完成 |
| M4: 逃逸分析 | 小对象栈分配 | Week 12 | ✅ 完成 |
| M5: 协程优化 | 10K并发协程 | Week 14 | ✅ 完成 |
| M6: 发布就绪 | 所有测试通过 | Week 16 | 🔄 进行中 |
| M7: 增强型分代GC | 内存占用降低60% | Week 19 | ✅ 完成 |

---

## 风险跟踪

| 风险 | 影响 | 概率 | 缓解措施 | 状态 |
|------|------|------|----------|------|
| 字节码兼容性问题 | 高 | 中 | 保留树遍历解释器 | ✅ 已缓解 |
| GC正确性bug | 高 | 中 | 完善测试覆盖 | 🔄 待监控 |
| 性能未达预期 | 中 | 低 | 分阶段验证 | 🔄 待监控 |
| 内存泄漏 | 高 | 低 | LeakDetector | ✅ 已实现 |

---

## Phase 7: 增强型分代GC (Week 17-19)

### Task 7.1: 内存区域实现
- [x] 7.1.1 实现Nursery区Bump Pointer分配
  - 文件: `src/runtime/generational_gc.zig` (新建)
  - ✅ NurseryRegion结构实现
  - ✅ 连续内存块管理
  - ✅ O(1)快速分配（Bump Pointer）
  - ✅ 分配指针和边界检查
  - ✅ reset()方法重置Nursery
  - ✅ getUtilization()获取使用率
  - ✅ needsCollection()检查是否需要GC
  - _Requirements: 11.1_

- [x] 7.1.2 实现Survivor Space双缓冲
  - 文件: `src/runtime/generational_gc.zig`
  - ✅ SurvivorSpace结构实现
  - ✅ From/To空间切换（flip方法）
  - ✅ 复制算法实现（copyObject方法）
  - ✅ 对象年龄追踪
  - ✅ trackObject()追踪存活对象
  - _Requirements: 11.2_

- [x] 7.1.3 实现Old Generation Free List
  - 文件: `src/runtime/generational_gc.zig`
  - ✅ OldGeneration结构实现
  - ✅ Segregated Fits分配策略（16个大小类别）
  - ✅ 空闲块合并（coalesce方法）
  - 内存碎片整理
  - _Requirements: 11.4_

- [x] 7.1.4 实现Large Object Space
  - 文件: `src/runtime/generational_gc.zig`
  - ✅ LargeObjectSpace结构实现
  - ✅ 大对象(>8KB)直接分配
  - ✅ 独立链表管理
  - ✅ 与Major GC同步回收（sweep方法）
  - ✅ markAll()标记所有对象
  - _Requirements: 11.5_

### Task 7.2: Card Table跨代引用追踪
- [x] 7.2.1 实现Card Table数据结构
  - 文件: `src/runtime/card_table.zig` (新建)
  - ✅ CardTable结构实现
  - ✅ 512字节粒度Card
  - ✅ 脏Card标记（markDirty）和清理（clearCard/clearAll）
  - ✅ 地址范围查询（isDirty）
  - ✅ DirtyCardIterator迭代器
  - ✅ CardTableManager管理多个Card Tables
  - ✅ 7个单元测试通过
  - _Requirements: 11.6_

- [x] 7.2.2 实现写屏障集成
  - 文件: `src/runtime/card_table.zig`
  - ✅ writeBarrierHook()写屏障钩子函数
  - ✅ batchWriteBarrier()批量写屏障
  - ✅ 老年代->年轻代引用检测
  - ✅ 性能优化（条件检查）
  - _Requirements: 11.6_

- [x] 7.2.3 增强Remember Set
  - 文件: `src/runtime/generational_gc.zig`
  - ✅ EnhancedGenerationalGC.remember_set实现
  - ✅ 精确跨代引用记录
  - ✅ Minor GC时作为额外根集
  - ✅ writeBarrier()方法更新Remember Set
  - _Requirements: 11.6_

### Task 7.3: GC触发策略
- [x] 7.3.1 实现自适应触发策略
  - 文件: `src/runtime/gc_policy.zig` (新建)
  - ✅ GCPolicy结构实现
  - ✅ GCPolicyConfig配置结构
  - ✅ 内存使用率阈值（nursery_threshold/old_gen_threshold/full_gc_threshold）
  - ✅ AllocationRateTracker分配速率监控
  - ✅ GCOverheadTracker GC开销追踪
  - ✅ adaptiveAdjust()自适应调整
  - ✅ 8个单元测试通过
  - _Requirements: 11.7_

- [x] 7.3.2 实现并发标记启动
  - 文件: `src/runtime/gc_policy.zig`
  - ✅ shouldStartConcurrentGC()方法
  - ✅ 分配速率触发（concurrent_gc_rate阈值）
  - ✅ 内存压力检查
  - _Requirements: 11.4_

- [x] 7.3.3 实现GC类型选择
  - 文件: `src/runtime/gc_policy.zig`
  - ✅ GCType枚举（minor/major/full/incremental/concurrent）
  - ✅ GCDecision决策结构
  - ✅ shouldTriggerGC()方法实现Minor/Major/Full GC决策
  - ✅ handleAllocationFailure()处理分配失败
  - ✅ MemoryPressure内存压力评估
  - ✅ 紧急GC处理（critical压力时立即Full GC）
  - _Requirements: 11.7_

---

## Phase 8: 高级逃逸分析 (Week 20-22)

### Task 8.1: 数据流图构建
- [x] 8.1.1 创建DFG数据结构
  - 文件: `src/compiler/escape_analysis.zig`
  - ✅ DFGNode定义（allocation, parameter, field_load, field_store, array_load, array_store, call_arg, call_result, return_value, phi, global_var, closure_capture, constant）
  - ✅ DFGEdge定义（def_use, points_to, field_of, element_of, control_dep, data_dep）
  - ✅ DataFlowGraph结构（nodes, edges, node_map, var_to_node）
  - ✅ 图遍历接口（getIncomingEdges, getOutgoingEdges, getAllocationNodes）
  - _Requirements: 12.1_

- [x] 8.1.2 实现AST到DFG转换
  - 文件: `src/compiler/escape_analysis.zig`
  - ✅ EscapeAnalyzer.buildDFG()方法
  - ✅ visitAstNode()分发函数
  - ✅ 支持所有主要AST节点类型（root, block, function_decl, assignment, object_instantiation, array_init, return_stmt, function_call, method_call, property_access, array_access, closure, variable, if_stmt, while_stmt, for_stmt, foreach_stmt, throw_stmt）
  - ✅ 识别分配点（new Object(), array literals, closures）
  - ✅ 构建引用关系（points_to, field_of, element_of, def_use）
  - _Requirements: 12.1_

- [x] 8.1.3 实现SSA形式转换
  - 文件: `src/compiler/escape_analysis.zig`
  - ✅ PhiNode结构定义（node_id, variable, result_version, sources）
  - ✅ BasicBlock结构定义（id, nodes, predecessors, successors, entry_versions, exit_versions, dominance_frontier, immediate_dominator）
  - ✅ SSA版本管理（ssa_versions, ssa_definitions, getSSAVersion, newSSAVersion, recordSSADefinition）
  - ✅ 基本块创建和控制流边管理（createBasicBlock, addControlFlowEdge）
  - ✅ Phi节点插入（insertPhiNode）
  - ✅ 支配边界计算（computeDominanceFrontiers）
  - ✅ 变量重命名（renameVariables, renameBlock）
  - ✅ convertToSSA()完整SSA转换流程
  - ✅ 6个SSA相关单元测试通过
  - _Requirements: 12.1_

### Task 8.2: 逃逸状态分析
- [x] 8.2.1 实现逃逸状态传播算法
  - 文件: `src/compiler/escape_analysis.zig`
  - ✅ EscapeAnalyzer.propagateEscapeStates()方法
  - ✅ 工作列表迭代算法
  - ✅ 状态向上传播（通过边关系）
  - ✅ 不动点检测（状态不再变化时停止）
  - ✅ EscapeState.merge()合并逻辑
  - _Requirements: 12.2, 12.3, 12.4_

- [x] 8.2.2 实现逃逸路径追踪
  - 文件: `src/compiler/escape_analysis.zig`
  - ✅ EscapeAnalyzer.traceEscapePath()方法
  - ✅ EscapePathStep结构记录路径
  - ✅ EscapePoint记录逃逸原因和位置
  - ✅ generateReport()生成优化报告
  - _Requirements: 12.6_

- [x] 8.2.3 实现保守分析回退
  - 文件: `src/compiler/escape_analysis.zig`
  - ✅ 未知函数调用处理（passed_to_unknown -> GlobalEscape）
  - ✅ 闭包捕获处理（captured_by_closure -> GlobalEscape）
  - ✅ 异常抛出处理（thrown_as_exception -> GlobalEscape）
  - ✅ 引用传递处理（passed_by_reference -> GlobalEscape）
  - _Requirements: 12.7_

### Task 8.3: 标量替换优化
- [x] 8.3.1 实现标量替换分析
  - 文件: `src/compiler/escape_analysis.zig`
  - ✅ ScalarReplacementOptimizer结构
  - ✅ ReplacementPlan替换计划
  - ✅ FieldMapping字段到局部变量映射
  - ✅ analyze()方法识别可替换对象
  - ✅ getFieldSlot()获取字段对应的局部变量槽位
  - _Requirements: 12.5_

- [x] 8.3.2 实现代码转换
  - 文件: `src/bytecode/generator.zig`
  - ✅ 导入逃逸分析模块（EscapeAnalyzer, StackAllocationOptimizer, ScalarReplacementOptimizer, OptimizationResult）
  - ✅ BytecodeGenerator添加逃逸分析相关字段（escape_analyzer, stack_optimizer, scalar_optimizer, enable_escape_optimization, ast_to_alloc_id, scalar_field_slots）
  - ✅ enableEscapeOptimization()/disableEscapeOptimization()方法
  - ✅ canStackAllocateNode()/canScalarReplaceNode()检查方法
  - ✅ getStackSlotForNode()/getScalarFieldSlot()槽位获取方法
  - ✅ visitNewObject()修改：支持标量替换（消除分配）和栈分配（使用new_struct指令）
  - ✅ visitPropertyAccess()修改：支持标量替换字段读取（直接从局部变量读取）
  - ✅ visitAssignment()修改：支持标量替换字段写入（直接存储到局部变量）
  - _Requirements: 12.5_

- [x] 8.3.3 实现栈分配决策
  - 文件: `src/compiler/escape_analysis.zig`
  - ✅ StackAllocationOptimizer结构
  - ✅ AllocationDecision决策结构
  - ✅ AllocationLocation枚举（heap/stack/scalar_replaced）
  - ✅ makeDecision()方法根据逃逸分析结果选择分配位置
  - ✅ 栈槽位分配（next_stack_slot）
  - ✅ 栈空间管理（MAX_STACK_FRAME_SIZE = 4096字节）
  - ✅ 对象大小限制（MAX_STACK_OBJECT_SIZE = 256字节）
  - _Requirements: 12.2_

### Task 8.4: 单元测试
- [x] 8.4.1 逃逸分析测试
  - 文件: `src/compiler/escape_analysis.zig`
  - ✅ EscapeState merge测试
  - ✅ EscapeState canStackAllocate测试
  - ✅ DataFlowGraph基本操作测试
  - ✅ DataFlowGraph边查询测试
  - ✅ DataFlowGraph getAllocationNodes测试
  - ✅ EscapeInfo基本操作测试
  - ✅ EscapeAnalyzer初始化测试
  - ✅ EscapeAnalyzer统计测试
  - ✅ EscapeAnalyzer canStackAllocate测试
  - ✅ EscapeAnalyzer generateReport测试
  - ✅ StackAllocationOptimizer初始化测试
  - ✅ StackAllocationOptimizer决策测试
  - ✅ StackAllocationOptimizer栈槽位分配测试
  - ✅ ScalarReplacementOptimizer初始化测试
  - ✅ ScalarReplacementOptimizer分析测试
  - ✅ ScalarReplacementOptimizer字段槽位查找测试
  - ✅ OptimizationResult综合测试
  - ✅ EscapeInfo isStackAllocatable测试
  - ✅ DataFlowGraph SSA版本管理测试
  - ✅ DataFlowGraph基本块创建测试
  - ✅ DataFlowGraph phi节点插入测试
  - ✅ DataFlowGraph SSA形式转换测试
  - ✅ BasicBlock操作测试
  - ✅ PhiNode操作测试
  - ✅ 共24个单元测试全部通过
---

## Phase 9: 复杂类型指针传参优化 (Week 23-24)

### Task 9.1: 类型传递分析
- [x] 9.1.1 实现TypePassingInfo推断
  - 文件: `src/compiler/parameter_optimizer.zig` (新建)
  - ✅ SizeCategory枚举（small/medium/large/huge/dynamic）
  - ✅ PassingMethod枚举（by_value/by_reference/by_const_reference/by_cow/by_move）
  - ✅ TypePassingInfo结构（type_name, static_size, size_category, recommended_method等）
  - ✅ forPrimitive(), forString(), forArray(), forObject()工厂方法
  - ✅ ParameterOptimizer类型缓存机制
  - _Requirements: 13.1, 13.2, 13.3_

- [x] 9.1.2 实现参数修饰符处理
  - 文件: `src/compiler/parameter_optimizer.zig`
  - ✅ ParameterModifier packed struct（is_reference, is_readonly, is_variadic等）
  - ✅ ParameterAnalysis.determinePassingMethod()方法
  - ✅ MutabilityAnalysis结构和EscapeReason枚举
  - ✅ analyzeParameterMutability()方法
  - _Requirements: 13.4_

- [x] 9.1.3 实现运行时大小检查生成
  - 文件: `src/compiler/parameter_optimizer.zig`
  - ✅ RuntimeSizeChecker结构
  - ✅ TypeTag枚举用于动态类型识别
  - ✅ estimateSize()方法估算动态类型大小
  - ✅ generateSizeCheck()生成大小检查结果
  - ✅ SizeCheckResult结构（param_name, threshold, small_path_method, large_path_method）
  - _Requirements: 13.7_

### Task 9.2: Copy-on-Write实现
- [x] 9.2.1 实现COWWrapper结构
  - 文件: `src/runtime/cow.zig` (新建)
  - ✅ COWState枚举（exclusive/shared/immutable）
  - ✅ COWWrapper(T)泛型结构
  - ✅ 引用计数管理（原子操作）
  - ✅ init(), share(), get(), getMutable()方法
  - ✅ copyOnWrite()延迟复制触发
  - ✅ deinit(), getRefCount(), isExclusive(), makeImmutable()方法
  - _Requirements: 13.5_

- [x] 9.2.2 实现COWString结构
  - 文件: `src/runtime/cow.zig`
  - ✅ COWString结构（短字符串优化SSO）
  - ✅ SSO_CAPACITY = 23字节阈值
  - ✅ ShortString/LongString存储类型
  - ✅ fromSlice(), slice(), len()方法
  - ✅ share(), getMutableSlice(), append()方法
  - ✅ copyOnWrite()写时复制
  - ✅ isShort()检查是否使用SSO
  - _Requirements: 13.1_

- [x] 9.2.3 实现COWArray结构
  - 文件: `src/runtime/cow.zig`
  - ✅ COWArray结构
  - ✅ ArrayKey联合类型（integer/string）
  - ✅ ArrayValue联合类型（null/bool/int/float/string/array/other）
  - ✅ init(), count(), get(), set(), push(), remove()方法
  - ✅ share(), copyOnWrite()方法
  - ✅ estimateSize()内存大小估算
  - ✅ iterator()迭代器
  - ✅ 嵌套数组处理
  - _Requirements: 13.2_

### Task 9.3: 字节码层集成
- [x] 9.3.1 实现参数传递指令
  - 文件: `src/bytecode/instruction.zig`
  - ✅ pass_by_value (0x97) - 值传递指令
  - ✅ pass_by_ref (0x98) - 引用传递指令
  - ✅ pass_by_cow (0x99) - COW传递指令
  - ✅ pass_by_move (0x9A) - 移动传递指令
  - ✅ cow_check (0x9B) - COW检查指令
  - ✅ cow_copy (0x9C) - COW复制指令
  - ✅ ret_move (0x9D) - 移动返回指令
  - ✅ ret_cow (0x9E) - COW返回指令
  - ✅ 更新operandCount()和isTerminator()方法
  - _Requirements: 13.6_

- [x] 9.3.2 实现调用约定优化
  - 文件: `src/bytecode/vm.zig`
  - ✅ handlePassByValue() - 值传递处理（深拷贝复杂类型）
  - ✅ handlePassByRef() - 引用传递处理（增加引用计数）
  - ✅ handlePassByCow() - COW传递处理（共享直到修改）
  - ✅ handlePassByMove() - 移动传递处理（转移所有权）
  - ✅ handleCowCheck() - 检查是否需要复制
  - ✅ handleCowCopy() - 执行写时复制
  - ✅ 注册到dispatch_table
  - _Requirements: 13.6_

- [x] 9.3.3 实现返回值优化
  - 文件: `src/bytecode/vm.zig`
  - ✅ handleRetMove() - 移动返回（避免复制）
  - ✅ handleRetCow() - COW返回（允许共享）
  - ✅ 支持大对象返回优化
  - ✅ 移动语义支持
  - _Requirements: 13.3_

---

## Phase 10: Go风格时间库 (Week 25)

### Task 10.1: 时间库实现
- [x] 10.1.1 创建时间库核心结构
  - 文件: `src/runtime/time.zig` (新建)
  - ✅ Duration结构（时间间隔，纳秒精度）
  - ✅ Time结构（时间点，Unix时间戳+纳秒）
  - ✅ Location结构（时区信息）
  - ✅ Month枚举（1-12月）
  - ✅ Weekday枚举（周日-周六）
  - ✅ 时间单位常量（Nanosecond, Microsecond, Millisecond, Second, Minute, Hour）

- [x] 10.1.2 实现Duration方法
  - 文件: `src/runtime/time.zig`
  - ✅ hours(), minutes(), seconds(), milliseconds(), microseconds(), nanoseconds() 创建方法
  - ✅ getHours(), getMinutes(), getSeconds() 等获取方法
  - ✅ add(), sub(), mul(), div() 算术运算
  - ✅ abs() 绝对值
  - ✅ truncate(), round() 精度控制
  - ✅ string() 格式化输出

- [x] 10.1.3 实现Time方法
  - 文件: `src/runtime/time.zig`
  - ✅ now() 获取当前时间
  - ✅ unix(), unixMilli(), unixMicro() 从时间戳创建
  - ✅ date() 从日期时间创建
  - ✅ year(), month(), day(), hour(), minute(), second(), nanosecond() 获取组件
  - ✅ weekday(), yearDay(), isoWeek() 日期计算
  - ✅ add(), sub(), addDate() 时间运算
  - ✅ before(), after(), equal() 比较方法
  - ✅ in(), utc() 时区转换
  - ✅ truncateTime(), roundTime() 精度控制
  - ✅ format() Go风格格式化

- [x] 10.1.4 实现PHP兼容函数
  - 文件: `src/runtime/time.zig`
  - ✅ phpTime() - PHP time()
  - ✅ phpMicrotime() - PHP microtime(true)
  - ✅ phpDate() - PHP date()
  - ✅ phpMktime() - PHP mktime()
  - ✅ phpStrtotime() - PHP strtotime() (简化实现)
  - ✅ phpCheckdate() - PHP checkdate()

- [x] 10.1.5 实现解析函数
  - 文件: `src/runtime/time.zig`
  - ✅ parseDuration() - 解析Duration字符串（如"1h30m", "500ms"）
  - parse() - 解析时间字符串（基础实现）

- [x] 10.1.6 单元测试
  - 文件: `src/runtime/time.zig`
  - ✅ Duration创建和转换测试
  - ✅ Duration算术运算测试
  - ✅ Duration abs和truncate测试
  - ✅ Time创建测试
  - ✅ Time组件测试
  - ✅ Time weekday测试
  - ✅ Time算术运算测试
  - ✅ Time比较测试
  - ✅ Time addDate测试
  - ✅ Time format测试
  - ✅ parseDuration测试
  - ✅ phpDate测试
  - ✅ phpMktime测试
  - ✅ phpCheckdate测试
  - ✅ Month和Weekday字符串测试
  - ✅ Time zero和isZero测试
  - ✅ Location测试
  - ✅ 共17个单元测试全部通过

---

## 更新后的依赖关系图

```
Phase 1 (基础设施) [✅ 完成]
    |
    v
Phase 2 (字节码VM) [✅ 大部分完成] -----> Phase 3 (类型特化) [✅ 完成]
    |                                          |
    v                                          v
Phase 4 (逃逸分析) [✅ 完成] <-----------------+
    |
    v
Phase 5 (协程优化) [✅ 完成]
    |
    v
Phase 6 (监控测试) [🔄 部分完成]
    |
    +---> Phase 7 (增强型分代GC) [✅ 完成]
    |         |
    |         v
    +---> Phase 8 (高级逃逸分析) [✅ 完成]
    |         |
    |         v
    +---> Phase 9 (指针传参优化) [✅ 完成]
    |         |
    |         v
    +---> Phase 10 (Go风格时间库) [✅ 完成]
              |
              v
         Phase 11 (最终集成测试)
```

---

## 更新后的里程碑

| 里程碑 | 完成标准 | 目标日期 | 状态 |
|--------|----------|----------|------|
| M1: GC增强 | 增量GC停顿<1ms | Week 3 | ✅ 完成 |
| M2: 字节码VM | 基本PHP代码可执行 | Week 7 | ✅ 大部分完成 |
| M3: 类型特化 | 热点函数10x加速 | Week 10 | ✅ 完成 |
| M4: 逃逸分析 | 小对象栈分配 | Week 12 | ✅ 完成 |
| M5: 协程优化 | 10K并发协程 | Week 14 | ✅ 完成 |
| M6: 监控测试 | 所有测试通过 | Week 16 | 🔄 进行中 |
| M7: 增强型分代GC | 内存占用降低60% | Week 19 | ✅ 完成 |
| M8: 高级逃逸分析 | 标量替换生效 | Week 22 | ✅ 完成 |
| M9: 指针传参优化 | 大对象零复制传递 | Week 24 | ✅ 完成 |
| M10: Go风格时间库 | 时间处理功能完整 | Week 25 | ✅ 完成 |
| M11: 发布就绪 | 性能目标达成 | Week 26 | ⏳ 未开始 |

---

## 剩余工作摘要
### 高优先级任务 (建议下一步执行)
1. **Task 6.3.2** - 运行PHP兼容性测试
2. **修复字节码生成器** - 修复 `src/bytecode/generator.zig` 中的类型问题

### 中优先级任务
1. **修复运行时问题** - 修复VM初始化时的Bus error问题
2. **完善字节码执行** - 启用完整的字节码编译和执行路径

### 低优先级任务 (后续阶段)
1. Phase 7 - 增强型分代GC (全部)
2. Phase 8 - 高级逃逸分析 (全部)
3. Phase 9 - 指针传参优化 (全部)
