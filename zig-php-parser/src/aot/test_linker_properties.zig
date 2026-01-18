//! 跨文件链接属性测试
//!
//! 本模块实现跨文件链接的属性测试，验证：
//! - 属性 19：跨文件链接正确性
//!
//! ## 测试策略
//! - 使用属性测试验证链接器在各种输入下的正确性
//! - 每个属性测试运行至少 100 次迭代
//! - 生成随机的编译单元、符号定义和引用
//!
//! ## 正确性属性
//! 1. 符号解析正确性：所有可解析的引用都应该被正确解析
//! 2. 重复定义检测：重复定义应该被正确检测
//! 3. 循环依赖检测：循环依赖应该被正确检测
//! 4. 可见性检查：私有符号不应该跨文件可见
//!
//! @test-framework Property-Based Testing
//! @iterations 100+

const std = @import("std");
const testing = std.testing;
const Linker = @import("linker.zig");
const Diagnostics = @import("diagnostics.zig");
const Random = std.Random;

// ============================================================================
// 属性测试框架
// ============================================================================

/// 属性测试配置
const PropertyTestConfig = struct {
    iterations: u32 = 100,
    seed: u64 = 0,
    verbose: bool = false,
};

/// 属性测试结果
const PropertyTestResult = struct {
    passed: u32,
    failed: u32,
    total: u32,
    
    pub fn isSuccess(self: PropertyTestResult) bool {
        return self.failed == 0;
    }
    
    pub fn successRate(self: PropertyTestResult) f64 {
        if (self.total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.passed)) / @as(f64, @floatFromInt(self.total));
    }
};

/// 运行属性测试
fn runPropertyTest(
    allocator: std.mem.Allocator,
    comptime PropertyFn: type,
    property_fn: PropertyFn,
    config: PropertyTestConfig,
) !PropertyTestResult {
    var result = PropertyTestResult{
        .passed = 0,
        .failed = 0,
        .total = config.iterations,
    };
    
    var prng = std.Random.DefaultPrng.init(config.seed);
    const random = prng.random();
    
    var i: u32 = 0;
    while (i < config.iterations) : (i += 1) {
        const test_passed = property_fn(allocator, random) catch |err| blk: {
            if (config.verbose) {
                std.debug.print("Property test iteration {d} failed: {}\n", .{ i, err });
            }
            break :blk false;
        };
        
        if (test_passed) {
            result.passed += 1;
        } else {
            result.failed += 1;
            if (config.verbose) {
                std.debug.print("Property test iteration {d} failed\n", .{i});
            }
        }
    }
    
    return result;
}

// ============================================================================
// 测试数据生成器
// ============================================================================

/// 生成随机符号名称
fn generateSymbolName(allocator: std.mem.Allocator, random: Random) ![]const u8 {
    const len = random.intRangeAtMost(usize, 3, 20);
    const name = try allocator.alloc(u8, len);
    
    for (name, 0..) |*c, idx| {
        if (idx == 0) {
            // 首字符必须是字母
            c.* = 'a' + @as(u8, @intCast(random.intRangeAtMost(u8, 0, 25)));
        } else {
            // 后续字符可以是字母或数字
            const choice = random.intRangeAtMost(u8, 0, 35);
            if (choice < 26) {
                c.* = 'a' + choice;
            } else {
                c.* = '0' + (choice - 26);
            }
        }
    }
    
    return name;
}

/// 生成随机文件路径
fn generateFilePath(allocator: std.mem.Allocator, random: Random) ![]const u8 {
    const name = try generateSymbolName(allocator, random);
    defer allocator.free(name);
    
    return std.fmt.allocPrint(allocator, "{s}.php", .{name});
}

/// 生成随机符号类型
fn generateSymbolType(random: Random) Linker.SymbolType {
    const types = [_]Linker.SymbolType{
        .function,
        .global_variable,
        .class_type,
        .constant,
    };
    const idx = random.intRangeAtMost(usize, 0, types.len - 1);
    return types[idx];
}

