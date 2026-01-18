//! 跨文件链接器 (Cross-File Linker)
//!
//! 本模块实现 AOT 编译器的跨文件链接功能，包括：
//! - 符号表合并：合并多个编译单元的符号表
//! - 跨文件依赖解析：解析文件间的依赖关系
//! - 符号引用解析：将符号引用解析到定义位置
//!
//! ## 设计原则
//! - 显式错误处理：所有链接错误必须明确报告
//! - 内存安全：使用 Allocator 显式管理内存
//! - 零成本抽象：链接过程不引入运行时开销
//!
//! ## 符号解析策略
//! 1. 收集所有编译单元的符号定义
//! 2. 构建全局符号表
//! 3. 解析符号引用
//! 4. 检测未定义符号和重复定义
//!
//! @ownership NON-OWNING (allocator)
//! @thread-safety ISOLATED (单线程)
//! @memory-protection 显式 Allocator 传递

const std = @import("std");
const Allocator = std.mem.Allocator;
const IR = @import("ir.zig");
const Diagnostics = @import("diagnostics.zig");

// ============================================================================
// 符号类型定义
// ============================================================================

/// 符号类型
pub const SymbolType = enum {
    function,
    global_variable,
    class_type,
    constant,
    external,
};

/// 符号可见性
pub const SymbolVisibility = enum {
    public,
    private,
    protected,
    internal,
};

/// 符号定义
/// @ownership TRANSFER (name 由调用者管理)
pub const SymbolDefinition = struct {
    name: []const u8,
    type_: SymbolType,
    visibility: SymbolVisibility,
    
    // 定义位置
    file_path: []const u8,
    location: Diagnostics.SourceLocation,
    
    // IR 引用（可选，用于代码生成）
    ir_value: ?*anyopaque,
    
    // 类型信息（可选）
    type_info: ?*anyopaque,
    
    /// 创建符号定义
    /// @pre name 和 file_path 必须有效
    /// @post 返回初始化的符号定义
    pub fn create(
        name: []const u8,
        type_: SymbolType,
        visibility: SymbolVisibility,
        file_path: []const u8,
        location: Diagnostics.SourceLocation,
    ) SymbolDefinition {
        return .{
            .name = name,
            .type_ = type_,
            .visibility = visibility,
            .file_path = file_path,
            .location = location,
            .ir_value = null,
            .type_info = null,
        };
    }
    
    /// 检查符号是否可导出
    /// @post 返回符号是否对外部可见
    pub fn isExportable(self: *const SymbolDefinition) bool {
        return self.visibility == .public or self.visibility == .protected;
    }
};

/// 符号引用
/// @ownership NON-OWNING (name 由调用者管理)
pub const SymbolReference = struct {
    name: []const u8,
    type_: SymbolType,
    
    // 引用位置
    file_path: []const u8,
    location: Diagnostics.SourceLocation,
    
    // 解析后的定义
    resolved_definition: ?*SymbolDefinition,
    
    /// 创建符号引用
    pub fn create(
        name: []const u8,
        type_: SymbolType,
        file_path: []const u8,
        location: Diagnostics.SourceLocation,
    ) SymbolReference {
        return .{
            .name = name,
            .type_ = type_,
            .file_path = file_path,
            .location = location,
            .resolved_definition = null,
        };
    }
    
    /// 检查引用是否已解析
    pub fn isResolved(self: *const SymbolReference) bool {
        return self.resolved_definition != null;
    }
};

// ============================================================================
// 编译单元
// ============================================================================

