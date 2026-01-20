# 编译错误诊断引擎

## 概述

诊断引擎（Diagnostic Engine）是 Zig-PHP AOT 编译器的核心组件，负责收集、格式化和报告编译过程中的错误、警告和提示信息。它提供了详细的错误信息、CWE（Common Weakness Enumeration）编号标注和修复建议，帮助开发者快速定位和修复问题。

**对应任务**: 55. 实现编译错误诊断  
**需求**: 10.6 - 调试和诊断支持

## 核心特性

### 1. 详细错误信息

诊断引擎提供丰富的错误信息，包括：

- **精确的源代码位置**：文件名、行号、列号
- **源代码上下文**：显示出错的代码行和位置标记
- **清晰的错误描述**：易于理解的错误消息
- **相关注释**：关联的其他位置信息

### 2. CWE 编号标注

每个诊断信息都可以关联一个 CWE 编号，帮助开发者了解问题的安全影响：

- **CWE-119**: Buffer Overflow（缓冲区溢出）
- **CWE-416**: Use After Free（释放后使用）
- **CWE-476**: NULL Pointer Dereference（空指针解引用）
- **CWE-362**: Data Race（数据竞争）
- **CWE-401**: Memory Leak（内存泄漏）
- 等等...

每个 CWE 都包含：
- 标准化的编号和名称
- 指向 MITRE CWE 数据库的链接
- 安全影响说明

### 3. 修复建议

诊断引擎可以提供具体的修复建议：

- **描述性建议**：解释如何修复问题
- **代码替换建议**：提供具体的代码示例
- **多个修复方案**：针对同一问题提供不同的解决方案

## 使用方法

### 基本用法

```zig
const std = @import("std");
const Diagnostics = @import("diagnostics.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建诊断引擎
    var engine = Diagnostics.DiagnosticEngine.init(allocator);
    defer engine.deinit();

    // 报告错误
    const loc = Diagnostics.SourceLocation{
        .file = "example.php",
        .line = 42,
        .column = 10,
        .length = 5,
    };

    engine.reportError(loc, "unexpected token '{s}'", .{";"});

    // 检查是否有错误
    if (engine.hasErrors()) {
        // 打印诊断信息到 stderr
        engine.printToStderr();
        return error.CompilationFailed;
    }
}
```

### 带 CWE 的错误报告

```zig
const loc = Diagnostics.SourceLocation{
    .file = "unsafe.php",
    .line = 15,
    .column = 8,
};

// 报告带 CWE 的错误
engine.reportErrorWithCWE(
    loc,
    .buffer_overflow,
    "unchecked array access may cause buffer overflow",
    .{}
);
```

### 带修复建议的错误报告

```zig
const loc = Diagnostics.SourceLocation{
    .file = "unsafe.php",
    .line = 15,
    .column = 8,
    .length = 10,
};

// 创建修复建议
const fix1 = Diagnostics.FixSuggestion{
    .description = "Add bounds checking before array access",
    .replacement = "if (index >= 0 && index < array.length) { ... }",
};

const fix2 = Diagnostics.FixSuggestion{
    .description = "Use safe array access method",
    .replacement = "array.get(index) ?? default_value",
};

const fixes = [_]Diagnostics.FixSuggestion{ fix1, fix2 };

const message = try std.fmt.allocPrint(
    allocator,
    "array index out of bounds",
    .{}
);

engine.reportErrorWithFix(
    loc,
    .buffer_overflow,
    message,
    &fixes
);
```

### 带源代码上下文的诊断

```zig
// 设置源代码
const source =
    \\<?php
    \\function test($arr, $index) {
    \\    return $arr[$index];  // Potential buffer overflow
    \\}
    \\?>
;

try engine.setSource(source);

// 报告错误（会自动显示源代码上下文）
const loc = Diagnostics.SourceLocation{
    .file = "test.php",
    .line = 3,
    .column = 12,
    .length = 12,
};

engine.reportError(loc, "unchecked array access", .{});

// 渲染诊断信息（包含源代码上下文）
var buf: [4096]u8 = undefined;
var fbs = std.io.fixedBufferStream(&buf);
try engine.render(fbs.writer());

const output = fbs.getWritten();
std.debug.print("{s}\n", .{output});
```