/// 生成随机可见性
fn generateVisibility(random: Random) Linker.SymbolVisibility {
    const visibilities = [_]Linker.SymbolVisibility{
        .public,
        .private,
        .protected,
        .internal,
    };
    const idx = random.intRangeAtMost(usize, 0, visibilities.len - 1);
    return visibilities[idx];
}

/// 生成随机源位置
fn generateLocation(random: Random) Diagnostics.SourceLocation {
    return .{
        .line = random.intRangeAtMost(u32, 1, 1000),
        .column = random.intRangeAtMost(u32, 1, 100),
    };
}

/// 生成随机编译单元
fn generateCompilationUnit(
    allocator: std.mem.Allocator,
    random: Random,
    file_path: []const u8,
) !*Linker.CompilationUnit {
    var unit = try allocator.create(Linker.CompilationUnit);
    unit.* = try Linker.CompilationUnit.init(allocator, file_path);
    
    // 生成符号定义
    const num_symbols = random.intRangeAtMost(usize, 1, 10);
    var i: usize = 0;
    while (i < num_symbols) : (i += 1) {
        const name = try generateSymbolName(allocator, random);
        const symbol = Linker.SymbolDefinition.create(
            name,
            generateSymbolType(random),
            generateVisibility(random),
            file_path,
            generateLocation(random),
        );
        try unit.addSymbol(symbol);
    }
    
    return unit;
}

// ============================================================================
// 属性 19：跨文件链接正确性
// ============================================================================

/// 属性 19：符号解析正确性
/// 对于任意多文件项目，链接后的符号引用应该正确解析到定义位置
/// Feature: zig-php-performance-optimization, Property 19
fn property_symbol_resolution_correctness(
    allocator: std.mem.Allocator,
    random: Random,
) !bool {
    // 创建诊断引擎
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();
    
    // 创建链接器
    var linker = try Linker.Linker.init(allocator, &diagnostics);
    defer linker.deinit();
    
    // 生成编译单元
    const num_units = random.intRangeAtMost(usize, 2, 5);
    var units: std.ArrayListUnmanaged(*Linker.CompilationUnit) = .{};
    defer {
        for (units.items) |unit| {
            unit.deinit();
            allocator.destroy(unit);
        }
        units.deinit(allocator);
    }
    
    // 创建编译单元并收集所有符号
    var all_symbols = std.StringHashMap(Linker.SymbolDefinition).init(allocator);
    defer all_symbols.deinit();
    
    var i: usize = 0;
    while (i < num_units) : (i += 1) {
        const file_path = try generateFilePath(allocator, random);
        const unit = try generateCompilationUnit(allocator, random, file_path);
        try units.append(allocator, unit);
        try linker.addCompilationUnit(unit);
        
        // 收集公共符号
        var iter = unit.symbols.iterator();
        while (iter.next()) |entry| {
            const symbol = entry.value_ptr.*;
            if (symbol.isExportable()) {
                try all_symbols.put(symbol.name, symbol);
            }
        }
    }
    
    // 为每个编译单元添加引用
    for (units.items) |unit| {
        const num_refs = random.intRangeAtMost(usize, 0, 5);
        var ref_idx: usize = 0;
        while (ref_idx < num_refs) : (ref_idx += 1) {
            // 随机选择一个已存在的符号
            if (all_symbols.count() == 0) break;
            
            const symbol_idx = random.intRangeAtMost(usize, 0, all_symbols.count() - 1);
            var symbol_iter = all_symbols.iterator();
            var current_idx: usize = 0;
            var target_symbol: ?Linker.SymbolDefinition = null;
            
            while (symbol_iter.next()) |entry| {
                if (current_idx == symbol_idx) {
                    target_symbol = entry.value_ptr.*;
                    break;
                }
                current_idx += 1;
            }
            
            if (target_symbol) |symbol| {
                const reference = Linker.SymbolReference.create(
                    symbol.name,
                    symbol.type_,
                    unit.file_path,
                    generateLocation(random),
                );
                try unit.addReference(reference);
            }
        }
    }
    
    // 执行链接
    linker.link() catch |err| {
        // 某些错误是预期的（如重复定义）
        if (err == Linker.LinkerError.DuplicateDefinition) {
            return true;
        }
        return false;
    };
    
    // 验证所有引用都已解析
    for (units.items) |unit| {
        for (unit.references.items) |reference| {
            if (!reference.isResolved()) {
                // 引用未解析 - 这是错误
                return false;
            }
            
            // 验证解析的定义是正确的
            const resolved = reference.resolved_definition.?;
            if (!std.mem.eql(u8, resolved.name, reference.name)) {
                return false;
            }
            
            if (resolved.type_ != reference.type_) {
                return false;
            }
        }
    }
    
    return true;
}