/// 编译单元 (Compilation Unit)
/// 表示单个源文件的编译结果
/// @ownership TRANSFER (symbols, references)
pub const CompilationUnit = struct {
    allocator: Allocator,
    
    // 文件信息
    file_path: []const u8,
    
    // 符号定义
    symbols: std.StringHashMap(SymbolDefinition),
    
    // 符号引用
    references: std.ArrayListUnmanaged(SymbolReference),
    
    // 依赖的文件
    dependencies: std.StringHashMap(void),
    
    // IR 模块（可选，用于代码生成）
    ir_module: ?*anyopaque,
    
    /// 初始化编译单元
    /// @pre allocator 必须有效
    /// @post 返回初始化的编译单元
    pub fn init(allocator: Allocator, file_path: []const u8) !CompilationUnit {
        return .{
            .allocator = allocator,
            .file_path = file_path,
            .symbols = std.StringHashMap(SymbolDefinition).init(allocator),
            .references = .{},
            .dependencies = std.StringHashMap(void).init(allocator),
            .ir_module = null,
        };
    }
    
    /// 释放资源
    /// @post 所有资源被正确释放
    pub fn deinit(self: *CompilationUnit) void {
        self.symbols.deinit();
        self.references.deinit(self.allocator);
        self.dependencies.deinit();
    }
    
    /// 添加符号定义
    /// @pre symbol.name 必须有效
    /// @post 符号被添加到符号表
    pub fn addSymbol(self: *CompilationUnit, symbol: SymbolDefinition) !void {
        try self.symbols.put(symbol.name, symbol);
    }
    
    /// 添加符号引用
    /// @pre reference 必须有效
    /// @post 引用被添加到引用列表
    pub fn addReference(self: *CompilationUnit, reference: SymbolReference) !void {
        try self.references.append(self.allocator, reference);
    }
    
    /// 添加依赖
    /// @pre dep_file_path 必须有效
    /// @post 依赖被记录
    pub fn addDependency(self: *CompilationUnit, dep_file_path: []const u8) !void {
        try self.dependencies.put(dep_file_path, {});
    }
    
    /// 查找符号定义
    /// @pre name 必须有效
    /// @post 返回符号定义或 null
    pub fn findSymbol(self: *const CompilationUnit, name: []const u8) ?*SymbolDefinition {
        return self.symbols.getPtr(name);
    }
};

// ============================================================================
// 全局符号表
// ============================================================================

/// 全局符号表
/// 合并所有编译单元的符号定义
/// @ownership TRANSFER (symbols)
/// @concurrency-model ISOLATED
pub const GlobalSymbolTable = struct {
    allocator: Allocator,
    
    // 符号定义映射：name -> SymbolDefinition
    symbols: std.StringHashMap(SymbolDefinition),
    
    // 重复定义检测：name -> []SymbolDefinition
    duplicate_definitions: std.StringHashMap(std.ArrayListUnmanaged(SymbolDefinition)),
    
    /// 初始化全局符号表
    /// @pre allocator 必须有效
    /// @post 返回空的符号表
    pub fn init(allocator: Allocator) GlobalSymbolTable {
        return .{
            .allocator = allocator,
            .symbols = std.StringHashMap(SymbolDefinition).init(allocator),
            .duplicate_definitions = std.StringHashMap(std.ArrayListUnmanaged(SymbolDefinition)).init(allocator),
        };
    }
    
    /// 释放资源
    /// @post 所有资源被正确释放
    pub fn deinit(self: *GlobalSymbolTable) void {
        self.symbols.deinit();
        
        var iter = self.duplicate_definitions.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.duplicate_definitions.deinit();
    }
    
    /// 添加符号定义
    /// @pre symbol 必须有效
    /// @post 符号被添加，或检测到重复定义
    pub fn addSymbol(self: *GlobalSymbolTable, symbol: SymbolDefinition) !void {
        // 检查是否已存在
        if (self.symbols.get(symbol.name)) |existing| {
            // 检测到重复定义
            const dups_ptr = self.duplicate_definitions.getPtr(symbol.name) orelse blk: {
                var list: std.ArrayListUnmanaged(SymbolDefinition) = .{};
                try list.append(self.allocator, existing);
                try self.duplicate_definitions.put(symbol.name, list);
                break :blk self.duplicate_definitions.getPtr(symbol.name).?;
            };
            
            try dups_ptr.append(self.allocator, symbol);
        } else {
            // 首次定义
            try self.symbols.put(symbol.name, symbol);
        }
    }
    
    /// 查找符号定义
    /// @pre name 必须有效
    /// @post 返回符号定义或 null
    pub fn findSymbol(self: *const GlobalSymbolTable, name: []const u8) ?*const SymbolDefinition {
        return self.symbols.getPtr(name);
    }
    
    /// 检查是否有重复定义
    /// @post 返回是否存在重复定义
    pub fn hasDuplicateDefinitions(self: *const GlobalSymbolTable) bool {
        return self.duplicate_definitions.count() > 0;
    }
    
    /// 获取重复定义列表
    /// @pre name 必须有效
    /// @post 返回重复定义列表或 null
    pub fn getDuplicateDefinitions(
        self: *const GlobalSymbolTable,
        name: []const u8,
    ) ?[]const SymbolDefinition {
        if (self.duplicate_definitions.getPtr(name)) |list| {
            return list.items;
        }
        return null;
    }
};

