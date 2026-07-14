# PHP-Zig AOT 编译器 — CodeGraph 知识图谱

> **生成日期**: 2026-07-02
> **CodeGraph 索引统计**: 370 文件 / 7,620 节点 / 10,894 边
> **Zig 版本**: 0.15.2 / 0.16.0

---

## 一、全项目概览

### 1.1 技术栈

| 维度 | 内容 |
|------|------|
| 主语言 | Zig (342 文件) |
| 测试脚本语言 | PHP (26 文件) |
| 其他 | Python (1), YAML (1) |
| 外部依赖 | PCRE2 |
| 目标 | PHP 8.5 AOT 编译器（Zig 后端生成 Native 可执行文件） |

### 1.2 三大执行模式

```
┌─────────────────────────────────────────────────────┐
│                    PHP Source                         │
│                        │                             │
│              ┌─────────┴─────────┐                   │
│              ▼                   ▼                    │
│        Interpreter              AOT Compiler          │
│    ┌─────────────────┐    ┌─────────────────┐        │
│    │ Tree Walking     │    │ AST → IR → Opt  │        │
│    │ Bytecode VM      │    │ → CodeGen → Bin │        │
│    │ FastVM (nanbox)  │    └─────────────────┘        │
│    │ JIT (hotspot)    │                               │
│    └─────────────────┘                                │
└─────────────────────────────────────────────────────┘
```

---

## 二、模块架构图

### 2.1 模块依赖关系（来自 `build.zig`）

```
                    ┌─────────────┐
                    │  shared     │
                    │  (nanbox    │
                    │   types)    │
                    └──────┬──────┘
                           │ imports compiler
                           ▼
┌─────────────┐    ┌─────────────┐    ┌──────────────┐
│  extension   │◄───│  compiler   │◄───│   runtime    │
│  (api/reg)   │    │  parser     │    │  vm/gc/value │
└─────────────┘    │  lexer/ast  │    │  builtins    │
                   └─────────────┘    │  coroutine   │
                           ▲          │  stdlib      │
                    ┌──────┴──────┐   └──────┬───────┘
                    │  bytecode   │          │
                    │  vm/gen     │          │
                    └──────┬──────┘          │
                           │                 │
                    ┌──────┴──────┐          │
                    │    jit      │◄─────────┘
                    │  codegen/   │
                    │  hotspot/   │
                    │  asm/       │
                    └─────────────┘

                           ┌─────────────┐
                           │    aot      │
                           │  compiler   │
                           │  ir/opt     │
                           │  codegen/   │
                           │  linker/    │
                           │  native_    │
                           │  linker/    │
                           └─────────────┘
```

### 2.2 模块导出符号表

| 模块 | 入口文件 | 符号数 | 核心类型 |
|------|---------|-------|---------|
| compiler | `src/compiler/mod.zig` | 14 | Node, Token, Parser, PHPContext, SyntaxMode |
| runtime | `src/runtime/mod.zig` | 51 | Value, PHPString, PHPArray, PHPObject, VM |
| aot | `src/aot/root.zig` | 105 | AOTCompiler, IR, TypeInferencer, CodeGen |
| bytecode | `src/bytecode/mod.zig` | 10 | Bytecode, VM, Generator, Optimizer |
| jit | `src/jit/mod.zig` | 11 | JITCompiler, CodeGen, Assembler, Hotspot |
| extension | `src/extension/mod.zig` | 8 | API, Registry |
| config | `src/config/root.zig` | 5 | ConfigLoader |
| shared | `src/shared/mod.zig` | 9 | NaNBox types, Time compat |
| gc | `src/gc/generational_gc.zig` | 8 | GenerationalGC |

---

## 三、全部源文件清单（按模块分组）

### 3.1 核心入口

| 文件 | 符号数 | 作用 |
|------|-------|------|
| `src/main.zig` | 28 | CLI 入口，协调 AOT/解释器模式 |
| `build.zig` | 4 | 构建脚本，定义模块依赖 |
| `debug_aot.zig` | 47 | AOT 调试辅助 |
| `src/builtins.zig` | 6 | 内置函数注册 |
| `src/root.zig` | 10 | 项目根导出 |

### 3.2 Compiler 模块（前端）- `src/compiler/`