/// 属性 19.1：重复定义检测
/// 对于任意包含重复定义的项目，链接器应该正确检测并报告错误
fn property_duplicate_definition_detection(
    allocator: std.mem.Allocator,
    random: Random,
) !bool {
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();
    
    var linker = try Linker.Linker.init(allocator, &diagnostics);
    defer linker.deinit();
    
    // 创建两个编译单元，包含相同名称的公共符号
    const file1 = try generateFilePath(allocator, random);
    const file2 = try generateFilePath(allocator, random);
    
    var unit1 = try allocator.create(Linker.CompilationUnit);
    unit1.* = try Linker.CompilationUnit.init(allocator, file1);
    defer {
        unit1.deinit();
        allocator.destroy(unit1);
    }
    
    var unit2 = try allocator.create(Linker.CompilationUnit);
    unit2.* = try Linker.CompilationUnit.init(allocator, file2);
    defer {
        unit2.deinit();
        allocator.destroy(unit2);
    }
    
    // 添加相同名称的符号
    const duplicate_name = try generateSymbolName(allocator, random);
    const symbol1 = Linker.SymbolDefinition.create(
        duplicate_name,
        .function,
        .public,
        file1,
        generateLocation(random),
    );
    try unit1.addSymbol(symbol1);
    
    const symbol2 = Linker.SymbolDefinition.create(
        duplicate_name,
        .function,
        .public,
        file2,
        generateLocation(random),
    );
    try unit2.addSymbol(symbol2);
    
    try linker.addCompilationUnit(unit1);
    try linker.addCompilationUnit(unit2);
    
    // 链接应该失败并报告重复定义
    const link_result = linker.link();
    
    if (link_result) |_| {
        // 链接成功 - 这是错误，应该检测到重复定义
        return false;
    } else |err| {
        // 应该是重复定义错误
        return err == Linker.LinkerError.DuplicateDefinition;
    }
}

/// 属性 19.2：私有符号可见性
/// 对于任意私有符号，不应该在其定义文件外可见
fn property_private_symbol_visibility(
    allocator: std.mem.Allocator,
    random: Random,
) !bool {
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();
    
    var linker = try Linker.Linker.init(allocator, &diagnostics);
    defer linker.deinit();
    
    // 创建两个编译单元
    const file1 = try generateFilePath(allocator, random);
    const file2 = try generateFilePath(allocator, random);
    
    var unit1 = try allocator.create(Linker.CompilationUnit);
    unit1.* = try Linker.CompilationUnit.init(allocator, file1);
    defer {
        unit1.deinit();
        allocator.destroy(unit1);
    }
    
    var unit2 = try allocator.create(Linker.CompilationUnit);
    unit2.* = try Linker.CompilationUnit.init(allocator, file2);
    defer {
        unit2.deinit();
        allocator.destroy(unit2);
    }
    
    // 在 unit1 中定义私有符号
    const private_name = try generateSymbolName(allocator, random);
    const private_symbol = Linker.SymbolDefinition.create(
        private_name,
        .function,
        .private,
        file1,
        generateLocation(random),
    );
    try unit1.addSymbol(private_symbol);
    
    // 在 unit2 中引用该私有符号
    const reference = Linker.SymbolReference.create(
        private_name,
        .function,
        file2,
        generateLocation(random),
    );
    try unit2.addReference(reference);
    
    try linker.addCompilationUnit(unit1);
    try linker.addCompilationUnit(unit2);
    
    // 链接应该失败（私有符号不可见）或引用未解析
    const link_result = linker.link();
    
    if (link_result) |_| {
        // 检查引用是否未解析
        for (unit2.references.items) |ref| {
            if (std.mem.eql(u8, ref.name, private_name)) {
                // 私有符号不应该被解析
                return !ref.isResolved();
            }
        }
        return false;
    } else |err| {
        // 链接失败是预期的
        return err == Linker.LinkerError.UndefinedSymbol or
            err == Linker.LinkerError.VisibilityViolation;
    }
}

