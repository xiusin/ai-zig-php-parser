//! Multi-File Compiler for AOT Compiler
//!
//! 处理多文件 PHP 项目的编译：
//! 1. 解析文件依赖关系
//! 2. 按依赖顺序编译每个文件（支持并行编译独立文件）
//! 3. 合并所有 IR 模块
//! 4. 生成单个可执行文件
//!
//! ## Parallel Compilation
//!
//! When `parallel_config.enabled` is true (default):
//! - Files with no mutual dependencies are grouped into "levels"
//! - Within each level, files are compiled in parallel across threads
//! - Levels are processed sequentially (respecting dependency ordering)
//! - Thread count is limited to available CPU cores by default
//!
//! Set `parallel_config.enabled` to false for deterministic sequential compilation.

const std = @import("std");
const Allocator = std.mem.Allocator;
const IR = @import("ir.zig");
const IRGenerator = @import("ir_generator.zig").IRGenerator;
const DependencyResolverMod = @import("dependency_resolver.zig");
const DependencyResolver = DependencyResolverMod.DependencyResolver;
const FileNode = DependencyResolverMod.FileNode;
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

/// 并行编译配置
pub const ParallelConfig = struct {
    /// 是否启用并行编译（设置为 false 可用于调试）
    enabled: bool = true,
    /// 最大线程数（null 表示自动检测 CPU 核心数）
    max_threads: ?usize = null,
};

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

/// 编译工作项 — 包含编译单个文件所需的所有不可变数据
const CompileWorkItem = struct {
    file_path: []const u8,
    source: []const u8,
    options: CompileOptions,
};

/// 并行编译时每个线程的上下文
const ThreadContext = struct {
    /// 线程 ID（0-based）
    thread_id: usize,
    /// 分配给该线程的工作项索引（在 level_files 中的索引）
    work_index: usize,
    /// 文件路径
    file_path: []const u8,
    /// 源码
    source: []const u8,
    /// 编译选项（只读）
    options: CompileOptions,
    /// 线程专属分配器
    arena: *std.heap.ArenaAllocator,
    /// 输出结果 — 由线程写入，主线程读取
    result: ThreadResult,

    const ThreadResult = struct {
        aot_compiler: ?*CompilerMod.AOTCompiler,
        success: bool,
        error_message: ?[]const u8,
        done: bool,
    };
};

/// 一个编译层级：同一层级内的文件无相互依赖，可并行编译
const CompilationLevel = struct {
    files: []const []const u8,
};

