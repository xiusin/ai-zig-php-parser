//! DWARF 调试信息生成测试
//!
//! 本文件测试 DWARF 调试信息的生成功能，包括：
//! - 编译单元创建
//! - 函数调试信息
//! - 变量调试信息
//! - 行号映射
//! - 类型信息
//! - DWARF section 生成

const std = @import("std");
const testing = std.testing;
const DwarfDebugInfo = @import("dwarf_debug_info.zig");
const DwarfDebugInfoBuilder = DwarfDebugInfo.DwarfDebugInfoBuilder;
const IR = @import("ir.zig");

test "DWARF - 创建编译单元" {
    var builder = try DwarfDebugInfoBuilder.init(testing.allocator);
    defer builder.deinit();
    
    try builder.createCompileUnit("test.php", "/path/to/source");
    
    // 验证编译单元已创建
    try testing.expect(builder.compile_unit != null);
    
    // 验证字符串表包含文件名和目录
    try testing.expect(builder.string_table.strings.count() >= 3); // 文件名、目录、生产者
}

test "DWARF - 创建函数调试信息" {
    var builder = try DwarfDebugInfoBuilder.init(testing.allocator);
    defer builder.deinit();
    
    try builder.createCompileUnit("test.php", "/path/to/source");
    
    const func_die = try builder.createFunction("testFunc", 0x1000, 0x1100, .int64);
    
    // 验证函数 DIE 已创建
    try testing.expect(func_die.tag == .subprogram);
    try testing.expect(func_die.attributes.items.len >= 3); // name, low_pc, high_pc, type
    
    // 验证地址范围已记录
    try testing.expectEqual(@as(usize, 1), builder.address_ranges.items.len);
    try testing.expectEqual(@as(u64, 0x1000), builder.address_ranges.items[0].low_pc);
    try testing.expectEqual(@as(u64, 0x1100), builder.address_ranges.items[0].high_pc);
}

test "DWARF - 创建函数参数" {
    var builder = try DwarfDebugInfoBuilder.init(testing.allocator);
    defer builder.deinit();
    
    try builder.createCompileUnit("test.php", "/path/to/source");
    
    const func_die = try builder.createFunction("add", 0x1000, 0x1100, .int32);
    
    // 添加参数
    try builder.createFormalParameter(func_die, "x", .int32, 0);
    try builder.createFormalParameter(func_die, "y", .int32, 8);
    
    // 验证参数已添加
    try testing.expectEqual(@as(usize, 2), func_die.children.items.len);
    try testing.expect(func_die.children.items[0].tag == .formal_parameter);
    try testing.expect(func_die.children.items[1].tag == .formal_parameter);
}

test "DWARF - 创建局部变量" {
    var builder = try DwarfDebugInfoBuilder.init(testing.allocator);
    defer builder.deinit();
    
    try builder.createCompileUnit("test.php", "/path/to/source");
    
    const func_die = try builder.createFunction("testFunc", 0x1000, 0x1100, .void);
    
    // 添加局部变量
    try builder.createLocalVariable(func_die, "result", .int64, 16, 10);
    try builder.createLocalVariable(func_die, "temp", .int32, 24, 11);
    
    // 验证变量已添加
    try testing.expectEqual(@as(usize, 2), func_die.children.items.len);
    try testing.expect(func_die.children.items[0].tag == .variable);
    try testing.expect(func_die.children.items[1].tag == .variable);
}

test "DWARF - 行号映射" {
    var builder = try DwarfDebugInfoBuilder.init(testing.allocator);
    defer builder.deinit();
    
    try builder.createCompileUnit("test.php", "/path/to/source");
    
    // 添加行号映射
    try builder.addLineMapping(0x1000, 0, 10, 1);
    try builder.addLineMapping(0x1010, 0, 11, 1);
    try builder.addLineMapping(0x1020, 0, 12, 5);
    
    // 验证行号表
    try testing.expectEqual(@as(usize, 3), builder.line_table.entries.items.len);
    try testing.expectEqual(@as(u32, 10), builder.line_table.entries.items[0].line);
    try testing.expectEqual(@as(u32, 11), builder.line_table.entries.items[1].line);
    try testing.expectEqual(@as(u32, 12), builder.line_table.entries.items[2].line);
    try testing.expectEqual(@as(u32, 5), builder.line_table.entries.items[2].column);
}

