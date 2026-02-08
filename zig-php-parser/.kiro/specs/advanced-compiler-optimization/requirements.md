# 需求文档：AOT 优先的深度性能优化

## 简介

本规范定义了 zig-php 项目的深度性能优化需求，**以 AOT（Ahead-Of-Time）编译为核心优化方向**。zig-php 是一个用 Zig 实现的完整 PHP 8.5 解释器，包含三层执行引擎（解释器、JIT、AOT）。

### 优化战略

**核心理念：AOT First - 追求极致的编译时优化**

我们的优化战略遵循以下优先级：
1. **AOT 编译器优化（P0）** - 全程序优化、链接时优化、配置文件引导优化、反射机制
2. **动态代码消除（P0）** - 通过 AOT 分析和反射机制减少运行时动态特性
3. **运行时系统优化（P1）** - 支撑 AOT 代码的高效执行、编译时反射
4. **内存管理优化（P2）** - 减少 GC 开销，提升 AOT 代码性能
5. **JIT 编译器优化（P3）** - 作为 AOT 的补充，处理少量必要的动态代码
6. **解释器优化（P4）** - 开发和调试阶段使用

**性能目标：**
- AOT 编译的 PHP 代码性能达到 C/Rust 的 **95%+**
- 相比原生 PHP 8.5，性能提升 **10-20 倍**
- 编译时间控制在 **< 5 秒/MB 源码**
- 生成的可执行文件大小合理（< 10MB for typical apps）

## 术语表

- **AOT**: 提前编译器（Ahead-Of-Time Compiler），编译时将代码编译为机器码
- **WPO**: 全程序优化（Whole Program Optimization）
- **LTO**: 链接时优化（Link-Time Optimization）
- **PGO**: 配置文件引导优化（Profile-Guided Optimization）
- **Reflection**: 反射（Reflection），程序在运行时检查和修改自身结构的能力
- **Compile-Time_Reflection**: 编译时反射，在编译阶段分析和优化反射操作
- **Dynamic_Code_Elimination**: 动态代码消除，通过静态分析减少运行时动态特性
- **VM**: 虚拟机（Virtual Machine），执行字节码的运行时环境
- **GC**: 垃圾回收器（Garbage Collector），自动内存管理系统
- **JIT**: 即时编译器（Just-In-Time Compiler），运行时将字节码编译为机器码
- **IC**: 内联缓存（Inline Cache），优化动态调用的缓存机制
- **OSR**: 栈上替换（On-Stack Replacement），运行时切换执行引擎
- **DCE**: 死代码消除（Dead Code Elimination），移除不可达代码
- **NaN_Boxing**: 使用 NaN 位模式存储类型标签的值表示技术
- **SIMD**: 单指令多数据（Single Instruction Multiple Data），向量化指令
- **Allocator**: 内存分配器，管理内存分配和释放
- **Opcode**: 操作码，虚拟机指令
- **Bytecode**: 字节码，中间表示形式
- **Hotspot**: 热点，频繁执行的代码路径
- **Deoptimization**: 去优化，从优化代码回退到解释执行
- **Type_Specialization**: 类型特化，针对特定类型生成优化代码
- **Register_Allocator**: 寄存器分配器，将虚拟寄存器映射到物理寄存器

## 需求

### 需求 1：AOT 全程序优化（P0 - 最高优先级）

**用户故事**：作为 AOT 开发者，我希望实现全程序优化，以生成接近 C/Rust 性能的原生可执行文件。

#### 验收标准

1. THE AOT SHALL 分析整个程序的调用图和数据流
2. THE AOT SHALL 在链接时执行跨模块优化（LTO）
3. WHEN 提供性能配置文件时，THE AOT SHALL 根据配置优化代码布局（PGO）
4. THE AOT SHALL 优化代码布局以提高指令缓存命中率（> 95%）
5. THE AOT SHALL 内联跨模块的函数调用（内联率 > 80%）
6. THE AOT SHALL 去虚化所有可确定的虚方法调用（去虚化率 > 90%）
7. THE AOT SHALL 消除所有可证明的边界检查（消除率 > 85%）
8. THE AOT SHALL 生成针对目标 CPU 的优化代码（x86-64、ARM64）
9. THE AOT SHALL 实现常量传播、死代码消除、公共子表达式消除
10. THE AOT SHALL 生成的代码性能达到 C/Rust 的 95% 以上

