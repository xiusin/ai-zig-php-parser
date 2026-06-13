# Tasks: AOT 模块深度优化

## Phase 1: 编译正确性修复（阻塞性，最高优先级）

- [x] Task 1: 修复 Mem2Reg Phi 节点生成（do-while/while/for 循环变量更新）
  - [x] 1.1 在 optimizer.zig 的 mem2reg pass 中修复 do-while 循环回边 phi 节点插入
  - [x] 1.2 确保 while/for 循环 header 块的 phi 节点覆盖所有前驱
  - [x] 1.3 添加 do-while/while/for 循环正确性的单元测试
  - [x] 1.4 运行 test_control_flow.php 验证循环正确性
  - **验证**: 所有循环类型测试通过，无死循环

- [x] Task 2: 修复多维数组 NaN Boxing 对齐崩溃
  - [x] 2.1 在 nanbox_abi.zig 的 encodePtr/decodePtr 中确保指针对齐
  - [x] 2.2 在 runtime_lib.zig 的 asArray() 中添加对齐断言和修复逻辑
  - [x] 2.3 确保数组分配时使用正确的对齐（@alignCast）
  - [x] 2.4 编写多维数组对齐测试
  - **验证**: 多维数组操作不崩溃，值正确存储和读取

## Phase 2: 代码生成架构重构（核心性能提升）

- [x] Task 3: 重构结构化代码生成支持多循环
  - [x] 3.1 将 generateStructuredCodeNew 中的单循环限制移除
  - [x] 3.2 实现块追踪系统（BlockTracker）：避免重复生成已处理块
  - [x] 3.3 实现嵌套循环递归生成（generateLoopRecursive 完善）
  - [x] 3.4 统一退出块处理逻辑（多循环共享退出路径）
  - [x] 3.5 处理循环内 if-else 分支的正确代码生成
  - [x] 3.6 消除 "仅 1 个循环才结构化" 的限制条件
  - **验证**: 多循环函数生成结构化代码，无状态机回退

- [x] Task 4: 消除状态机代码生成回退路径
  - [x] 4.1 确保所有控制流模式都有结构化代码生成路径
  - [x] 4.2 在无法生成结构化代码时输出明确的诊断信息
  - [x] 4.3 验证所有现有测试在结构化代码生成下通过
  - **验证**: 所有测试套件函数使用结构化代码生成

## Phase 3: 内存管理优化

- [x] Task 5: PHPValue NanBox 迁移（24 字节 → 8 字节）
  - [x] 5.1 重构 runtime_lib.zig 的 PHPValue 为 8 字节 u64 NanBox 表示
  - [x] 5.2 实现整数、布尔、null、浮点的内联编码
  - [x] 5.3 实现指针类型（string/array/object）的 NanBox 指针编码
  - [x] 5.4 更新所有运行时函数适配新 PHPValue（加、减、比较、类型转换等）
  - [x] 5.5 更新 native_linker.zig 的代码生成适配 8 字节值
  - [x] 5.6 更新 optimizer.zig 的类型系统（IR Type 保持兼容）
  - **验证**: 所有现有测试在新 PHPValue 上通过，内存占用减少 66%

- [x] Task 6: SSO 短字符串优化
  - [x] 6.1 实现 24 字节内联缓冲区 PHPString，长度 <= 23 的字符串不堆分配
  - [x] 6.2 实现 StringBuilder 类：支持原地扩容和批量拼接
  - [x] 6.3 在 native_linker.zig 中检测连续字符串拼接并生成 StringBuilder 代码
  - [x] 6.4 实现字符串操作的写时复制（COW）优化
  - **验证**: 短字符串零堆分配，循环拼接性能提升 10x+

## Phase 4: 运算优化

- [x] Task 7: 算术运算标量化
  - [x] 7.1 在 optimizer.zig 实现标量类型追踪：标记纯整数/浮点运算路径
  - [x] 7.2 在 native_linker.zig 中为标量路径生成原生 i64/f64 运算
  - [x] 7.3 消除标量运算中的 PHPValue 类型分派和 ref_count 操作
  - [x] 7.4 实现整数溢出检测（PHP 语义：溢出转 float）
  - **验证**: 纯整数循环累加生成无运行时类型分派的代码