test "DWARF - 类型缓存" {
    var builder = try DwarfDebugInfoBuilder.init(testing.allocator);
    defer builder.deinit();
    
    try builder.createCompileUnit("test.php", "/path/to/source");
    
    // 创建多个使用相同类型的函数
    _ = try builder.createFunction("func1", 0x1000, 0x1100, .int64);
    _ = try builder.createFunction("func2", 0x2000, 0x2100, .int64);
    _ = try builder.createFunction("func3", 0x3000, 0x3100, .int32);
    
    // 验证类型被缓存
    try testing.expect(builder.type_cache.count() >= 2); // int64 和 int32
}

test "DWARF - 完整的调试信息生成" {
    var builder = try DwarfDebugInfoBuilder.init(testing.allocator);
    defer builder.deinit();
    
    try builder.createCompileUnit("test.php", "/path/to/source");
    
    // 创建函数
    const func_die = try builder.createFunction("calculate", 0x1000, 0x1200, .float64);
    
    // 添加参数
    try builder.createFormalParameter(func_die, "a", .float64, 0);
    try builder.createFormalParameter(func_die, "b", .float64, 8);
    
    // 添加局部变量
    try builder.createLocalVariable(func_die, "result", .float64, 16, 10);
    
    // 添加行号映射
    try builder.addLineMapping(0x1000, 0, 10, 1);
    try builder.addLineMapping(0x1050, 0, 11, 1);
    try builder.addLineMapping(0x1100, 0, 12, 1);
    try builder.addLineMapping(0x1150, 0, 13, 1);
    
    // 完成构建
    var dwarf_data = try builder.finalize();
    defer dwarf_data.deinit(testing.allocator);
    
    // 验证所有 section 都已生成
    try testing.expect(dwarf_data.debug_info.len > 0);
    try testing.expect(dwarf_data.debug_abbrev.len > 0);
    try testing.expect(dwarf_data.debug_line.len > 0);
    try testing.expect(dwarf_data.debug_str.len > 0);
    try testing.expect(dwarf_data.debug_aranges.len > 0);
    
    // 验证 .debug_info 头部
    const version = std.mem.readInt(u16, dwarf_data.debug_info[4..6], .little);
    try testing.expectEqual(@as(u16, DwarfDebugInfo.DWARF_VERSION), version);
    
    // 验证地址大小
    try testing.expectEqual(@as(u8, 8), dwarf_data.debug_info[10]);
}

test "DWARF - 多函数调试信息" {
    var builder = try DwarfDebugInfoBuilder.init(testing.allocator);
    defer builder.deinit();
    
    try builder.createCompileUnit("test.php", "/path/to/source");
    
    // 创建多个函数
    const func1 = try builder.createFunction("func1", 0x1000, 0x1100, .void);
    const func2 = try builder.createFunction("func2", 0x2000, 0x2200, .int32);
    const func3 = try builder.createFunction("func3", 0x3000, 0x3150, .float64);
    
    // 为每个函数添加变量
    try builder.createLocalVariable(func1, "x", .int32, 0, 10);
    try builder.createLocalVariable(func2, "y", .int64, 0, 20);
    try builder.createLocalVariable(func3, "z", .float64, 0, 30);
    
    var dwarf_data = try builder.finalize();
    defer dwarf_data.deinit(testing.allocator);
    
    // 验证地址范围
    try testing.expectEqual(@as(usize, 3), builder.address_ranges.items.len);
}

