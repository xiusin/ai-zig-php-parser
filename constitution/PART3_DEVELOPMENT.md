# 第三部分：开发流程与质量标准

## 7. 开发流程

### 7.1 需求分析阶段

#### 7.1.1 需求文档模板

```markdown
# 功能需求文档

## 1. 功能概述
- 功能名称：
- 功能描述：
- 优先级：P0/P1/P2/P3
- 预期完成时间：

## 2. 技术分析
- 涉及模块：
- 技术难点：
- 性能影响：
- 兼容性影响：

## 3. 设计方案
- 算法选择：
- 数据结构：
- 接口设计：
- 性能预期：

## 4. 风险评估
- 技术风险：
- 性能风险：
- 兼容性风险：
- 时间风险：

## 5. 测试计划
- 单元测试：
- 集成测试：
- 性能测试：
- 回归测试：
```

#### 7.1.2 复杂度评估

**复杂度等级**:
- **简单** (< 200行): 单代理实现
- **中等** (200-500行): 单代理实现 + 审查
- **复杂** (500-1000行): 多代理协作
- **极复杂** (> 1000行): 多代理协作 + 分阶段实现

**评估标准**:
```zig
pub const ComplexityLevel = enum {
    simple,      // 明确的算法实现
    medium,      // 需要设计数据结构
    complex,     // 涉及多个模块交互
    very_complex // 核心架构修改
};

pub fn assessComplexity(task: Task) ComplexityLevel {
    var score: u32 = 0;
    
    // 代码量
    if (task.estimated_lines > 1000) score += 3
    else if (task.estimated_lines > 500) score += 2
    else if (task.estimated_lines > 200) score += 1;
    
    // 模块数量
    if (task.affected_modules > 5) score += 2
    else if (task.affected_modules > 2) score += 1;
    
    // 性能影响
    if (task.performance_critical) score += 2;
    
    // 架构影响
    if (task.affects_core_architecture) score += 3;
    
    return switch (score) {
        0...2 => .simple,
        3...5 => .medium,
        6...8 => .complex,
        else => .very_complex,
    };
}
```

### 7.2 设计阶段

#### 7.2.1 设计文档模板

```markdown
# 设计文档

## 1. 架构设计

### 1.1 模块划分
```
┌─────────────────────────────────────┐
│ Module A                             │
│ ├─ Component 1                       │
│ ├─ Component 2                       │
│ └─ Component 3                       │
└─────────────────────────────────────┘
```

### 1.2 接口设计
```zig
pub const Interface = struct {
    pub fn method1(self: *Interface, param: Type) !ReturnType;
    pub fn method2(self: *Interface) void;
};
```

### 1.3 数据结构设计
```zig
pub const DataStructure = struct {
    field1: Type1,
    field2: Type2,
};
```

## 2. 算法设计

### 2.1 算法选择
- 算法名称：
- 时间复杂度：
- 空间复杂度：
- 选择理由：

### 2.2 伪代码
```
function algorithm(input):
    step 1
    step 2
    return result
```

### 2.3 优化策略
- 缓存优化：
- SIMD优化：
- 并行优化：

## 3. 性能分析

### 3.1 性能预期
- 操作延迟：
- 吞吐量：
- 内存占用：

### 3.2 性能瓶颈
- 瓶颈1：
- 瓶颈2：

### 3.3 优化方案
- 方案1：
- 方案2：

## 4. 风险分析

### 4.1 技术风险
- 风险描述：
- 影响程度：
- 缓解措施：

### 4.2 性能风险
- 风险描述：
- 影响程度：
- 缓解措施：
```

#### 7.2.2 多代理协作流程

**协作触发条件**:
1. 代码量 > 500行
2. 涉及核心架构修改
3. 性能影响 > 5%
4. 技术方案不确定

**协作流程**:
```
用户需求
    ↓
┌─────────────────────────────────────┐
│ 架构师代理                           │
│ - 分析需求                           │
│ - 设计架构                           │
│ - 制定性能目标                       │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 算法专家代理                         │
│ - 选择算法                           │
│ - 分析复杂度                         │
│ - 设计数据结构                       │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 性能优化代理                         │
│ - 识别瓶颈                           │
│ - 实施优化                           │
│ - 验证性能                           │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 安全审查代理                         │
│ - 检查内存安全                       │
│ - 检查线程安全                       │
│ - 检查边界条件                       │
└─────────────────────────────────────┘
    ↓
反馈给用户审核
```