输出示例：

```
test.php:3:12: error: unchecked array access [CWE-119: Buffer Overflow]
  3 |     return $arr[$index];  // Potential buffer overflow
    |            ^~~~~~~~~~~~
    hint: Add bounds checking before array access
    fix:
      - Add bounds checking before array access
        suggestion: if ($index >= 0 && $index < count($arr)) { return $arr[$index]; }
    info: https://cwe.mitre.org/data/definitions/119.html

1 error(s) generated.
```

### 带相关注释的诊断

```zig
const main_loc = Diagnostics.SourceLocation{
    .file = "test.php",
    .line = 20,
    .column = 5,
};

const note1_loc = Diagnostics.SourceLocation{
    .file = "test.php",
    .line = 10,
    .column = 1,
};

const note2_loc = Diagnostics.SourceLocation{
    .file = "lib.php",
    .line = 5,
    .column = 10,
};

const note1 = Diagnostics.Diagnostic.Note{
    .message = "variable '$ptr' allocated here",
    .location = note1_loc,
};

const note2 = Diagnostics.Diagnostic.Note{
    .message = "variable '$ptr' freed here",
    .location = note2_loc,
};

const notes = [_]Diagnostics.Diagnostic.Note{ note1, note2 };

const message = try std.fmt.allocPrint(
    allocator,
    "use after free: variable '$ptr' accessed after being freed",
    .{}
);

try engine.diagnostics.append(allocator, .{
    .severity = .@"error",
    .message = message,
    .location = main_loc,
    .cwe = .use_after_free,
    .notes = &notes,
});

engine.error_count += 1;
```

## 便捷函数

诊断引擎提供了一系列便捷函数，用于创建常见类型的诊断信息：

### 内存安全诊断

```zig
// 缓冲区溢出
const diag1 = Diagnostics.bufferOverflowError(
    loc,
    "buffer overflow detected",
    &fixes
);

// 空指针解引用
const diag2 = Diagnostics.nullPointerError(
    loc,
    "null pointer dereference",
    &fixes
);

// 内存泄漏
const diag3 = Diagnostics.memoryLeakWarning(
    loc,
    "potential memory leak",
    &fixes
);
```

### 并发安全诊断

```zig
// 数据竞争
const diag4 = Diagnostics.dataRaceError(
    loc,
    "data race detected",
    &fixes
);

// 死锁
// (使用 reportErrorWithCWE 和 CWE.deadlock)
```

### 代码质量诊断

```zig
// 死代码
const diag5 = Diagnostics.deadCodeWarning(
    loc,
    "unreachable code",
    &fixes
);
```

### 数值安全诊断

```zig
// 整数溢出
const diag6 = Diagnostics.integerOverflowError(
    loc,
    "integer overflow",
    &fixes
);

// 除零错误
const diag7 = Diagnostics.divisionByZeroError(
    loc,
    "division by zero",
    &fixes
);
```

### 类型安全诊断

```zig
// 类型混淆
const diag8 = Diagnostics.typeConfusionError(
    loc,
    "type confusion",
    &fixes
);
```

## 支持的 CWE 类型

诊断引擎支持以下 CWE 类型：

### 内存安全

- **CWE-119**: Buffer Overflow（缓冲区溢出）
- **CWE-416**: Use After Free（释放后使用）
- **CWE-476**: NULL Pointer Dereference（空指针解引用）
- **CWE-415**: Double Free（双重释放）
- **CWE-401**: Memory Leak（内存泄漏）
- **CWE-457**: Use of Uninitialized Variable（使用未初始化变量）

### 类型安全

- **CWE-843**: Type Confusion（类型混淆）
- **CWE-1287**: Improper Type Validation（不当类型验证）

### 资源管理

- **CWE-400**: Resource Exhaustion（资源耗尽）
- **CWE-404**: Improper Resource Shutdown（不当资源关闭）

### 代码质量

- **CWE-561**: Dead Code（死代码）

### 并发

- **CWE-362**: Data Race（数据竞争）
- **CWE-833**: Deadlock（死锁）

