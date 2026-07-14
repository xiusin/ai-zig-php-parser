/// JIT 调试信息模块
///
/// 实现机器码到源代码的映射和调试符号生成
///
/// @ownership NON-OWNING (allocator)
/// @thread-safety ISOLATED (单线程)
/// @验证：需求 10.1
const std = @import("std");

/// 源代码位置信息
/// @memory-layout 紧凑布局以优化缓存
pub const SourceLocation = struct {
    /// 文件路径
    file_path: []const u8,

    /// 行号（从 1 开始）
    line: u32,

    /// 列号（从 1 开始）
    column: u32,

    /// 函数名
    function_name: []const u8,

    /// 创建源代码位置
    /// @pre file_path 和 function_name 必须有效
    /// @post 返回初始化的位置信息
    pub fn init(
        file_path: []const u8,
        line: u32,
        column: u32,
        function_name: []const u8,
    ) SourceLocation {
        return .{
            .file_path = file_path,
            .line = line,
            .column = column,
            .function_name = function_name,
        };
    }

    /// 格式化输出
    pub fn format(
        self: SourceLocation,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}:{d}:{d} in {s}", .{
            self.file_path,
            self.line,
            self.column,
            self.function_name,
        });
    }
};

/// 机器码地址范围
pub const AddressRange = struct {
    /// 起始地址
    start: usize,

    /// 结束地址（不包含）
    end: usize,

    /// 检查地址是否在范围内
    /// @pre start <= end
    /// @post 返回 address 是否在 [start, end) 范围内
    pub fn contains(self: AddressRange, address: usize) bool {
        return address >= self.start and address < self.end;
    }

    /// 获取范围大小
    pub fn size(self: AddressRange) usize {
        return self.end - self.start;
    }
};

/// 机器码到源代码的映射条目
/// @memory-layout 64 字节对齐以优化缓存行
pub const CodeMapping = struct {
    /// 机器码地址范围
    address_range: AddressRange,

    /// 对应的源代码位置
    source_location: SourceLocation,

    /// 字节码指令索引（可选）
    bytecode_ip: ?usize,

    /// 创建代码映射
    pub fn init(
        address_range: AddressRange,
        source_location: SourceLocation,
        bytecode_ip: ?usize,
    ) CodeMapping {
        return .{
            .address_range = address_range,
            .source_location = source_location,
            .bytecode_ip = bytecode_ip,
        };
    }
};

/// 调试符号类型
pub const SymbolType = enum {
    /// 函数符号
    function,

    /// 变量符号
    variable,

    /// 参数符号
    parameter,

    /// 局部变量符号
    local,

    /// 临时变量符号
    temporary,
};

/// 调试符号
pub const DebugSymbol = struct {
    /// 符号名称
    name: []const u8,

    /// 符号类型
    type_: SymbolType,

    /// 地址或偏移量
    address: usize,

    /// 大小（字节）
    size: usize,

    /// 源代码位置
    source_location: SourceLocation,

    /// 创建调试符号
    pub fn init(
        name: []const u8,
        type_: SymbolType,
        address: usize,
        size: usize,
        source_location: SourceLocation,
    ) DebugSymbol {
        return .{
            .name = name,
            .type_ = type_,
            .address = address,
            .size = size,
            .source_location = source_location,
        };
    }
};