| 文件 | 符号数 | 作用 |
|------|-------|------|
| `ast.zig` | 9 | AST 节点定义 |
| `parser.zig` | 11 | 递归下降解析器 |
| `token.zig` | 3 | Token 类型定义 |
| `lexer.zig` | 7 | 词法分析器 |
| `syntax_mode.zig` | 9 | PHP/Go 语法模式 |
| `escape_analysis.zig` | 18 | 逃逸分析 |
| `keyword_lookup.zig` | 6 | 关键字查找表 |
| `parameter_optimizer.zig` | 12 | 参数优化 |
| `register_alloc.zig` | 8 | 寄存器分配 |
| `root.zig` | 11 | 编译器中端入口 |
| `mod.zig` | 14 | 模块统一入口 |

### 3.3 Runtime 模块（运行时）- `src/runtime/`

| 文件 | 符号数 | 作用 |
|------|-------|------|
| `vm.zig` | 123 | 虚拟机主循环 |
| `types.zig` | 42 | 核心值类型系统 |
| `mod.zig` | 51 | 模块统一入口 |
| `gc.zig` | 27 | 垃圾回收核心 |
| `coroutine.zig` | 26 | 协程系统 |
| `fn_dispatch.zig` | 40 | 函数分发 |
| **`stdlib_string.zig`** | **92** | 字符串标准库 |
| **`stdlib_array.zig`** | **77** | 数组标准库 |
| **`stdlib_math.zig`** | **64** | 数学标准库 |
| **`builtin_io.zig`** | **83** | IO 内置函数 |
| **`builtin_vars.zig`** | **99** | 超全局变量内置函数 |
| `builtin_math.zig` | 11 | 数学内置函数 |
| `builtin_time.zig` | 15 | 时间内置函数 |
| `concurrency.zig` | 19 | 并发支持 |
| `async_io.zig` | 23 | 异步 IO |
| `channel.zig` | 5 | 通道 |
| `fast_vm.zig` | 17 | FastVM 高性能执行器 |
| `fast_value.zig` | 28 | FastVM NaN-boxed 值 |
| `memory.zig` | 14 | 内存管理 |
| `object_pool.zig` | 5 | 对象池 |
| `scheduler.zig` | 12 | 调度器 |
| `http_client.zig` | 11 | HTTP 客户端 |
| `http_server.zig` | 31 | HTTP 服务器 |
| `pcre2.zig` | 46 | PCRE2 正则封装 |
| `database.zig` | 20 | 数据库接口 |

#### 3.3.1 Runtime Core 子系统 - `src/runtime/core/`

| 文件 | 符号数 | 作用 |
|------|-------|------|
| `aot_adapter.zig` | 43 | AOT 运行时适配 |
| `math_functions.zig` | 32 | 核心数学函数 |
| `string_functions.zig` | 28 | 核心字符串函数 |
| `json_functions.zig` | 21 | JSON 函数 |
| `time_functions.zig` | 20 | 时间函数 |
| `type_functions.zig` | 20 | 类型操作函数 |
| `random_functions.zig` | 19 | 随机数函数 |
| `root.zig` | 18 | 核心模块入口 |
| `common.zig` | 8 | 公共工具函数 |
| `vm_adapter.zig` | 6 | VM 适配层 |

### 3.4 AOT 模块（提前编译）- `src/aot/`