### 输入验证

- **CWE-20**: Improper Input Validation（不当输入验证）
- **CWE-190**: Integer Overflow（整数溢出）
- **CWE-369**: Division by Zero（除零）

### 逻辑错误

- **CWE-682**: Incorrect Calculation（错误计算）
- **CWE-193**: Off-by-one Error（差一错误）

### 安全

- **CWE-94**: Code Injection（代码注入）
- **CWE-22**: Path Traversal（路径遍历）

### 未定义行为

- **CWE-758**: Undefined Behavior（未定义行为）

## API 参考

### DiagnosticEngine

主要的诊断引擎类。

#### 方法

- `init(allocator: Allocator) DiagnosticEngine`  
  创建新的诊断引擎实例

- `deinit(self: *DiagnosticEngine) void`  
  释放诊断引擎资源

- `setSource(self: *DiagnosticEngine, source: []const u8) !void`  
  设置源代码，用于显示上下文

- `reportError(self: *DiagnosticEngine, location: SourceLocation, comptime fmt: []const u8, args: anytype) void`  
  报告错误

- `reportErrorWithCWE(self: *DiagnosticEngine, location: SourceLocation, cwe: CWE, comptime fmt: []const u8, args: anytype) void`  
  报告带 CWE 的错误

- `reportErrorWithFix(self: *DiagnosticEngine, location: SourceLocation, cwe: CWE, message: []const u8, fix_suggestions: []const FixSuggestion) void`  
  报告带修复建议的错误

- `reportWarning(self: *DiagnosticEngine, location: SourceLocation, comptime fmt: []const u8, args: anytype) void`  
  报告警告

- `reportWarningWithCWE(self: *DiagnosticEngine, location: SourceLocation, cwe: CWE, comptime fmt: []const u8, args: anytype) void`  
  报告带 CWE 的警告

- `reportNote(self: *DiagnosticEngine, location: SourceLocation, comptime fmt: []const u8, args: anytype) void`  
  报告提示信息

- `hasErrors(self: *const DiagnosticEngine) bool`  
  检查是否有错误

- `hasWarnings(self: *const DiagnosticEngine) bool`  
  检查是否有警告

- `count(self: *const DiagnosticEngine) usize`  
  获取诊断信息总数

- `clear(self: *DiagnosticEngine) void`  
  清除所有诊断信息

- `render(self: *const DiagnosticEngine, writer: anytype) !void`  
  渲染诊断信息到指定的 writer

- `printToStderr(self: *const DiagnosticEngine) void`  
  打印诊断信息到 stderr

### SourceLocation

源代码位置信息。

```zig
pub const SourceLocation = struct {
    file: []const u8 = "<unknown>",
    line: u32 = 0,
    column: u32 = 0,
    length: u32 = 1,
};
```

### FixSuggestion

修复建议。

```zig
pub const FixSuggestion = struct {
    description: []const u8,
    replacement: ?[]const u8 = null,
    location: ?SourceLocation = null,
};
```

### Diagnostic

单个诊断信息。

```zig
pub const Diagnostic = struct {
    severity: Severity,
    message: []const u8,
    location: SourceLocation,
    cwe: ?CWE = null,
    hint: ?[]const u8 = null,
    fix_suggestions: []const FixSuggestion = &.{},
    notes: []const Note = &.{},

    pub const Note = struct {
        message: []const u8,
        location: ?SourceLocation = null,
    };
};
```

### Severity

诊断严重程度。

```zig
pub const Severity = enum {
    note,
    warning,
    @"error",
};
```

## 最佳实践

### 1. 始终提供精确的位置信息

```zig
// 好的做法
const loc = SourceLocation{
    .file = "example.php",
    .line = 42,
    .column = 10,
    .length = 5,  // 标记长度
};

// 避免
const loc = SourceLocation{
    .file = "example.php",
    // 缺少行号和列号
};
```

### 2. 为安全相关的错误添加 CWE

```zig
// 好的做法
engine.reportErrorWithCWE(
    loc,
    .buffer_overflow,
    "unchecked array access",
    .{}
);

// 避免（对于安全问题）
engine.reportError(loc, "unchecked array access", .{});
```