/// JIT 调试信息管理器
/// @concurrency-model ISOLATED
pub const DebugInfoManager = struct {
    allocator: std.mem.Allocator,

    /// 代码映射表（按地址排序）
    code_mappings: std.ArrayListUnmanaged(CodeMapping),

    /// 调试符号表
    debug_symbols: std.StringHashMap(DebugSymbol),

    /// 函数地址映射
    function_addresses: std.StringHashMap(AddressRange),

    /// 统计信息
    stats: Stats,

    /// 统计信息
    pub const Stats = struct {
        /// 映射条目数量
        mapping_count: usize = 0,

        /// 符号数量
        symbol_count: usize = 0,

        /// 查找次数
        lookup_count: usize = 0,

        /// 查找命中次数
        lookup_hits: usize = 0,

        /// 获取命中率
        pub fn hitRate(self: Stats) f64 {
            if (self.lookup_count == 0) return 0.0;
            return @as(f64, @floatFromInt(self.lookup_hits)) /
                @as(f64, @floatFromInt(self.lookup_count));
        }
    };

    /// 初始化调试信息管理器
    /// @pre allocator 必须有效
    /// @post 返回初始化的管理器实例
    pub fn init(allocator: std.mem.Allocator) DebugInfoManager {
        return .{
            .allocator = allocator,
            .code_mappings = .{},
            .debug_symbols = std.StringHashMap(DebugSymbol).init(allocator),
            .function_addresses = std.StringHashMap(AddressRange).init(allocator),
            .stats = .{},
        };
    }

    /// 清理资源
    /// @pre self 必须已初始化
    /// @post 释放所有资源
    pub fn deinit(self: *DebugInfoManager) void {
        self.code_mappings.deinit(self.allocator);
        self.debug_symbols.deinit();
        self.function_addresses.deinit();
    }

    /// 添加代码映射
    /// @pre mapping 必须有效
    /// @post 映射被添加到表中，保持地址排序
    pub fn addCodeMapping(self: *DebugInfoManager, mapping: CodeMapping) !void {
        try self.code_mappings.append(self.allocator, mapping);
        self.stats.mapping_count += 1;

        // 保持按地址排序（插入排序，因为通常是顺序添加）
        var i = self.code_mappings.items.len - 1;
        while (i > 0) : (i -= 1) {
            const curr = self.code_mappings.items[i];
            const prev = self.code_mappings.items[i - 1];

            if (curr.address_range.start >= prev.address_range.start) {
                break;
            }

            // 交换
            self.code_mappings.items[i] = prev;
            self.code_mappings.items[i - 1] = curr;
        }
    }

    /// 批量添加代码映射
    /// @pre mappings 必须有效
    /// @post 所有映射被添加并排序
    pub fn addCodeMappings(self: *DebugInfoManager, mappings: []const CodeMapping) !void {
        for (mappings) |mapping| {
            try self.addCodeMapping(mapping);
        }
    }

    /// 添加调试符号
    /// @pre symbol 必须有效
    /// @post 符号被添加到符号表
    pub fn addDebugSymbol(self: *DebugInfoManager, symbol: DebugSymbol) !void {
        try self.debug_symbols.put(symbol.name, symbol);
        self.stats.symbol_count += 1;
    }

    /// 注册函数地址范围
    /// @pre function_name 必须有效
    /// @post 函数地址范围被记录
    pub fn registerFunction(
        self: *DebugInfoManager,
        function_name: []const u8,
        address_range: AddressRange,
    ) !void {
        try self.function_addresses.put(function_name, address_range);
    }

    /// 根据机器码地址查找源代码位置
    /// @pre address 必须是有效的机器码地址
    /// @post 返回对应的源代码位置，如果找不到返回 null
    pub fn lookupSourceLocation(
        self: *DebugInfoManager,
        address: usize,
    ) ?SourceLocation {
        self.stats.lookup_count += 1;

        // 二分查找
        var left: usize = 0;
        var right: usize = self.code_mappings.items.len;

        while (left < right) {
            const mid = left + (right - left) / 2;
            const mapping = self.code_mappings.items[mid];

            if (mapping.address_range.contains(address)) {
                self.stats.lookup_hits += 1;
                return mapping.source_location;
            } else if (address < mapping.address_range.start) {
                right = mid;
            } else {
                left = mid + 1;
            }
        }

        return null;
    }

    /// 根据符号名查找调试符号
    /// @pre name 必须有效
    /// @post 返回对应的调试符号，如果找不到返回 null
    pub fn lookupSymbol(self: *DebugInfoManager, name: []const u8) ?DebugSymbol {
        return self.debug_symbols.get(name);
    }

    /// 根据函数名查找地址范围
    /// @pre function_name 必须有效
    /// @post 返回函数的地址范围，如果找不到返回 null
    pub fn lookupFunctionAddress(
        self: *DebugInfoManager,
        function_name: []const u8,
    ) ?AddressRange {
        return self.function_addresses.get(function_name);
    }

    /// 获取地址范围内的所有映射
    /// @pre range 必须有效
    /// @post 返回范围内的所有映射
    pub fn getMappingsInRange(
        self: *DebugInfoManager,
        range: AddressRange,
    ) !std.ArrayListUnmanaged(CodeMapping) {
        var result: std.ArrayListUnmanaged(CodeMapping) = .{};

        for (self.code_mappings.items) |mapping| {
            // 检查是否有重叠
            if (mapping.address_range.start < range.end and
                mapping.address_range.end > range.start)
            {
                try result.append(self.allocator, mapping);
            }
        }

        return result;
    }

    /// 生成堆栈跟踪
    /// @pre addresses 必须是有效的返回地址数组
    /// @post 返回格式化的堆栈跟踪字符串
    pub fn generateStackTrace(
        self: *DebugInfoManager,
        addresses: []const usize,
        writer: anytype,
    ) !void {
        try writer.writeAll("Stack trace:\n");

        for (addresses, 0..) |address, i| {
            try writer.print("  #{d}: 0x{x:0>16}", .{ i, address });

            if (self.lookupSourceLocation(address)) |location| {
                try writer.print(" at {s}:{d}:{d} in {s}", .{
                    location.file_path,
                    location.line,
                    location.column,
                    location.function_name,
                });
            } else {
                try writer.writeAll(" (unknown location)");
            }

            try writer.writeAll("\n");
        }
    }

    /// 打印调试信息统计
    pub fn printStats(self: *DebugInfoManager, writer: anytype) !void {
        try writer.writeAll("\n=== JIT Debug Info Statistics ===\n");
        try writer.print("Code mappings: {d}\n", .{self.stats.mapping_count});
        try writer.print("Debug symbols: {d}\n", .{self.stats.symbol_count});
        try writer.print("Lookup count: {d}\n", .{self.stats.lookup_count});
        try writer.print("Lookup hits: {d}\n", .{self.stats.lookup_hits});
        try writer.print("Hit rate: {d:.2}%\n", .{self.stats.hitRate() * 100.0});
    }

    /// 清空所有调试信息
    pub fn clear(self: *DebugInfoManager) void {
        self.code_mappings.clearRetainingCapacity();
        self.debug_symbols.clearRetainingCapacity();
        self.function_addresses.clearRetainingCapacity();
        self.stats = .{};
    }
};