### 需求 2：AOT 编译器高级优化（P0）

**用户故事**：作为编译器开发者，我希望实现多种高级编译器优化技术，以最大化 AOT 代码性能。

#### 验收标准

1. WHEN 编译常量表达式时，THE Compiler SHALL 在编译时计算结果（常量折叠）
2. WHEN 检测到不可达代码时，THE Compiler SHALL 移除死代码
3. WHEN 分析变量逃逸时，THE Compiler SHALL 将未逃逸对象分配在栈上
4. WHEN 检测到循环时，THE Compiler SHALL 分析循环不变量并外提
5. WHEN 循环迭代次数已知且较小时，THE Compiler SHALL 展开循环
6. WHEN 函数体积小于 100 字节码时，THE Compiler SHALL 内联函数调用
7. WHEN 检测到尾调用时，THE Compiler SHALL 优化为跳转指令
8. WHEN 检测到可向量化操作时，THE Compiler SHALL 生成 SIMD 指令
9. THE Compiler SHALL 实现强度削减优化（乘法转移位等）
10. THE Compiler SHALL 实现代数简化（a + 0 -> a, a * 1 -> a）

### 需求 3：AOT 代码生成与优化（P0）

**用户故事**：作为 AOT 开发者，我希望生成高质量的 LLVM IR 和原生机器码。

#### 验收标准

1. THE AOT SHALL 生成完整的 LLVM IR（非简化实现）
2. THE AOT SHALL 实现完整的结构体类型生成（支持所有 PHP 类特性）
3. THE AOT SHALL 实现完整的异常处理（landing pad、catch、finally）
4. THE AOT SHALL 实现常量初始化器（全局常量、类常量）
5. THE AOT SHALL 实现跨文件链接（符号表合并、依赖解析）
6. THE AOT SHALL 支持多平台目标（Linux、macOS、Windows）
7. THE AOT SHALL 支持多架构（x86-64、ARM64）
8. THE AOT SHALL 生成调试信息（DWARF、PDB）
9. THE AOT SHALL 实现增量编译（只重新编译修改的文件）
10. THE AOT SHALL 编译时间 < 5 秒/MB 源码

### 需求 4：运行时系统优化（P1）

**用户故事**：作为运行时开发者，我希望优化运行时系统，以支撑 AOT 代码的高效执行。

#### 验收标准

1. THE VM SHALL 使用 NaN_Boxing 技术在 64 位值中存储类型标签和数据
2. WHEN 执行字符串操作时，THE VM SHALL 使用 SIMD 指令加速（性能提升 2-3 倍）
3. WHEN 执行数组操作时，THE VM SHALL 使用 SIMD 指令加速（性能提升 2-4 倍）
4. WHEN 调用方法时，THE VM SHALL 使用内联缓存记录调用目标
5. WHEN 访问对象属性时，THE VM SHALL 使用内联缓存记录属性偏移
6. THE VM SHALL 使用对象池复用频繁创建的对象类型
7. WHEN 字符串不可变时，THE VM SHALL 共享字符串数据
8. WHEN 数组为连续整数索引时，THE VM SHALL 使用密集数组表示
9. THE VM SHALL 使用 Robin Hood 哈希表实现关联数组
10. THE VM SHALL 使用 Boyer-Moore 算法进行字符串搜索

### 需求 5：内存管理优化（P2）

**用户故事**：作为系统开发者，我希望优化内存管理系统，以减少 GC 开销，提升 AOT 代码性能。

#### 验收标准