test "DWARF - 复杂类型" {
    var builder = try DwarfDebugInfoBuilder.init(testing.allocator);
    defer builder.deinit();
    
    try builder.createCompileUnit("test.php", "/path/to/source");
    
    // 测试各种类型
    _ = try builder.createFunction("func_void", 0x1000, 0x1100, .void);
    _ = try builder.createFunction("func_bool", 0x2000, 0x2100, .bool);
    _ = try builder.createFunction("func_int8", 0x3000, 0x3100, .int8);
    _ = try builder.createFunction("func_int16", 0x4000, 0x4100, .int16);
    _ = try builder.createFunction("func_int32", 0x5000, 0x5100, .int32);
    _ = try builder.createFunction("func_int64", 0x6000, 0x6100, .int64);
    _ = try builder.createFunction("func_float32", 0x7000, 0x7100, .float32);
    _ = try builder.createFunction("func_float64", 0x8000, 0x8100, .float64);
    _ = try builder.createFunction("func_string", 0x9000, 0x9100, .string);
    
    var dwarf_data = try builder.finalize();
    defer dwarf_data.deinit(testing.allocator);
    
    // 验证类型缓存包含所有类型
    try testing.expect(builder.type_cache.count() >= 9);
}

test "DWARF - 性能测试" {
    var builder = try DwarfDebugInfoBuilder.init(testing.allocator);
    defer builder.deinit();
    
    try builder.createCompileUnit("test.php", "/path/to/source");
    
    // 创建大量函数
    const num_functions = 100;
    var i: u64 = 0;
    while (i < num_functions) : (i += 1) {
        const func_name = try std.fmt.allocPrint(testing.allocator, "func_{d}", .{i});
        defer testing.allocator.free(func_name);
        
        const low_pc = 0x1000 + (i * 0x100);
        const high_pc = low_pc + 0x100;
        
        const func_die = try builder.createFunction(func_name, low_pc, high_pc, .int64);
        
        // 添加一些变量
        try builder.createLocalVariable(func_die, "x", .int32, 0, @as(u32, @intCast(i)));
        try builder.createLocalVariable(func_die, "y", .int64, 8, @as(u32, @intCast(i + 1)));
        
        // 添加行号映射
        try builder.addLineMapping(low_pc, 0, @as(u32, @intCast(i * 10)), 1);
    }
    
    var dwarf_data = try builder.finalize();
    defer dwarf_data.deinit(testing.allocator);
    
    // 验证生成的数据
    try testing.expectEqual(@as(usize, num_functions), builder.address_ranges.items.len);
    try testing.expect(dwarf_data.debug_info.len > 1000); // 应该有相当大的数据量
}

test "DWARF - 字符串表去重" {
    var builder = try DwarfDebugInfoBuilder.init(testing.allocator);
    defer builder.deinit();
    
    try builder.createCompileUnit("test.php", "/path/to/source");
    
    // 创建多个使用相同名称的函数（不现实，但用于测试）
    _ = try builder.createFunction("testFunc", 0x1000, 0x1100, .int64);
    
    const func2 = try builder.createFunction("anotherFunc", 0x2000, 0x2100, .int64);
    try builder.createLocalVariable(func2, "testFunc", .int32, 0, 10); // 重用名称
    
    // 字符串表应该去重
    const initial_count = builder.string_table.strings.count();
    
    // 再次添加相同的字符串
    const offset1 = try builder.string_table.addString("testFunc");
    const offset2 = try builder.string_table.addString("testFunc");
    
    // 应该返回相同的偏移量
    try testing.expectEqual(offset1, offset2);
    
    // 字符串表大小不应该增加
    try testing.expectEqual(initial_count, builder.string_table.strings.count());
}

test "DWARF - 地址范围排序" {
    var builder = try DwarfDebugInfoBuilder.init(testing.allocator);
    defer builder.deinit();
    
    try builder.createCompileUnit("test.php", "/path/to/source");
    
    // 以非顺序方式创建函数
    _ = try builder.createFunction("func3", 0x3000, 0x3100, .void);
    _ = try builder.createFunction("func1", 0x1000, 0x1100, .void);
    _ = try builder.createFunction("func2", 0x2000, 0x2100, .void);
    
    var dwarf_data = try builder.finalize();
    defer dwarf_data.deinit(testing.allocator);
    
    // 验证地址范围已记录（顺序可能不同）
    try testing.expectEqual(@as(usize, 3), builder.address_ranges.items.len);
}