/// 调试信息构建器
/// 用于在 JIT 编译过程中收集调试信息
pub const DebugInfoBuilder = struct {
    allocator: std.mem.Allocator,

    /// 当前函数名
    current_function: []const u8,

    /// 当前文件路径
    current_file: []const u8,

    /// 代码起始地址
    code_start_address: usize,

    /// 当前代码偏移量
    current_offset: usize,

    /// 待添加的映射
    pending_mappings: std.ArrayListUnmanaged(CodeMapping),

    /// 待添加的符号
    pending_symbols: std.ArrayListUnmanaged(DebugSymbol),

    /// 初始化构建器
    pub fn init(
        allocator: std.mem.Allocator,
        function_name: []const u8,
        file_path: []const u8,
        code_start_address: usize,
    ) DebugInfoBuilder {
        return .{
            .allocator = allocator,
            .current_function = function_name,
            .current_file = file_path,
            .code_start_address = code_start_address,
            .current_offset = 0,
            .pending_mappings = .{},
            .pending_symbols = .{},
        };
    }

    /// 清理资源
    pub fn deinit(self: *DebugInfoBuilder) void {
        self.pending_mappings.deinit(self.allocator);
        self.pending_symbols.deinit(self.allocator);
    }

    /// 记录指令映射
    /// @pre line 和 column 必须有效
    /// @post 添加从当前偏移量到指令的映射
    pub fn recordInstruction(
        self: *DebugInfoBuilder,
        line: u32,
        column: u32,
        instruction_size: usize,
        bytecode_ip: ?usize,
    ) !void {
        const start_address = self.code_start_address + self.current_offset;
        const end_address = start_address + instruction_size;

        const mapping = CodeMapping.init(
            .{ .start = start_address, .end = end_address },
            SourceLocation.init(
                self.current_file,
                line,
                column,
                self.current_function,
            ),
            bytecode_ip,
        );

        try self.pending_mappings.append(self.allocator, mapping);
        self.current_offset += instruction_size;
    }

    /// 记录变量符号
    pub fn recordVariable(
        self: *DebugInfoBuilder,
        name: []const u8,
        type_: SymbolType,
        address: usize,
        size: usize,
        line: u32,
        column: u32,
    ) !void {
        const symbol = DebugSymbol.init(
            name,
            type_,
            address,
            size,
            SourceLocation.init(
                self.current_file,
                line,
                column,
                self.current_function,
            ),
        );

        try self.pending_symbols.append(self.allocator, symbol);
    }

    /// 完成构建并提交到管理器
    pub fn finalize(self: *DebugInfoBuilder, manager: *DebugInfoManager) !void {
        // 添加所有映射
        for (self.pending_mappings.items) |mapping| {
            try manager.addCodeMapping(mapping);
        }

        // 添加所有符号
        for (self.pending_symbols.items) |symbol| {
            try manager.addDebugSymbol(symbol);
        }

        // 注册函数地址范围
        const function_range = AddressRange{
            .start = self.code_start_address,
            .end = self.code_start_address + self.current_offset,
        };
        try manager.registerFunction(self.current_function, function_range);
    }
};