/// 属性 19.3：循环依赖检测
/// 对于任意包含循环依赖的项目，链接器应该正确检测
fn property_circular_dependency_detection(
    allocator: std.mem.Allocator,
    random: Random,
) !bool {
    var diagnostics = Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();
    
    var linker = try Linker.Linker.init(allocator, &diagnostics);
    defer linker.deinit();
    
    // 创建三个编译单元形成循环：A -> B -> C -> A
    const file_a = try generateFilePath(allocator, random);
    const file_b = try generateFilePath(allocator, random);
    const file_c = try generateFilePath(allocator, random);
    
    var unit_a = try allocator.create(Linker.CompilationUnit);
    unit_a.* = try Linker.CompilationUnit.init(allocator, file_a);
    defer {
        unit_a.deinit();
        allocator.destroy(unit_a);
    }
    
    var unit_b = try allocator.create(Linker.CompilationUnit);
    unit_b.* = try Linker.CompilationUnit.init(allocator, file_b);
    defer {
        unit_b.deinit();
        allocator.destroy(unit_b);
    }
    
    var unit_c = try allocator.create(Linker.CompilationUnit);
    unit_c.* = try Linker.CompilationUnit.init(allocator, file_c);
    defer {
        unit_c.deinit();
        allocator.destroy(unit_c);
    }
    
    // 建立循环依赖
    try unit_a.addDependency(file_b);
    try unit_b.addDependency(file_c);
    try unit_c.addDependency(file_a);
    
    try linker.addCompilationUnit(unit_a);
    try linker.addCompilationUnit(unit_b);
    try linker.addCompilationUnit(unit_c);
    
    // 链接应该失败并检测到循环依赖
    const link_result = linker.link();
    
    if (link_result) |_| {
        // 链接成功 - 这是错误，应该检测到循环依赖
        return false;
    } else |err| {
        // 应该是循环依赖错误
        return err == Linker.LinkerError.CircularDependency;
    }
}

// ============================================================================
// 主测试入口
// ============================================================================

test "Property 19: Cross-file linking correctness - Symbol resolution" {
    // Feature: zig-php-performance-optimization, Property 19
    const config = PropertyTestConfig{
        .iterations = 100,
        .seed = 12345,
        .verbose = false,
    };
    
    const result = try runPropertyTest(
        testing.allocator,
        @TypeOf(property_symbol_resolution_correctness),
        property_symbol_resolution_correctness,
        config,
    );
    
    std.debug.print("\n=== Property 19: Symbol Resolution Correctness ===\n", .{});
    std.debug.print("Passed: {d}/{d} ({d:.2}%)\n", .{
        result.passed,
        result.total,
        result.successRate() * 100.0,
    });
    
    try testing.expect(result.isSuccess());
}

test "Property 19.1: Duplicate definition detection" {
    // Feature: zig-php-performance-optimization, Property 19
    const config = PropertyTestConfig{
        .iterations = 100,
        .seed = 23456,
        .verbose = false,
    };
    
    const result = try runPropertyTest(
        testing.allocator,
        @TypeOf(property_duplicate_definition_detection),
        property_duplicate_definition_detection,
        config,
    );
    
    std.debug.print("\n=== Property 19.1: Duplicate Definition Detection ===\n", .{});
    std.debug.print("Passed: {d}/{d} ({d:.2}%)\n", .{
        result.passed,
        result.total,
        result.successRate() * 100.0,
    });
    
    try testing.expect(result.isSuccess());
}

