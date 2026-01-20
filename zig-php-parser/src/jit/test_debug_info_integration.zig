/// JIT 调试信息集成测试
/// 
/// 验证调试信息在 JIT 编译过程中的正确生成和使用

const std = @import("std");
const testing = std.testing;
const DebugInfoManager = @import("debug_info.zig").DebugInfoManager;
const DebugInfoBuilder = @import("debug_info.zig").DebugInfoBuilder;
const SourceLocation = @import("debug_info.zig").SourceLocation;
const AddressRange = @import("debug_info.zig").AddressRange;
const CodeMapping = @import("debug_info.zig").CodeMapping;
const DebugSymbol = @import("debug_info.zig").DebugSymbol;
const SymbolType = @import("debug_info.zig").SymbolType;

test "JIT 编译器集成 - 基本代码映射" {
    var manager = DebugInfoManager.init(testing.allocator);
    defer manager.deinit();
    
    // 模拟 JIT 编译一个简单函数
    // function add(a, b) { return a + b; }
    
    const code_start = 0x100000;
    var builder = DebugInfoBuilder.init(
        testing.allocator,
        "add",
        "test.php",
        code_start,
    );
    defer builder.deinit();
    
    // 记录函数序言（prologue）
    try builder.recordInstruction(1, 1, 8, null); // push rbp
    try builder.recordInstruction(1, 1, 4, null); // mov rbp, rsp
    
    // 记录参数加载
    try builder.recordInstruction(1, 15, 4, 0); // mov rax, [rbp+16] (a)
    try builder.recordInstruction(1, 18, 4, 1); // mov rbx, [rbp+24] (b)
    
    // 记录加法操作
    try builder.recordInstruction(1, 21, 3, 2); // add rax, rbx
    
    // 记录返回
    try builder.recordInstruction(1, 28, 2, 3); // ret
    
    // 完成构建
    try builder.finalize(&manager);
    
    // 验证映射
    try testing.expectEqual(@as(usize, 6), manager.stats.mapping_count);
    
    // 查找各个指令的源代码位置
    const loc1 = manager.lookupSourceLocation(code_start + 0);
    try testing.expect(loc1 != null);
    try testing.expectEqual(@as(u32, 1), loc1.?.line);
    try testing.expectEqual(@as(u32, 1), loc1.?.column);
    
    const loc2 = manager.lookupSourceLocation(code_start + 12);
    try testing.expect(loc2 != null);
    try testing.expectEqual(@as(u32, 1), loc2.?.line);
    try testing.expectEqual(@as(u32, 15), loc2.?.column);
    
    const loc3 = manager.lookupSourceLocation(code_start + 20);
    try testing.expect(loc3 != null);
    try testing.expectEqual(@as(u32, 1), loc3.?.line);
    try testing.expectEqual(@as(u32, 21), loc3.?.column);
}

test "JIT 编译器集成 - 多函数调试信息" {
    var manager = DebugInfoManager.init(testing.allocator);
    defer manager.deinit();
    
    // 编译第一个函数
    {
        const code_start = 0x100000;
        var builder = DebugInfoBuilder.init(
            testing.allocator,
            "func1",
            "test.php",
            code_start,
        );
        defer builder.deinit();
        
        try builder.recordInstruction(10, 1, 4, 0);
        try builder.recordInstruction(11, 1, 4, 1);
        try builder.recordInstruction(12, 1, 4, 2);
        
        try builder.finalize(&manager);
    }
    
    // 编译第二个函数
    {
        const code_start = 0x200000;
        var builder = DebugInfoBuilder.init(
            testing.allocator,
            "func2",
            "test.php",
            code_start,
        );
        defer builder.deinit();
        
        try builder.recordInstruction(20, 1, 4, 0);
        try builder.recordInstruction(21, 1, 4, 1);
        try builder.recordInstruction(22, 1, 4, 2);
        
        try builder.finalize(&manager);
    }
    
    // 验证两个函数的映射都存在
    try testing.expectEqual(@as(usize, 6), manager.stats.mapping_count);
    
    // 验证第一个函数
    const func1_range = manager.lookupFunctionAddress("func1");
    try testing.expect(func1_range != null);
    try testing.expectEqual(@as(usize, 0x100000), func1_range.?.start);
    try testing.expectEqual(@as(usize, 0x10000C), func1_range.?.end);
    
    // 验证第二个函数
    const func2_range = manager.lookupFunctionAddress("func2");
    try testing.expect(func2_range != null);
    try testing.expectEqual(@as(usize, 0x200000), func2_range.?.start);
    try testing.expectEqual(@as(usize, 0x20000C), func2_range.?.end);
    
    // 验证地址查找
    const loc1 = manager.lookupSourceLocation(0x100004);
    try testing.expect(loc1 != null);
    try testing.expectEqualStrings("func1", loc1.?.function_name);
    try testing.expectEqual(@as(u32, 11), loc1.?.line);
    
    const loc2 = manager.lookupSourceLocation(0x200004);
    try testing.expect(loc2 != null);
    try testing.expectEqualStrings("func2", loc2.?.function_name);
    try testing.expectEqual(@as(u32, 21), loc2.?.line);
}