1. WHEN GC 执行时，THE GC SHALL 使用分代算法将对象分为年轻代和老年代
2. WHEN 年轻代满时，THE GC SHALL 执行增量式的 Minor GC，单次停顿时间不超过 3ms
3. WHEN 老年代满时，THE GC SHALL 执行并发式的 Major GC，最大停顿时间不超过 10ms
4. WHEN 内存碎片率超过 30% 时，THE GC SHALL 执行内存压缩
5. WHEN 对象被修改时，THE VM SHALL 使用 Copy-on-Write 策略延迟复制
6. THE Allocator SHALL 使用内存池管理小对象（<256 字节）
7. THE Allocator SHALL 使用 Arena 分配器管理临时对象
8. THE Allocator SHALL 使用 Slab 分配器管理固定大小对象
9. THE Allocator SHALL 使用 Bump 分配器管理短生命周期对象
10. WHEN 对象分配失败时，THE Allocator SHALL 返回明确的错误码

### 需求 6：JIT 编译器优化（P3 - 作为 AOT 补充）

**用户故事**：作为 JIT 开发者，我希望优化 JIT 编译器，以处理 AOT 无法优化的动态代码。

#### 验收标准

1. WHEN 函数执行次数超过 1000 次时，THE JIT SHALL 将其标记为热点
2. WHEN 循环执行次数超过 10000 次时，THE JIT SHALL 将其标记为热点
3. THE JIT SHALL 使用图着色算法进行寄存器分配
4. WHEN 函数在解释执行中被标记为热点时，THE JIT SHALL 执行 OSR 切换到编译代码
5. WHEN 类型信息可用时，THE JIT SHALL 生成类型特化的代码
6. WHEN 虚方法调用目标单一时，THE JIT SHALL 去虚化调用
7. THE JIT SHALL 实现三层编译（解释器 → 基础 JIT → 优化 JIT）
8. WHEN 类型假设失效时，THE JIT SHALL 去优化回退到解释器
9. THE JIT SHALL 支持并行编译（多线程）
10. THE JIT SHALL 编译时间 < 100ms per function

### 需求 7：算法优化（P2）

**用户故事**：作为算法开发者，我希望使用高效的数据结构和算法，以提升核心操作性能。

#### 验收标准

1. THE VM SHALL 使用 Robin Hood 哈希表实现关联数组
2. WHEN 哈希表负载因子超过 0.75 时，THE VM SHALL 自动扩容
3. WHEN 执行字符串搜索时，THE VM SHALL 使用 Boyer-Moore 算法
4. WHEN 执行字符串匹配时，THE VM SHALL 使用 SIMD 加速的 memchr
5. WHEN 执行排序时，THE VM SHALL 根据数据规模选择算法（插入排序 vs 快速排序）
6. WHEN 执行数值计算时，THE VM SHALL 使用 FMA 指令（融合乘加）
7. THE VM SHALL 使用 Slab 分配器管理固定大小对象
8. THE VM SHALL 使用 Bump 分配器管理短生命周期对象
9. THE VM SHALL 实现 SIMD 加速的 strlen、strcmp、memcpy
10. THE VM SHALL 实现 SIMD 加速的数组求和、映射、过滤

### 需求 8：性能监控与分析（P1）

**用户故事**：作为性能工程师，我希望有完善的性能监控工具，以识别性能瓶颈和回归。

#### 验收标准

1. THE Profiler SHALL 实时采样函数执行时间
2. THE Profiler SHALL 记录每个函数的调用次数和累计时间
3. THE Profiler SHALL 生成火焰图展示性能热点
4. THE Leak_Detector SHALL 跟踪所有内存分配和释放
5. WHEN 检测到内存泄漏时，THE Leak_Detector SHALL 报告分配栈追踪
6. THE Hotspot_Analyzer SHALL 识别执行频率最高的代码路径
7. THE Regression_Detector SHALL 对比基准测试结果检测性能回归
8. WHEN 性能回归超过 3% 时，THE Regression_Detector SHALL 发出警告
9. THE Profiler SHALL 支持 perf、tracy 集成
10. THE Profiler SHALL 生成详细的性能报告（HTML、JSON）

### 需求 9：兼容性和正确性（P0）

**用户故事**：作为质量保证工程师，我希望所有优化保持语义正确性和兼容性。

#### 验收标准

