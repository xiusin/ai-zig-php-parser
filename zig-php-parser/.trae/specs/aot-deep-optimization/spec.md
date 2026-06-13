# AOT 模块深度优化 Spec

## Why
当前 AOT 编译器存在多项核心技术债务：代码生成仅支持单循环的结构化模式导致大部分函数回退到状态机、do-while 循环 phi 节点缺失导致死循环、多维数组 NaN boxing 对齐错误、运行时 PHPValue 24 字节 tagged union 内存开销大、字符串操作性能差、缺少与 PHP 的基准对比。需要全面深度优化以确保编译结果完全正确、运行时性能超过 PHP 原生执行。

## What Changes
- 修复 do-while/while/for 循环的 mem2reg phi 节点生成和 codegen 正确性
- 修复多维数组 NaN boxing 对齐崩溃
- **重构代码生成架构**：支持多循环、嵌套循环的完整结构化代码生成，消除状态机回退
- 实现运行时的 include/require_once 支持（编译期 + 运行时混合）
- 优化 PHPValue 内存布局（方案：NanBox 值类型 8 字节 + 堆分配指针，减少 66% 栈内存）
- 优化字符串操作：SSO（Small String Optimization）、原地拼接缓冲区
- 优化数组操作：Robin Hood hashing（已有实现但未集成）、预分配容量提示
- 优化整数/浮点运算：消除不必要的类型转换，直接生成标量运算
- 实现 PHP 基准测试套件并建立性能回归检测
- 优化引用计数：RC elision 增强、局部变量栈分配
- 补全缺失的运行时函数（implode、字符串索引等）
- 实现编译器自动并行化（独立函数并行编译）
- **BREAKING**: PHPValue 从 24 字节 tagged union 变更为 8 字节 NanBox 值

## Impact
- Affected specs: AOT 编译器核心、运行时系统、内存管理、代码生成
- Affected code: native_linker.zig（重构）、runtime_lib.zig（NanBox 化）、optimizer.zig（增强）、ir_generator.zig（include 处理）、mem2reg/phi 修复、新 benchmark 框架

## ADDED Requirements

### Requirement: PHP 基准测试套件
系统 SHALL 提供一套覆盖 30+ 场景的 PHP 基准测试套件，可比对 AOT 编译结果与原生 PHP 8.x 的性能。

#### Scenario: 循环求和基准
- **WHEN** 运行 sum(10000000) 基准测试
- **THEN** AOT release-fast 编译结果比 PHP 8.x 快 3x 以上

#### Scenario: 斐波那契基准
- **WHEN** 运行 fibonacci(35) 基准测试
- **THEN** AOT release-fast 编译结果比 PHP 8.x 快 5x 以上

#### Scenario: 字符串操作基准
- **WHEN** 运行 10000 次字符串拼接、查找、替换操作
- **THEN** AOT 编译结果比 PHP 8.x 快 2x 以上

#### Scenario: 数组操作基准
- **WHEN** 运行 100000 次数组插入、查找、遍历
- **THEN** AOT 编译结果比 PHP 8.x 快 3x 以上

### Requirement: Include/Require 运行时支持
系统 SHALL 在编译时解析静态 include/require 并将其 IR 合并，同时支持运行时的动态 include/require_once 回退到解释器路径。

#### Scenario: 静态 include 编译合并
- **WHEN** 编译包含 `include 'lib.php'` 的主文件
- **THEN** lib.php 的 IR 自动合并到主模块，无需运行时文件读取

#### Scenario: 动态 include 运行时回退
- **WHEN** AOT 程序执行 `include $dynamic_path . '.php'`
- **THEN** 回退到解释器路径执行动态 include，并输出 warning

#### Scenario: require_once 去重
- **WHEN** 多个文件 require_once 同一文件
- **THEN** 该文件 IR 仅合并一次，重复 require_once 变为空操作

### Requirement: 结构化代码生成多循环重构
系统 SHALL 支持任意复杂度的控制流（多循环、嵌套循环、循环内 if-else）生成结构化 Zig 代码，不依赖状态机回退。

#### Scenario: 双循环函数
- **WHEN** 编译包含两个独立 for 循环的函数
- **THEN** 生成为结构化 for 循环代码，不使用状态机