| 文件 | 符号数 | 作用 |
|------|-------|------|
| `compiler.zig` | 32 | AOT 编译器主入口（AOTCompiler struct） |
| `root.zig` | **105** | AOT 模块统一导出 |
| `ir.zig` | 18 | IR 指令集定义 |
| `ir_generator.zig` | 37 | AST → IR 生成器 |
| `optimizer.zig` | 22 | IR 优化器 |
| `codegen.zig` | 8 | 代码生成器 |
| `linker.zig` | 20 | 静态链接器 |
| `runtime_lib.zig` | **169** | AOT 运行时库 |
| `runtime_lib_template.zig` | **1,081** | AOT 运行时模板（最大文件） |
| `native_linker.zig` | 15 | 原生代码链接器 |
| `type_inference.zig` | 22 | 类型推断 |
| `type_inference_pass.zig` | 6 | 类型推断 Pass |
| `type_specialization_pass.zig` | 5 | 类型特化 Pass |
| `type_specializer.zig` | 9 | 类型特化器 |
| `type_constraint_solver.zig` | 8 | 类型约束求解 |
| `symbol_table.zig` | 13 | 符号表 |
| `diagnostics.zig` | 19 | 诊断/错误收集 |
| `call_graph.zig` | 14 | 调用图分析 |
| `data_flow.zig` | 13 | 数据流分析 |
| `escape_analysis.zig` | 8 | 逃逸分析 (AOT) |
| `liveness_analysis.zig` | 4 | 活跃性分析 |
| `bounds_check.zig` | 11 | 边界检查消除 |
| `constant_folder.zig` | 19 | 常量折叠 |
| `devirtualization.zig` | 11 | 去虚化优化 |
| `interprocedural.zig` | 14 | 跨过程优化 |
| `register_allocator.zig` | 6 | 寄存器分配器 |
| `advanced_optimizer.zig` | 3 | 高级优化器 |
| `validation_pass.zig` | 7 | IR 验证 Pass |
| `reflection.zig` | 15 | 编译期反射 |
| `incremental_compiler.zig` | 20 | 增量编译器 |
| `multi_file_compiler.zig` | 23 | 多文件编译 |
| `dependency_resolver.zig` | 12 | 依赖解析器 |
| `pgo.zig` | 12 | Profile-Guided 优化 |
| `lto.zig` | 9 | 链接时优化 |
| `nanbox_abi.zig` | 23 | NaN-boxing ABI |
| `analysis.zig` | 19 | IR 分析工具集 |
| `oop_runtime.zig` | 17 | OOP 运行时 |

#### 3.4.1 AOT 运行时组件（代码生成目标）

| 文件 | 符号数 | 作用 |
|------|-------|------|
| **`rt_funcs2.zig`** | **290** | AOT 运行时函数集 2 |
| **`rt_funcs1.zig`** | **273** | AOT 运行时函数集 1 |
| **`rt_io.zig`** | **137** | AOT IO 运行时 |
| **`rt_runtime.zig`** | **119** | AOT 运行时核心 |
| **`rt_funcs3.zig`** | **117** | AOT 运行时函数集 3 |
| **`rt_class.zig`** | **92** | AOT 类运行时 |
| `rt_value.zig` | 47 | AOT 值操作运行时 |
| `rt_array.zig` | 9 | AOT 数组运行时 |
| `rt_string.zig` | 6 | AOT 字符串运行时 |
| `rt_core.zig` | 14 | AOT 核心运行时 |

### 3.5 Bytecode 模块 - `src/bytecode/`

| 文件 | 符号数 | 作用 |
|------|-------|------|
| `vm.zig` | **318** | 字节码虚拟机（最大业务文件） |
| `generator.zig` | 20 | 字节码生成器 |
| `instruction.zig` | 9 | 字节码指令定义 |
| `mod.zig` | 10 | 模块入口 |
| `optimizer.zig` | 11 | 字节码优化器 |
| `register_bytecode_gen.zig` | 11 | 寄存器字节码生成 |
| `jit.zig` | 14 | 字节码 JIT 集成 |
| `root.zig` | 11 | 测试导出 |

### 3.6 JIT 模块 - `src/jit/`

| 文件 | 符号数 | 作用 |
|------|-------|------|
| `compiler.zig` | 21 | JIT 编译器 |
| `codegen_x64.zig` | 13 | x64 代码生成 |
| `root.zig` | 22 | 模块导出 |
| `parallel_compiler.zig` | 15 | 并行编译 |
| `perf_counter.zig` | 14 | 性能计数器 |
| `code_cache.zig` | 9 | 代码缓存 |
| `imports.zig` | 7 | JIT 导入工具 |
| `inline_decision.zig` | 8 | 内联决策 |
| `debug_info.zig` | 9 | 调试信息 |
| `fallback.zig` | 10 | 降级策略 |
| `stack_trace_integration.zig` | 8 | 栈回溯集成 |
| `osr.zig` | 3 | 栈上替换 |
| `simd.zig` | 5 | SIMD 支持 |
| `tiered_compilation.zig` | 3 | 分层编译 |

### 3.7 算法与数据结构 - `src/algorithms/`

| 文件 | 符号数 | 作用 |
|------|-------|------|
| `robin_hood_hashmap.zig` | 4 | Robin Hood 哈希表 |
| `slab_allocator.zig` | 4 | Slab 分配器 |
| `boyer_moore.zig` | 4 | Boyer-Moore 字符串搜索 |

### 3.8 内存管理 - `src/memory/`

| 文件 | 符号数 | 作用 |
|------|-------|------|
| `allocators.zig` | 9 | 分配器实现 |
| `cow.zig` | 5 | Copy-on-Write |