// ============================================================================
// 目标平台和对象格式
// ============================================================================

/// 目标平台
pub const Target = enum {
    linux_x86_64,
    linux_aarch64,
    macos_x86_64,
    macos_aarch64,
    windows_x86_64,
    
    pub fn getObjectFormat(self: Target) ObjectFormat {
        return switch (self) {
            .linux_x86_64, .linux_aarch64 => .elf,
            .macos_x86_64, .macos_aarch64 => .macho,
            .windows_x86_64 => .coff,
        };
    }
};

/// 对象文件格式
pub const ObjectFormat = enum {
    elf,    // Linux
    macho,  // macOS
    coff,   // Windows
    
    /// 从目标平台获取对象格式
    pub fn fromTarget(target: anytype) ObjectFormat {
        // 支持 linker.Target 和 codegen.Target
        const target_name = @typeName(@TypeOf(target));
        if (std.mem.indexOf(u8, target_name, "Target") != null) {
            // 尝试获取 arch 和 os 字段
            if (@hasField(@TypeOf(target), "arch") and @hasField(@TypeOf(target), "os")) {
                // codegen.Target 类型
                const os_name = @tagName(target.os);
                if (std.mem.startsWith(u8, os_name, "linux")) {
                    return .elf;
                } else if (std.mem.startsWith(u8, os_name, "macos")) {
                    return .macho;
                } else if (std.mem.startsWith(u8, os_name, "windows")) {
                    return .coff;
                }
            }
        }
        
        // 默认返回 ELF
        return .elf;
    }
};

/// 对象代码
pub const ObjectCode = struct {
    data: []const u8,
    format: ObjectFormat,
    symbols: []const []const u8,
    
    /// 创建借用的对象代码（用于测试）
    pub fn initBorrowed(data: []const u8, format: ObjectFormat, symbol_name: []const u8) ObjectCode {
        const symbols = &[_][]const u8{symbol_name};
        return .{
            .data = data,
            .format = format,
            .symbols = symbols,
        };
    }
};

/// 链接器配置
pub const LinkerConfig = struct {
    target: Target,
    output_format: ObjectFormat,
    strip_debug: bool = false,
    optimize: bool = true,
    
    pub fn default(target: anytype) LinkerConfig {
        // 支持 linker.Target 和 codegen.Target
        const target_type = @TypeOf(target);
        const target_name = @typeName(target_type);
        
        if (std.mem.indexOf(u8, target_name, "codegen.Target") != null) {
            // codegen.Target - 转换为 linker.Target
            const os_name = @tagName(target.os);
            const arch_name = @tagName(target.arch);
            
            const linker_target: Target = blk: {
                if (std.mem.eql(u8, os_name, "linux")) {
                    if (std.mem.eql(u8, arch_name, "x86_64")) {
                        break :blk .linux_x86_64;
                    } else if (std.mem.eql(u8, arch_name, "aarch64")) {
                        break :blk .linux_aarch64;
                    }
                } else if (std.mem.eql(u8, os_name, "macos")) {
                    if (std.mem.eql(u8, arch_name, "x86_64")) {
                        break :blk .macos_x86_64;
                    } else if (std.mem.eql(u8, arch_name, "aarch64")) {
                        break :blk .macos_aarch64;
                    }
                } else if (std.mem.eql(u8, os_name, "windows")) {
                    break :blk .windows_x86_64;
                }
                // 默认
                break :blk .linux_x86_64;
            };
            
            return .{
                .target = linker_target,
                .output_format = linker_target.getObjectFormat(),
            };
        } else {
            // linker.Target
            return .{
                .target = target,
                .output_format = target.getObjectFormat(),
            };
        }
    }
};

// ============================================================================
// 链接器
// ============================================================================

/// 链接错误
pub const LinkerError = error{
    // 符号错误
    UndefinedSymbol,
    DuplicateDefinition,
    SymbolTypeMismatch,
    VisibilityViolation,
    
    // 依赖错误
    CircularDependency,
    MissingDependency,
    
    // 内存错误
    OutOfMemory,
};

