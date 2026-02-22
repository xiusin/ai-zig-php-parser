//! Multi-File Compiler for AOT Compiler
//!
//! 处理多文件 PHP 项目的编译：
//! 1. 解析文件依赖关系
//! 2. 按依赖顺序编译每个文件
//! 3. 合并所有 IR 模块
//! 4. 生成单个可执行文件

const std = @import("std");
const Allocator = std.mem.Allocator;
const IR = @import("ir.zig");
const IRGenerator = @import("ir_generator.zig").IRGenerator;
const DependencyResolverMod = @import("dependency_resolver.zig");
const DependencyResolver = DependencyResolverMod.DependencyResolver;
const DiagnosticsMod = @import("diagnostics.zig");
const DiagnosticEngine = DiagnosticsMod.DiagnosticEngine;
const CompilerMod = @import("compiler.zig");
const CompileOptions = CompilerMod.CompileOptions;
const NativeLinkerMod = @import("native_linker.zig");
const NativeLinker = NativeLinkerMod.NativeLinker;
const NativeLinkerConfig = NativeLinkerMod.NativeLinkerConfig;
const Target = NativeLinkerMod.Target;
const OptimizeLevel = NativeLinkerMod.OptimizeLevel;

// 导入共享模块
const shared = @import("shared");
const Parser = shared.Parser;
const PHPContext = shared.PHPContext;
const SyntaxMode = shared.SyntaxMode;

/// 编译结果
pub const MultiFileCompileResult = struct {
    success: bool,
    output_path: ?[]const u8,
    files_compiled: usize,
    error_message: ?[]const u8,
};

/// 单个文件的编译结果
const FileCompileResult = struct {
    path: []const u8,
    aot_compiler: *CompilerMod.AOTCompiler,  // 保存编译器实例以保持 module 存活
    success: bool,
    error_message: ?[]const u8,
};