### 3.9 GC - `src/gc/`

| 文件 | 符号数 | 作用 |
|------|-------|------|
| `generational_gc.zig` | 8 | 分代垃圾回收 |

### 3.10 基准测试 - `src/benchmark/`

| 文件 | 符号数 | 作用 |
|------|-------|------|
| `microbench_suite.zig` | 22 | 微基准套件 |
| `string_benchmark_complete.zig` | 17 | 字符串完整基准 |
| `jit_benchmark.zig` | 16 | JIT 基准 |
| `framework.zig` | 11 | 基准测试框架 |
| `regression_detector.zig` | 8 | 性能回归检测 |

### 3.11 分析工具 - `src/profiler/`

| 文件 | 符号数 | 作用 |
|------|-------|------|
| `hotspot_analyzer.zig` | 7 | 热点分析器 |
| `leak_detector.zig` | 5 | 泄漏检测器 |
| `profiler.zig` | 5 | 性能分析器 |
| `regression_detector.zig` | 6 | 回归检测器 |

### 3.12 工具 - `src/tools/`

| 文件 | 符号数 | 作用 |
|------|-------|------|
| `profile_cli.zig` | 11 | 性能分析 CLI |
| `aot_coverage.zig` | 9 | AOT 覆盖率工具 |

---

## 四、AOT 编译器管道详解

```
PHP Source
     │
     ▼
┌─────────────────────┐
│  Lexer (compiler/)   │  Token 化
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│  Parser (compiler/)  │  递归下降 → AST
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│  Type Inference      │  类型推断
│  (aot/type_inference) │  (Hindley-Milner)
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│  IR Generation       │  AST → SSA IR
│  (aot/ir_generator)  │  (Module/Function/BB)
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│  Optimization        │  DCE, ConstFold, LICM,
│  (aot/optimizer)     │  CSE, Inline, Unroll...
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│  Code Generation     │  IR → Zig 源代码
│  (aot/native_linker) │  (最大文件 664KB)
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│  Zig Compilation     │  zig build-exe → Native
│  (aot/compiler.zig) │  可执行文件
└──────────┬──────────┘
           ▼
      可执行文件
```

### 4.1 优化 Pass 管线

```
输入 IR
   │
   ▼
┌──────────────────────────┐
│ Dead Code Elimination    │  (DCE)     ─ 死代码消除
├──────────────────────────┤
│ Constant Folding         │  (CF)     ─ 常量折叠
├──────────────────────────┤
│ Common Subexpr Elim      │  (CSE)    ─ 公共子表达式消除
├──────────────────────────┤
│ Constant Propagation     │  (CP)     ─ 常量传播
├──────────────────────────┤
│ Box/Unbox Elimination    │           ─ 装箱消除
├──────────────────────────┤
│ Type Specialization      │           ─ 类型特化
├──────────────────────────┤
│ Function Inlining        │           ─ 函数内联
├──────────────────────────┤
│ Loop Invariant Code Mot  │  (LICM)   ─ 循环不变量外提
├──────────────────────────┤
│ Loop Unrolling           │           ─ 循环展开
├──────────────────────────┤
│ Strength Reduction       │           ─ 强度削弱
├──────────────────────────┤
│ Mem2Reg                  │           ─ 内存提升至寄存器
├──────────────────────────┤
│ CFG Cleanup              │           ─ 控制流清理
└──────────────────────────┘
   │
   ▼
   优化后 IR
```

---

## 五、关键符号索引（全局查询入口）

### 5.1 顶级函数

| 符号名 | 文件 | 行号 | 作用域 |
|-------|------|------|--------|
| `main` | `src/main.zig` | 172 | CLI 入口 |
| `runAOTCompilation` | `src/main.zig` | 555 | AOT 编译执行 |
| `printUsage` | `src/main.zig` | 20 | CLI 帮助 |

### 5.2 核心结构体