// ============================================================================
// 测试
// ============================================================================

test "SourceLocation 基本功能" {
    const location = SourceLocation.init(
        "test.php",
        42,
        10,
        "testFunction",
    );

    try std.testing.expectEqualStrings("test.php", location.file_path);
    try std.testing.expectEqual(@as(u32, 42), location.line);
    try std.testing.expectEqual(@as(u32, 10), location.column);
    try std.testing.expectEqualStrings("testFunction", location.function_name);
}

test "AddressRange 包含检查" {
    const range = AddressRange{ .start = 0x1000, .end = 0x2000 };

    try std.testing.expect(range.contains(0x1000));
    try std.testing.expect(range.contains(0x1500));
    try std.testing.expect(range.contains(0x1FFF));
    try std.testing.expect(!range.contains(0x0FFF));
    try std.testing.expect(!range.contains(0x2000));
    try std.testing.expect(!range.contains(0x2001));

    try std.testing.expectEqual(@as(usize, 0x1000), range.size());
}

test "DebugInfoManager 基本操作" {
    var manager = DebugInfoManager.init(std.testing.allocator);
    defer manager.deinit();

    // 添加代码映射
    const mapping1 = CodeMapping.init(
        .{ .start = 0x1000, .end = 0x1010 },
        SourceLocation.init("test.php", 10, 5, "func1"),
        0,
    );
    try manager.addCodeMapping(mapping1);

    const mapping2 = CodeMapping.init(
        .{ .start = 0x1010, .end = 0x1020 },
        SourceLocation.init("test.php", 11, 5, "func1"),
        1,
    );
    try manager.addCodeMapping(mapping2);

    // 查找源代码位置
    const loc1 = manager.lookupSourceLocation(0x1005);
    try std.testing.expect(loc1 != null);
    try std.testing.expectEqual(@as(u32, 10), loc1.?.line);

    const loc2 = manager.lookupSourceLocation(0x1015);
    try std.testing.expect(loc2 != null);
    try std.testing.expectEqual(@as(u32, 11), loc2.?.line);

    const loc3 = manager.lookupSourceLocation(0x2000);
    try std.testing.expect(loc3 == null);

    // 检查统计
    try std.testing.expectEqual(@as(usize, 2), manager.stats.mapping_count);
    try std.testing.expectEqual(@as(usize, 3), manager.stats.lookup_count);
    try std.testing.expectEqual(@as(usize, 2), manager.stats.lookup_hits);
}

test "DebugInfoManager 调试符号" {
    var manager = DebugInfoManager.init(std.testing.allocator);
    defer manager.deinit();

    // 添加符号
    const symbol = DebugSymbol.init(
        "myVar",
        .local,
        0x1000,
        8,
        SourceLocation.init("test.php", 5, 10, "func1"),
    );
    try manager.addDebugSymbol(symbol);

    // 查找符号
    const found = manager.lookupSymbol("myVar");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("myVar", found.?.name);
    try std.testing.expectEqual(SymbolType.local, found.?.type_);
    try std.testing.expectEqual(@as(usize, 0x1000), found.?.address);

    const not_found = manager.lookupSymbol("nonexistent");
    try std.testing.expect(not_found == null);
}

test "DebugInfoManager 函数地址查找" {
    var manager = DebugInfoManager.init(std.testing.allocator);
    defer manager.deinit();

    // 注册函数
    const range = AddressRange{ .start = 0x1000, .end = 0x2000 };
    try manager.registerFunction("testFunc", range);

    // 查找函数地址
    const found = manager.lookupFunctionAddress("testFunc");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(@as(usize, 0x1000), found.?.start);
    try std.testing.expectEqual(@as(usize, 0x2000), found.?.end);

    const not_found = manager.lookupFunctionAddress("nonexistent");
    try std.testing.expect(not_found == null);
}