#### Scenario: 嵌套循环函数
- **WHEN** 编译包含嵌套 for 循环（外层 3 次迭代、内层 5 次迭代）的函数
- **THEN** 生成为嵌套 for 循环代码，内层循环变量正确管理

#### Scenario: 循环+条件混合
- **WHEN** 编译包含循环内 if-else 分支的函数
- **THEN** 分支代码正确内联到循环体中，变量作用域正确

## MODIFIED Requirements

### Requirement: Mem2Reg Phi 节点正确性
系统 SHALL 在所有循环类型（do-while、while、for）的 header 块正确插入 phi 节点，确保循环变量在每次迭代时正确更新。

#### Scenario: do-while 循环变量更新
- **WHEN** 编译 `do { $n = $n + 1; } while ($n <= 3);`
- **THEN** 输出 1, 2, 3，而非死循环

#### Scenario: while 循环变量更新
- **WHEN** 编译 `while ($i < 10) { $i++; }`
- **THEN** 循环正确执行 10 次后退出

#### Scenario: for 循环变量更新
- **WHEN** 编译 `for ($i = 0; $i < 5; $i++) { echo $i; }`
- **THEN** 输出 0, 1, 2, 3, 4

### Requirement: PHPValue NanBox 内存优化
系统 SHALL 将 PHPValue 从 24 字节 tagged union 迁移到 8 字节 NaN-boxed 表示，整数和简单类型内联在 8 字节中，字符串/数组/对象使用指针堆分配。

#### Scenario: 整数运算零堆分配
- **WHEN** 执行 `$a = 1; $b = 2; $c = $a + $b;`
- **THEN** 三个变量均为栈上 8 字节值，无堆分配

#### Scenario: 函数参数传递
- **WHEN** 调用 `add(1, 2)` 传递整数参数
- **THEN** 参数通过寄存器传递，无堆分配无引用计数开销

### Requirement: 多维数组对齐修复
系统 SHALL 确保所有 NaN-boxed 指针在 decodePtr 时返回正确对齐的地址，消除多维数组访问的 alignment panic。

#### Scenario: 多维数组赋值
- **WHEN** 执行 `$matrix[$i][$j] = $value;`
- **THEN** 正常运行不崩溃，值正确存储

### Requirement: 运行时函数补全
系统 SHALL 实现所有常用 PHP 运行时函数的 AOT 版本，包括 implode、字符串索引访问、array_keys、array_values 等。

#### Scenario: implode 字符串连接
- **WHEN** 执行 `implode(',', ['a', 'b', 'c'])`
- **THEN** 返回 "a,b,c"

#### Scenario: 字符串索引访问
- **WHEN** 执行 `$str = "hello"; echo $str[1];`
- **THEN** 输出 "e"

### Requirement: 字符串操作优化
系统 SHALL 实现 SSO（Small String Optimization，24 字节以内字符串内联）和 StringBuilder 原地拼接模式，消除频繁字符串拼接的重复分配。

#### Scenario: 短字符串内联
- **WHEN** 创建长度 <= 24 字节的字符串
- **THEN** 不进行堆分配，字符串数据内联在 PHPString 结构体内

#### Scenario: 循环内字符串拼接
- **WHEN** 在循环中执行 10000 次 `$s .= "x"`
- **THEN** 使用 StringBuilder 批量扩容，分配次数 O(log n) 而非 O(n)

### Requirement: 算术运算优化
系统 SHALL 在编译期识别纯整数/浮点运算路径，避免 PHPValue 类型分派和转换开销。

#### Scenario: 纯整数循环累加
- **WHEN** 编译 `for ($i = 0; $i < N; $i++) { $sum += $i; }`
- **THEN** 代码生成使用原生 i64 运算，无类型分派无 ref_count 操作

#### Scenario: 混合类型算术
- **WHEN** 编译 `$a = 1; $b = 2.5; $c = $a + $b;`
- **THEN** 正确将 int 提升为 float 后执行 f64 加法

### Requirement: 引用计数优化增强
系统 SHALL 扩展 escape analysis 支持跨基本块分析、增强局部变量栈分配、消除更多冗余 retain/release。

#### Scenario: 局部数组不逃逸
- **WHEN** 编译函数内创建数组并仅用于读取
- **THEN** 消除 retain/release 调用，必要时栈分配数组

#### Scenario: 函数返回值优化
- **WHEN** 编译函数返回新创建的字符串
- **THEN** 通过返回值转移所有权而非 retain+release