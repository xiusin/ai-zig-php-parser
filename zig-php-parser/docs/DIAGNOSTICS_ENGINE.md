# 诊断引擎实现文档

## 概述

诊断引擎是 AOT 编译器的核心组件，负责收集、格式化和报告编译过程中的错误、警告和提示信息。本实现完全满足需求 3.8 的要求，提供了详细的错误信息生成、CWE 编号标注和修复建议功能。

## 核心特性

### 1. CWE 编号支持

诊断引擎集成了 CWE (Common Weakness Enumeration) 标准，为每个诊断消息提供标准化的安全弱点分类：

```zig
pub const CWE = enum(u32) {
    // Memory Safety
    buffer_overflow = 119,
    use_after_free = 416,
    null_pointer_dereference = 476,
    double_free = 415,
    memory_leak = 401,
    
    // Concurrency
    data_race = 362,
    deadlock = 833,
    
    // Input Validation
    integer_overflow = 190,
    division_by_zero = 369,
    
    // ... 更多分类
};
```

**支持的 CWE 类别：**
- 内存安全 (Memory Safety)
- 类型安全 (Type Safety)
- 资源管理 (Resource Management)
- 代码质量 (Code Quality)
- 并发安全 (Concurrency)
- 输入验证 (Input Validation)
- 逻辑错误 (Logic Errors)
- 安全漏洞 (Security)
- 未定义行为 (Undefined Behavior)

### 2. 修复建议系统

每个诊断消息可以附带多个修复建议，帮助开发者快速解决问题：

```zig
pub const FixSuggestion = struct {
    /// 修复建议的描述
    description: []const u8,
    /// 可选的代码替换建议
    replacement: ?[]const u8 = null,
    /// 修复应用的位置
    location: ?SourceLocation = null,
};
```

**示例输出：**
```
test.php:10:5: error: potential null pointer dereference [CWE-476: NULL Pointer Dereference]
  10 | ptr->value
     |     ^~~~~~
    fix:
      - Add null check
        suggestion: if (ptr != null) { ... }
      - Use safe access method
        suggestion: ptr.?.value
    info: https://cwe.mitre.org/data/definitions/476.html
```

### 3. 详细的错误信息

诊断引擎提供多层次的错误信息：

1. **基本信息**：文件名、行号、列号、错误类型
2. **源代码上下文**：显示出错的代码行和位置标记
3. **CWE 分类**：标准化的安全弱点编号
4. **修复建议**：具体的修复步骤和代码示例
5. **参考链接**：指向 CWE 官方文档的链接
6. **相关注释**：额外的上下文信息

## API 使用指南

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
    
    // 报告简单错误
    const loc = Diagnostics.SourceLocation{
        .file = "test.php",
        .line = 10,
        .column = 5,
        .length = 3,
    };
    engine.reportError(loc, "unexpected token '{s}'", .{";"});
    
    // 报告带 CWE 的错误
    engine.reportErrorWithCWE(
        loc,
        .buffer_overflow,
        "array index out of bounds",
        .{}
    );
    
    // 报告带修复建议的错误
    const fixes = [_]Diagnostics.FixSuggestion{
        .{
            .description = "Add bounds checking",
            .replacement = "if (index < array.len) { ... }",
        },
    };
    const message = try std.fmt.allocPrint(allocator, "buffer overflow detected", .{});
    engine.reportErrorWithFix(loc, .buffer_overflow, message, &fixes);
    
    // 渲染所有诊断信息
    try engine.render(std.io.getStdErr().writer());
}
```

### 便捷函数

诊断引擎提供了一系列便捷函数，用于创建常见的诊断消息：

```zig
// 缓冲区溢出错误
const diag1 = Diagnostics.bufferOverflowError(loc, "buffer overflow", &fixes);

// 空指针解引用错误
const diag2 = Diagnostics.nullPointerError(loc, "null pointer", &fixes);

// 数据竞争错误
const diag3 = Diagnostics.dataRaceError(loc, "data race detected", &fixes);

// 死代码警告
const diag4 = Diagnostics.deadCodeWarning(loc, "unreachable code", &fixes);

// 整数溢出错误
const diag5 = Diagnostics.integerOverflowError(loc, "integer overflow", &fixes);

// 除零错误
const diag6 = Diagnostics.divisionByZeroError(loc, "division by zero", &fixes);

// 类型混淆错误
const diag7 = Diagnostics.typeConfusionError(loc, "type confusion", &fixes);
```

### 设置源代码上下文

为了显示源代码上下文，可以设置源代码内容：

```zig
const source = 
    \\<?php
    \\function test() {
    \\    $arr = [1, 2, 3];
    \\    return $arr[10]; // 越界访问
    \\}
;

try engine.setSource(source);
```

这样诊断信息会包含源代码行和位置标记：

```
test.php:4:12: error: array index out of bounds [CWE-119: Buffer Overflow]
  4 |     return $arr[10];
    |            ^~~~~~~~