### 3. 提供具体的修复建议

```zig
// 好的做法
const fix = FixSuggestion{
    .description = "Add bounds checking before array access",
    .replacement = "if (index >= 0 && index < array.length) { ... }",
};

// 避免
const fix = FixSuggestion{
    .description = "Fix the error",  // 太模糊
};
```

### 4. 使用相关注释提供上下文

```zig
// 好的做法
const note = Diagnostic.Note{
    .message = "variable '$ptr' allocated here",
    .location = alloc_loc,
};

// 在主诊断中包含注释
```

### 5. 设置源代码以显示上下文

```zig
// 好的做法
try engine.setSource(source_code);
engine.reportError(loc, "error message", .{});

// 这样会显示源代码行和位置标记
```

### 6. 在编译结束时检查错误

```zig
// 好的做法
if (engine.hasErrors()) {
    engine.printToStderr();
    return error.CompilationFailed;
}
```

### 7. 使用便捷函数

```zig
// 好的做法
const diag = Diagnostics.bufferOverflowError(loc, message, &fixes);

// 而不是手动构造
const diag = Diagnostic{
    .severity = .@"error",
    .message = message,
    .location = loc,
    .cwe = .buffer_overflow,
    .fix_suggestions = &fixes,
};
```

## 集成示例

### 在编译器中集成

```zig
pub const Compiler = struct {
    allocator: Allocator,
    diagnostics: *DiagnosticEngine,

    pub fn init(allocator: Allocator) !*Compiler {
        const self = try allocator.create(Compiler);
        
        const diagnostics = try allocator.create(DiagnosticEngine);
        diagnostics.* = DiagnosticEngine.init(allocator);
        
        self.* = .{
            .allocator = allocator,
            .diagnostics = diagnostics,
        };
        
        return self;
    }

    pub fn deinit(self: *Compiler) void {
        self.diagnostics.deinit();
        self.allocator.destroy(self.diagnostics);
        self.allocator.destroy(self);
    }

    pub fn compile(self: *Compiler, source: []const u8) !void {
        // 设置源代码
        try self.diagnostics.setSource(source);

        // 编译过程...
        // 遇到错误时报告
        if (error_detected) {
            const loc = SourceLocation{ ... };
            self.diagnostics.reportError(loc, "error message", .{});
        }

        // 检查是否有错误
        if (self.diagnostics.hasErrors()) {
            self.diagnostics.printToStderr();
            return error.CompilationFailed;
        }
    }
};
```

## 测试

诊断引擎包含全面的测试套件：

```bash
# 运行所有诊断引擎测试
zig test src/aot/test_diagnostics_comprehensive.zig

# 运行基本测试
zig test src/aot/diagnostics.zig
```

测试覆盖：
- 基本错误报告
- CWE 编号标注
- 修复建议
- 源代码上下文显示
- 相关注释
- 便捷函数
- 内存安全诊断
- 并发安全诊断
- 清除和重用
- 颜色输出控制

## 性能考虑

1. **内存分配**：诊断信息使用 allocator 分配，确保在 deinit 时释放
2. **延迟渲染**：诊断信息只在需要时才渲染，避免不必要的字符串操作
3. **批量报告**：可以收集多个诊断信息后一次性渲染

## 未来改进

1. **国际化支持**：支持多语言错误消息
2. **IDE 集成**：提供 LSP 兼容的诊断格式
3. **自动修复**：实现自动应用修复建议的功能
4. **诊断分组**：按文件或类型分组显示诊断信息
5. **严重程度过滤**：允许过滤特定严重程度的诊断信息

## 参考资料

- [CWE - Common Weakness Enumeration](https://cwe.mitre.org/)
- [Zig 错误处理](https://ziglang.org/documentation/master/#Errors)
- [编译器诊断最佳实践](https://clang.llvm.org/diagnostics.html)

## 相关文档

- [AOT 编译器实现](AOT_OPTIMIZER_IMPLEMENTATION.md)
- [调试信息生成](AOT_DEBUG_INFO_IMPLEMENTATION.md)
- [技术参考](TECHNICAL_REFERENCE.md)