test "JIT 编译器集成 - 变量符号调试" {
    var manager = DebugInfoManager.init(testing.allocator);
    defer manager.deinit();
    
    const code_start = 0x100000;
    var builder = DebugInfoBuilder.init(
        testing.allocator,
        "testFunc",
        "test.php",
        code_start,
    );
    defer builder.deinit();
    
    // 记录参数
    try builder.recordVariable("a", .parameter, 0, 8, 1, 15);
    try builder.recordVariable("b", .parameter, 8, 8, 1, 18);
    
    // 记录局部变量
    try builder.recordVariable("result", .local, 16, 8, 2, 5);
    try builder.recordVariable("temp", .local, 24, 8, 3, 5);
    
    // 记录指令
    try builder.recordInstruction(1, 1, 4, 0);
    try builder.recordInstruction(2, 1, 4, 1);
    try builder.recordInstruction(3, 1, 4, 2);
    
    try builder.finalize(&manager);
    
    // 验证符号
    try testing.expectEqual(@as(usize, 4), manager.stats.symbol_count);
    
    const sym_a = manager.lookupSymbol("a");
    try testing.expect(sym_a != null);
    try testing.expectEqual(SymbolType.parameter, sym_a.?.type_);
    try testing.expectEqual(@as(usize, 0), sym_a.?.address);
    
    const sym_result = manager.lookupSymbol("result");
    try testing.expect(sym_result != null);
    try testing.expectEqual(SymbolType.local, sym_result.?.type_);
    try testing.expectEqual(@as(usize, 16), sym_result.?.address);
}

test "JIT 编译器集成 - 堆栈跟踪生成" {
    var manager = DebugInfoManager.init(testing.allocator);
    defer manager.deinit();
    
    // 模拟三个函数的调用链
    const addresses = [_]usize{
        0x100000, // main
        0x200000, // func1
        0x300000, // func2
    };
    
    // 为每个函数添加调试信息
    for (addresses, 0..) |addr, i| {
        const func_name = try std.fmt.allocPrint(
            testing.allocator,
            "func{d}",
            .{i},
        );
        defer testing.allocator.free(func_name);
        
        var builder = DebugInfoBuilder.init(
            testing.allocator,
            func_name,
            "test.php",
            addr,
        );
        defer builder.deinit();
        
        try builder.recordInstruction(@intCast(10 + i * 10), 1, 4, 0);
        try builder.finalize(&manager);
    }
    
    // 验证可以查找到所有地址
    for (addresses) |addr| {
        const loc = manager.lookupSourceLocation(addr);
        try testing.expect(loc != null);
        try testing.expectEqualStrings("test.php", loc.?.file_path);
    }
}