### 7.3 实现阶段

#### 7.3.1 编码规范

**命名约定**:
```zig
// 类型：PascalCase
pub const MyStruct = struct {};
pub const MyEnum = enum {};

// 函数：camelCase
pub fn myFunction() void {}
pub fn calculateSum() i64 {}

// 变量：snake_case
const my_variable: i32 = 42;
var loop_counter: usize = 0;

// 常量：SCREAMING_SNAKE_CASE
const MAX_SIZE: usize = 1024;
const DEFAULT_TIMEOUT: u64 = 5000;

// 私有成员：前缀下划线
const _internal_state: State = .idle;
fn _helperFunction() void {}
```

**注释规范**:
```zig
/// 函数功能简述（必须）
/// 
/// 详细描述（可选）
/// 
/// 算法: 算法名称（必须）
/// 时间复杂度: O(?)（必须）
/// 空间复杂度: O(?)（必须）
/// 线程安全: ISOLATED/SYNCHRONIZED/LOCK_FREE/UNSAFE（必须）
/// 所有权: OWNING/NON-OWNING/SHARED（必须）
/// 
/// 参数:（必须）
///   - param1: 参数说明
///   - param2: 参数说明
/// 
/// 返回:（必须）
///   - 返回值说明
/// 
/// 错误:（如果有错误）
///   - ErrorType1: 错误说明
///   - ErrorType2: 错误说明
/// 
/// 示例:（推荐）
/// ```zig
/// const result = try function(arg1, arg2);
/// ```
/// 
/// 性能:（性能关键函数必须）
///   - 基准: 15ns/op
///   - 瓶颈: 哈希计算
pub fn function(param1: Type1, param2: Type2) !ReturnType {
    // 实现
}
```

**代码结构**:
```zig
// 1. 导入
const std = @import("std");
const builtin = @import("builtin");

// 2. 类型定义
pub const MyType = struct {
    // 2.1 字段
    field1: Type1,
    field2: Type2,
    
    // 2.2 公共方法
    pub fn publicMethod(self: *MyType) void {}
    
    // 2.3 私有方法
    fn privateMethod(self: *MyType) void {}
};

// 3. 全局函数
pub fn globalFunction() void {}

// 4. 测试
test "test name" {
    // 测试代码
}
```

#### 7.3.2 错误处理

**错误类型定义**:
```zig
pub const Error = error{
    // 内存错误
    OutOfMemory,
    AllocationFailed,
    
    // 类型错误
    TypeError,
    InvalidCast,
    
    // 运行时错误
    DivisionByZero,
    IndexOutOfBounds,
    NullPointer,
    
    // 编译错误
    SyntaxError,
    SemanticError,
    
    // IO错误
    FileNotFound,
    PermissionDenied,
};
```

**错误处理模式**:
```zig
// 1. 传播错误
pub fn function1() !void {
    try function2();  // 传播错误
}

// 2. 捕获错误
pub fn function2() void {
    function3() catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };
}

// 3. 错误联合
pub fn function3() !?Value {
    const result = try operation();
    if (result == null) return null;
    return result;
}

// 4. 错误恢复
pub fn function4() !void {
    operation() catch |err| switch (err) {
        error.OutOfMemory => {
            // 尝试释放内存后重试
            try gc.collect();
            return try operation();
        },
        else => return err,
    };
}
```

### 7.4 测试阶段

#### 7.4.1 单元测试

**测试模板**:
```zig
test "function_name: basic functionality" {
    // Arrange
    const input = 42;
    const expected = 84;
    
    // Act
    const actual = function(input);
    
    // Assert
    try std.testing.expectEqual(expected, actual);
}

test "function_name: edge cases" {
    // 测试边界条件
    try std.testing.expectError(error.DivisionByZero, divide(1, 0));
    try std.testing.expectEqual(0, divide(0, 1));
}