test "DebugInfoBuilder 工作流" {
    var manager = DebugInfoManager.init(std.testing.allocator);
    defer manager.deinit();

    // 创建构建器
    var builder = DebugInfoBuilder.init(
        std.testing.allocator,
        "testFunc",
        "test.php",
        0x1000,
    );
    defer builder.deinit();

    // 记录指令
    try builder.recordInstruction(10, 5, 4, 0);
    try builder.recordInstruction(11, 5, 4, 1);
    try builder.recordInstruction(12, 5, 4, 2);

    // 记录变量
    try builder.recordVariable("x", .local, 0x1000, 8, 10, 5);
    try builder.recordVariable("y", .local, 0x1008, 8, 11, 5);

    // 完成构建
    try builder.finalize(&manager);

    // 验证映射
    try std.testing.expectEqual(@as(usize, 3), manager.stats.mapping_count);

    const loc1 = manager.lookupSourceLocation(0x1002);
    try std.testing.expect(loc1 != null);
    try std.testing.expectEqual(@as(u32, 10), loc1.?.line);

    // 验证符号
    try std.testing.expectEqual(@as(usize, 2), manager.stats.symbol_count);

    const sym_x = manager.lookupSymbol("x");
    try std.testing.expect(sym_x != null);
    try std.testing.expectEqual(@as(usize, 0x1000), sym_x.?.address);

    // 验证函数地址
    const func_range = manager.lookupFunctionAddress("testFunc");
    try std.testing.expect(func_range != null);
    try std.testing.expectEqual(@as(usize, 0x1000), func_range.?.start);
    try std.testing.expectEqual(@as(usize, 0x100C), func_range.?.end);
}

test "DebugInfoManager 地址排序" {
    var manager = DebugInfoManager.init(std.testing.allocator);
    defer manager.deinit();

    // 乱序添加映射
    try manager.addCodeMapping(CodeMapping.init(
        .{ .start = 0x1020, .end = 0x1030 },
        SourceLocation.init("test.php", 12, 5, "func1"),
        2,
    ));

    try manager.addCodeMapping(CodeMapping.init(
        .{ .start = 0x1000, .end = 0x1010 },
        SourceLocation.init("test.php", 10, 5, "func1"),
        0,
    ));

    try manager.addCodeMapping(CodeMapping.init(
        .{ .start = 0x1010, .end = 0x1020 },
        SourceLocation.init("test.php", 11, 5, "func1"),
        1,
    ));

    // 验证排序
    try std.testing.expectEqual(@as(usize, 0x1000), manager.code_mappings.items[0].address_range.start);
    try std.testing.expectEqual(@as(usize, 0x1010), manager.code_mappings.items[1].address_range.start);
    try std.testing.expectEqual(@as(usize, 0x1020), manager.code_mappings.items[2].address_range.start);
}

test "DebugInfoManager 范围查询" {
    var manager = DebugInfoManager.init(std.testing.allocator);
    defer manager.deinit();

    // 添加多个映射
    try manager.addCodeMapping(CodeMapping.init(
        .{ .start = 0x1000, .end = 0x1010 },
        SourceLocation.init("test.php", 10, 5, "func1"),
        0,
    ));

    try manager.addCodeMapping(CodeMapping.init(
        .{ .start = 0x1010, .end = 0x1020 },
        SourceLocation.init("test.php", 11, 5, "func1"),
        1,
    ));

    try manager.addCodeMapping(CodeMapping.init(
        .{ .start = 0x2000, .end = 0x2010 },
        SourceLocation.init("test.php", 20, 5, "func2"),
        10,
    ));

    // 查询范围
    const range = AddressRange{ .start = 0x1005, .end = 0x1015 };
    var mappings = try manager.getMappingsInRange(range);
    defer mappings.deinit(std.testing.allocator);

    // 应该找到前两个映射
    try std.testing.expectEqual(@as(usize, 2), mappings.items.len);
}

test "DebugInfoManager 统计信息" {
    var manager = DebugInfoManager.init(std.testing.allocator);
    defer manager.deinit();

    // 添加映射
    try manager.addCodeMapping(CodeMapping.init(
        .{ .start = 0x1000, .end = 0x1010 },
        SourceLocation.init("test.php", 10, 5, "func1"),
        0,
    ));

    // 执行查找
    _ = manager.lookupSourceLocation(0x1005); // 命中
    _ = manager.lookupSourceLocation(0x2000); // 未命中
    _ = manager.lookupSourceLocation(0x1008); // 命中

    // 验证统计
    try std.testing.expectEqual(@as(usize, 3), manager.stats.lookup_count);
    try std.testing.expectEqual(@as(usize, 2), manager.stats.lookup_hits);

    const hit_rate = manager.stats.hitRate();
    try std.testing.expect(hit_rate > 0.66 and hit_rate < 0.67);
}