/// 静态链接器
/// @ownership NON-OWNING (allocator)
/// @thread-safety ISOLATED
pub const StaticLinker = struct {
    allocator: Allocator,
    
    // 配置
    config: LinkerConfig,
    
    // 编译单元列表
    compilation_units: std.ArrayListUnmanaged(*CompilationUnit),
    
    // 全局符号表
    global_symbols: GlobalSymbolTable,
    
    // 诊断引擎
    diagnostics: *Diagnostics.DiagnosticEngine,
    
    /// 初始化链接器
    /// @pre allocator 和 diagnostics 必须有效
    /// @post 返回初始化的链接器
    pub fn init(
        allocator: Allocator,
        config: LinkerConfig,
        diagnostics: *Diagnostics.DiagnosticEngine,
    ) !*StaticLinker {
        const self = try allocator.create(StaticLinker);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .compilation_units = .{},
            .global_symbols = GlobalSymbolTable.init(allocator),
            .diagnostics = diagnostics,
        };
        return self;
    }
    
    /// 释放资源
    /// @post 所有资源被正确释放
    pub fn deinit(self: *StaticLinker) void {
        self.compilation_units.deinit(self.allocator);
        self.global_symbols.deinit();
        self.allocator.destroy(self);
    }
    
    /// 检查是否是运行时函数
    /// @post 返回函数名是否以 "php_" 开头
    pub fn isRuntimeFunction(name: []const u8) bool {
        return std.mem.startsWith(u8, name, "php_");
    }
    
    /// 添加编译单元
    /// @pre unit 必须有效
    /// @post 编译单元被添加到链接器
    pub fn addCompilationUnit(self: *StaticLinker, unit: *CompilationUnit) !void {
        try self.compilation_units.append(self.allocator, unit);
    }
    
    /// 执行链接
    /// @post 所有符号引用被解析，或返回错误
    pub fn link(self: *StaticLinker) !void {
        // 1. 合并符号表
        try self.mergeSymbolTables();
        
        // 2. 检测重复定义
        try self.checkDuplicateDefinitions();
        
        // 3. 解析依赖关系
        try self.resolveDependencies();
        
        // 4. 解析符号引用
        try self.resolveSymbolReferences();
        
        // 5. 检测未定义符号
        try self.checkUndefinedSymbols();
    }
    
    /// 合并符号表
    /// @post 所有编译单元的符号被合并到全局符号表
    fn mergeSymbolTables(self: *StaticLinker) !void {
        for (self.compilation_units.items) |unit| {
            var iter = unit.symbols.iterator();
            while (iter.next()) |entry| {
                const symbol = entry.value_ptr.*;
                
                // 只导出可见的符号
                if (symbol.isExportable()) {
                    try self.global_symbols.addSymbol(symbol);
                }
            }
        }
    }
    
    /// 检测重复定义
    /// @post 如果存在重复定义，报告错误
    fn checkDuplicateDefinitions(self: *StaticLinker) !void {
        if (!self.global_symbols.hasDuplicateDefinitions()) {
            return;
        }
        
        var iter = self.global_symbols.duplicate_definitions.iterator();
        while (iter.next()) |entry| {
            const name = entry.key_ptr.*;
            const defs = entry.value_ptr.items;
            
            // 报告重复定义错误
            for (defs) |def| {
                self.diagnostics.reportError(
                    def.location,
                    "duplicate definition of symbol '{s}'",
                    .{name},
                );
                
                // 添加注释：显示其他定义位置
                for (defs) |other_def| {
                    if (&def != &other_def) {
                        self.diagnostics.reportNote(
                            other_def.location,
                            "previous definition here",
                            .{},
                        );
                    }
                }
            }
        }
        
        return LinkerError.DuplicateDefinition;
    }
    
    /// 解析依赖关系
    /// @post 依赖关系被解析，或检测到循环依赖
    fn resolveDependencies(self: *StaticLinker) !void {
        // 构建依赖图
        var dep_graph = std.StringHashMap(std.ArrayListUnmanaged([]const u8)).init(self.allocator);
        defer {
            var iter = dep_graph.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            dep_graph.deinit();
        }
        
        for (self.compilation_units.items) |unit| {
            var deps: std.ArrayListUnmanaged([]const u8) = .{};
            
            var dep_iter = unit.dependencies.iterator();
            while (dep_iter.next()) |entry| {
                try deps.append(self.allocator, entry.key_ptr.*);
            }
            
            try dep_graph.put(unit.file_path, deps);
        }
        
        // 拓扑排序检测循环依赖
        var visited = std.StringHashMap(bool).init(self.allocator);
        defer visited.deinit();
        
        var rec_stack = std.StringHashMap(bool).init(self.allocator);
        defer rec_stack.deinit();
        
        for (self.compilation_units.items) |unit| {
            if (try self.detectCycle(unit.file_path, &dep_graph, &visited, &rec_stack)) {
                self.diagnostics.reportError(
                    .{ .line = 0, .column = 0 },
                    "circular dependency detected involving '{s}'",
                    .{unit.file_path},
                );
                return LinkerError.CircularDependency;
            }
        }
    }
    
    /// 检测循环依赖（DFS）
    /// @post 返回是否存在循环
    fn detectCycle(
        self: *StaticLinker,
        file: []const u8,
        dep_graph: *std.StringHashMap(std.ArrayListUnmanaged([]const u8)),
        visited: *std.StringHashMap(bool),
        rec_stack: *std.StringHashMap(bool),
    ) !bool {
        // 标记为已访问
        try visited.put(file, true);
        try rec_stack.put(file, true);
        
        // 访问所有依赖
        if (dep_graph.get(file)) |deps| {
            for (deps.items) |dep| {
                const is_visited = visited.get(dep) orelse false;
                if (!is_visited) {
                    if (try self.detectCycle(dep, dep_graph, visited, rec_stack)) {
                        return true;
                    }
                } else if (rec_stack.get(dep) orelse false) {
                    // 检测到循环
                    return true;
                }
            }
        }
        
        // 从递归栈中移除
        try rec_stack.put(file, false);
        return false;
    }
    
    /// 解析符号引用
    /// @post 所有符号引用被解析到定义
    fn resolveSymbolReferences(self: *StaticLinker) !void {
        for (self.compilation_units.items) |unit| {
            for (unit.references.items) |*reference| {
                // 首先在本地符号表中查找
                if (unit.findSymbol(reference.name)) |local_def| {
                    reference.resolved_definition = local_def;
                    continue;
                }
                
                // 在全局符号表中查找
                if (self.global_symbols.findSymbol(reference.name)) |global_def| {
                    // 检查可见性
                    if (!self.checkVisibility(unit, global_def)) {
                        self.diagnostics.reportError(
                            reference.location,
                            "symbol '{s}' is not visible from '{s}'",
                            .{ reference.name, unit.file_path },
                        );
                        return LinkerError.VisibilityViolation;
                    }
                    
                    // 检查类型匹配
                    if (reference.type_ != global_def.type_) {
                        self.diagnostics.reportError(
                            reference.location,
                            "symbol '{s}' type mismatch: expected {s}, found {s}",
                            .{
                                reference.name,
                                @tagName(reference.type_),
                                @tagName(global_def.type_),
                            },
                        );
                        return LinkerError.SymbolTypeMismatch;
                    }
                    
                    reference.resolved_definition = @constCast(global_def);
                }
            }
        }
    }
    
    /// 检查符号可见性
    /// @post 返回符号是否对编译单元可见
    fn checkVisibility(
        self: *StaticLinker,
        unit: *CompilationUnit,
        symbol: *const SymbolDefinition,
    ) bool {
        _ = self;
        
        switch (symbol.visibility) {
            .public => return true,
            .private => {
                // 只在同一文件内可见
                return std.mem.eql(u8, unit.file_path, symbol.file_path);
            },
            .protected => {
                // 在同一文件或子类中可见（简化实现）
                return true;
            },
            .internal => {
                // 在同一模块内可见（简化实现）
                return true;
            },
        }
    }
    
    /// 检测未定义符号
    /// @post 如果存在未定义符号，报告错误
    fn checkUndefinedSymbols(self: *StaticLinker) !void {
        var has_undefined = false;
        
        for (self.compilation_units.items) |unit| {
            for (unit.references.items) |reference| {
                if (!reference.isResolved()) {
                    has_undefined = true;
                    
                    self.diagnostics.reportError(
                        reference.location,
                        "undefined symbol '{s}'",
                        .{reference.name},
                    );
                }
            }
        }
        
        if (has_undefined) {
            return LinkerError.UndefinedSymbol;
        }
    }
    
    /// 获取链接统计信息
    /// @post 返回链接统计
    pub fn getStatistics(self: *const StaticLinker) LinkStatistics {
        var total_symbols: usize = 0;
        var total_references: usize = 0;
        var resolved_references: usize = 0;
        
        for (self.compilation_units.items) |unit| {
            total_symbols += unit.symbols.count();
            total_references += unit.references.items.len;
            
            for (unit.references.items) |reference| {
                if (reference.isResolved()) {
                    resolved_references += 1;
                }
            }
        }
        
        return .{
            .compilation_units = self.compilation_units.items.len,
            .total_symbols = total_symbols,
            .global_symbols = self.global_symbols.symbols.count(),
            .total_references = total_references,
            .resolved_references = resolved_references,
            .duplicate_definitions = self.global_symbols.duplicate_definitions.count(),
        };
    }
};