test "Property 19.2: Private symbol visibility" {
    // Feature: zig-php-performance-optimization, Property 19
    const config = PropertyTestConfig{
        .iterations = 100,
        .seed = 34567,
        .verbose = false,
    };
    
    const result = try runPropertyTest(
        testing.allocator,
        @TypeOf(property_private_symbol_visibility),
        property_private_symbol_visibility,
        config,
    );
    
    std.debug.print("\n=== Property 19.2: Private Symbol Visibility ===\n", .{});
    std.debug.print("Passed: {d}/{d} ({d:.2}%)\n", .{
        result.passed,
        result.total,
        result.successRate() * 100.0,
    });
    
    try testing.expect(result.isSuccess());
}

test "Property 19.3: Circular dependency detection" {
    // Feature: zig-php-performance-optimization, Property 19
    const config = PropertyTestConfig{
        .iterations = 100,
        .seed = 45678,
        .verbose = false,
    };
    
    const result = try runPropertyTest(
        testing.allocator,
        @TypeOf(property_circular_dependency_detection),
        property_circular_dependency_detection,
        config,
    );
    
    std.debug.print("\n=== Property 19.3: Circular Dependency Detection ===\n", .{});
    std.debug.print("Passed: {d}/{d} ({d:.2}%)\n", .{
        result.passed,
        result.total,
        result.successRate() * 100.0,
    });
    
    try testing.expect(result.isSuccess());
}

// ============================================================================
// 单元测试
// ============================================================================

test "Linker basic functionality" {
    var diagnostics = Diagnostics.DiagnosticEngine.init(testing.allocator);
    defer diagnostics.deinit();
    
    var linker = try Linker.Linker.init(testing.allocator, &diagnostics);
    defer linker.deinit();
    
    // 创建编译单元
    var unit = try testing.allocator.create(Linker.CompilationUnit);
    defer testing.allocator.destroy(unit);
    unit.* = try Linker.CompilationUnit.init(testing.allocator, "test.php");
    defer unit.deinit();
    
    // 添加符号
    const symbol = Linker.SymbolDefinition.create(
        "test_func",
        .function,
        .public,
        "test.php",
        .{ .line = 10, .column = 5 },
    );
    try unit.addSymbol(symbol);
    
    // 添加到链接器
    try linker.addCompilationUnit(unit);
    
    // 执行链接
    try linker.link();
    
    // 验证统计信息
    const stats = linker.getStatistics();
    try testing.expectEqual(@as(usize, 1), stats.compilation_units);
    try testing.expectEqual(@as(usize, 1), stats.total_symbols);
}

test "Linker resolves cross-file references" {
    var diagnostics = Diagnostics.DiagnosticEngine.init(testing.allocator);
    defer diagnostics.deinit();
    
    var linker = try Linker.Linker.init(testing.allocator, &diagnostics);
    defer linker.deinit();
    
    // 创建两个编译单元
    var unit1 = try testing.allocator.create(Linker.CompilationUnit);
    defer testing.allocator.destroy(unit1);
    unit1.* = try Linker.CompilationUnit.init(testing.allocator, "file1.php");
    defer unit1.deinit();
    
    var unit2 = try testing.allocator.create(Linker.CompilationUnit);
    defer testing.allocator.destroy(unit2);
    unit2.* = try Linker.CompilationUnit.init(testing.allocator, "file2.php");
    defer unit2.deinit();
    
    // unit1 定义符号
    const symbol = Linker.SymbolDefinition.create(
        "shared_func",
        .function,
        .public,
        "file1.php",
        .{ .line = 10, .column = 5 },
    );
    try unit1.addSymbol(symbol);
    
    // unit2 引用符号
    const reference = Linker.SymbolReference.create(
        "shared_func",
        .function,
        "file2.php",
        .{ .line = 20, .column = 10 },
    );
    try unit2.addReference(reference);
    
    // 添加到链接器
    try linker.addCompilationUnit(unit1);
    try linker.addCompilationUnit(unit2);
    
    // 执行链接
    try linker.link();
    
    // 验证引用已解析
    try testing.expect(unit2.references.items[0].isResolved());
    try testing.expectEqualStrings(
        "shared_func",
        unit2.references.items[0].resolved_definition.?.name,
    );
}