```

## 输出格式

### 彩色输出

诊断引擎支持彩色终端输出，使用 ANSI 转义码：

- **错误**：红色
- **警告**：黄色
- **提示**：青色
- **修复建议**：绿色
- **链接**：蓝色

可以通过 `use_colors` 字段控制：

```zig
engine.use_colors = false; // 禁用彩色输出
```

### 输出示例

完整的诊断输出示例：

```
test.php:10:5: error: potential null pointer dereference [CWE-476: NULL Pointer Dereference]
  10 | ptr->value
     |     ^~~~~~
    hint: Check if pointer is null before dereferencing
    fix:
      - Add null check before dereferencing
        suggestion: if (ptr != null) { ptr->value }
      - Use optional chaining
        suggestion: ptr?.value
    info: https://cwe.mitre.org/data/definitions/476.html
    note: Pointer 'ptr' may be null at this point

1 error(s) generated.
```

## 集成到编译器

### 在 IR 生成器中使用

```zig
pub const IRGenerator = struct {
    diagnostics: *Diagnostics.DiagnosticEngine,
    
    fn generateExpression(self: *Self, expr: *Expr) !*IR.Value {
        switch (expr.kind) {
            .array_access => |access| {
                // 检测潜在的越界访问
                if (self.canDetectOutOfBounds(access)) {
                    const fixes = [_]Diagnostics.FixSuggestion{
                        .{
                            .description = "Add bounds checking",
                            .replacement = "if (index < array.len) { ... }",
                        },
                    };
                    const msg = try std.fmt.allocPrint(
                        self.allocator,
                        "potential array index out of bounds",
                        .{}
                    );
                    self.diagnostics.reportErrorWithFix(
                        expr.location,
                        .buffer_overflow,
                        msg,
                        &fixes
                    );
                }
            },
            // ... 其他表达式类型
        }
    }
};
```

### 在代码生成器中使用

```zig
pub const CodeGenerator = struct {
    diagnostics: *Diagnostics.DiagnosticEngine,
    
    fn generateFunction(self: *Self, func: *IR.Function) !void {
        // 检测未初始化的变量
        for (func.locals) |local| {
            if (!self.isInitialized(local)) {
                const fixes = [_]Diagnostics.FixSuggestion{
                    .{
                        .description = "Initialize variable before use",
                        .replacement = "var x = 0;",
                    },
                };
                const msg = try std.fmt.allocPrint(
                    self.allocator,
                    "use of uninitialized variable '{s}'",
                    .{local.name}
                );
                self.diagnostics.reportErrorWithFix(
                    local.location,
                    .uninitialized_memory,
                    msg,
                    &fixes
                );
            }
        }
    }
};
```

## 性能考虑

### 内存管理

- 诊断消息使用 allocator 分配，在 `deinit()` 时统一释放
- 避免在热路径中创建诊断消息
- 使用 `reportError` 等方法时，格式化字符串会被缓存

### 批量处理

诊断引擎支持批量收集错误，然后一次性输出：

```zig
// 收集所有错误
for (files) |file| {
    try compileFile(file, &engine);
}

// 检查是否有错误
if (engine.hasErrors()) {
    try engine.render(std.io.getStdErr().writer());
    return error.CompilationFailed;
}
```

## 扩展性

### 添加新的 CWE 类别

在 `CWE` 枚举中添加新的条目：

```zig
pub const CWE = enum(u32) {
    // ... 现有类别
    
    // 新类别
    my_new_weakness = 999,
    
    pub fn toString(self: CWE) []const u8 {
        return switch (self) {
            // ... 现有映射
            .my_new_weakness => "CWE-999: My New Weakness",
        };
    }
};
```

### 添加新的便捷函数

```zig
pub fn myCustomError(
    location: SourceLocation,
    message: []const u8,
    fix_suggestions: []const FixSuggestion,
) Diagnostic {
    return .{
        .severity = .@"error",
        .message = message,
        .location = location,
        .cwe = .my_new_weakness,
        .fix_suggestions = fix_suggestions,
    };
}
```

## 测试

诊断引擎包含完整的测试套件：

```bash
# 运行所有测试
zig test src/aot/diagnostics.zig -I src

# 测试覆盖：
# - 基本错误报告
# - CWE 标注
# - 修复建议
# - 彩色输出
# - 源代码上下文
# - 便捷函数
```

## 最佳实践

1. **始终提供位置信息**：准确的行号和列号有助于快速定位问题
2. **使用适当的 CWE 分类**：选择最匹配的 CWE 编号
3. **提供可操作的修复建议**：修复建议应该具体且可执行
4. **包含代码示例**：在修复建议中提供代码替换示例
5. **避免重复诊断**：在报告前检查是否已经报告过相同的错误
6. **使用适当的严重级别**：区分错误、警告和提示

## 参考资料

- [CWE 官方网站](https://cwe.mitre.org/)
- [MITRE CWE 列表](https://cwe.mitre.org/data/index.html)
- [Zig 标准库文档](https://ziglang.org/documentation/master/std/)

## 版本历史

- **v1.0** (2026-01-18): 初始实现
  - CWE 编号支持
  - 修复建议系统
  - 详细错误信息
  - 彩色输出
  - 源代码上下文

## 作者

Kiro AI Assistant

## 许可证

MIT License