/// 向后兼容别名
pub const Linker = StaticLinker;

/// 链接统计信息
pub const LinkStatistics = struct {
    compilation_units: usize,
    total_symbols: usize,
    global_symbols: usize,
    total_references: usize,
    resolved_references: usize,
    duplicate_definitions: usize,
    
    /// 打印统计信息
    pub fn print(self: *const LinkStatistics, writer: anytype) !void {
        try writer.print("=== Link Statistics ===\n", .{});
        try writer.print("Compilation Units: {d}\n", .{self.compilation_units});
        try writer.print("Total Symbols: {d}\n", .{self.total_symbols});
        try writer.print("Global Symbols: {d}\n", .{self.global_symbols});
        try writer.print("Total References: {d}\n", .{self.total_references});
        try writer.print("Resolved References: {d}\n", .{self.resolved_references});
        try writer.print("Duplicate Definitions: {d}\n", .{self.duplicate_definitions});
    }
};

// ============================================================================
// 测试
// ============================================================================

test "SymbolDefinition creation" {
    const symbol = SymbolDefinition.create(
        "test_func",
        .function,
        .public,
        "test.php",
        .{ .line = 10, .column = 5 },
    );
    
    try std.testing.expectEqualStrings("test_func", symbol.name);
    try std.testing.expectEqual(SymbolType.function, symbol.type_);
    try std.testing.expect(symbol.isExportable());
}

