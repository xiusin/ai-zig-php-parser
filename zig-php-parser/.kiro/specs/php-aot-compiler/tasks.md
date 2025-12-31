# Implementation Plan: PHP AOT Compiler

## Overview

本实现计划将 PHP AOT 编译器功能分解为可执行的编码任务。实现采用增量方式，每个阶段都能产出可测试的功能。

## Tasks

- [x] 1. 项目结构和基础设施
  - [x] 1.1 创建 AOT 编译器目录结构
    - 创建 `src/aot/` 目录
    - 创建模块入口文件 `src/aot/root.zig`
    - 更新 `build.zig` 添加 AOT 模块编译
    - _Requirements: 1.1_

  - [x] 1.2 扩展命令行接口
    - 在 `src/main.zig` 添加 `--compile` 选项解析
    - 添加 `--output`, `--target`, `--optimize`, `--static` 选项
    - 添加 `--dump-ir`, `--dump-ast`, `--verbose` 调试选项
    - 添加 `--list-targets` 选项
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 7.4, 7.5, 7.6, 9.4_

  - [x] 1.3 实现诊断引擎
    - 创建 `src/aot/diagnostics.zig`
    - 实现 `DiagnosticEngine` 结构
    - 实现错误/警告收集和格式化输出
    - _Requirements: 1.6, 7.1, 7.2, 7.3_

- [x] 2. 中间表示 (IR) 定义
  - [x] 2.1 定义 IR 数据结构
    - 创建 `src/aot/ir.zig`
    - 定义 `Module`, `Function`, `BasicBlock` 结构
    - 定义 `Instruction` 和所有操作类型
    - 定义 `Register`, `Type`, `Terminator`
    - _Requirements: 2.1, 2.2, 2.3_

  - [x] 2.2 编写 IR 数据结构单元测试
    - 测试 IR 结构的创建和操作
    - 测试 IR 的序列化/反序列化 (用于 --dump-ir)
    - _Requirements: 2.1_

- [x] 3. 类型推断系统
  - [x] 3.1 实现符号表
    - 创建 `src/aot/symbol_table.zig`
    - 实现作用域管理
    - 实现符号查找和注册
    - _Requirements: 3.1, 3.2, 3.3_

  - [x] 3.2 实现类型推断器
    - 创建 `src/aot/type_inference.zig`
    - 实现字面量类型推断
    - 实现函数参数/返回类型推断
    - 实现变量类型推断
    - 实现动态类型回退
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

  - [x] 3.3 编写类型推断属性测试
    - **Property 3: 类型推断正确性**
    - **Validates: Requirements 3.1, 3.2, 3.3, 3.4**
    - ✅ All 10 property tests passed (100 iterations each)

- [x] 4. IR 生成器
  - [x] 4.1 实现 IR 生成器核心
    - 创建 `src/aot/ir_generator.zig`
    - 实现 SSA 寄存器分配
    - 实现基本块管理
    - 实现源位置信息传递
    - _Requirements: 2.1, 2.4, 2.6_

  - [x] 4.2 实现表达式 IR 生成
    - 实现字面量 IR 生成
    - 实现变量访问 IR 生成
    - 实现二元/一元运算 IR 生成
    - 实现函数调用 IR 生成
    - 实现数组/对象操作 IR 生成
    - _Requirements: 2.1, 2.2, 2.3_

  - [x] 4.3 实现语句 IR 生成
    - 实现赋值语句 IR 生成
    - 实现 if/while/for/foreach IR 生成
    - 实现 try-catch-finally IR 生成
    - 实现函数/类定义 IR 生成
    - 实现 echo/return IR 生成
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

  - [x] 4.4 实现常量折叠优化
    - 在 IR 生成时识别常量表达式
    - 计算常量表达式的值
    - 替换为常量 IR 节点
    - _Requirements: 2.5, 8.1_

  - [x] 4.5 编写 IR 生成属性测试
    - **Property 2: IR SSA 正确性**
    - **Validates: Requirements 2.6**
    - **Property 4: 常量折叠正确性**
    - **Validates: Requirements 2.5, 8.1**
    - **Property 9: 源位置信息保留**
    - **Validates: Requirements 2.4, 11.2**
    - ✅ All 12 property tests passed (100 iterations each)

