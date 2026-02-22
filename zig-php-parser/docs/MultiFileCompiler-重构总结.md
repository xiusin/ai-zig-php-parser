# MultiFileCompiler 重构总结与后续方案

## 已完成的工作

### 1. 架构简化 ✅
- **从 800+ 行简化到 270 行**
- 移除所有旧的 LLVM 相关代码
- 移除复杂的符号表合并逻辑
- 使用现有的 DependencyResolver 和 NativeLinker

### 2. 核心流程 ✅
```zig
pub fn compile(entry_file, output_path) {
    // 1. 解析依赖
    dependency_resolver.resolveFile(entry_file)
    compile_order = dependency_resolver.getCompilationOrder()
    
    // 2. 编译每个文件
    for (compile_order) |file| {
        compileFile(file)  // 生成 IR.Module
    }
    
    // 3. 合并模块
    mergeModules()  // 合并所有 IR.Module
    
    // 4. 生成输出
    generateOutput(output_path)  // 使用 NativeLinker
}
```

### 3. 修复的问题 ✅
- ArrayList API 兼容性（Zig 0.15.2）
- Target 和 OptimizeLevel 类型转换
- DiagnosticEngine 方法调用
- Module.init 参数
- NativeLinker 配置

## 当前问题

### 核心问题：模块导入限制 ⚠️

**问题描述**：
```zig
// src/aot/multi_file_compiler.zig
const parser = @import("../compiler/parser.zig");  // ❌ 错误：跨模块导入
```

**错误信息**：
```
error: import of file outside module path
error: file exists in modules 'compiler' and 'root'
```

**根本原因**：
- Zig 的模块系统要求严格的模块边界
- `aot` 模块和 `compiler` 模块是独立的
- 无法在 `aot` 中直接导入 `compiler` 的文件

## 解决方案

### 方案 1：在 main.zig 中实现多文件编译（推荐）⭐

**优点**：
- 不需要修改模块结构
- 可以直接使用 Parser 和 AOTCompiler
- 实现简单，风险低

**实现步骤**：

#### Step 1：在 main.zig 中添加多文件编译函数

```zig
// src/main.zig

fn runMultiFileCompilation(
    allocator: std.mem.Allocator,
    options: aot.CompileOptions,
    entry_file: []const u8,
    output_path: []const u8,
) !void {
    // 1. 创建依赖解析器
    var diagnostics = aot.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();
    
    var resolver = try aot.DependencyResolver.init(allocator, &diagnostics);
    defer {
        resolver.deinit();
        allocator.destroy(resolver);
    }
    
    // 2. 解析依赖
    try resolver.resolveFile(entry_file);
    const compile_order = try resolver.getCompilationOrder();
    
    std.debug.print("Files to compile: {d}\n", .{compile_order.len});
    for (compile_order) |file| {
        std.debug.print("  - {s}\n", .{file});
    }
    
    // 3. 编译每个文件
    var modules = std.ArrayList(*aot.IR.Module).init(allocator);
    defer {
        for (modules.items) |module| {
            module.deinit();
            allocator.destroy(module);
        }
        modules.deinit();
    }
    
    for (compile_order) |file_path| {
        std.debug.print("Compiling: {s}\n", .{file_path});
        
        // 读取源文件
        const file_node = resolver.getFileNode(file_path);
        const source = file_node.?.source orelse continue;
        
        // 解析 PHP 代码
        var context = PHPContext.init(allocator);
        defer context.deinit();
        
        var p = try parser.Parser.initWithMode(
            allocator,
            &context,
            source,
            SyntaxMode.php,
        );
        defer p.deinit();
        
        const root_index = try p.parse();
        
        // 构建字符串表
        var string_table = std.ArrayList([]const u8).init(allocator);
        defer {
            for (string_table.items) |s| allocator.free(s);
            string_table.deinit();
        }
        
        for (context.string_pool.items) |str| {
            try string_table.append(try allocator.dupe(u8, str));
        }
        
        // 使用 AOTCompiler 生成 IR
        var compiler = try aot.AOTCompiler.init(allocator, options);
        defer compiler.deinit();
        
        try compiler.setSource(source);
        try compiler.setAST(context.nodes.items, string_table.items, root_index);
        
        const module = try compiler.compileToIR();
        if (module) |m| {
            try modules.append(m);
        }
    }
    
    // 4. 合并模块
    std.debug.print("Merging {d} modules...\n", .{modules.items.len});
    
    const merged = try allocator.create(aot.IR.Module);
    merged.* = aot.IR.Module.init(allocator, "merged", "merged.php");
    defer {
        merged.deinit();
        allocator.destroy(merged);
    }
    
    for (modules.items) |module| {
        for (module.functions.items) |func| {
            try merged.functions.append(allocator, func);
        }
        for (module.types.items) |type_def| {
            try merged.types.append(allocator, type_def);
        }
        for (module.globals.items) |global| {
            try merged.globals.append(allocator, global);
        }
        for (module.string_table.items) |str| {
            try merged.string_table.append(allocator, str);
        }
    }
    
    std.debug.print("Merged module has {d} functions\n", .{merged.functions.items.len});
    
    // 5. 生成可执行文件
    std.debug.print("Generating executable...\n", .{});
    
    var linker = try aot.NativeLinker.init(
        allocator,
        .{
            .target = convertTarget(options.target),
            .optimize_level = convertOptimizeLevel(options.optimize_level),
            .static_link = options.static_link,
        },
        &diagnostics,
    );
    defer linker.deinit();
    
    const zig_code = try linker.generateZigCode(merged);
    defer allocator.free(zig_code);
    
    try linker.compileToExecutable(zig_code, output_path);
    
    std.debug.print("Success: Compiled {d} files to {s}\n", .{
        compile_order.len,
        output_path,
    });
}

fn convertTarget(t: aot.CompilerMod.Target) aot.NativeLinkerMod.Target {
    return .{
        .arch = @enumFromInt(@intFromEnum(t.arch)),
        .os = @enumFromInt(@intFromEnum(t.os)),
        .abi = @enumFromInt(@intFromEnum(t.abi)),
    };
}

fn convertOptimizeLevel(o: aot.CompilerMod.OptimizeLevel) aot.NativeLinkerMod.OptimizeLevel {
    return @enumFromInt(@intFromEnum(o));
}
```