test "CompilationUnit basic operations" {
    const allocator = std.testing.allocator;
    
    var unit = try CompilationUnit.init(allocator, "test.php");
    defer unit.deinit();
    
    // 添加符号
    const symbol = SymbolDefinition.create(
        "test_func",
        .function,
        .public,
        "test.php",
        .{ .line = 10, .column = 5 },
    );
    try unit.addSymbol(symbol);
    
    // 查找符号
    const found = unit.findSymbol("test_func");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("test_func", found.?.name);
    
    // 添加引用
    const reference = SymbolReference.create(
        "other_func",
        .function,
        "test.php",
        .{ .line = 20, .column = 10 },
    );
    try unit.addReference(reference);
    
    try std.testing.expectEqual(@as(usize, 1), unit.references.items.len);
}

test "GlobalSymbolTable merge" {
    const allocator = std.testing.allocator;
    
    var table = GlobalSymbolTable.init(allocator);
    defer table.deinit();
    
    // 添加符号
    const symbol1 = SymbolDefinition.create(
        "func1",
        .function,
        .public,
        "file1.php",
        .{ .line = 10, .column = 5 },
    );
    try table.addSymbol(symbol1);
    
    const symbol2 = SymbolDefinition.create(
        "func2",
        .function,
        .public,
        "file2.php",
        .{ .line = 20, .column = 10 },
    );
    try table.addSymbol(symbol2);
    
    // 查找符号
    const found1 = table.findSymbol("func1");
    try std.testing.expect(found1 != null);
    
    const found2 = table.findSymbol("func2");
    try std.testing.expect(found2 != null);
    
    // 不存在的符号
    const not_found = table.findSymbol("func3");
    try std.testing.expect(not_found == null);
}

test "GlobalSymbolTable duplicate detection" {
    const allocator = std.testing.allocator;
    
    var table = GlobalSymbolTable.init(allocator);
    defer table.deinit();
    
    // 添加相同名称的符号
    const symbol1 = SymbolDefinition.create(
        "duplicate_func",
        .function,
        .public,
        "file1.php",
        .{ .line = 10, .column = 5 },
    );
    try table.addSymbol(symbol1);
    
    const symbol2 = SymbolDefinition.create(
        "duplicate_func",
        .function,
        .public,
        "file2.php",
        .{ .line = 20, .column = 10 },
    );
    try table.addSymbol(symbol2);
    
    // 检测重复定义
    try std.testing.expect(table.hasDuplicateDefinitions());
    
    const dups = table.getDuplicateDefinitions("duplicate_func");
    try std.testing.expect(dups != null);
    try std.testing.expectEqual(@as(usize, 2), dups.?.len);
}