/// 多文件编译器
pub const MultiFileCompiler = struct {
    allocator: Allocator,
    options: CompileOptions,
    diagnostics: *DiagnosticEngine,
    dependency_resolver: *DependencyResolver,
    compiled_files: std.StringHashMap(FileCompileResult),
    merged_module: ?*IR.Module,

    const Self = @This();

    /// 初始化
    pub fn init(
        allocator: Allocator,
        options: CompileOptions,
        diagnostics: *DiagnosticEngine,
    ) !Self {
        return Self{
            .allocator = allocator,
            .options = options,
            .diagnostics = diagnostics,
            .dependency_resolver = try DependencyResolver.init(allocator, diagnostics),
            .compiled_files = std.StringHashMap(FileCompileResult).init(allocator),
            .merged_module = null,
        };
    }

    /// 清理
    pub fn deinit(self: *Self) void {
        self.dependency_resolver.deinit();
        self.allocator.destroy(self.dependency_resolver);
        
        var it = self.compiled_files.iterator();
        while (it.next()) |entry| {
            const compiler = entry.value_ptr.aot_compiler;
            compiler.deinit();
            self.allocator.destroy(compiler);
        }
        self.compiled_files.deinit();
        
        if (self.merged_module) |module| {
            module.deinit();
            self.allocator.destroy(module);
        }
    }

    /// 编译多文件项目
    pub fn compile(self: *Self, entry_file: []const u8, output_path: []const u8) !MultiFileCompileResult {
        // 1. 解析依赖
        if (self.options.verbose) {
            std.debug.print("Resolving dependencies...\n", .{});
        }
        
        try self.dependency_resolver.resolveFile(entry_file);
        const compile_order = try self.dependency_resolver.getCompilationOrder();
        
        if (self.options.verbose) {
            std.debug.print("  Files to compile: {d}\n", .{compile_order.len});
            for (compile_order) |file| {
                std.debug.print("    - {s}\n", .{file});
            }
        }

        // 2. 编译每个文件
        var files_compiled: usize = 0;
        for (compile_order) |file_path| {
            const success = try self.compileFile(file_path);
            if (!success) {
                return MultiFileCompileResult{
                    .success = false,
                    .output_path = null,
                    .files_compiled = files_compiled,
                    .error_message = "compilation failed",
                };
            }
            files_compiled += 1;
        }

        // 3. 合并模块
        if (self.options.verbose) {
            std.debug.print("Merging IR modules...\n", .{});
        }
        
        try self.mergeModules();

        // 4. 生成输出
        if (self.options.verbose) {
            std.debug.print("Generating output...\n", .{});
        }
        
        try self.generateOutput(output_path);

        return MultiFileCompileResult{
            .success = true,
            .output_path = output_path,
            .files_compiled = files_compiled,
            .error_message = null,
        };
    }

    /// 编译单个文件
    fn compileFile(self: *Self, file_path: []const u8) !bool {
        if (self.options.verbose) {
            std.debug.print("  Compiling: {s}\n", .{file_path});
        }

        // 检查是否已编译
        if (self.compiled_files.contains(file_path)) {
            return true;
        }

        // 获取文件节点
        const file_node = self.dependency_resolver.getFileNode(file_path);
        if (file_node == null) {
            self.diagnostics.reportError(
                .{ .file = file_path },
                "file not found in dependency graph",
                .{},
            );
            return false;
        }

        // 获取源码
        const source = file_node.?.source orelse {
            self.diagnostics.reportError(
                .{ .file = file_path },
                "source not loaded",
                .{},
            );
            return false;
        };
        
        // 确保源码是 null-terminated
        const source_z = try self.allocator.dupeZ(u8, source);
        defer self.allocator.free(source_z);

        // 使用共享的 Parser 解析源码
        var context = PHPContext.init(self.allocator);
        defer context.deinit();
        
        const syntax_mode = switch (self.options.syntax_mode) {
            .php => SyntaxMode.php,
            .go => SyntaxMode.go,
        };
        
        var p = try Parser.initWithMode(self.allocator, &context, source_z, syntax_mode);
        defer p.deinit();
        
        const root_index = p.parse() catch |err| {
            self.diagnostics.reportError(
                .{ .file = file_path },
                "parsing failed: {s}",
                .{@errorName(err)},
            );
            return false;
        };
        
        // 构建字符串表
        var string_table = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
        defer {
            for (string_table.items) |s| {
                self.allocator.free(s);
            }
            string_table.deinit(self.allocator);
        }
        
        for (context.string_pool.keys()) |str| {
            const str_copy = try self.allocator.dupe(u8, str);
            try string_table.append(self.allocator, str_copy);
        }
        
        // 使用 AOTCompiler 完整编译流程
        // 创建临时 options，设置不链接（只生成 IR）
        var temp_options = self.options;
        temp_options.link_executable = false;
        
        const aot_compiler = try CompilerMod.AOTCompiler.init(self.allocator, temp_options);
        
        try aot_compiler.setSource(source_z);
        try aot_compiler.setAST(context.nodes.items, string_table.items, root_index);
        
        // 只编译到 IR，不生成可执行文件
        const module_opt = aot_compiler.compileToIR() catch |err| {
            self.diagnostics.reportError(
                .{ .file = file_path },
                "compilation failed: {s}",
                .{@errorName(err)},
            );
            aot_compiler.deinit();
            self.allocator.destroy(aot_compiler);
            return false;
        };
        
        if (module_opt == null) {
            self.diagnostics.reportError(
                .{ .file = file_path },
                "compilation returned null module",
                .{},
            );
            aot_compiler.deinit();
            self.allocator.destroy(aot_compiler);
            return false;
        }
        
        // 保存结果（保存编译器实例以保持 module 存活）
        try self.compiled_files.put(file_path, .{
            .path = file_path,
            .aot_compiler = aot_compiler,
            .success = true,
            .error_message = null,
        });

        return true;
    }

    /// 合并所有模块
    fn mergeModules(self: *Self) !void {
        // 创建合并后的模块
        const merged = try self.allocator.create(IR.Module);
        merged.* = IR.Module.init(self.allocator, "merged", "merged.php");
        self.merged_module = merged;

        // 合并所有文件的 IR
        var it = self.compiled_files.iterator();
        while (it.next()) |entry| {
            const file_result = entry.value_ptr;
            if (!file_result.success) continue;
            
            const source_module = file_result.aot_compiler.ir_module orelse continue;
            
            // 合并函数
            for (source_module.functions.items) |func| {
                try merged.functions.append(self.allocator, func);
            }
            
            // 合并类型定义
            for (source_module.types.items) |type_def| {
                try merged.types.append(self.allocator, type_def);
            }
            
            // 合并全局变量
            for (source_module.globals.items) |global| {
                try merged.globals.append(self.allocator, global);
            }
            
            // 合并字符串表
            for (source_module.string_table.items) |str| {
                try merged.string_table.append(self.allocator, str);
            }
        }

        if (self.options.verbose) {
            std.debug.print("  Merged module has {d} functions\n", .{merged.functions.items.len});
        }
    }

    /// 生成输出文件
    fn generateOutput(self: *Self, output_path: []const u8) !void {
        if (self.merged_module == null) {
            return error.NoMergedModule;
        }

        // 转换 Target 类型
        const target = Target{
            .arch = @enumFromInt(@intFromEnum(self.options.target.arch)),
            .os = @enumFromInt(@intFromEnum(self.options.target.os)),
            .abi = @enumFromInt(@intFromEnum(self.options.target.abi)),
        };
        
        // 转换 OptimizeLevel 类型
        const optimize_level = @as(OptimizeLevel, @enumFromInt(@intFromEnum(self.options.optimize_level)));

        // 使用 NativeLinker 生成可执行文件
        var linker = try NativeLinker.init(
            self.allocator,
            .{
                .target = target,
                .optimize_level = optimize_level,
                .static_link = self.options.static_link,
            },
            self.diagnostics,
        );
        defer linker.deinit();

        // 生成 Zig 代码
        const zig_code = try linker.generateZigCode(self.merged_module.?);
        defer self.allocator.free(zig_code);
        
        // 编译到可执行文件
        try linker.compileToExecutable(zig_code, output_path);
    }
};