1. THE Optimizer SHALL 保持与 PHP 8.5 语义完全兼容
2. WHEN 执行优化后的代码时，THE VM SHALL 产生与未优化代码相同的结果
3. THE Optimizer SHALL 通过所有现有的测试套件（> 95%）
4. THE Optimizer SHALL 保持内存安全，无缓冲区溢出和悬垂指针
5. THE Optimizer SHALL 支持 x86-64 和 ARM64 架构
6. WHEN 优化失败时，THE Optimizer SHALL 回退到未优化版本
7. THE Optimizer SHALL 提供编译选项控制优化级别（-O0、-O1、-O2、-O3）
8. THE Optimizer SHALL 在调试模式下禁用可能影响调试的优化
9. THE Optimizer SHALL 生成正确的调试信息（DWARF、PDB）
10. THE Optimizer SHALL 支持增量编译和缓存

### 需求 10：反射机制（P0 - 支撑 AOT 优化）

**用户故事**：作为 AOT 开发者，我希望实现高效的反射机制，以支持编译时优化和运行时反射 API。

#### 验收标准

1. THE Compiler SHALL 在编译时收集所有类、方法、属性的元数据
2. THE Compiler SHALL 生成反射元数据表（类名、方法签名、属性类型）
3. THE Compiler SHALL 实现编译时反射分析（类层次、方法调用图）
4. THE Runtime SHALL 提供 ReflectionClass API（获取类信息）
5. THE Runtime SHALL 提供 ReflectionMethod API（获取方法信息）
6. THE Runtime SHALL 提供 ReflectionProperty API（获取属性信息）
7. THE Runtime SHALL 缓存反射信息以减少运行时开销（缓存命中率 > 95%）
8. THE Compiler SHALL 使用反射信息优化虚方法调用（去虚化率 > 90%）
9. THE Compiler SHALL 使用反射信息优化属性访问（内联率 > 85%）
10. THE Runtime SHALL 反射 API 性能开销 < 10%（相比直接访问）

### 需求 11：动态代码消除（P0 - AOT 核心优化）

**用户故事**：作为 AOT 开发者，我希望通过静态分析消除动态代码，以最大化 AOT 优化效果。

#### 验收标准

1. THE Compiler SHALL 静态分析所有动态特性（eval、variable variables、dynamic calls）
2. THE Compiler SHALL 识别可静态化的动态代码（常量字符串、已知类型）
3. THE Compiler SHALL 将可静态化的动态代码转换为静态代码
4. WHEN 变量名是常量时，THE Compiler SHALL 将 variable variables 转换为直接访问
5. WHEN 方法名是常量时，THE Compiler SHALL 将动态调用转换为静态调用
6. WHEN eval 参数是常量时，THE Compiler SHALL 在编译时执行 eval
7. THE Compiler SHALL 标记无法静态化的动态代码（使用 JIT 处理）
8. THE Compiler SHALL 生成动态代码分析报告（静态化率、动态代码位置）
9. THE Compiler SHALL 动态代码静态化率 > 80%（典型应用）
10. THE Compiler SHALL 静态化后性能提升 > 5 倍（相比动态执行）

### 需求 12：性能目标（P0 - AOT 优先）

**用户故事**：作为项目负责人，我希望达到明确的性能提升目标，**以 AOT 为核心**。

#### 验收标准

1. THE AOT SHALL 生成性能达到 C/Rust 的 **95%+**（核心目标）
2. THE AOT SHALL 相比原生 PHP 8.5 性能提升 **10-20 倍**
3. THE AOT SHALL 编译时间 < 5 秒/MB 源码
4. THE AOT SHALL 生成的可执行文件大小合理（< 10MB for typical apps）
5. THE JIT SHALL 相比解释器性能提升 5-10 倍（作为 AOT 补充）
6. THE Interpreter SHALL 相比优化前性能提升 2-3 倍（开发调试用）
7. THE GC SHALL 将停顿时间减少 60% 以上（支撑 AOT 性能）
8. THE VM SHALL 将内存占用减少 40% 以上
9. THE Optimizer SHALL 在标准基准测试中超越 PHP 官方实现 **10 倍以上**
10. THE System SHALL 在实际应用场景中展现可测量的性能提升（> 10x）