- [x] Task 8: 数组操作优化
  - [x] 8.1 集成 src/algorithms/robin_hood_hashmap.zig 到 runtime_lib 的 PHPArray
  - [x] 8.2 实现数组预分配容量提示（array_reserve）
  - [x] 8.3 在连续 push 模式下批量扩容（2x 增长策略）
  - [x] 8.4 优化数组遍历的迭代器（减少间接访问）
  - **验证**: 数组操作性能显著提升，哈希冲突减少

## Phase 5: Include/Require 增强

- [x] Task 9: 完善 include/require 编译时支持
  - [x] 9.1 在多文件编译器中将 include 文件的 IR 完整合并到主 IR 模块
  - [x] 9.2 实现 require_once/include_once 的去重逻辑（基于文件路径）
  - [x] 9.3 处理 include 文件的全局作用域代码（顶层语句）
  - [x] 9.4 处理 include 链中的循环依赖检测
  - **验证**: 静态 include 项目编译为单一可执行文件，正确执行

- [x] Task 10: 实现动态 include 运行时支持
  - [x] 10.1 在 runtime_lib.zig 实现 php_include 运行时函数
  - [x] 10.2 实现动态路径解析和文件加载
  - [x] 10.3 对于无法静态解析的 include，生成回退到解释器的代码
  - **验证**: 动态 include 在运行时正确加载并执行

## Phase 6: 引用计数优化增强

- [x] Task 11: 增强逃逸分析
  - [x] 11.1 实现跨基本块的逃逸分析（inter-procedural 雏形）
  - [x] 11.2 识别函数内局部变量（确定不逃逸），栈分配替代堆分配
  - [x] 11.3 实现返回值所有权转移优化（RVO/移动语义）
  - [x] 11.4 在 native_linker.zig 中为不逃逸变量消除 retain/release
  - **验证**: 局部变量 RC 操作减少 50%+

## Phase 7: 运行时函数补全

- [x] Task 12: 补全缺失的 PHP 运行时函数
  - [x] 12.1 实现 implode/join 函数
  - [x] 12.2 实现字符串索引读写 ($str[0]、$str[0] = 'x')
  - [x] 12.3 实现 array_keys、array_values 函数
  - [x] 12.4 实现 explode 函数
  - [x] 12.5 实现 in_array、array_search 函数
  - [x] 12.6 实现 strlen、strpos、substr 等基础字符串函数（如缺失）
  - **验证**: 所有补充函数单元测试通过

## Phase 8: 基准测试与验证

- [x] Task 13: 建立 PHP 基准测试套件
  - [x] 13.1 创建 benchmarks/php_vs_aot/ 目录，包含 30+ 测试场景
  - [x] 13.2 实现基准运行器：同时运行 PHP 和 AOT 版本，对比性能
  - [x] 13.3 覆盖场景：循环、递归、字符串、数组、数学、条件、OOP
  - [x] 13.4 实现性能回归检测脚本
  - [x] 13.5 生成性能对比报告（CSV/JSON 格式）
  - **验证**: 所有基准场景 AOT 性能超过 PHP 8.x

- [x] Task 14: 端到端集成测试
  - [x] 14.1 运行所有现有 fuzzy test 100 个场景
  - [x] 14.2 运行所有回归测试
  - [x] 14.3 修复发现的所有测试失败
  - [x] 14.4 确保 release-safe 和 release-fast 均正确
  - **验证**: 100% 测试通过率

## Phase 9: 并行编译优化

- [x] Task 15: 编译器并行化
  - [x] 15.1 在多文件编译中并行编译独立文件（无依赖关系的文件）
  - [x] 15.2 实现并行 IR 生成和优化（每个函数独立优化）
  - [x] 15.3 使用线程池管理编译任务
  - **验证**: 多文件编译时间减少 30%+

# Task Dependencies
- Task 2 依赖 Task 5（NanBox 迁移后对齐问题自然解决）
- Task 3, 4 依赖 Task 1（Phi 节点修复是结构化代码生成的前提）
- Task 6, 7, 8 依赖 Task 5（NanBox 迁移改变值表示）
- Task 9, 10 无前置依赖
- Task 11 依赖 Task 5（迁移后重新分析）
- Task 12 依赖 Task 5（新值类型）
- Task 13, 14 依赖 Task 1-12 全部完成
- Task 15 无前置依赖

建议执行顺序：Task 1 → Task 3 → Task 4 → Task 5 → Task 2, 6, 7, 8, 9, 10, 11, 12（并行） → Task 13, 14 → Task 15