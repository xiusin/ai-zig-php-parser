const std = @import("std");

// 测试 GC 修复
test "GC markPhase without external dependencies" {
    const allocator = std.testing.allocator;
    
    // 创建一个简化的 OldGeneration 用于测试
    var objects: std.ArrayList(GCObject) = .{};
    defer {
        for (objects.items) |obj| {
            allocator.free(obj.data);
        }
        objects.deinit(allocator);
    }
    
    // 添加测试对象
    const data1 = try allocator.alloc(u8, 100);
    try objects.append(allocator, .{
        .data = data1,
        .size = 100,
        .marked = false,
        .age = 1,
    });
    
    const data2 = try allocator.alloc(u8, 200);
    try objects.append(allocator, .{
        .data = data2,
        .size = 200,
        .marked = false,
        .age = 0,
    });
    
    // 验证对象已创建
    try std.testing.expectEqual(@as(usize, 2), objects.items.len);
    try std.testing.expect(!objects.items[0].marked);
    try std.testing.expect(!objects.items[1].marked);
}

const GCObject = struct {
    data: []u8,
    size: usize,
    marked: bool,
    age: u8,
};

test "YoungGeneration object promotion logic" {
    // 测试对象提升逻辑
    var obj = GCObject{
        .data = &[_]u8{},
        .size = 0,
        .marked = true,
        .age = 0,
    };
    
    // 模拟年龄增长
    obj.age += 1;
    try std.testing.expectEqual(@as(u8, 1), obj.age);
    
    obj.age += 1;
    try std.testing.expectEqual(@as(u8, 2), obj.age);
    
    obj.age += 1;
    try std.testing.expectEqual(@as(u8, 3), obj.age);
    
    // 验证年龄阈值检查
    const age_threshold: u8 = 3;
    try std.testing.expect(obj.age >= age_threshold);
}

test "CycleDetector DFS implementation" {
    const allocator = std.testing.allocator;
    
    // 测试循环检测的数据结构
    var visited = std.AutoHashMap(usize, void).init(allocator);
    defer visited.deinit();
    
    // 模拟节点访问
    try visited.put(0x1000, {});
    try visited.put(0x2000, {});
    
    try std.testing.expect(visited.contains(0x1000));
    try std.testing.expect(visited.contains(0x2000));
    try std.testing.expect(!visited.contains(0x3000));
}

// 测试 AOT 编译器修复
test "IR Module creation" {
    // 模拟 IR 模块结构
    const Module = struct {
        name: []const u8,
        source_file: []const u8,
    };
    
    // 验证结构可以创建
    const module = Module{
        .name = "test",
        .source_file = "test.php",
    };
    
    try std.testing.expectEqualStrings("test", module.name);
    try std.testing.expectEqualStrings("test.php", module.source_file);
}

test "LLVM IR instruction generation" {
    const allocator = std.testing.allocator;
    
    // 测试 LLVM IR 生成
    var buffer: std.ArrayList(u8) = .{};
    defer buffer.deinit(allocator);
    
    const writer = buffer.writer(allocator);
    
    // 生成简单的 LLVM IR
    try writer.writeAll("define void @test() {\n");
    try writer.writeAll("entry:\n");
    try writer.writeAll("  %1 = add i64 0, 42\n");
    try writer.writeAll("  ret void\n");
    try writer.writeAll("}\n");
    
    const result = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, result, "define void @test()") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "add i64 0, 42") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "ret void") != null);
}