/// 多文件编译器
pub const MultiFileCompiler = struct {
    allocator: Allocator,
    options: CompileOptions,
    diagnostics: *DiagnosticEngine,
    dependency_resolver: *DependencyResolver,
    compiled_files: std.StringHashMap(FileCompileResult),
    merged_module: ?*IR.Module,
    /// Set of files whose IR has been merged via include_once/require_once
    /// Used to prevent double-merging of the same included file
    once_merged: std.StringHashMap(void),
    /// 并行编译配置
    parallel_config: ParallelConfig,
    /// 线程安全的诊断互斥锁（并行编译时使用）
    diagnostics_mutex: std.Thread.Mutex,

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
            .once_merged = std.StringHashMap(void).init(allocator),
            .parallel_config = .{},
            .diagnostics_mutex = .{},
        };
    }

    /// 初始化（带并行配置）
    pub fn initWithParallelConfig(
        allocator: Allocator,
        options: CompileOptions,
        diagnostics: *DiagnosticEngine,
        parallel_config: ParallelConfig,
    ) !Self {
        var self = try Self.init(allocator, options, diagnostics);
        self.parallel_config = parallel_config;
        return self;
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

        // 4. 清理 once_merged
        self.once_merged.deinit();
    }

    /// 编译多文件项目
    pub fn compile(self: *Self, entry_file: []const u8, output_path: []const u8) !MultiFileCompileResult {
        // 1. 解析依赖
        if (self.options.verbose) {
            std.debug.print("Resolving dependencies...\n", .{});
        }
        
        try self.dependency_resolver.resolveFile(entry_file);

        // 检查循环依赖
        if (self.dependency_resolver.hasCircularDependencies()) {
            const cycles = self.dependency_resolver.getCircularDependencies();
            for (cycles) |cycle| {
                const cycle_strs: [][]const u8 = @constCast(cycle.cycle);
                self.diagnostics.reportError(
                    .{ .file = cycle.start_file },
                    "circular dependency detected in include chain",
                    .{},
                );
                if (self.options.verbose) {
                    std.debug.print("  Circular dependency cycle:\n", .{});
                    for (cycle_strs) |f| {
                        std.debug.print("    -> {s}\n", .{f});
                    }
                }
            }
            return MultiFileCompileResult{
                .success = false,
                .output_path = null,
                .files_compiled = 0,
                .error_message = "circular dependency detected in include chain",
            };
        }

        const compile_order = try self.dependency_resolver.getCompilationOrder();
        
        if (self.options.verbose) {
            std.debug.print("  Files to compile: {d}\n", .{compile_order.len});
            for (compile_order) |file| {
                std.debug.print("    - {s}\n", .{file});
            }
        }

        // 2. 编译所有文件（根据配置选择并行或顺序）
        if (self.parallel_config.enabled and compile_order.len > 1) {
            if (self.options.verbose) {
                const max_threads = self.parallel_config.max_threads orelse try std.Thread.getCpuCount();
                std.debug.print("Parallel compilation enabled (max {d} threads)\n", .{max_threads});
            }
            const files_compiled = try self.compileWithParallelism(compile_order);
            if (files_compiled < compile_order.len) {
                return MultiFileCompileResult{
                    .success = false,
                    .output_path = null,
                    .files_compiled = files_compiled,
                    .error_message = "compilation failed",
                };
            }
        } else {
            if (self.options.verbose and !self.parallel_config.enabled) {
                std.debug.print("Parallel compilation disabled — using sequential compilation\n", .{});
            }
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

        const total_compiled = self.compiled_files.count();

        return MultiFileCompileResult{
            .success = true,
            .output_path = output_path,
            .files_compiled = total_compiled,
            .error_message = null,
        };
    }

    // ========================================================================
    // 并行编译实现
    // ========================================================================

    /// 将编译顺序列表分解为可并行的层级
    ///
    /// 算法：基于拓扑排序的 BFS 分层
    ///   - 从已经出现在 compile_order 中的文件构建子图
    ///   - 使用 Kahn's algorithm 对子图分层
    ///   - 每层的文件之间无直接依赖，可以并行编译
    fn computeParallelLevels(
        self: *Self,
        compile_order: []const []const u8,
        allocator: Allocator,
    ) !std.ArrayList(CompilationLevel) {
        var levels = std.ArrayList(CompilationLevel).init(allocator);

        // 构建 compile_order 内的快速查找集合
        var order_set = std.StringHashMap(void).init(allocator);
        defer order_set.deinit();
        for (compile_order) |f| {
            try order_set.put(f, {});
        }

        // 构建入度表（只统计 compile_order 内部的依赖边）
        var in_degree = std.StringHashMap(usize).init(allocator);
        defer in_degree.deinit();

        // 构建反向依赖（谁依赖我）—— 用于 Kahn 算法减入度
        var dependents = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
        defer {
            var dep_it = dependents.iterator();
            while (dep_it.next()) |entry| {
                entry.value_ptr.deinit();
            }
            dependents.deinit();
        }

        // 初始化入度和依赖关系
        for (compile_order) |file| {
            try in_degree.put(file, 0);
            try dependents.put(file, std.ArrayList([]const u8).init(allocator));
        }

        // 计算内部依赖
        for (compile_order) |file| {
            const node = self.dependency_resolver.getFileNode(file);
            if (node == null) continue;

            for (node.?.dependencies.items) |dep| {
                // 只统计在 compile_order 内部的依赖
                if (!order_set.contains(dep)) continue;

                // dep 是 file 的前驱（file 依赖 dep）
                // in_degree[file] += 1
                const current = in_degree.get(file) orelse 0;
                try in_degree.put(file, current + 1);

                // dependents[dep].append(file)
                if (dependents.getPtr(dep)) |dep_list| {
                    try dep_list.append(file);
                }
            }
        }

        // Kahn's algorithm BFS 分层
        // 每一层：当前入度为 0 的所有节点
        var remaining = compile_order.len;
        while (remaining > 0) {
            // 收集当前层（入度为 0 的节点）
            var current_level_files = std.ArrayList([]const u8).init(allocator);

            var it = in_degree.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.* == 0) {
                    try current_level_files.append(entry.key_ptr.*);
                }
            }

            if (current_level_files.items.len == 0) {
                // 没有入度为 0 的节点，但还有剩余节点 → 内部循环依赖
                // 这种情况不应该出现（外层已检查循环依赖），作为安全回退
                // 将剩余节点全部放入一层顺序编译
                var fallback = std.ArrayList([]const u8).init(allocator);
                var fit = in_degree.iterator();
                while (fit.next()) |entry| {
                    if (entry.value_ptr.* > 0) {
                        try fallback.append(entry.key_ptr.*);
                    }
                }
                if (fallback.items.len > 0) {
                    try levels.append(.{ .files = try fallback.toOwnedSlice() });
                    remaining -= fallback.items.len;
                }
                break;
            }

            // 将该层加入结果
            const level_files = try current_level_files.toOwnedSlice();
            try levels.append(.{ .files = level_files });
            remaining -= level_files.len;

            // 标记该层节点已处理（将入度设为极大值，避免重复）
            for (level_files) |f| {
                try in_degree.put(f, std.math.maxInt(usize));
            }

            // 减少后继节点的入度
            for (level_files) |f| {
                if (dependents.get(f)) |dep_list| {
                    for (dep_list.items) |dependent| {
                        const current = in_degree.get(dependent) orelse 0;
                        if (current > 0) {
                            try in_degree.put(dependent, current - 1);
                        }
                    }
                }
            }
        }

        return levels;
    }

    /// 使用层级并行编译所有文件
    fn compileWithParallelism(self: *Self, compile_order: []const []const u8) !usize {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const level_allocator = arena.allocator();

        const levels = try self.computeParallelLevels(compile_order, level_allocator);

        if (self.options.verbose) {
            std.debug.print("  Compilation levels: {d}\n", .{levels.items.len});
            for (levels.items, 0..) |level, i| {
                std.debug.print("    Level {d}: {d} file(s)", .{ i, level.files.len });
                if (level.files.len <= 5) {
                    for (level.files) |f| {
                        std.debug.print(" [{s}]", .{std.fs.path.basename(f)});
                    }
                }
                std.debug.print("\n", .{});
            }
        }

        var files_compiled: usize = 0;

        // 逐层编译
        for (levels.items) |level| {
            if (level.files.len == 1) {
                // 单文件层级：直接编译，不创建线程
                const success = try self.compileFile(level.files[0]);
                if (!success) {
                    return files_compiled;
                }
                files_compiled += 1;
            } else {
                // 多文件层级：并行编译
                const compiled = try self.compileLevelParallel(level.files);
                if (compiled < level.files.len) {
                    return files_compiled + compiled;
                }
                files_compiled += compiled;
            }
        }

        return files_compiled;
    }

    /// 并行编译一个层级的所有文件
    fn compileLevelParallel(self: *Self, level_files: []const []const u8) !usize {
        const file_count = level_files.len;

        // 确定线程数
        const max_threads = self.parallel_config.max_threads orelse try std.Thread.getCpuCount();
        const thread_count = @min(file_count, max_threads);

        if (self.options.verbose) {
            std.debug.print("  Parallel level: {d} files, {d} threads\n", .{ file_count, thread_count });
        }

        // 准备每个文件的工作项数据
        var work_items = try self.allocator.alloc(CompileWorkItem, file_count);
        defer self.allocator.free(work_items);

        for (level_files, 0..) |file_path, i| {
            const file_node = self.dependency_resolver.getFileNode(file_path);
            if (file_node == null) {
                return i; // i files compiled before failure
            }
            const source = file_node.?.source orelse {
                return i;
            };

            var temp_options = self.options;
            temp_options.link_executable = false;

            work_items[i] = .{
                .file_path = file_path,
                .source = source,
                .options = temp_options,
            };
        }

        // 创建线程上下文数组
        var contexts = try self.allocator.alloc(ThreadContext, file_count);
        defer self.allocator.free(contexts);

        // 创建每个线程的 arena allocator
        // 使用 thread-safe page_allocator 作为 backing allocator
        var thread_arenas = try self.allocator.alloc(std.heap.ArenaAllocator, file_count);
        defer self.allocator.free(thread_arenas);

        var threads = try self.allocator.alloc(?std.Thread, file_count);
        defer self.allocator.free(threads);
        @memset(threads, null);

        // 初始化上下文和 arena
        for (0..file_count) |i| {
            thread_arenas[i] = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            contexts[i] = .{
                .thread_id = i,
                .work_index = i,
                .file_path = work_items[i].file_path,
                .source = work_items[i].source,
                .options = work_items[i].options,
                .arena = &thread_arenas[i],
                .result = .{
                    .aot_compiler = null,
                    .success = false,
                    .error_message = null,
                    .done = false,
                },
            };
        }

        // 使用工作窃取：将 file_count 个文件分配给 thread_count 个线程
        // 使用原子计数器追踪下一个待处理的工作项索引
        var next_work_index: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

        // 启动工作线程
        for (0..thread_count) |t| {
            const args = try self.allocator.create(WorkerArgs);
            args.* = .{
                .compiler = self,
                .contexts = contexts,
                .next_index = &next_work_index,
                .file_count = file_count,
            };

            threads[t] = try std.Thread.spawn(.{}, workerThreadFn, .{args});
        }

        // 等待所有线程完成
        for (0..thread_count) |t| {
            if (threads[t]) |th| {
                th.join();
            }
        }

        // 收集结果并插入到 compiled_files
        var compiled: usize = 0;
        for (contexts[0..file_count]) |*ctx| {
            if (!ctx.result.success) {
                // 清理已编译的文件（如果有失败）
                if (ctx.result.aot_compiler) |compiler| {
                    compiler.deinit();
                    self.allocator.destroy(compiler);
                }
                return compiled;
            }

            if (ctx.result.aot_compiler) |compiler| {
                try self.compiled_files.put(ctx.file_path, .{
                    .path = ctx.file_path,
                    .aot_compiler = compiler,
                    .success = true,
                    .error_message = null,
                });
            }
            compiled += 1;
        }

        // 清理 arena — 注意：不释放 arena 中分配的对象，aot_compiler 仍持有引用
        // 只释放 arena 元数据结构
        for (0..file_count) |i| {
            // 不调用 arena.deinit()，因为 arena 中的数据已被 aot_compiler 接管
            // 只释放 arena 自身
            _ = thread_arenas[i];
        }

        return compiled;
    }

    /// 工作线程函数：从工作队列获取任务并编译
    fn workerThreadFn(args: *WorkerArgs) void {
        const contexts = args.contexts;
        const file_count = args.file_count;
        const compiler = args.compiler;
        const next_index = args.next_index;
        // 释放 args（由主线程分配，线程不再需要）
        compiler.allocator.destroy(args);

        while (true) {
            // 原子获取下一个工作项索引
            const current = next_index.fetchAdd(1, .monotonic);
            if (current >= file_count) break;

            const ctx = &contexts[current];
            compileFileInThread(ctx, compiler);
        }
    }

    /// 在线程中编译单个文件（与 compileFile 逻辑相同，但使用线程专属 allocator）
    fn compileFileInThread(ctx: *ThreadContext, self: *Self) void {
        defer ctx.result.done = true;

        const file_path = ctx.file_path;
        const source = ctx.source;
        const allocator = ctx.arena.allocator();

        if (self.options.verbose) {
            self.diagnostics_mutex.lock();
            defer self.diagnostics_mutex.unlock();
            std.debug.print("  Compiling [thread {d}]: {s}\n", .{ ctx.thread_id, file_path });
        }

        // 确保源码是 null-terminated
        const source_z = allocator.dupeZ(u8, source) catch {
            self.diagnostics_mutex.lock();
            defer self.diagnostics_mutex.unlock();
            self.diagnostics.reportError(
                .{ .file = file_path },
                "allocation failed for source duplication",
                .{},
            );
            ctx.result.success = false;
            ctx.result.error_message = "allocation failed";
            return;
        };

        // 使用共享的 Parser 解析源码
        var context = PHPContext.init(allocator);
        defer context.deinit();

        const syntax_mode = switch (ctx.options.syntax_mode) {
            .php => SyntaxMode.php,
            .go => SyntaxMode.go,
        };

        var p = Parser.initWithMode(allocator, &context, source_z, syntax_mode) catch {
            self.diagnostics_mutex.lock();
            defer self.diagnostics_mutex.unlock();
            self.diagnostics.reportError(
                .{ .file = file_path },
                "parser initialization failed",
                .{},
            );
            ctx.result.success = false;
            ctx.result.error_message = "parser init failed";
            return;
        };
        defer p.deinit();

        const root_index = p.parse() catch |err| {
            self.diagnostics_mutex.lock();
            defer self.diagnostics_mutex.unlock();
            self.diagnostics.reportError(
                .{ .file = file_path },
                "parsing failed: {s}",
                .{@errorName(err)},
            );
            ctx.result.success = false;
            ctx.result.error_message = "parse failed";
            return;
        };

        // 构建字符串表
        var string_table = std.ArrayList([]const u8).initCapacity(allocator, 0) catch {
            ctx.result.success = false;
            ctx.result.error_message = "allocation failed";
            return;
        };

        for (context.string_pool.keys()) |str| {
            const str_copy = allocator.dupe(u8, str) catch {
                ctx.result.success = false;
                ctx.result.error_message = "allocation failed";
                return;
            };
            string_table.append(allocator, str_copy) catch {
                ctx.result.success = false;
                ctx.result.error_message = "allocation failed";
                return;
            };
        }

        // 使用 AOTCompiler 完整编译流程
        var temp_options = ctx.options;
        temp_options.link_executable = false;

        const aot_compiler = CompilerMod.AOTCompiler.init(allocator, temp_options) catch {
            self.diagnostics_mutex.lock();
            defer self.diagnostics_mutex.unlock();
            self.diagnostics.reportError(
                .{ .file = file_path },
                "compiler initialization failed",
                .{},
            );
            ctx.result.success = false;
            ctx.result.error_message = "compiler init failed";
            return;
        };

        aot_compiler.setSource(source_z) catch {
            aot_compiler.deinit();
            allocator.destroy(aot_compiler);
            ctx.result.success = false;
            ctx.result.error_message = "set source failed";
            return;
        };

        aot_compiler.setAST(context.nodes.items, string_table.items, root_index) catch {
            aot_compiler.deinit();
            allocator.destroy(aot_compiler);
            ctx.result.success = false;
            ctx.result.error_message = "set AST failed";
            return;
        };

        // 只编译到 IR，不生成可执行文件
        const module_opt = aot_compiler.compileToIR() catch |err| {
            self.diagnostics_mutex.lock();
            defer self.diagnostics_mutex.unlock();
            self.diagnostics.reportError(
                .{ .file = file_path },
                "compilation failed: {s}",
                .{@errorName(err)},
            );
            aot_compiler.deinit();
            allocator.destroy(aot_compiler);
            ctx.result.success = false;
            ctx.result.error_message = "compileToIR failed";
            return;
        };

        if (module_opt == null) {
            self.diagnostics_mutex.lock();
            defer self.diagnostics_mutex.unlock();
            self.diagnostics.reportError(
                .{ .file = file_path },
                "compilation returned null module",
                .{},
            );
            aot_compiler.deinit();
            allocator.destroy(aot_compiler);
            ctx.result.success = false;
            ctx.result.error_message = "null module";
            return;
        }

        ctx.result.aot_compiler = aot_compiler;
        ctx.result.success = true;
        ctx.result.error_message = null;
    }

    // ========================================================================
    // 顺序编译回退（与原始逻辑相同）
    // ========================================================================

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
        defer string_table.deinit(self.allocator);  // 只释放容器，不释放内容（所有权转移给ir_module）
        
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

        // 合并所有文件的 IR（同时处理 include_once/require_once 去重）
        var it = self.compiled_files.iterator();
        while (it.next()) |entry| {
            const file_path = entry.key_ptr.*;
            const file_result = entry.value_ptr;
            if (!file_result.success) continue;
            
            const source_module = file_result.aot_compiler.ir_module orelse continue;
            
            // 检查是否需要因为 _once 去重而跳过
            // 如果该文件是通过 include_once 包含的，且已合并过一次，则跳过
            if (self.dependency_resolver.isOnceIncluded(file_path)) {
                if (self.once_merged.contains(file_path)) {
                    // 跳过重复的 include_once 文件
                    if (self.options.verbose) {
                        std.debug.print("  Skipping once-included file (already merged): {s}\n", .{file_path});
                    }
                    continue;
                }
                try self.once_merged.put(file_path, {});
            }
            
            // 创建字符串索引映射
            var string_index_map = std.AutoHashMap(usize, usize).init(self.allocator);
            defer string_index_map.deinit();
            
            // 合并字符串表并记录映射
            for (source_module.string_table.items, 0..) |str, old_idx| {
                const new_idx = merged.string_table.items.len;
                try merged.string_table.append(self.allocator, str);
                try string_index_map.put(old_idx, new_idx);
            }
            
            // 合并函数并更新字符串索引（转移所有权）
            for (source_module.functions.items) |func| {
                const new_func = func;
                // 更新函数中的所有 const_string 和 include/require 指令的字符串索引
                for (new_func.blocks.items) |block| {
                    for (block.*.instructions.items) |*inst| {
                        switch (inst.*.op) {
                            .const_string => {
                                const old_idx = inst.*.op.const_string;
                                if (string_index_map.get(old_idx)) |new_idx| {
                                    inst.*.op = .{ .const_string = @intCast(new_idx) };
                                }
                            },
                            .include => |*inc_op| {
                                // Compile-time include: IR is already merged, transform to nop
                                if (string_index_map.get(inc_op.path_str_id)) |new_idx| {
                                    inc_op.path_str_id = @intCast(new_idx);
                                }
                                inst.*.op = .nop;
                            },
                            .require => |*req_op| {
                                // Compile-time require: IR is already merged, transform to nop
                                if (string_index_map.get(req_op.path_str_id)) |new_idx| {
                                    req_op.path_str_id = @intCast(new_idx);
                                }
                                inst.*.op = .nop;
                            },
                            .include_runtime => |op| {
                                // Runtime include: transform to call to php_include
                                const args = try self.allocator.alloc(IR.Register, 1);
                                args[0] = op.operand;
                                inst.*.op = .{ .call = .{
                                    .func_name = "php_include",
                                    .args = args,
                                    .return_type = .php_value,
                                } };
                            },
                            .require_runtime => |op| {
                                // Runtime require: transform to call to php_require
                                const args = try self.allocator.alloc(IR.Register, 1);
                                args[0] = op.operand;
                                inst.*.op = .{ .call = .{
                                    .func_name = "php_require",
                                    .args = args,
                                    .return_type = .php_value,
                                } };
                            },
                            else => {},
                        }
                    }
                }
                try merged.functions.append(self.allocator, new_func);
            }
            
            // 合并类型定义（转移所有权）
            for (source_module.types.items) |type_def| {
                try merged.types.append(self.allocator, type_def);
            }
            
            // 合并全局变量（转移所有权）
            for (source_module.globals.items) |global| {
                try merged.globals.append(self.allocator, global);
            }

            // 合并 compile_time_includes（更新字符串索引后转移所有权）
            for (source_module.compile_time_includes.items) |inc| {
                try merged.compile_time_includes.append(self.allocator, inc);
            }
            
            // 清空原始module的容器（所有权已转移，避免双重释放）
            source_module.functions.clearRetainingCapacity();
            source_module.types.clearRetainingCapacity();
            source_module.globals.clearRetainingCapacity();
            source_module.string_table.clearRetainingCapacity();
            source_module.compile_time_includes.clearRetainingCapacity();
        }

        if (self.options.verbose) {
            std.debug.print("  Merged module has {d} functions\n", .{merged.functions.items.len});
            std.debug.print("  Merged string table has {d} entries\n", .{merged.string_table.items.len});
            std.debug.print("  Merged compile-time includes: {d}\n", .{merged.compile_time_includes.items.len});
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
                error.TraitPropertyConflict =>
                    "trait property conflict: imported properties are not definition-compatible",
                error.TraitConstantConflict =>
                    "trait constant conflict: imported constants are not definition-compatible",
                error.UnknownTraitMethodReference =>
                    "trait adaptation error: referenced method was not found in imported traits",
                error.AmbiguousTraitMethodReference =>
                    "trait adaptation error: referenced method is ambiguous across imported traits",
                error.TraitNotFound =>
                    "trait adaptation error: referenced trait was not found",
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

// WorkerArgs 定义在 struct 外部以便 workerThreadFn 引用
const WorkerArgs = struct {
    compiler: *MultiFileCompiler,
    contexts: []ThreadContext,
    next_index: *std.atomic.Value(usize),
    file_count: usize,
};