#### Step 2：在 runAOTCompilation 中调用

```zig
fn runAOTCompilation(allocator: std.mem.Allocator, options: aot.CompileOptions) !void {
    // ... 读取源文件 ...
    
    // 检测是否需要多文件编译
    const needs_multi_file = blk: {
        if (std.mem.indexOf(u8, source, "require") != null or
            std.mem.indexOf(u8, source, "include") != null)
        {
            break :blk true;
        }
        break :blk false;
    };

    if (needs_multi_file) {
        std.debug.print("Detected require/include, using multi-file compiler...\n", .{});
        
        const output_path = options.output_file orelse blk: {
            const input = options.input_file;
            if (std.mem.endsWith(u8, input, ".php")) {
                break :blk input[0 .. input.len - 4];
            }
            break :blk input;
        };
        
        try runMultiFileCompilation(allocator, options, options.input_file, output_path);
        return;
    }
    
    // 单文件编译...
}
```

### 方案 2：重构模块结构（长期方案）

**优点**：
- 更清晰的模块边界
- Parser 可以被多个模块使用
- 更好的代码组织

**缺点**：
- 需要大量重构
- 可能影响现有代码
- 风险较高

**实现步骤**：

1. 创建共享模块 `src/shared/`
2. 将 Parser 移到 `src/shared/parser.zig`
3. 更新 build.zig 的模块依赖
4. 更新所有导入路径

### 方案 3：使用回调函数（中间方案）

**优点**：
- 不需要重构模块
- MultiFileCompiler 保持独立
- 灵活性高

**缺点**：
- 接口复杂
- 需要传递大量上下文

**实现**：

```zig
// MultiFileCompiler 接受解析回调
pub const ParseCallback = *const fn (
    allocator: Allocator,
    source: []const u8,
) anyerror!ParseResult;

pub const ParseResult = struct {
    nodes: []const Node,
    string_table: []const []const u8,
    root_index: u32,
};

pub fn compile(
    self: *Self,
    entry_file: []const u8,
    output_path: []const u8,
    parse_callback: ParseCallback,
) !MultiFileCompileResult {
    // 使用回调解析每个文件
    for (compile_order) |file| {
        const result = try parse_callback(self.allocator, source);
        // ...
    }
}
```

## 推荐方案

**立即实施：方案 1（在 main.zig 中实现）**

理由：
1. 实现简单，1-2 小时完成
2. 不需要修改模块结构
3. 可以立即测试多文件编译
4. 风险低，不影响现有功能

**长期规划：方案 2（重构模块结构）**

理由：
1. 更好的代码组织
2. 更清晰的模块边界
3. 便于未来扩展

## 测试计划

### 1. 单元测试
```bash
# 测试依赖解析
./zig-out/bin/php-interpreter --compile tests/aot/require_test.php

# 测试多文件编译
./zig-out/bin/php-interpreter --compile --output=/tmp/multi tests/aot/require_test.php
/tmp/multi
```

### 2. 集成测试
```bash
# 测试复杂依赖
./zig-out/bin/php-interpreter --compile tests/aot/complex_require.php

# 测试循环依赖检测
./zig-out/bin/php-interpreter --compile tests/aot/circular_require.php
```

### 3. 性能测试
```bash
# 测试大型项目
./zig-out/bin/php-interpreter --compile --verbose large_project/index.php
```

## 时间估算

| 任务 | 时间 | 优先级 |
|------|------|--------|
| 实现方案 1 | 1-2 小时 | P0 |
| 测试多文件编译 | 30 分钟 | P0 |
| 修复发现的 bug | 1 小时 | P0 |
| 文档更新 | 30 分钟 | P1 |
| 方案 2 重构 | 4-6 小时 | P2 |

**总计（方案 1）**：3-4 小时

## 后续建议

1. **立即实施方案 1**，让多文件编译功能可用
2. **完善测试用例**，覆盖各种依赖场景
3. **性能优化**：
   - 并行编译独立文件
   - 缓存已编译的模块
   - 增量编译支持
4. **长期规划方案 2**，改善架构

## 相关文件

- `src/aot/multi_file_compiler.zig` - 多文件编译器（已重构）
- `src/aot/dependency_resolver.zig` - 依赖解析器
- `src/aot/native_linker.zig` - 原生链接器
- `src/main.zig` - 主入口（需要添加多文件编译逻辑）
- `tests/aot/require_test.php` - 测试文件