test "JIT 编译器集成 - 性能测试" {
    var manager = DebugInfoManager.init(testing.allocator);
    defer manager.deinit();
    
    // 添加大量映射以测试性能
    const num_functions = 10;  // 减少数量以避免内存问题
    const instructions_per_function = 10;
    
    var func_names: std.ArrayListUnmanaged([]const u8) = .{};
    defer {
        for (func_names.items) |name| {
            testing.allocator.free(name);
        }
        func_names.deinit(testing.allocator);
    }
    
    var i: usize = 0;
    while (i < num_functions) : (i += 1) {
        const code_start = 0x100000 + i * 0x1000;
        const func_name = try std.fmt.allocPrint(
            testing.allocator,
            "func{d}",
            .{i},
        );
        try func_names.append(testing.allocator, func_name);
        
        var builder = DebugInfoBuilder.init(
            testing.allocator,
            func_name,
            "test.php",
            code_start,
        );
        defer builder.deinit();
        
        var j: usize = 0;
        while (j < instructions_per_function) : (j += 1) {
            try builder.recordInstruction(
                @intCast(10 + j),
                @intCast(1 + j),
                4,
                j,
            );
        }
        
        try builder.finalize(&manager);
    }
    
    // 验证映射数量
    const expected_mappings = num_functions * instructions_per_function;
    try testing.expectEqual(expected_mappings, manager.stats.mapping_count);
    
    // 测试查找性能
    var timer = try std.time.Timer.start();
    
    const num_lookups = 100;  // 减少查找次数
    var lookup_count: usize = 0;
    var k: usize = 0;
    while (k < num_lookups) : (k += 1) {
        const addr = 0x100000 + (k % (num_functions * 0x1000));
        if (manager.lookupSourceLocation(addr)) |_| {
            lookup_count += 1;
        }
    }
    
    const elapsed_ns = timer.read();
    const ns_per_lookup = elapsed_ns / num_lookups;
    
    // 验证查找性能（应该在微秒级别）
    try testing.expect(ns_per_lookup < 100000); // < 100 微秒
    
    // 验证命中率
    const hit_rate = manager.stats.hitRate();
    try testing.expect(hit_rate > 0.0);
}

test "JIT 编译器集成 - 字节码 IP 映射" {
    var manager = DebugInfoManager.init(testing.allocator);
    defer manager.deinit();
    
    const code_start = 0x100000;
    var builder = DebugInfoBuilder.init(
        testing.allocator,
        "testFunc",
        "test.php",
        code_start,
    );
    defer builder.deinit();
    
    // 记录指令并关联字节码 IP
    try builder.recordInstruction(10, 1, 4, 0);  // bytecode IP 0
    try builder.recordInstruction(11, 1, 4, 1);  // bytecode IP 1
    try builder.recordInstruction(12, 1, 4, 2);  // bytecode IP 2
    try builder.recordInstruction(13, 1, 4, 3);  // bytecode IP 3
    
    try builder.finalize(&manager);
    
    // 验证可以通过机器码地址找到字节码 IP
    const loc1 = manager.lookupSourceLocation(code_start + 0);
    try testing.expect(loc1 != null);
    
    // 查找对应的映射以获取字节码 IP
    for (manager.code_mappings.items) |mapping| {
        if (mapping.address_range.contains(code_start + 0)) {
            try testing.expectEqual(@as(?usize, 0), mapping.bytecode_ip);
            break;
        }
    }
    
    for (manager.code_mappings.items) |mapping| {
        if (mapping.address_range.contains(code_start + 8)) {
            try testing.expectEqual(@as(?usize, 2), mapping.bytecode_ip);
            break;
        }
    }
}

test "JIT 编译器集成 - 统计信息报告" {
    var manager = DebugInfoManager.init(testing.allocator);
    defer manager.deinit();
    
    // 添加一些调试信息
    const code_start = 0x100000;
    var builder = DebugInfoBuilder.init(
        testing.allocator,
        "testFunc",
        "test.php",
        code_start,
    );
    defer builder.deinit();
    
    try builder.recordInstruction(10, 1, 4, 0);
    try builder.recordInstruction(11, 1, 4, 1);
    try builder.recordVariable("x", .local, 0, 8, 10, 5);
    
    try builder.finalize(&manager);
    
    // 执行一些查找
    _ = manager.lookupSourceLocation(code_start + 0);
    _ = manager.lookupSourceLocation(code_start + 4);
    _ = manager.lookupSourceLocation(0x999999); // 未命中
    
    // 验证统计信息
    try testing.expectEqual(@as(usize, 2), manager.stats.mapping_count);
    try testing.expectEqual(@as(usize, 1), manager.stats.symbol_count);
    try testing.expectEqual(@as(usize, 3), manager.stats.lookup_count);
    try testing.expectEqual(@as(usize, 2), manager.stats.lookup_hits);
    
    const hit_rate = manager.stats.hitRate();
    try testing.expect(hit_rate > 0.66 and hit_rate < 0.67);
}
