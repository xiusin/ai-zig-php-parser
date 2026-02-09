const std = @import("std");
const RegisterAllocator = @import("jit/register_allocator.zig").RegisterAllocator;

// Feature: advanced-compiler-optimization, Property 27: 寄存器分配正确性
test "register allocation - correctly allocates non-interfering registers" {
    const allocator = std.testing.allocator;
    var ra = RegisterAllocator.init(allocator, 4);
    
    // 创建虚拟寄存器
    var v1 = RegisterAllocator.VirtualReg{ .id = 1, .name = "v1" };
    var v2 = RegisterAllocator.VirtualReg{ .id = 2, .name = "v2" };
    var v3 = RegisterAllocator.VirtualReg{ .id = 3, .name = "v3" };
    
    // 创建干涉图（无干涉）
    var graph = RegisterAllocator.InterferenceGraph.init(allocator);
    defer graph.deinit();
    
    try graph.addNode(&v1);
    try graph.addNode(&v2);
    try graph.addNode(&v3);
    
    // 分配寄存器
    var allocation = try ra.allocate(&graph);
    defer allocation.deinit();
    
    // 验证所有寄存器都被分配
    try std.testing.expect(allocation.contains(&v1));
    try std.testing.expect(allocation.contains(&v2));
    try std.testing.expect(allocation.contains(&v3));
}

test "register allocation - respects interference constraints" {
    const allocator = std.testing.allocator;
    var ra = RegisterAllocator.init(allocator, 4);
    
    // 创建虚拟寄存器
    var v1 = RegisterAllocator.VirtualReg{ .id = 1, .name = "v1" };
    var v2 = RegisterAllocator.VirtualReg{ .id = 2, .name = "v2" };
    
    // 创建干涉图（v1 和 v2 干涉）
    var graph = RegisterAllocator.InterferenceGraph.init(allocator);
    defer graph.deinit();
    
    try graph.addNode(&v1);
    try graph.addNode(&v2);
    try graph.addEdge(&v1, &v2);
    
    // 分配寄存器
    var allocation = try ra.allocate(&graph);
    defer allocation.deinit();
    
    // 验证 v1 和 v2 分配到不同的物理寄存器
    const r1 = allocation.get(&v1).?;
    const r2 = allocation.get(&v2).?;
    try std.testing.expect(r1 != r2);
}

test "register allocation - handles graph coloring" {
    const allocator = std.testing.allocator;
    var ra = RegisterAllocator.init(allocator, 3);
    
    // 创建三角形干涉图
    var v1 = RegisterAllocator.VirtualReg{ .id = 1, .name = "v1" };
    var v2 = RegisterAllocator.VirtualReg{ .id = 2, .name = "v2" };
    var v3 = RegisterAllocator.VirtualReg{ .id = 3, .name = "v3" };
    
    var graph = RegisterAllocator.InterferenceGraph.init(allocator);
    defer graph.deinit();
    
    try graph.addNode(&v1);
    try graph.addNode(&v2);
    try graph.addNode(&v3);
    try graph.addEdge(&v1, &v2);
    try graph.addEdge(&v2, &v3);
    try graph.addEdge(&v3, &v1);
    
    // 分配寄存器
    var allocation = try ra.allocate(&graph);
    defer allocation.deinit();
    
    // 验证所有寄存器都被分配到不同的物理寄存器
    const r1 = allocation.get(&v1).?;
    const r2 = allocation.get(&v2).?;
    const r3 = allocation.get(&v3).?;
    
    try std.testing.expect(r1 != r2);
    try std.testing.expect(r2 != r3);
    try std.testing.expect(r3 != r1);
}

test "register allocation - interference graph degree" {
    const allocator = std.testing.allocator;
    
    var v1 = RegisterAllocator.VirtualReg{ .id = 1, .name = "v1" };
    var v2 = RegisterAllocator.VirtualReg{ .id = 2, .name = "v2" };
    var v3 = RegisterAllocator.VirtualReg{ .id = 3, .name = "v3" };
    
    var graph = RegisterAllocator.InterferenceGraph.init(allocator);
    defer graph.deinit();
    
    try graph.addNode(&v1);
    try graph.addNode(&v2);
    try graph.addNode(&v3);
    try graph.addEdge(&v1, &v2);
    try graph.addEdge(&v1, &v3);
    
    // v1 的度数应为 2
    try std.testing.expectEqual(@as(u32, 2), graph.degree(&v1));
    // v2 和 v3 的度数应为 1
    try std.testing.expectEqual(@as(u32, 1), graph.degree(&v2));
    try std.testing.expectEqual(@as(u32, 1), graph.degree(&v3));
}

test "register allocation - handles spilling" {
    const allocator = std.testing.allocator;
    var ra = RegisterAllocator.init(allocator, 2);
    
    // 创建 3 个相互干涉的虚拟寄存器（需要 3 个物理寄存器，但只有 2 个）
    var v1 = RegisterAllocator.VirtualReg{ .id = 1, .name = "v1" };
    var v2 = RegisterAllocator.VirtualReg{ .id = 2, .name = "v2" };
    var v3 = RegisterAllocator.VirtualReg{ .id = 3, .name = "v3" };
    
    var graph = RegisterAllocator.InterferenceGraph.init(allocator);
    defer graph.deinit();
    
    try graph.addNode(&v1);
    try graph.addNode(&v2);
    try graph.addNode(&v3);
    try graph.addEdge(&v1, &v2);
    try graph.addEdge(&v2, &v3);
    try graph.addEdge(&v3, &v1);
    
    // 分配寄存器
    var allocation = try ra.allocate(&graph);
    defer allocation.deinit();
    
    // 至少有一个寄存器应该溢出（未分配物理寄存器）
    const allocated_count = allocation.count();
    try std.testing.expect(allocated_count < 3);
}
