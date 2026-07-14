const std = @import("std");

/// 寄存器分配器
///
/// 使用图着色算法将虚拟寄存器映射到物理寄存器
pub const RegisterAllocator = struct {
    allocator: std.mem.Allocator,

    /// 可用物理寄存器数量
    num_registers: u32,

    /// 虚拟寄存器
    pub const VirtualReg = struct {
        id: u32,
        name: []const u8,
    };

    /// 物理寄存器
    pub const PhysicalReg = enum(u8) {
        rax,
        rbx,
        rcx,
        rdx,
        rsi,
        rdi,
        r8,
        r9,
        r10,
        r11,
        r12,
        r13,
        r14,
        r15,
        xmm0,
        xmm1,
        xmm2,
        xmm3,
        xmm4,
        xmm5,
        xmm6,
        xmm7,
    };

    /// 干涉图
    pub const InterferenceGraph = struct {
        allocator: std.mem.Allocator,
        /// 节点（虚拟寄存器）
        nodes: std.AutoHashMap(*VirtualReg, void),
        /// 边（干涉关系）
        edges: std.AutoHashMap(Edge, void),

        pub const Edge = struct {
            from: *VirtualReg,
            to: *VirtualReg,

            pub fn hash(self: Edge) u64 {
                const from_addr = @intFromPtr(self.from);
                const to_addr = @intFromPtr(self.to);
                // 确保边的方向无关性
                const min_addr = @min(from_addr, to_addr);
                const max_addr = @max(from_addr, to_addr);
                return min_addr ^ (max_addr << 32);
            }

            pub fn eql(self: Edge, other: Edge) bool {
                return (self.from == other.from and self.to == other.to) or
                    (self.from == other.to and self.to == other.from);
            }
        };

        pub fn init(allocator: std.mem.Allocator) InterferenceGraph {
            return .{
                .allocator = allocator,
                .nodes = std.AutoHashMap(*VirtualReg, void).init(allocator),
                .edges = std.AutoHashMap(Edge, void).init(allocator),
            };
        }

        pub fn deinit(self: *InterferenceGraph) void {
            self.nodes.deinit();
            self.edges.deinit();
        }

        pub fn addNode(self: *InterferenceGraph, node: *VirtualReg) !void {
            try self.nodes.put(node, {});
        }

        pub fn addEdge(self: *InterferenceGraph, from: *VirtualReg, to: *VirtualReg) !void {
            try self.edges.put(.{ .from = from, .to = to }, {});
        }

        pub fn degree(self: *InterferenceGraph, node: *VirtualReg) u32 {
            var count: u32 = 0;
            var it = self.edges.keyIterator();
            while (it.next()) |edge| {
                if (edge.from == node or edge.to == node) {
                    count += 1;
                }
            }
            return count;
        }
    };

    /// 着色结果
    pub const Coloring = std.AutoHashMap(*VirtualReg, u32);

    /// 分配结果
    pub const Allocation = std.AutoHashMap(*VirtualReg, PhysicalReg);

    pub fn init(allocator: std.mem.Allocator, num_registers: u32) RegisterAllocator {
        return .{
            .allocator = allocator,
            .num_registers = num_registers,
        };
    }

    /// 分配寄存器
    /// @pre graph 必须已构建
    /// @post 返回分配结果
    pub fn allocate(self: *RegisterAllocator, graph: *InterferenceGraph) !Allocation {
        // 1. 图着色
        var coloring = try self.colorGraph(graph);
        defer coloring.deinit();

        // 2. 生成分配结果
        return try self.generateAllocation(coloring);
    }

    /// 图着色算法
    fn colorGraph(self: *RegisterAllocator, graph: *InterferenceGraph) !Coloring {
        var coloring = Coloring.init(self.allocator);
        errdefer coloring.deinit();

        // 简化阶段：移除度数 < K 的节点
        var stack = try std.ArrayList(*VirtualReg).initCapacity(self.allocator, 0);
        defer stack.deinit(self.allocator);

        var temp_graph = InterferenceGraph.init(self.allocator);
        defer temp_graph.deinit();

        // 复制图
        var node_it = graph.nodes.keyIterator();
        while (node_it.next()) |node| {
            try temp_graph.addNode(node.*);
        }
        var edge_it = graph.edges.keyIterator();
        while (edge_it.next()) |edge| {
            try temp_graph.addEdge(edge.from, edge.to);
        }

        // 简化
        while (temp_graph.nodes.count() > 0) {
            var removed = false;
            var it = temp_graph.nodes.keyIterator();
            while (it.next()) |node_ptr| {
                const node = node_ptr.*;
                const deg = temp_graph.degree(node);

                if (deg < self.num_registers) {
                    try stack.append(self.allocator, node);
                    _ = temp_graph.nodes.remove(node);
                    removed = true;
                    break;
                }
            }

            // 如果无法简化，选择溢出节点
            if (!removed) {
                var first_it = temp_graph.nodes.keyIterator();
                if (first_it.next()) |node_ptr| {
                    const node = node_ptr.*;
                    try stack.append(self.allocator, node);
                    _ = temp_graph.nodes.remove(node);
                }
            }
        }

        // 着色阶段：从栈中恢复节点并分配颜色
        while (stack.items.len > 0) {
            const node = stack.items[stack.items.len - 1];
            _ = stack.pop();
            const color = try self.selectColor(node, graph, &coloring);
            try coloring.put(node, color);
        }

        return coloring;
    }

    /// 选择颜色
    fn selectColor(
        self: *RegisterAllocator,
        node: *VirtualReg,
        graph: *InterferenceGraph,
        coloring: *Coloring,
    ) !u32 {
        // 收集邻居的颜色
        var used_colors = std.AutoHashMap(u32, void).init(self.allocator);
        defer used_colors.deinit();

        var it = graph.edges.keyIterator();
        while (it.next()) |edge| {
            var neighbor: ?*VirtualReg = null;
            if (edge.from == node) {
                neighbor = edge.to;
            } else if (edge.to == node) {
                neighbor = edge.from;
            }

            if (neighbor) |n| {
                if (coloring.get(n)) |color| {
                    try used_colors.put(color, {});
                }
            }
        }

        // 选择第一个未使用的颜色
        var color: u32 = 0;
        while (color < self.num_registers) : (color += 1) {
            if (!used_colors.contains(color)) {
                return color;
            }
        }

        // 溢出：返回特殊颜色
        return self.num_registers;
    }

    /// 生成分配结果
    fn generateAllocation(self: *RegisterAllocator, coloring: Coloring) !Allocation {
        var allocation = Allocation.init(self.allocator);
        errdefer allocation.deinit();

        var it = coloring.iterator();
        while (it.next()) |entry| {
            const vreg = entry.key_ptr.*;
            const color = entry.value_ptr.*;

            if (color < self.num_registers) {
                const preg = @as(PhysicalReg, @enumFromInt(color));
                try allocation.put(vreg, preg);
            }
            // 溢出的寄存器不分配物理寄存器
        }

        return allocation;
    }
};