test "function_name: performance" {
    // 性能测试
    const iterations = 1_000_000;
    const start = std.time.nanoTimestamp();
    
    for (0..iterations) |_| {
        _ = function(42);
    }
    
    const end = std.time.nanoTimestamp();
    const ns_per_op = @divTrunc(end - start, iterations);
    
    // 断言性能要求
    try std.testing.expect(ns_per_op < 50);
}
```

**测试覆盖率要求**:
- 核心模块: ≥ 95%
- 一般模块: ≥ 90%
- 工具模块: ≥ 80%

#### 7.4.2 集成测试

```zig
test "integration: lexer + parser" {
    const source = "<?php echo 'Hello'; ?>";
    
    // Lexer
    var lexer = Lexer.init(source);
    const tokens = try lexer.tokenize();
    
    // Parser
    var parser = Parser.init(tokens);
    const ast = try parser.parse();
    
    // 验证AST
    try std.testing.expectEqual(1, ast.statements.len);
    try std.testing.expectEqual(.echo_stmt, ast.statements[0].tag);
}
```

#### 7.4.3 性能测试

```zig
test "performance: hash table lookup" {
    var table = try HashTable.init(allocator);
    defer table.deinit();
    
    // 插入1000个元素
    for (0..1000) |i| {
        const key = try std.fmt.allocPrint(allocator, "key{d}", .{i});
        try table.insert(key, i);
    }
    
    // 测试查找性能
    const iterations = 100_000;
    const start = std.time.nanoTimestamp();
    
    for (0..iterations) |_| {
        _ = table.lookup("key500");
    }
    
    const end = std.time.nanoTimestamp();
    const ns_per_op = @divTrunc(end - start, iterations);
    
    // 断言: 查找 < 20ns
    try std.testing.expect(ns_per_op < 20);
}
```

#### 7.4.4 内存安全测试

```bash
# Valgrind内存检查
valgrind --leak-check=full \
         --show-leak-kinds=all \
         --track-origins=yes \
         ./php-interpreter test.php

# AddressSanitizer
zig build -Doptimize=Debug -fsanitize=address
./zig-out/bin/php-interpreter test.php

# ThreadSanitizer
zig build -Doptimize=Debug -fsanitize=thread
./zig-out/bin/php-interpreter test.php

# MemorySanitizer
zig build -Doptimize=Debug -fsanitize=memory
./zig-out/bin/php-interpreter test.php
```

#### 7.4.5 AOT 输出对比容差规范

> **依据**: [PART1 §4 — AOT 已知限制与测试容差标准](./PART1_ARCHITECTURE.md)

AOT 编译产物与 PHP 解释器在输出格式上存在天然差异。批量测试对比时，**必须**先通过 `normalize_output()` 规范化函数消除以下已知容差，再进行逐行比较：

| 容差编号 | 差异类别 | 规范化处理 | 判定 |
|---------|---------|-----------|------|
| T1 | 栈追踪文件路径/行号不一致 | 去除 `in /path/file.php:NN` 和 `in /path/file.php on line NN` | 不计为错误 |
| T2 | 栈追踪调用链深度差异 | 跳过所有 `#N` 开头的栈帧行及 `thrown in` 行 | 不计为错误 |
| T3 | 浮点数末位精度微差 | 截断到小数点后 12 位（`2.7182818284591` → `2.718281828459`） | 不计为错误 |
| T4 | 输出缩进不一致 | 一律忽略 | 不计为错误 |
| T5 | `microtime`/时间戳精度差异 | AOT 与 PHP 执行时机不同导致 `microtime(true)` 返回值差异，包括 JSON 序列化中浮点时间戳的精度差异（如 `0` vs `0.00002193450927734375`） | 不计为错误 |

**判定流程**:

```
AOT 输出 vs PHP 输出
    ↓
规范化（normalize_output）
    ↓
逐行比较
    ├─ 一致 → PASS
    └─ 不一致 → 检查差异是否属于 T1-T5 容差
        ├─ 是 → 容差，PASS
        └─ 否 → 语义差异，RUNTIME_DIFF（AOT BUG）
```

**强制要求**:
1. 所有 AOT 批量测试脚本必须实现 `normalize_output()` 并覆盖 T1-T3 规范化规则
2. 测试报告中 PASS/RUNTIME_DIFF 判定必须基于规范化后的输出
3. 禁止将语义差异（值不同、逻辑分支不同）归入容差

### 7.4.6 AOT 编译产物命名规范（防误删）

> **目的**: 防止 AOT 编译产物与 PHP 源文件同名导致误删 PHP 源代码

**强制规则**:
- 所有 AOT 编译产物（可执行文件）必须以 `aot_compile_{filename}` 命名
  - `{filename}` 为 PHP 源文件名去掉 `.php` 后缀
  - 示例：`test.php` → 编译产物为 `aot_compile_test`
  - 示例：`f001_arithmetic.php` → 编译产物为 `aot_compile_f001_arithmetic`
