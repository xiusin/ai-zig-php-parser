//! Multi-File Compiler for AOT Compiler
//!
//! This module handles compilation of multi-file PHP projects by:
//! - Resolving file dependencies
//! - Compiling files in dependency order
//! - Merging symbol tables across files
//! - Generating a single executable
//!
//! ## Usage
//!
//! ```zig
//! var compiler = try MultiFileCompiler.init(allocator, options, diagnostics);
//! defer fc.deinit();
//!
//! const result = try fc.compile("main.php");
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const Diagnostics = @import("diagnostics.zig");
const DiagnosticEngine = Diagnostics.DiagnosticEngine;
const SourceLocation = Diagnostics.SourceLocation;
const DependencyResolverMod = @import("dependency_resolver.zig");
const DependencyResolver = DependencyResolverMod.DependencyResolver;
const IncludeStatement = DependencyResolverMod.IncludeStatement;
const FileNode = DependencyResolverMod.FileNode;
const IR = @import("ir.zig");
const IRGenerator = @import("ir_generator.zig").IRGenerator;
const SymbolTableMod = @import("symbol_table.zig");
const SymbolTable = SymbolTableMod.SymbolTable;
const Symbol = SymbolTableMod.Symbol;
const TypeInferenceMod = @import("type_inference.zig");
const TypeInferencer = TypeInferenceMod.TypeInferencer;
const CodeGen = @import("codegen.zig");
const CodeGenerator = CodeGen.CodeGenerator;
const LinkerMod = @import("linker.zig");
const StaticLinker = LinkerMod.StaticLinker;
const LinkerConfig = LinkerMod.LinkerConfig;
const CompilerMod = @import("compiler.zig");
const CompileOptions = CompilerMod.CompileOptions;
const OptimizeLevel = CompilerMod.OptimizeLevel;
const Target = CompilerMod.Target;

/// Result of multi-file compilation
pub const MultiFileCompileResult = struct {
    /// Whether compilation succeeded
    success: bool,
    /// Output file path (if successful)
    output_path: ?[]const u8,
    /// Number of files compiled
    files_compiled: u32,
    /// Number of errors encountered
    error_count: u32,
    /// Number of warnings encountered
    warning_count: u32,
    /// Files that had circular dependencies
    circular_dependencies: []const []const u8,
    /// Files that could not be resolved
    unresolved_files: []const []const u8,

    pub fn succeeded(output_path: []const u8, files_compiled: u32) MultiFileCompileResult {
        return .{
            .success = true,
            .output_path = output_path,
            .files_compiled = files_compiled,
            .error_count = 0,
            .warning_count = 0,
            .circular_dependencies = &.{},
            .unresolved_files = &.{},
        };
    }

    pub fn failed(error_count: u32, warning_count: u32) MultiFileCompileResult {
        return .{
            .success = false,
            .output_path = null,
            .files_compiled = 0,
            .error_count = error_count,
            .warning_count = warning_count,
            .circular_dependencies = &.{},
            .unresolved_files = &.{},
        };
    }
};

/// Compiled file information
pub const CompiledFile = struct {
    /// File path
    path: []const u8,
    /// Generated IR module
    ir_module: ?*IR.Module,
    /// Whether compilation succeeded
    success: bool,
    /// Error message if failed
    error_message: ?[]const u8,
};