- [x] 5. Checkpoint - IR 生成完成
  - 确保所有测试通过
  - 验证 `--dump-ir` 输出正确的 IR
  - 如有问题请询问用户

- [x] 6. 运行时库
  - [x] 6.1 实现 PHP Value 运行时类型
    - 创建 `src/aot/runtime_lib.zig`
    - 实现 `PHPValue` 结构和内存布局
    - 实现值创建函数 (int, float, string, array, object)
    - 实现类型转换函数
    - _Requirements: 5.1, 5.2_

  - [x] 6.2 实现引用计数 GC
    - 实现 `php_gc_retain` 和 `php_gc_release`
    - 实现自动内存释放
    - _Requirements: 5.3_

  - [x] 6.3 实现数组运行时操作
    - 实现 `php_array_create`, `php_array_get`, `php_array_set`
    - 实现 `php_array_push`, `php_array_count`
    - _Requirements: 5.1, 6.6_

  - [x] 6.4 实现字符串运行时操作
    - 实现 `php_string_concat`, `php_string_length`
    - 实现字符串插值支持
    - _Requirements: 5.1, 6.7_

  - [x] 6.5 实现 I/O 和内置函数
    - 实现 `php_echo`, `php_print`
    - 实现 `php_builtin_strlen`, `php_builtin_count`
    - 实现 `php_builtin_var_dump`
    - _Requirements: 5.1_

  - [x] 6.6 实现异常处理运行时
    - 实现 `php_throw`, `php_catch`, `php_has_exception`
    - 实现堆栈跟踪生成
    - _Requirements: 5.4, 6.4, 11.4_

  - [x] 6.7 编写运行时库属性测试
    - **Property 7: 运行时库类型转换正确性**
    - **Validates: Requirements 5.2**
    - **Property 8: 垃圾回收正确性**
    - **Validates: Requirements 5.3**
    - ✅ All 11 property tests passed (100 iterations each)

- [x] 7. Checkpoint - 运行时库完成
  - 确保所有测试通过
  - 验证运行时库可以独立编译
  - 如有问题请询问用户


- [x] 8. LLVM 代码生成
  - [x] 8.1 设置 LLVM 集成
    - 创建 `src/aot/codegen.zig`
    - 配置 LLVM C API 绑定
    - 初始化 LLVM 上下文、模块、构建器
    - 配置目标机器
    - _Requirements: 4.1, 4.2, 4.3_

  - [x] 8.2 实现类型映射
    - 将 IR 类型映射到 LLVM 类型
    - 定义 PHPValue 的 LLVM 结构类型
    - 定义函数类型
    - _Requirements: 4.1_

  - [x] 8.3 实现运行时函数声明
    - 声明所有运行时库函数
    - 设置正确的调用约定
    - _Requirements: 4.6_

  - [x] 8.4 实现指令代码生成
    - 实现算术运算代码生成
    - 实现比较运算代码生成
    - 实现内存操作代码生成
    - 实现函数调用代码生成
    - 实现 Phi 节点代码生成
    - _Requirements: 4.4, 4.5_

  - [x] 8.5 实现控制流代码生成
    - 实现基本块和跳转
    - 实现条件分支
    - 实现循环结构
    - _Requirements: 6.3_

  - [x] 8.6 实现安全检查代码生成
    - 生成数组边界检查
    - 生成空指针检查
    - _Requirements: 12.1, 12.2_

  - [x] 8.7 实现调试信息生成
    - 生成 DWARF 调试信息
    - 保留源代码行号映射
    - _Requirements: 11.1, 11.2, 11.3_

  - [x] 8.8 编写代码生成属性测试
    - **Property 6: 安全检查有效性**
    - **Validates: Requirements 12.1, 12.2**