- **禁止**编译产物与 PHP 源文件同名（即禁止仅去掉 `.php` 后缀作为产物名）
- **禁止**编译产物覆盖或写入 PHP 源文件路径
- 编译产物的临时 Zig 源码（`.zig` 文件）同样以 `aot_compile_{filename}.zig` 命名

**实现要求**:
- `CompileOptions.getOutputPath()` 默认输出路径必须遵循此命名规范
- 用户显式指定 `output_file` 时不受此限制，但编译器应在产物名与 PHP 源文件同名时发出警告

### 7.4.7 PHP 原始脚本保护铁律

> **性质**: 不可违背的强制规则，优先级最高

**强制规则**:
- **任何时候都不可删除 PHP 的原始脚本文件**（`.php` 文件）
- 无论出于何种目的（测试、清理、重构、产物回收等），均不得删除 `.php` 源文件
- AOT 编译产物清理时，仅可删除符合 §7.4.6 命名规范的可执行文件及临时 `.zig` 文件
- 如需修改 PHP 测试脚本，必须创建新文件或在原文件上修改，不得删除原文件后重建

**适用范围**:
- 项目内所有 `.php` 文件（含 `fuzzy_scripts/`、`fuzzy_scripts_73/`、测试用例等所有目录）
- 无一例外，无任何豁免条件

**违规后果**:
- 违反此规则的任何操作均视为严重事故
- AI 代理在执行任何文件删除操作前，必须校验目标文件扩展名不为 `.php`

### 7.5 审查阶段

#### 7.5.1 代码审查清单

**性能审查**:
- [ ] 算法复杂度是否最优
- [ ] 是否有不必要的内存分配
- [ ] 是否有缓存优化机会
- [ ] 是否有SIMD优化机会
- [ ] 是否有并行优化机会
- [ ] 性能基准测试是否通过
- [ ] 性能回归检测是否通过

**内存安全审查**:
- [ ] 所有权是否明确
- [ ] 是否有内存泄漏
- [ ] 是否有悬空指针
- [ ] 是否有双重释放
- [ ] 是否有缓冲区溢出
- [ ] Valgrind检查是否通过
- [ ] ASan检查是否通过

**线程安全审查**:
- [ ] 线程安全性是否标注
- [ ] 共享状态是否保护
- [ ] 是否有数据竞争
- [ ] 是否有死锁风险
- [ ] 原子操作是否正确
- [ ] TSan检查是否通过

**代码质量审查**:
- [ ] 命名是否规范
- [ ] 注释是否完整
- [ ] 错误处理是否正确
- [ ] 测试覆盖率是否达标
- [ ] 代码是否清晰易懂
- [ ] 是否遵循最佳实践

**AOT 超越特性审查**:
- [ ] 本次变更是否引入了新的 AOT 超越行为（AOT 成功但 PHP 报错的场景）？
- [ ] 已有的超越特性是否被本次变更破坏？
- [ ] 若有新超越特性，宪法 §3 是否已更新？
- [ ] 超越特性的测试脚本是否已添加到 `fuzzy_scripts/pass/` 目录？
- [ ] 超越特性的边界条件是否已验证（字面量生命周期、引用语义、错误路径）？

#### 7.5.2 性能审查工具

```zig
/// 性能审查报告生成器
pub const PerformanceReview = struct {
    benchmarks: []Benchmark,
    baseline: std.StringHashMap(u64),
    
    pub fn generate(self: *PerformanceReview) !Report {
        var report = Report.init(allocator);
        
        for (self.benchmarks) |bench| {
            const result = try bench.run();
            const baseline = self.baseline.get(bench.name);
            
            if (baseline) |b| {
                const regression = @as(f64, @floatFromInt(result.ns_per_op)) / 
                                  @as(f64, @floatFromInt(b)) - 1.0;
                
                if (regression > 0.05) {
                    try report.addRegression(bench.name, regression * 100.0);
                } else if (regression < -0.05) {
                    try report.addImprovement(bench.name, -regression * 100.0);
                }
            }
        }
        
        return report;
    }
    
    pub const Report = struct {
        regressions: std.ArrayList(Regression),
        improvements: std.ArrayList(Improvement),
        
        pub fn print(self: Report) void {
            if (self.regressions.items.len > 0) {
                std.debug.print("⚠️  Performance Regressions:\n", .{});
                for (self.regressions.items) |reg| {
                    std.debug.print("  {s}: +{d:.2}%\n", .{ reg.name, reg.percent });
                }
            }
            
            if (self.improvements.items.len > 0) {
                std.debug.print("✅ Performance Improvements:\n", .{});
                for (self.improvements.items) |imp| {
                    std.debug.print("  {s}: -{d:.2}%\n", .{ imp.name, imp.percent });
                }
            }
        }
    };
};
```