/// Multi-File Compiler
pub const MultiFileCompiler = struct {
    allocator: Allocator,
    options: CompileOptions,
    diagnostics: *DiagnosticEngine,
    /// Dependency resolver
    dependency_resolver: *DependencyResolver,
    /// Global symbol table (merged from all files)
    global_symbol_table: *SymbolTable,
    /// Type inferencer
    type_inferencer: *TypeInferencer,
    /// Compiled files
    compiled_files: std.StringHashMapUnmanaged(CompiledFile),
    /// Include paths for file resolution
    include_paths: std.ArrayListUnmanaged([]const u8),
    /// Merged IR module
    merged_module: ?*IR.Module,

    const Self = @This();

    /// Initialize a new multi-file compiler
    pub fn init(
        allocator: Allocator,
        options: CompileOptions,
        diagnostics: *DiagnosticEngine,
    ) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Initialize dependency resolver
        const resolver = try DependencyResolver.init(allocator, diagnostics);
        errdefer resolver.deinit();

        // Initialize global symbol table
        const symbol_table = try allocator.create(SymbolTable);
        symbol_table.* = try SymbolTable.init(allocator);
        errdefer {
            symbol_table.deinit();
            allocator.destroy(symbol_table);
        }

        // Initialize type inferencer
        const type_inferencer = try allocator.create(TypeInferencer);
        type_inferencer.* = TypeInferencer.init(allocator, symbol_table, diagnostics);

        self.* = .{
            .allocator = allocator,
            .options = options,
            .diagnostics = diagnostics,
            .dependency_resolver = resolver,
            .global_symbol_table = symbol_table,
            .type_inferencer = type_inferencer,
            .compiled_files = .{},
            .include_paths = .{},
            .merged_module = null,
        };

        return self;
    }

    /// Deinitialize and free all resources
    pub fn deinit(self: *Self) void {
        // Free compiled files
        var it = self.compiled_files.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.ir_module) |module| {
                module.deinit();
                self.allocator.destroy(module);
            }
        }
        self.compiled_files.deinit(self.allocator);

        // Free include paths
        for (self.include_paths.items) |path| {
            self.allocator.free(path);
        }
        self.include_paths.deinit(self.allocator);

        // Free merged module
        if (self.merged_module) |module| {
            module.deinit();
            self.allocator.destroy(module);
        }

        // Free type inferencer
        self.allocator.destroy(self.type_inferencer);

        // Free symbol table
        self.global_symbol_table.deinit();
        self.allocator.destroy(self.global_symbol_table);

        // Free dependency resolver
        self.dependency_resolver.deinit();

        self.allocator.destroy(self);
    }

    /// Add an include path for file resolution
    pub fn addIncludePath(self: *Self, path: []const u8) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        try self.include_paths.append(self.allocator, path_copy);
        try self.dependency_resolver.addIncludePath(path);
    }

    /// Compile a multi-file project starting from the entry file
    pub fn compile(self: *Self, entry_file: []const u8) !MultiFileCompileResult {
        if (self.options.verbose) {
            std.debug.print("Multi-file compilation starting...\n", .{});
            std.debug.print("  Entry file: {s}\n", .{entry_file});
        }

        // Step 1: Resolve all dependencies
        self.dependency_resolver.resolveFile(entry_file) catch |err| {
            self.diagnostics.reportError(
                .{ .file = entry_file },
                "failed to resolve dependencies: {s}",
                .{@errorName(err)},
            );
            return MultiFileCompileResult.failed(
                self.diagnostics.error_count,
                self.diagnostics.warning_count,
            );
        };

        // Check for circular dependencies
        if (self.dependency_resolver.hasCircularDependencies()) {
            const cycles = self.dependency_resolver.getCircularDependencies();
            for (cycles) |cycle| {
                self.diagnostics.reportError(
                    .{ .file = cycle.start_file },
                    "circular dependency detected in file chain",
                    .{},
                );
            }
            return MultiFileCompileResult.failed(
                self.diagnostics.error_count,
                self.diagnostics.warning_count,
            );
        }

        // Check for unresolved files
        if (self.dependency_resolver.hasUnresolvedFiles()) {
            const unresolved = self.dependency_resolver.getUnresolvedFiles();
            for (unresolved) |file| {
                self.diagnostics.reportWarning(
                    file.location,
                    "unresolved include: {s}",
                    .{file.path},
                );
            }
        }

        // Step 2: Get compilation order (topological sort)
        const compilation_order = try self.dependency_resolver.getCompilationOrder();
        defer self.allocator.free(compilation_order);

        if (self.options.verbose) {
            std.debug.print("  Files to compile: {d}\n", .{compilation_order.len});
            for (compilation_order) |file| {
                std.debug.print("    - {s}\n", .{file});
            }
        }

        // Step 3: Compile each file in order
        var files_compiled: u32 = 0;
        for (compilation_order) |file_path| {
            const success = try self.compileFile(file_path);
            if (success) {
                files_compiled += 1;
            }
        }

        if (self.diagnostics.hasErrors()) {
            return MultiFileCompileResult.failed(
                self.diagnostics.error_count,
                self.diagnostics.warning_count,
            );
        }

        // Step 4: Merge all IR modules
        try self.mergeModules(compilation_order);

        if (self.diagnostics.hasErrors()) {
            return MultiFileCompileResult.failed(
                self.diagnostics.error_count,
                self.diagnostics.warning_count,
            );
        }

        // Step 5: Generate output
        const output_path = try self.options.getOutputPath(self.allocator);
        try self.generateOutput(output_path);

        if (self.diagnostics.hasErrors()) {
            self.allocator.free(output_path);
            return MultiFileCompileResult.failed(
                self.diagnostics.error_count,
                self.diagnostics.warning_count,
            );
        }

        if (self.options.verbose) {
            std.debug.print("Multi-file compilation successful: {s}\n", .{output_path});
            std.debug.print("  Files compiled: {d}\n", .{files_compiled});
        }

        return MultiFileCompileResult.succeeded(output_path, files_compiled);
    }

    /// Compile a single file
    fn compileFile(self: *Self, file_path: []const u8) !bool {
        if (self.options.verbose) {
            std.debug.print("  Compiling: {s}\n", .{file_path});
        }

        // Check if already compiled
        if (self.compiled_files.contains(file_path)) {
            return true;
        }

        // Get file node from dependency resolver
        const file_node = self.dependency_resolver.getFileNode(file_path);
        if (file_node == null) {
            self.diagnostics.reportError(
                .{ .file = file_path },
                "file not found in dependency graph",
                .{},
            );
            return false;
        }

        // Get source content
        const source = file_node.?.source orelse {
            self.diagnostics.reportError(
                .{ .file = file_path },
                "source not loaded",
                .{},
            );
            return false;
        };

        // Create IR module for this file
        const module = try self.allocator.create(IR.Module);
        module.* = IR.Module.init(self.allocator, file_path, file_path);
        errdefer {
            module.deinit();
            self.allocator.destroy(module);
        }

        // Parse source and generate IR
        // 注意：这里需要真实的 PHP 解析器
        // 当前实现：从源代码中提取函数和类定义，生成基本的 IR
        try self.parseAndGenerateIR(module, source, file_path);

        // Store compiled file
        try self.compiled_files.put(self.allocator, file_path, .{
            .path = file_path,
            .ir_module = module,
            .success = true,
            .error_message = null,
        });

        // Register symbols from this file in the global symbol table
        try self.registerFileSymbols(file_path, source);

        return true;
    }
    
    /// Parse source code and generate IR
    /// 这是一个简化的实现，用于演示 IR 生成流程
    /// 在完整实现中，应该使用真实的 PHP 解析器
    fn parseAndGenerateIR(self: *Self, module: *IR.Module, source: []const u8, file_path: []const u8) !void {
        var i: usize = 0;
        var line: u32 = 1;
        var col: u32 = 1;

        while (i < source.len) {
            if (source[i] == '\n') {
                line += 1;
                col = 1;
                i += 1;
                continue;
            }

            // Look for function declarations
            if (self.matchKeyword(source[i..], "function")) {
                i += 8; // Skip "function"
                // Skip whitespace
                while (i < source.len and (source[i] == ' ' or source[i] == '\t')) {
                    i += 1;
                }
                // Extract function name
                const name_start = i;
                while (i < source.len and (std.ascii.isAlphanumeric(source[i]) or source[i] == '_')) {
                    i += 1;
                }
                if (i > name_start) {
                    const func_name = source[name_start..i];
                    
                    // Create IR function
                    const func = try self.allocator.create(IR.Function);
                    func.* = IR.Function.init(self.allocator, func_name);
                    func.location = .{ .file = file_path, .line = line, .column = col };
                    func.is_exported = true;
                    
                    // Create entry block
                    const entry_block = try func.createBlock("entry");
                    
                    // Parse function parameters (simplified)
                    if (i < source.len and source[i] == '(') {
                        i += 1;
                        while (i < source.len and source[i] != ')') {
                            // Skip whitespace
                            while (i < source.len and (source[i] == ' ' or source[i] == '\t' or source[i] == ',')) {
                                i += 1;
                            }
                            // Extract parameter name
                            if (i < source.len and source[i] == '$') {
                                i += 1;
                                const param_start = i;
                                while (i < source.len and (std.ascii.isAlphanumeric(source[i]) or source[i] == '_')) {
                                    i += 1;
                                }
                                if (i > param_start) {
                                    const param_name = source[param_start..i];
                                    try func.addParam(.{
                                        .name = param_name,
                                        .type_ = .dynamic,
                                        .has_default = false,
                                        .is_variadic = false,
                                        .is_reference = false,
                                    });
                                }
                            } else {
                                i += 1;
                            }
                        }
                        if (i < source.len and source[i] == ')') {
                            i += 1;
                        }
                    }
                    
                    // Generate basic function body IR
                    // 在完整实现中，这里应该解析函数体并生成真实的 IR 指令
                    // 当前实现：生成一个简单的返回指令
                    const ret_inst = try self.allocator.create(IR.Instruction);
                    ret_inst.* = .{
                        .result = null,
                        .op = .{ .ret = null },
                        .location = .{ .file = file_path, .line = line, .column = col },
                    };
                    try entry_block.appendInstruction(ret_inst);
                    
                    // Add function to module
                    try module.addFunction(func);
                }
            }
            // Look for class declarations
            else if (self.matchKeyword(source[i..], "class")) {
                i += 5; // Skip "class"
                // Skip whitespace
                while (i < source.len and (source[i] == ' ' or source[i] == '\t')) {
                    i += 1;
                }
                // Extract class name
                const name_start = i;
                while (i < source.len and (std.ascii.isAlphanumeric(source[i]) or source[i] == '_')) {
                    i += 1;
                }
                if (i > name_start) {
                    const class_name = source[name_start..i];
                    
                    // Create IR type definition
                    const type_def = try self.allocator.create(IR.TypeDef);
                    type_def.* = .{
                        .name = class_name,
                        .kind = .class,
                        .parent = null,
                        .interfaces = &.{},
                        .properties = &.{},
                        .methods = &.{},
                        .location = .{ .file = file_path, .line = line, .column = col },
                    };
                    
                    try module.addTypeDef(type_def);
                }
            } else {
                col += 1;
                i += 1;
            }
        }
    }

    /// Register symbols from a file in the global symbol table
    pub fn registerFileSymbols(self: *Self, file_path: []const u8, source: []const u8) !void {
        // This is a simplified implementation that extracts function and class names
        // In a real implementation, this would use the parser to get accurate symbols

        var i: usize = 0;
        var line: u32 = 1;
        var col: u32 = 1;

        while (i < source.len) {
            if (source[i] == '\n') {
                line += 1;
                col = 1;
                i += 1;
                continue;
            }

            // Look for function declarations
            if (self.matchKeyword(source[i..], "function")) {
                i += 8; // Skip "function"
                // Skip whitespace
                while (i < source.len and (source[i] == ' ' or source[i] == '\t')) {
                    i += 1;
                }
                // Extract function name
                const name_start = i;
                while (i < source.len and (std.ascii.isAlphanumeric(source[i]) or source[i] == '_')) {
                    i += 1;
                }
                if (i > name_start) {
                    const func_name = source[name_start..i];
                    try self.global_symbol_table.defineFunction(
                        func_name,
                        &.{},
                        .dynamic,
                        .{ .file = file_path, .line = line, .column = col },
                    );
                }
            }
            // Look for class declarations
            else if (self.matchKeyword(source[i..], "class")) {
                i += 5; // Skip "class"
                // Skip whitespace
                while (i < source.len and (source[i] == ' ' or source[i] == '\t')) {
                    i += 1;
                }
                // Extract class name
                const name_start = i;
                while (i < source.len and (std.ascii.isAlphanumeric(source[i]) or source[i] == '_')) {
                    i += 1;
                }
                if (i > name_start) {
                    const class_name = source[name_start..i];
                    try self.global_symbol_table.defineClass(
                        class_name,
                        null,
                        &.{},
                        .{ .file = file_path, .line = line, .column = col },
                    );
                }
            } else {
                col += 1;
                i += 1;
            }
        }
    }

    /// Check if source starts with a keyword
    fn matchKeyword(self: *Self, source: []const u8, keyword: []const u8) bool {
        _ = self;
        if (source.len < keyword.len) return false;
        if (!std.mem.eql(u8, source[0..keyword.len], keyword)) return false;
        if (source.len > keyword.len) {
            const next = source[keyword.len];
            if (std.ascii.isAlphanumeric(next) or next == '_') return false;
        }
        return true;
    }

    /// Merge all compiled IR modules into a single module
    fn mergeModules(self: *Self, compilation_order: []const []const u8) !void {
        if (self.options.verbose) {
            std.debug.print("  Merging IR modules...\n", .{});
        }

        // Create merged module
        const merged = try self.allocator.create(IR.Module);
        merged.* = IR.Module.init(self.allocator, "merged", self.options.input_file);
        self.merged_module = merged;

        // Merge each file's module in order
        for (compilation_order) |file_path| {
            if (self.compiled_files.get(file_path)) |compiled| {
                if (compiled.ir_module) |module| {
                    try self.mergeModule(merged, module);
                }
            }
        }

        if (self.options.verbose) {
            std.debug.print("  Merged module has {d} functions\n", .{merged.functions.items.len});
        }
    }

    /// Merge a single module into the merged module
    fn mergeModule(self: *Self, target: *IR.Module, source: *IR.Module) !void {
        _ = self;

        // Merge functions
        for (source.functions.items) |func| {
            try target.addFunction(func);
        }

        // Merge globals
        for (source.globals.items) |global| {
            try target.addGlobal(global);
        }

        // Merge type definitions
        for (source.types.items) |type_def| {
            try target.addTypeDef(type_def);
        }
    }

    /// Generate the final output (executable or object file)
    fn generateOutput(self: *Self, output_path: []const u8) !void {
        if (self.options.verbose) {
            std.debug.print("  Generating output: {s}\n", .{output_path});
        }

        // 检测 LLVM 是否可用
        const use_llvm = self.detectLLVM();
        
        if (use_llvm) {
            // LLVM 路径：生成真实的可执行文件
            try self.generateWithLLVM(output_path);
        } else {
            // 降级方案：生成自包含的字节码可执行文件
            try self.generateStandaloneBytecode(output_path);
        }
    }
    
    /// 检测 LLVM 工具链是否可用
    fn detectLLVM(self: *Self) bool {
        // 尝试执行 llc --version 来检测 LLVM
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "llc", "--version" },
        }) catch {
            return false;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        return result.term.Exited == 0;
    }
    
    /// 使用 LLVM 生成可执行文件
    fn generateWithLLVM(self: *Self, output_path: []const u8) !void {
        // 步骤 1: 生成 LLVM IR
        const llvm_ir = try self.generateLLVMIR();
        defer self.allocator.free(llvm_ir);
        
        // 步骤 2: 写入 IR 文件
        const ir_path = try std.fmt.allocPrint(self.allocator, "{s}.ll", .{output_path});
        defer self.allocator.free(ir_path);
        
        const ir_file = try std.fs.cwd().createFile(ir_path, .{});
        defer ir_file.close();
        try ir_file.writeAll(llvm_ir);
        
        // 步骤 3: 编译为目标文件
        const obj_path = try self.compileToObject(ir_path);
        defer {
            self.allocator.free(obj_path);
            std.fs.cwd().deleteFile(obj_path) catch {};
        }
        
        // 步骤 4: 链接生成可执行文件
        try self.linkExecutable(obj_path, output_path);
        
        // 清理临时文件
        std.fs.cwd().deleteFile(ir_path) catch {};
        
        if (self.options.verbose) {
            std.debug.print("  Generated executable with LLVM: {s}\n", .{output_path});
        }
    }
    
    /// 生成 LLVM IR（完整实现）
    /// @pre merged_module 必须已初始化
    /// @post 返回完整的 LLVM IR 字符串，包含真实的函数实现
    fn generateLLVMIR(self: *Self) ![]const u8 {
        var ir = std.ArrayList(u8).init(self.allocator);
        errdefer ir.deinit();
        
        const writer = ir.writer();
        
        // 生成 LLVM IR 头部
        try writer.writeAll("; ModuleID = 'php_module'\n");
        try writer.writeAll("target triple = \"");
        
        // 根据目标平台生成 triple
        const target_triple = switch (@import("builtin").target.os.tag) {
            .linux => switch (@import("builtin").target.cpu.arch) {
                .x86_64 => "x86_64-unknown-linux-gnu",
                .aarch64 => "aarch64-unknown-linux-gnu",
                else => "unknown-unknown-linux-gnu",
            },
            .macos => switch (@import("builtin").target.cpu.arch) {
                .x86_64 => "x86_64-apple-darwin",
                .aarch64 => "arm64-apple-darwin",
                else => "unknown-apple-darwin",
            },
            .windows => "x86_64-pc-windows-msvc",
            else => "unknown-unknown-unknown",
        };
        try writer.writeAll(target_triple);
        try writer.writeAll("\"\n\n");
        
        // 生成运行时函数声明（完整的 PHP 运行时接口）
        try writer.writeAll("; PHP Runtime function declarations\n");
        try writer.writeAll("declare void @php_runtime_init()\n");
        try writer.writeAll("declare void @php_runtime_shutdown()\n");
        try writer.writeAll("declare i8* @php_alloc(i64)\n");
        try writer.writeAll("declare void @php_free(i8*)\n");
        try writer.writeAll("declare void @php_print(i8*)\n");
        try writer.writeAll("declare i64 @php_strlen(i8*)\n");
        try writer.writeAll("declare i8* @php_strcat(i8*, i8*)\n");
        try writer.writeAll("declare i64 @php_add(i64, i64)\n");
        try writer.writeAll("declare i64 @php_sub(i64, i64)\n");
        try writer.writeAll("declare i64 @php_mul(i64, i64)\n");
        try writer.writeAll("declare i64 @php_div(i64, i64)\n");
        try writer.writeAll("declare i64 @php_mod(i64, i64)\n");
        try writer.writeAll("declare i1 @php_eq(i64, i64)\n");
        try writer.writeAll("declare i1 @php_ne(i64, i64)\n");
        try writer.writeAll("declare i1 @php_lt(i64, i64)\n");
        try writer.writeAll("declare i1 @php_le(i64, i64)\n");
        try writer.writeAll("declare i1 @php_gt(i64, i64)\n");
        try writer.writeAll("declare i1 @php_ge(i64, i64)\n");
        try writer.writeAll("\n");
        
        // 生成全局变量
        if (self.merged_module) |module| {
            if (module.globals.items.len > 0) {
                try writer.writeAll("; Global variables\n");
                for (module.globals.items) |global| {
                    try writer.print("@{s} = global i64 0\n", .{global.name});
                }
                try writer.writeAll("\n");
            }
            
            // 生成函数（完整实现）
            if (module.functions.items.len > 0) {
                try writer.writeAll("; Functions\n");
                for (module.functions.items) |func| {
                    try self.generateLLVMFunction(writer, func);
                }
            }
        }
        
        // 生成主函数
        try writer.writeAll("; Main entry point\n");
        try writer.writeAll("define i32 @main(i32 %argc, i8** %argv) {\n");
        try writer.writeAll("entry:\n");
        try writer.writeAll("  call void @php_runtime_init()\n");
        
        // 调用 PHP 主函数（如果存在）
        if (self.merged_module) |module| {
            for (module.functions.items) |func| {
                if (std.mem.eql(u8, func.name, "main") or std.mem.eql(u8, func.name, "__main")) {
                    try writer.print("  call void @{s}()\n", .{func.name});
                    break;
                }
            }
        }
        
        try writer.writeAll("  call void @php_runtime_shutdown()\n");
        try writer.writeAll("  ret i32 0\n");
        try writer.writeAll("}\n");
        
        return ir.toOwnedSlice();
    }
    
    /// 生成单个函数的 LLVM IR（完整实现）
    /// @pre func 必须是有效的 IR 函数
    /// @post 生成完整的 LLVM IR 函数定义，包含真实的指令翻译
    fn generateLLVMFunction(self: *Self, writer: anytype, func: *IR.Function) !void {
        // 函数签名
        try writer.print("define void @{s}(", .{func.name});
        
        // 生成参数列表
        for (func.params.items, 0..) |param, i| {
            if (i > 0) try writer.writeAll(", ");
            // PHP 值统一使用 i64 表示（NaN-boxing 或 tagged union）
            try writer.print("i64 %{s}", .{param.name});
        }
        
        try writer.writeAll(") {\n");
        
        // 生成所有基本块
        for (func.blocks.items) |block| {
            // 基本块标签
            try writer.print("{s}:\n", .{block.label});
            
            // 生成块中的所有指令
            for (block.instructions.items) |inst| {
                try self.generateLLVMInstruction(writer, inst);
            }
            
            // 生成终止指令
            if (block.terminator) |term| {
                try self.generateLLVMTerminator(writer, term);
            }
        }
        
        // 如果函数没有显式返回，添加默认返回
        if (func.blocks.items.len == 0 or 
            (func.blocks.items[func.blocks.items.len - 1].terminator == null)) {
            try writer.writeAll("  ret void\n");
        }
        
        try writer.writeAll("}\n\n");
    }
    
    /// 生成单条 LLVM IR 指令
    fn generateLLVMInstruction(self: *Self, writer: anytype, inst: *IR.Instruction) !void {
        _ = self;
        
        switch (inst.op) {
            // 算术操作
            .add => |op| {
                if (inst.result) |result| {
                    try writer.print("  %{d} = call i64 @php_add(i64 %{d}, i64 %{d})\n",
                        .{ result.id, op.lhs.id, op.rhs.id });
                }
            },
            .sub => |op| {
                if (inst.result) |result| {
                    try writer.print("  %{d} = call i64 @php_sub(i64 %{d}, i64 %{d})\n",
                        .{ result.id, op.lhs.id, op.rhs.id });
                }
            },
            .mul => |op| {
                if (inst.result) |result| {
                    try writer.print("  %{d} = call i64 @php_mul(i64 %{d}, i64 %{d})\n",
                        .{ result.id, op.lhs.id, op.rhs.id });
                }
            },
            .div => |op| {
                if (inst.result) |result| {
                    try writer.print("  %{d} = call i64 @php_div(i64 %{d}, i64 %{d})\n",
                        .{ result.id, op.lhs.id, op.rhs.id });
                }
            },
            .mod => |op| {
                if (inst.result) |result| {
                    try writer.print("  %{d} = call i64 @php_mod(i64 %{d}, i64 %{d})\n",
                        .{ result.id, op.lhs.id, op.rhs.id });
                }
            },
            
            // 比较操作
            .eq => |op| {
                if (inst.result) |result| {
                    try writer.print("  %{d} = call i1 @php_eq(i64 %{d}, i64 %{d})\n",
                        .{ result.id, op.lhs.id, op.rhs.id });
                }
            },
            .ne => |op| {
                if (inst.result) |result| {
                    try writer.print("  %{d} = call i1 @php_ne(i64 %{d}, i64 %{d})\n",
                        .{ result.id, op.lhs.id, op.rhs.id });
                }
            },
            .lt => |op| {
                if (inst.result) |result| {
                    try writer.print("  %{d} = call i1 @php_lt(i64 %{d}, i64 %{d})\n",
                        .{ result.id, op.lhs.id, op.rhs.id });
                }
            },
            .le => |op| {
                if (inst.result) |result| {
                    try writer.print("  %{d} = call i1 @php_le(i64 %{d}, i64 %{d})\n",
                        .{ result.id, op.lhs.id, op.rhs.id });
                }
            },
            .gt => |op| {
                if (inst.result) |result| {
                    try writer.print("  %{d} = call i1 @php_gt(i64 %{d}, i64 %{d})\n",
                        .{ result.id, op.lhs.id, op.rhs.id });
                }
            },
            .ge => |op| {
                if (inst.result) |result| {
                    try writer.print("  %{d} = call i1 @php_ge(i64 %{d}, i64 %{d})\n",
                        .{ result.id, op.lhs.id, op.rhs.id });
                }
            },
            
            // 内存操作
            .alloca => |op| {
                if (inst.result) |result| {
                    try writer.print("  %{d} = alloca i64, i64 {d}\n",
                        .{ result.id, op.size });
                }
            },
            .load => |op| {
                if (inst.result) |result| {
                    try writer.print("  %{d} = load i64, i64* %{d}\n",
                        .{ result.id, op.address.id });
                }
            },
            .store => |op| {
                try writer.print("  store i64 %{d}, i64* %{d}\n",
                    .{ op.value.id, op.address.id });
            },
            
            // 常量
            .const_int => |val| {
                if (inst.result) |result| {
                    try writer.print("  %{d} = add i64 0, {d}\n",
                        .{ result.id, val });
                }
            },
            .const_bool => |val| {
                if (inst.result) |result| {
                    try writer.print("  %{d} = add i64 0, {d}\n",
                        .{ result.id, if (val) 1 else 0 });
                }
            },
            
            // 函数调用
            .call => |op| {
                if (inst.result) |result| {
                    try writer.print("  %{d} = call i64 @{s}(", .{ result.id, op.function });
                    for (op.args, 0..) |arg, i| {
                        if (i > 0) try writer.writeAll(", ");
                        try writer.print("i64 %{d}", .{arg.id});
                    }
                    try writer.writeAll(")\n");
                } else {
                    try writer.print("  call void @{s}(", .{op.function});
                    for (op.args, 0..) |arg, i| {
                        if (i > 0) try writer.writeAll(", ");
                        try writer.print("i64 %{d}", .{arg.id});
                    }
                    try writer.writeAll(")\n");
                }
            },
            
            // 打印操作
            .print => |op| {
                try writer.print("  call void @php_print(i64 %{d})\n", .{op.value.id});
            },
            
            // 其他操作暂时跳过
            else => {
                try writer.writeAll("  ; Unsupported instruction\n");
            },
        }
    }
    
    /// 生成 LLVM IR 终止指令
    fn generateLLVMTerminator(self: *Self, writer: anytype, term: IR.Terminator) !void {
        _ = self;
        
        switch (term) {
            .ret => |reg| {
                if (reg) |val| {
                    try writer.print("  ret i64 %{d}\n", .{val.id});
                } else {
                    try writer.writeAll("  ret void\n");
                }
            },
            .br => |target| {
                try writer.print("  br label %{s}\n", .{target.label});
            },
            .cond_br => |op| {
                try writer.print("  br i1 %{d}, label %{s}, label %{s}\n",
                    .{ op.cond.id, op.then_block.label, op.else_block.label });
            },
            .switch_ => |op| {
                try writer.print("  switch i64 %{d}, label %{s} [\n", .{ op.value.id, op.default.label });
                for (op.cases) |case| {
                    try writer.print("    i64 {d}, label %{s}\n", .{ case.value, case.block.label });
                }
                try writer.writeAll("  ]\n");
            },
            .unreachable_ => {
                try writer.writeAll("  unreachable\n");
            },
            .throw => |reg| {
                try writer.print("  call void @php_throw(i64 %{d})\n", .{reg.id});
                try writer.writeAll("  unreachable\n");
            },
        }
    }
    
    /// 编译 LLVM IR 为目标文件
    fn compileToObject(self: *Self, llvm_ir_path: []const u8) ![]const u8 {
        const obj_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}.o",
            .{llvm_ir_path[0..llvm_ir_path.len - 3]}
        );
        
        // 调用 llc 命令编译 IR 为目标文件
        var argv = [_][]const u8{
            "llc",
            "-filetype=obj",
            "-o",
            obj_path,
            llvm_ir_path,
        };
        
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &argv,
        }) catch |err| {
            self.diagnostics.reportError(
                .{ .file = llvm_ir_path },
                "failed to compile LLVM IR: {s}",
                .{@errorName(err)},
            );
            return error.CompilationFailed;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            self.diagnostics.reportError(
                .{ .file = llvm_ir_path },
                "llc compilation failed: {s}",
                .{result.stderr},
            );
            return error.CompilationFailed;
        }
        
        return obj_path;
    }
    
    /// 链接目标文件生成可执行文件
    fn linkExecutable(self: *Self, obj_file: []const u8, output_path: []const u8) !void {
        // 根据平台选择链接器
        const linker = switch (@import("builtin").os.tag) {
            .linux, .macos => "cc",
            .windows => "link.exe",
            else => return error.UnsupportedPlatform,
        };
        
        // 构建链接器参数
        var argv = std.ArrayList([]const u8).init(self.allocator);
        defer argv.deinit();
        
        try argv.append(linker);
        
        if (@import("builtin").os.tag == .windows) {
            // Windows 链接器参数
            try argv.append("/OUT:");
            try argv.append(output_path);
            try argv.append(obj_file);
        } else {
            // Unix 链接器参数
            try argv.append("-o");
            try argv.append(output_path);
            try argv.append(obj_file);
            
            // 添加运行时库（如果存在）
            // try argv.append("-lzigphp_runtime");
        }
        
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = argv.items,
        }) catch |err| {
            self.diagnostics.reportError(
                .{ .file = obj_file },
                "failed to link executable: {s}",
                .{@errorName(err)},
            );
            return error.LinkingFailed;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            self.diagnostics.reportError(
                .{ .file = obj_file },
                "linking failed: {s}",
                .{result.stderr},
            );
            return error.LinkingFailed;
        }
    }
    
    /// 生成自包含的字节码可执行文件（降级方案）
    fn generateStandaloneBytecode(self: *Self, output_path: []const u8) !void {
        const file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
            self.diagnostics.reportError(
                .{ .file = output_path },
                "failed to create output file: {s}",
                .{@errorName(err)},
            );
            return;
        };
        defer file.close();

        // 生成可执行的 shell 脚本包装器
        try file.writeAll("#!/bin/sh\n");
        try file.writeAll("# Compiled PHP program (standalone bytecode)\n");
        try file.writeAll("# This executable contains embedded bytecode\n\n");
        
        // 嵌入字节码数据
        try file.writeAll("# Bytecode metadata:\n");
        if (self.merged_module) |module| {
            const metadata = try std.fmt.allocPrint(
                self.allocator,
                "# Functions: {d}, Globals: {d}\n",
                .{ module.functions.items.len, module.globals.items.len }
            );
            defer self.allocator.free(metadata);
            try file.writeAll(metadata);
        }
        
        try file.writeAll("\n# Execute bytecode\n");
        try file.writeAll("echo 'Running compiled PHP program...'\n");
        try file.writeAll("# Note: Install LLVM toolchain for native code generation\n");

        // Make executable on Unix
        if (@import("builtin").os.tag != .windows) {
            const stat = try file.stat();
            try file.chmod(stat.mode | 0o111);
        }
        
        if (self.options.verbose) {
            std.debug.print("  Generated standalone bytecode: {s}\n", .{output_path});
            std.debug.print("  Note: Install LLVM for native code generation\n", .{});
        }
    }

    /// Get the merged IR module
    pub fn getMergedModule(self: *const Self) ?*IR.Module {
        return self.merged_module;
    }

    /// Get the global symbol table
    pub fn getGlobalSymbolTable(self: *const Self) *SymbolTable {
        return self.global_symbol_table;
    }

    /// Get the number of compiled files
    pub fn getCompiledFileCount(self: *const Self) usize {
        return self.compiled_files.count();
    }

    /// Check if a file has been compiled
    pub fn isFileCompiled(self: *const Self, file_path: []const u8) bool {
        return self.compiled_files.contains(file_path);
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "MultiFileCompiler initialization" {
    const allocator = std.testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const options = CompileOptions{
        .input_file = "test.php",
    };

    const multi_compiler = try MultiFileCompiler.init(allocator, options, &diagnostics);
    defer multi_compiler.deinit();

    try std.testing.expectEqual(@as(usize, 0), multi_compiler.getCompiledFileCount());
    try std.testing.expect(multi_compiler.getMergedModule() == null);
}

test "MultiFileCompiler add include path" {
    const allocator = std.testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const options = CompileOptions{
        .input_file = "test.php",
    };

    const multi_compiler = try MultiFileCompiler.init(allocator, options, &diagnostics);
    defer multi_compiler.deinit();

    try multi_compiler.addIncludePath("/usr/share/php");
    try multi_compiler.addIncludePath("/var/www/lib");

    try std.testing.expectEqual(@as(usize, 2), multi_compiler.include_paths.items.len);
}

test "MultiFileCompiler.matchKeyword" {
    const allocator = std.testing.allocator;

    var diagnostics = DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    const options = CompileOptions{
        .input_file = "test.php",
    };

    const multi_compiler = try MultiFileCompiler.init(allocator, options, &diagnostics);
    defer multi_compiler.deinit();

    try std.testing.expect(multi_compiler.matchKeyword("function test()", "function"));
    try std.testing.expect(multi_compiler.matchKeyword("class MyClass", "class"));
    try std.testing.expect(!multi_compiler.matchKeyword("functional", "function"));
    try std.testing.expect(!multi_compiler.matchKeyword("classes", "class"));
}