- [ ] 9. 静态链接器
  - [ ] 9.1 实现目标代码输出
    - 创建 `src/aot/linker.zig`
    - 实现 LLVM 目标代码生成
    - 写入临时目标文件
    - _Requirements: 4.1_

  - [ ] 9.2 实现运行时库编译
    - 将运行时库编译为静态库
    - 支持不同目标平台的运行时库
    - _Requirements: 5.5, 9.2_

  - [ ] 9.3 实现链接器调用
    - 根据目标平台选择链接器
    - 配置静态链接参数
    - 生成最终可执行文件
    - _Requirements: 1.5, 5.5, 9.3_

  - [ ] 9.4 实现死代码消除
    - 分析使用的运行时函数
    - 只链接必要的代码
    - _Requirements: 5.6, 8.2_

  - [ ] 9.5 编写链接器属性测试
    - **Property 10: 死代码消除正确性**
    - **Validates: Requirements 8.2**

- [ ] 10. Checkpoint - 代码生成完成
  - 确保所有测试通过
  - 验证可以生成可执行文件
  - 如有问题请询问用户

- [ ] 11. AOT 编译器主入口
  - [ ] 11.1 实现 AOTCompiler 结构
    - 创建 `src/aot/compiler.zig`
    - 实现编译选项解析
    - 实现目标平台配置
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

  - [ ] 11.2 实现编译流水线
    - 集成解析器
    - 集成类型推断
    - 集成 IR 生成
    - 集成代码生成
    - 集成链接器
    - _Requirements: 1.1_

  - [ ] 11.3 实现错误处理
    - 收集编译错误
    - 格式化错误输出
    - 设置正确的退出码
    - _Requirements: 1.6, 7.1, 7.2, 7.3_

  - [ ] 11.4 实现调试输出
    - 实现 `--dump-ast` 功能
    - 实现 `--dump-ir` 功能
    - 实现 `--verbose` 功能
    - _Requirements: 7.4, 7.5, 7.6_

- [ ] 12. 多文件项目支持
  - [ ] 12.1 实现文件依赖解析
    - 解析 include/require 语句
    - 构建文件依赖图
    - 检测循环依赖
    - _Requirements: 10.1, 10.3_

  - [ ] 12.2 实现多文件编译
    - 编译所有依赖文件
    - 合并符号表
    - 生成单一可执行文件
    - _Requirements: 10.5_

  - [ ] 12.3 编写多文件编译测试
    - 测试 include/require 解析
    - 测试循环依赖检测
    - _Requirements: 10.1, 10.3_

- [ ] 13. 优化器
  - [ ] 13.1 实现 IR 优化 Pass
    - 实现死代码消除
    - 实现函数内联 (小函数)
    - 实现类型特化
    - _Requirements: 8.2, 8.3, 8.4_

  - [ ] 13.2 配置 LLVM 优化
    - 根据优化级别配置 LLVM Pass
    - 实现 release-small 优化
    - 实现 release-fast 优化
    - _Requirements: 8.5, 8.6_

- [ ] 14. Checkpoint - 优化器完成
  - 确保所有测试通过
  - 验证优化不改变程序行为
  - 如有问题请询问用户

- [ ] 15. 端到端集成测试
  - [ ] 15.1 编写编译执行往返测试
    - **Property 1: 编译执行往返正确性**
    - **Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7**

  - [ ] 15.2 编写错误报告测试
    - **Property 5: 错误报告完整性**
    - **Validates: Requirements 7.1, 7.2, 7.3**

  - [ ] 15.3 编写跨平台测试
    - 测试 Linux 目标编译
    - 测试 macOS 目标编译
    - 测试 Windows 目标编译
    - _Requirements: 4.2, 4.3, 9.1_

  - [ ] 15.4 编写性能基准测试
    - 比较编译后与解释执行的性能
    - 比较不同优化级别的效果
    - _Requirements: 8.5, 8.6_

- [ ] 16. 文档和示例
  - [ ] 16.1 更新 README
    - 添加 AOT 编译功能说明
    - 添加使用示例
    - 添加支持的目标平台列表

  - [ ] 16.2 创建示例 PHP 文件
    - 创建简单的 Hello World 示例
    - 创建函数和类示例
    - 创建数组和字符串操作示例

- [ ] 17. Final Checkpoint - 功能完成
  - 确保所有测试通过
  - 验证所有需求已实现
  - 如有问题请询问用户

## Notes

- 所有任务都是必需的，包括测试任务
- 每个任务引用了具体的需求编号以便追溯
- Checkpoint 任务用于确保增量验证
- 属性测试验证核心正确性属性
- 单元测试验证具体示例和边界情况