| 符号名 | 文件 | 行号 | 作用 |
|-------|------|------|------|
| `AOTCompiler` | `src/aot/compiler.zig` | 463 | AOT 编译器主结构 |
| `IR.Module` | `src/aot/ir.zig` | — | IR 模块 |
| `IR.Function` | `src/aot/ir.zig` | — | IR 函数 |
| `IR.Instruction` | `src/aot/ir.zig` | — | IR 指令 |
| `IR.Type` | `src/aot/ir.zig` | — | IR 类型 |
| `CodeGenerator` | `src/aot/codegen.zig` | 33 | 代码生成器 |
| `IROptimizer` | `src/aot/optimizer.zig` | — | IR 优化器 |
| `TypeInferencer` | `src/aot/type_inference.zig` | — | 类型推断器 |
| `SymbolTable` | `src/aot/symbol_table.zig` | — | 符号表 |
| `PHPValue` | `src/aot/runtime_lib.zig` | 105 | AOT PHP 值 |
| `PHPArray` | `src/aot/runtime_lib.zig` | — | AOT PHP 数组 |
| `PHPObject` | `src/aot/runtime_lib.zig` | — | AOT PHP 对象 |
| `CompileOptions` | `src/aot/compiler.zig` | 132 | 编译选项 |
| `DiagnosticEngine` | `src/aot/diagnostics.zig` | — | 诊断引擎 |
| `Value` | `src/runtime/types.zig` | — | 运行时值类型 |
| `PHPCaller` | `src/runtime/types.zig` | — | 调用上下文 |
| `ExecutionMode` | `src/runtime/vm.zig` | — | 执行模式 |

### 5.3 超大型文件清单（需谨慎修改）

| 文件 | 大小 | 符号数 | 用途 |
|------|------|--------|------|
| `runtime_lib_template.zig` | 389 KB | 1,081 | AOT 运行时代码模板 |
| `native_linker.zig` | 664 KB | 15 | 原生 Zig 代码生成器 |
| `ir_generator.zig` | 234 KB | 37 | IR 生成器 |
| `optimizer.zig` | 255 KB | 22 | 优化器 |
| `runtime_lib.zig` | — | 169 | AOT 运行时库 |
| `vm.zig` (bytecode) | — | 318 | 字节码虚拟机 |
| `vm.zig` (runtime) | — | 123 | 运行时虚拟机 |
| `rt_funcs2.zig` | — | 290 | AOT 运行时函数集 |
| `rt_funcs1.zig` | — | 273 | AOT 运行时函数集 |

---

## 六、模块依赖关系（`@import` 图）

```
compiler (src/compiler/mod.zig)
  ├── ast, parser, token, lexer
  ├── syntax_mode, escape_analysis
  └── root
      ↓ imports runtime

runtime (src/runtime/mod.zig)
  ├── types, vm, func, opcode, environment  ── 核心运行时
  ├── gc, memory, object_pool               ── 内存管理
  ├── coroutine, concurrency, async_io       ── 并发
  ├── fn_dispatch, fn_table, builtin_*       ── 内置函数
  ├── stdlib_math, stdlib_string, stdlib_*   ── 标准库
  ├── fast_vm, fast_value, fast_runtime      ── 高性能执行
  ├── profiler, debugger, crash_handler      ── 诊断
  ├── bytecode     (addImport)
  ├── jit          (addImport)
  └── extension    (addImport)

aot (src/aot/mod.zig)
  ├── compiler      ── AOTCompiler 主入口
  ├── ir, ir_generator ── IR 系统
  ├── optimizer, codegen, linker ── 后端
  ├── runtime_lib, rt_*         ── 运行时
  ├── type_inference, symbol_table ── 语义分析
  ├── native_linker  ── 原生代码生成
  ├── diagnostics    ── 诊断系统
  └── lto, pgo, reflection    ── 高级优化

bytecode (src/bytecode/mod.zig)
  ├── vm           ── 虚拟机执行引擎
  ├── generator    ── 字节码生成
  ├── optimizer    ── 字节码优化
  └── jit          ── JIT 集成

jit (src/jit/mod.zig)
  ├── compiler     ── JIT 编译器
  ├── codegen_x64  ── x64 代码发射
  ├── assembler_x64/arm64 ── 汇编器
  ├── hotspot_detector  ── 热点检测
  └── tiered_compilation ── 分层编译
```

---

## 七、运行时类型体系

```
Runtime Value (src/runtime/types.zig / src/aot/runtime_lib.zig)
  │
  ├── Null
  ├── Bool (bool)
  ├── Int (i64)
  ├── Float (f64)
  ├── String ([]u8 / PHPString)
  ├── Array (PHPArray)
  ├── Object (PHPObject)
  ├── Resource
  └── Callable (PHPCallable)

Low-level optimizations:
  ├── NaN-Boxing (nanbox_abi.zig) ── 64 位中编码类型+值
  └── FastVM (fast_value.zig)     ── 高性能 NaN-boxed 值
```

