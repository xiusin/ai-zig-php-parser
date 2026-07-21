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
    aot_compiler: *CompilerMod.AOTCompiler, // 保存编译器实例以保持 module 存活
    success: bool,
    error_message: ?[]const u8,
};

/// 多文件编译器
pub const MultiFileCompiler = struct {
    allocator: Allocator,
    io: std.Io,
    cwd: std.Io.Dir,
    options: CompileOptions,
    diagnostics: *DiagnosticEngine,
    dependency_resolver: *DependencyResolver,
    compiled_files: std.StringHashMap(FileCompileResult),
    merged_module: ?*IR.Module,

    const Self = @This();

    /// 初始化
    pub fn init(
        allocator: Allocator,
        io: std.Io,
        cwd: std.Io.Dir,
        options: CompileOptions,
        diagnostics: *DiagnosticEngine,
    ) !Self {
        return Self{
            .allocator = allocator,
            .io = io,
            .cwd = cwd,
            .options = options,
            .diagnostics = diagnostics,
            .dependency_resolver = try DependencyResolver.init(allocator, io, cwd, diagnostics),
            .compiled_files = std.StringHashMap(FileCompileResult).init(allocator),
            .merged_module = null,
        };
    }

    /// 清理
    pub fn deinit(self: *Self) void {
        // 1. 清理 dependency_resolver
        self.dependency_resolver.deinit();
        self.allocator.destroy(self.dependency_resolver);

        // 2. 清理 merged_module
        if (self.merged_module) |module| {
            module.deinit();
            self.allocator.destroy(module);
        }

        // 3. 清理 compiled_files
        var it = self.compiled_files.iterator();
        while (it.next()) |entry| {
            const compiler = entry.value_ptr.aot_compiler;
            compiler.deinit();
            self.allocator.destroy(compiler);
        }
        self.compiled_files.deinit();
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

        // 确保源码是 null-terminated (dupeZ removed in Zig 0.17)
        const source_z = try self.allocator.allocSentinel(u8, source.len, 0);
        @memcpy(source_z[0..source.len], source);
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
        defer string_table.deinit(self.allocator); // 只释放容器，不释放内容（所有权转移给ir_module）

        for (context.string_pool.keys()) |str| {
            const str_copy = try self.allocator.dupe(u8, str);
            try string_table.append(self.allocator, str_copy);
        }

        // 使用 AOTCompiler 完整编译流程
        // 创建临时 options，设置不链接（只生成 IR）
        var temp_options = self.options;
        temp_options.link_executable = false;

        const aot_compiler = try CompilerMod.AOTCompiler.init(self.allocator, self.io, temp_options);

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

        // 维护已见函数名集合（检测多文件间的函数名冲突）
        var seen_func_names = std.StringHashMap(void).init(self.allocator);
        defer seen_func_names.deinit();

        // 合并所有文件的 IR
        var file_idx: usize = 0;
        var it = self.compiled_files.iterator();
        while (it.next()) |entry| {
            const file_result = entry.value_ptr;
            if (!file_result.success) continue;

            const source_module = file_result.aot_compiler.ir_module orelse continue;

            // 创建字符串索引映射
            var string_index_map = std.AutoHashMap(usize, usize).init(self.allocator);
            defer string_index_map.deinit();

            // 该文件的函数名重命名映射（旧名→新名），解决多文件箭头函数/闭包命名冲突
            // 注意：键需要独立分配，因为原函数名会在重命名后被释放
            var rename_map = std.StringHashMap([]const u8).init(self.allocator);
            defer {
                var rit_clean = rename_map.iterator();
                while (rit_clean.next()) |rn_entry| {
                    self.allocator.free(rn_entry.key_ptr.*);
                }
                rename_map.deinit();
            }

            // 合并字符串表并记录映射
            for (source_module.string_table.items, 0..) |str, old_idx| {
                const new_idx = merged.string_table.items.len;
                try merged.string_table.append(self.allocator, str);
                try string_index_map.put(old_idx, new_idx);
            }

            // 记录此文件函数在 merged.functions 中的起始索引
            // 用于后续回溯更新 const_string 中的箭头函数/闭包名引用
            const func_start_idx = merged.functions.items.len;

            // 合并函数并更新字符串索引（转移所有权）
            for (source_module.functions.items) |func| {
                var new_func = func;

                // 检测多文件间函数名冲突：对 __arrow_ 和 __closure_ 前缀的函数
                // 追加文件索引后缀以确保全局唯一
                if (seen_func_names.contains(new_func.name)) {
                    if (std.mem.startsWith(u8, new_func.name, "__arrow_") or
                        std.mem.startsWith(u8, new_func.name, "__closure_"))
                    {
                        const renamed = std.fmt.allocPrint(self.allocator, "{s}_mf{d}", .{ new_func.name, file_idx }) catch new_func.name;
                        // 复制旧名作为 rename_map 的键，因为下方会释放原 new_func.name
                        const old_name_copy = try self.allocator.dupe(u8, new_func.name);
                        try rename_map.put(old_name_copy, renamed);
                        if (self.options.verbose) {
                            std.debug.print("    Renamed: {s} -> {s} (file_idx={d})\n", .{ new_func.name, renamed, file_idx });
                        }
                        if (new_func.name_owned) {
                            self.allocator.free(new_func.name);
                        }
                        new_func.name = renamed;
                        new_func.name_owned = true;
                    }
                }
                try seen_func_names.put(new_func.name, {});

                // 更新函数中的所有 const_string 指令和 call 指令
                for (new_func.blocks.items) |block| {
                    for (block.*.instructions.items) |*inst| {
                        if (inst.*.op == .const_string) {
                            const old_idx = inst.*.op.const_string;
                            if (string_index_map.get(old_idx)) |new_idx| {
                                inst.*.op = .{ .const_string = @intCast(new_idx) };
                            }
                        }
                        // 更新 call 指令中的函数名引用（应用重命名）
                        if (inst.*.op == .call) {
                            const call_op = inst.*.op.call;
                            if (rename_map.get(call_op.func_name)) |renamed| {
                                inst.*.op = .{ .call = .{
                                    .func_name = renamed,
                                    .args = call_op.args,
                                    .return_type = call_op.return_type,
                                } };
                            }
                        }
                    }
                }
                try merged.functions.append(self.allocator, new_func);
            }

            // 回溯更新 const_string 中的箭头函数/闭包名引用
            // 箭头函数/闭包的名字通过 const_string 指令存入字符串表，
            // 再传递给 php_create_closure 作为回调名。
            // 上面重命名只更新了 call 指令的 func_name，未更新 const_string 中的函数名。
            // 此处补全：扫描本文件所有函数中的 const_string 指令，
            // 若其字符串值匹配 rename_map 中的旧名，则更新为新名对应的字符串索引。
            if (rename_map.count() > 0) {
                for (merged.functions.items[func_start_idx..]) |func| {
                    for (func.blocks.items) |block| {
                        for (block.*.instructions.items) |*inst| {
                            if (inst.*.op == .const_string) {
                                const str_idx = inst.*.op.const_string;
                                if (str_idx < merged.string_table.items.len) {
                                    const str_val = merged.string_table.items[str_idx];
                                    if (rename_map.get(str_val)) |new_name| {
                                        if (self.options.verbose) {
                                            std.debug.print("    Updated const_string in func '{s}': '{s}' -> '{s}'\n", .{func.name, str_val, new_name});
                                        }
                                        const new_name_id = try merged.internString(new_name);
                                        inst.*.op = .{ .const_string = new_name_id };
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 合并类型定义（转移所有权）
            for (source_module.types.items) |type_def| {
                try merged.types.append(self.allocator, type_def);
            }

            // 合并全局变量（转移所有权）
            for (source_module.globals.items) |global| {
                try merged.globals.append(self.allocator, global);
            }

            // 清空原始module的容器（所有权已转移，避免双重释放）
            source_module.functions.clearRetainingCapacity();
            source_module.types.clearRetainingCapacity();
            source_module.globals.clearRetainingCapacity();
            source_module.string_table.clearRetainingCapacity();
            file_idx += 1;
        }

        if (self.options.verbose) {
            std.debug.print("  Merged module has {d} functions\n", .{merged.functions.items.len});
            std.debug.print("  Merged string table has {d} entries\n", .{merged.string_table.items.len});
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
        const zig_code = linker.generateZigCode(self.merged_module.?) catch |err| {
            const linker_message = switch (err) {
                //error.TraitMethodConflict =>
                //    "trait method conflict: colliding methods require insteadof/as resolution",
                error.TraitPropertyConflict => "trait property conflict: imported properties are not definition-compatible",
                error.TraitConstantConflict => "trait constant conflict: imported constants are not definition-compatible",
                error.UnknownTraitMethodReference => "trait adaptation error: referenced method was not found in imported traits",
                error.AmbiguousTraitMethodReference => "trait adaptation error: referenced method is ambiguous across imported traits",
                error.TraitNotFound => "trait adaptation error: referenced trait was not found",
                else => @errorName(err),
            };
            self.diagnostics.reportError(
                .{ .file = self.options.input_file },
                "Zig code generation failed: {s}",
                .{linker_message},
            );
            return err;
        };
        defer self.allocator.free(zig_code);

        // 编译到可执行文件
        try linker.compileToExecutable(zig_code, output_path);
    }
};