### 7.6 部署阶段

#### 7.6.1 发布检查清单

**功能检查**:
- [ ] 所有测试通过
- [ ] 性能测试通过
- [ ] 内存检查通过
- [ ] 线程安全检查通过
- [ ] 文档更新完成

**性能检查**:
- [ ] 无性能回归
- [ ] 性能目标达成
- [ ] 基准测试通过

**兼容性检查**:
- [ ] PHP 8.5兼容性测试通过
- [ ] 跨平台测试通过
- [ ] 向后兼容性测试通过

**文档检查**:
- [ ] API文档更新
- [ ] 用户文档更新
- [ ] 变更日志更新
- [ ] 迁移指南（如需要）

#### 7.6.2 版本号规范

**语义化版本**:
```
MAJOR.MINOR.PATCH

MAJOR: 不兼容的API修改
MINOR: 向后兼容的功能新增
PATCH: 向后兼容的问题修正
```

**示例**:
- `1.0.0` - 首个稳定版本
- `1.1.0` - 新增JIT编译器
- `1.1.1` - 修复GC bug
- `2.0.0` - 重构IR系统（不兼容）

## 8. 质量保证

### 8.1 自动化测试

#### 8.1.1 CI/CD流程

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.15.2
      
      - name: Build
        run: zig build
      
      - name: Run Tests
        run: zig build test
      
      - name: Run Benchmarks
        run: zig build benchmark
      
      - name: Memory Check
        run: |
          valgrind --leak-check=full \
                   --error-exitcode=1 \
                   ./zig-out/bin/php-interpreter test.php
      
      - name: Coverage Report
        run: zig build coverage
```

#### 8.1.2 性能监控

```zig
/// 持续性能监控
pub const PerformanceMonitor = struct {
    metrics: std.ArrayList(Metric),
    
    pub const Metric = struct {
        name: []const u8,
        timestamp: i64,
        value: u64,
    };
    
    pub fn record(self: *PerformanceMonitor, name: []const u8, value: u64) !void {
        try self.metrics.append(.{
            .name = name,
            .timestamp = std.time.timestamp(),
            .value = value,
        });
    }
    
    pub fn analyze(self: *PerformanceMonitor) !Analysis {
        // 分析性能趋势
        var analysis = Analysis.init(allocator);
        
        // 按名称分组
        var groups = std.StringHashMap(std.ArrayList(u64)).init(allocator);
        defer groups.deinit();
        
        for (self.metrics.items) |metric| {
            var group = groups.get(metric.name) orelse blk: {
                var list = std.ArrayList(u64).init(allocator);
                try groups.put(metric.name, list);
                break :blk list;
            };
            try group.append(metric.value);
        }
        
        // 计算统计信息
        var it = groups.iterator();
        while (it.next()) |entry| {
            const stats = calculateStats(entry.value_ptr.items);
            try analysis.addStats(entry.key_ptr.*, stats);
        }
        
        return analysis;
    }
};
```

### 8.2 质量指标

#### 8.2.1 代码质量指标

| 指标 | 目标 | 测量方法 |
|------|------|---------|
| 测试覆盖率 | ≥ 90% | `zig build coverage` |
| 圈复杂度 | ≤ 10 | 静态分析 |
| 代码重复率 | ≤ 5% | 重复检测工具 |
| 文档覆盖率 | ≥ 95% | 文档检查 |
| 编译警告 | 0 | 编译器输出 |

#### 8.2.2 性能质量指标

| 指标 | 目标 | 测量方法 |
|------|------|---------|
| 性能回归 | ≤ 5% | 回归检测 |
| 内存泄漏 | 0 bytes | Valgrind |
| 数据竞争 | 0 | TSan |
| 缓冲区溢出 | 0 | ASan |
| 未定义行为 | 0 | UBSan |

#### 8.2.3 可靠性指标

| 指标 | 目标 | 测量方法 |
|------|------|---------|
| 崩溃率 | < 0.01% | 崩溃报告 |
| 错误率 | < 0.1% | 错误日志 |
| 可用性 | > 99.9% | 监控系统 |
| MTBF | > 1000小时 | 故障统计 |
| MTTR | < 1小时 | 修复时间 |