---

## 八、测试文件索引

| 测试方向 | 文件 | 类型 |
|---------|------|------|
| AOT IR | `src/aot/test_control_flow_ir.zig` | 单元测试 |
| AOT 优化 | `src/aot/test_optimizer_metrics.zig` | 单元测试 |
| AOT LICM | `src/aot/test_licm.zig` | 单元测试 |
| AOT Loop Unroll | `src/aot/test_loop_unroll.zig` | 单元测试 |
| AOT 运行时 | `src/aot/test_runtime_arrays.zig` | 单元测试 |
| AOT GC | `src/aot/test_runtime_cycle_gc.zig` | 单元测试 |
| AOT 综合 | `src/aot/test_runtime_comprehensive.zig` | 单元测试 |
| AOT OOP | `src/aot/test_oop_runtime.zig` | 单元测试 |
| 运行时函数分派 | `src/runtime/test_fn_dispatch.zig` | 单元测试 |
| 运行时标准库 | `src/runtime/test_stdlib.zig` | 单元测试 |
| PHP 兼容性 | `run_compatibility_tests.sh` | 集成测试 |
| 模糊测试 | `run_fuzzy_test.py` + `fuzzy_scripts/` | 模糊测试 |

---

## 九、CodeGraph 工具配置参考

CodeGraph MCP 服务运行在 stdio 模式，支持以下查询：

```bash
# 当前状态
codegraph status

# 查询符号
codegraph query "AOTCompiler" --kind variable

# 调用链
codegraph callers "main"
codegraph callees "main"

# 影响分析
codegraph impact "src/aot/compiler.zig" -d 2

# 获取上下文
codegraph context "AOT compilation pipeline"

# 文件列表
codegraph files
```

---

## 十、后续 CodeGraph 优化建议

| 优先级 | 建议 | 影响 |
|--------|------|------|
| P1 | 完善 Zig extractor 的树节点类型映射（当前为基础版） | 增加节点精度 |
| P2 | 添加 `callTypes` 和 `importTypes` 的精确映射 | 丰富调用图 |
| P2 | 添加 `getSignature` 的自定义签名提取 | 提升搜索质量 |
| P3 | 添加对 `build.zig` 中模块依赖的自动提取 | 自动维护依赖图 |
| P3 | 对超大文件（native_linker.zig）做分模块拆解后重索引 | 降低单文件复杂度 |

---

## 附录 A：CodeGraph 版本升级注意事项

### ⚠️ 补丁丢失风险

本项目对 CodeGraph 的底层 Zig 支持是通过**直接修改安装目录文件**实现的：
- `/Users/tuoke/.codegraph/versions/v0.9.4/lib/dist/extraction/grammars.js`
- `/Users/tuoke/.codegraph/versions/v0.9.4/lib/dist/extraction/languages/index.js`
- `/Users/tuoke/.codegraph/versions/v0.9.4/lib/dist/extraction/languages/zig.js`

当 CodeGraph 版本升级时（如 `v0.9.4` → `v0.9.5+`），这些补丁文件**会全部丢失**，需要重新打补丁。

### 🔧 升级后恢复步骤

```bash
# 1. 确认新版本路径
ls /Users/tuoke/.codegraph/versions/

# 2. 检查新版本是否已有 Zig 原生支持
grep "'.zig'" /Users/tuoke/.codegraph/versions/v0.9.5/lib/dist/extraction/grammars.js

# 3. 如无原生支持，参考教学文档 docs/codegraph/codegraph-zig-patch-guide.md 重打补丁

# 4. 重新索引
codegraph uninit -f
codegraph init -i -v

# 5. 验证
codegraph status | grep "zig"
```

### ✅ 验证补丁是否有效的快速检查

```bash
# 检查扩展映射
grep "'.zig'" /Users/tuoke/.codegraph/versions/v0.9.4/lib/dist/extraction/grammars.js

# 检查 WASM 语法文件注册
grep "zig:" /Users/tuoke/.codegraph/versions/v0.9.4/lib/dist/extraction/grammars.js

# 检查 extractor 注册
grep "zig" /Users/tuoke/.codegraph/versions/v0.9.4/lib/dist/extraction/languages/index.js

# 检查当前索引中 Zig 文件数
codegraph status 2>&1 | grep "zig"

# 验证 Zig 符号可查询
codegraph query "main" --kind function --limit 3
```
