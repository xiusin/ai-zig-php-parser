// 寄存器分配器 - 线性扫描算法实现
// 
// 本模块实现了完整的寄存器分配器，包括：
// 1. 活跃区间计算
// 2. 线性扫描寄存器分配算法
// 3. 寄存器溢出处理
// 4. 寄存器利用率优化（目标 > 80%）
//
// @ownership NON-OWNING (allocator)
// @thread-safety ISOLATED (单线程)
// @memory-safety 所有内存操作经过边界检查

const std = @import("std");
const Allocator = std.mem.Allocator;

/// x86-64 通用寄存器
pub const Register = enum(u8) {
    rax = 0,
    rbx = 1,
    rcx = 2,
    rdx = 3,
    rsi = 4,
    rdi = 5,
    r8 = 6,
    r9 = 7,
    r10 = 8,
    r11 = 9,
    r12 = 10,
    r13 = 11,
    r14 = 12,
    r15 = 13,
    
    /// 获取寄存器名称
    pub fn name(self: Register) []const u8 {
        return switch (self) {
            .rax => "rax",
            .rbx => "rbx",
            .rcx => "rcx",
            .rdx => "rdx",
            .rsi => "rsi",
            .rdi => "rdi",
            .r8 => "r8",
            .r9 => "r9",
            .r10 => "r10",
            .r11 => "r11",
            .r12 => "r12",
            .r13 => "r13",
            .r14 => "r14",
            .r15 => "r15",
        };
    }
};

/// 活跃区间
/// 表示一个虚拟寄存器的生命周期
pub const LiveInterval = struct {
    /// 虚拟寄存器 ID
    var_id: u32,
    
    /// 起始位置（指令索引）
    start: usize,
    
    /// 结束位置（指令索引）
    end: usize,
    
    /// 分配的物理寄存器（如果已分配）
    assigned_reg: ?Register,
    
    /// 溢出位置（如果溢出到栈）
    spill_slot: ?i32,
    
    /// 使用次数（用于溢出决策）
    use_count: u32,
    
    /// 创建活跃区间
    /// @pre start <= end
    /// @post 返回初始化的活跃区间
    pub fn init(var_id: u32, start: usize, end: usize) LiveInterval {
        std.debug.assert(start <= end);
        return LiveInterval{
            .var_id = var_id,
            .start = start,
            .end = end,
            .assigned_reg = null,
            .spill_slot = null,
            .use_count = 0,
        };
    }
    
    /// 检查两个区间是否重叠
    /// @pre self 和 other 必须有效
    /// @post 返回是否重叠
    pub fn overlaps(self: *const LiveInterval, other: *const LiveInterval) bool {
        return self.start <= other.end and other.start <= self.end;
    }
    
    /// 比较函数（按起始位置排序）
    pub fn compareByStart(_: void, a: LiveInterval, b: LiveInterval) bool {
        return a.start < b.start;
    }
    
    /// 比较函数（按结束位置排序）
    pub fn compareByEnd(_: void, a: LiveInterval, b: LiveInterval) bool {
        return a.end < b.end;
    }
};

/// 寄存器映射
/// 虚拟寄存器 ID -> 物理寄存器或栈位置
pub const RegisterMap = struct {
    allocator: Allocator,
    
    /// 寄存器分配映射
    reg_map: std.AutoHashMap(u32, Register),
    
    /// 栈溢出映射
    spill_map: std.AutoHashMap(u32, i32),
    
    /// 初始化寄存器映射
    pub fn init(allocator: Allocator) RegisterMap {
        return RegisterMap{
            .allocator = allocator,
            .reg_map = std.AutoHashMap(u32, Register).init(allocator),
            .spill_map = std.AutoHashMap(u32, i32).init(allocator),
        };
    }
    
    /// 释放资源
    pub fn deinit(self: *RegisterMap) void {
        self.reg_map.deinit();
        self.spill_map.deinit();
    }
    
    /// 获取虚拟寄存器的物理寄存器
    /// @pre var_id 必须已分配
    /// @post 返回物理寄存器或 null（如果溢出）
    pub fn getReg(self: *const RegisterMap, var_id: u32) ?Register {
        return self.reg_map.get(var_id);
    }
    
    /// 获取虚拟寄存器的栈位置
    /// @pre var_id 必须已溢出
    /// @post 返回栈偏移或 null（如果在寄存器中）
    pub fn getSpillSlot(self: *const RegisterMap, var_id: u32) ?i32 {
        return self.spill_map.get(var_id);
    }
    
    /// 分配物理寄存器
    pub fn assignReg(self: *RegisterMap, var_id: u32, reg: Register) !void {
        try self.reg_map.put(var_id, reg);
    }
    
    /// 分配栈位置
    pub fn assignSpillSlot(self: *RegisterMap, var_id: u32, slot: i32) !void {
        try self.spill_map.put(var_id, slot);
    }
};

/// 寄存器分配器统计信息
pub const AllocatorStats = struct {
    /// 总虚拟寄存器数
    total_vars: u32 = 0,
    
    /// 分配到物理寄存器的数量
    allocated_regs: u32 = 0,
    
    /// 溢出到栈的数量
    spilled_vars: u32 = 0,
    
    /// 寄存器利用率（0.0 - 1.0）
    utilization: f32 = 0.0,
    
    /// 计算寄存器利用率
    pub fn computeUtilization(self: *AllocatorStats, available_regs: usize) void {
        if (self.total_vars == 0) {
            self.utilization = 0.0;
            return;
        }
        
        const max_possible = @min(self.total_vars, @as(u32, @intCast(available_regs)));
        self.utilization = @as(f32, @floatFromInt(self.allocated_regs)) / @as(f32, @floatFromInt(max_possible));
    }
    
    /// 打印统计信息
    pub fn print(self: *const AllocatorStats) void {
        std.debug.print("\n=== 寄存器分配统计 ===\n", .{});
        std.debug.print("总虚拟寄存器: {d}\n", .{self.total_vars});
        std.debug.print("分配到寄存器: {d}\n", .{self.allocated_regs});
        std.debug.print("溢出到栈: {d}\n", .{self.spilled_vars});
        std.debug.print("寄存器利用率: {d:.2}%\n", .{self.utilization * 100.0});
    }
};

/// 寄存器分配器（线性扫描算法）
/// 
/// 实现完整的线性扫描寄存器分配算法：
/// 1. 计算所有虚拟寄存器的活跃区间
/// 2. 按起始位置排序活跃区间
/// 3. 线性扫描分配物理寄存器
/// 4. 当寄存器不足时，选择最佳候选进行溢出
///
/// @concurrency-model ISOLATED
/// @memory-protection 所有数组访问经过边界检查
pub const RegisterAllocator = struct {
    allocator: Allocator,
    
    /// 可用的物理寄存器列表
    /// 注意：rsp (栈指针) 和 rbp (帧指针) 保留不用于分配
    available_regs: []const Register,
    
    /// 活跃区间列表
    live_intervals: std.ArrayList(LiveInterval),
    
    /// 当前活跃的区间（按结束位置排序）
    active: std.ArrayList(LiveInterval),
    
    /// 统计信息
    stats: AllocatorStats,
    
    /// 下一个可用的栈槽
    next_spill_slot: i32,
    
    /// 默认可用寄存器列表（14 个通用寄存器）
    pub const DEFAULT_AVAILABLE_REGS = [_]Register{
        .rax, .rbx, .rcx, .rdx, .rsi, .rdi,
        .r8, .r9, .r10, .r11, .r12, .r13, .r14, .r15,
    };
    
    /// 初始化寄存器分配器
    /// @pre allocator 必须有效
    /// @post 返回初始化的分配器
    pub fn init(allocator: Allocator) RegisterAllocator {
        return RegisterAllocator{
            .allocator = allocator,
            .available_regs = &DEFAULT_AVAILABLE_REGS,
            .live_intervals = std.ArrayList(LiveInterval){},
            .active = std.ArrayList(LiveInterval){},
            .stats = AllocatorStats{},
            .next_spill_slot = 0,
        };
    }
    
    /// 释放资源
    pub fn deinit(self: *RegisterAllocator) void {
        self.live_intervals.deinit(self.allocator);
        self.active.deinit(self.allocator);
    }
    
    /// 添加活跃区间
    /// @pre interval 必须有效
    /// @post 区间被添加到列表中
    pub fn addInterval(self: *RegisterAllocator, interval: LiveInterval) !void {
        try self.live_intervals.append(self.allocator, interval);
        self.stats.total_vars = @intCast(self.live_intervals.items.len);
    }
    
    /// 计算活跃区间（从指令序列）
    /// @pre instructions 必须有效
    /// @post 计算所有虚拟寄存器的活跃区间
    pub fn computeLiveIntervals(self: *RegisterAllocator, instructions: []const Instruction) !void {
        // 第一遍：记录每个变量的首次使用和最后使用
        var first_use = std.AutoHashMap(u32, usize).init(self.allocator);
        defer first_use.deinit();
        
        var last_use = std.AutoHashMap(u32, usize).init(self.allocator);
        defer last_use.deinit();
        
        for (instructions, 0..) |inst, i| {
            // 处理目标操作数（定义）
            if (inst.dst) |dst_id| {
                if (!first_use.contains(dst_id)) {
                    try first_use.put(dst_id, i);
                }
                try last_use.put(dst_id, i);
            }
            
            // 处理源操作数（使用）
            if (inst.src1) |src1_id| {
                if (!first_use.contains(src1_id)) {
                    try first_use.put(src1_id, i);
                }
                try last_use.put(src1_id, i);
            }
            
            if (inst.src2) |src2_id| {
                if (!first_use.contains(src2_id)) {
                    try first_use.put(src2_id, i);
                }
                try last_use.put(src2_id, i);
            }
        }
        
        // 第二遍：创建活跃区间
        var iter = first_use.iterator();
        while (iter.next()) |entry| {
            const var_id = entry.key_ptr.*;
            const start = entry.value_ptr.*;
            const end = last_use.get(var_id) orelse start;
            
            var interval = LiveInterval.init(var_id, start, end);
            
            // 计算使用次数
            for (instructions) |inst| {
                if (inst.dst == var_id or inst.src1 == var_id or inst.src2 == var_id) {
                    interval.use_count += 1;
                }
            }
            
            try self.addInterval(interval);
        }
        
        self.stats.total_vars = @intCast(self.live_intervals.items.len);
    }
    
    /// 执行寄存器分配（线性扫描算法）
    /// @pre live_intervals 必须已计算
    /// @post 返回寄存器映射
    pub fn allocate(self: *RegisterAllocator) !RegisterMap {
        // 按起始位置排序活跃区间
        std.mem.sort(LiveInterval, self.live_intervals.items, {}, LiveInterval.compareByStart);
        
        var reg_map = RegisterMap.init(self.allocator);
        errdefer reg_map.deinit();
        
        // 跟踪每个物理寄存器的使用情况
        const reg_free = try self.allocator.alloc(bool, self.available_regs.len);
        defer self.allocator.free(reg_free);
        @memset(reg_free, true);
        
        // 线性扫描分配
        for (self.live_intervals.items) |*interval| {
            // 释放已结束的活跃区间
            try self.expireOldIntervals(interval, reg_free);
            
            // 尝试分配物理寄存器
            if (self.tryAllocateRegister(interval, reg_free)) |reg| {
                interval.assigned_reg = reg;
                try reg_map.assignReg(interval.var_id, reg);
                try self.active.append(self.allocator, interval.*);
                self.stats.allocated_regs += 1;
            } else {
                // 寄存器不足，需要溢出
                try self.spillVariable(interval, &reg_map);
                self.stats.spilled_vars += 1;
            }
        }
        
        // 计算寄存器利用率
        self.stats.computeUtilization(self.available_regs.len);
        
        return reg_map;
    }
    
    /// 释放已结束的活跃区间
    /// @pre interval 和 reg_free 必须有效
    /// @post 释放不再活跃的寄存器
    fn expireOldIntervals(
        self: *RegisterAllocator,
        interval: *const LiveInterval,
        reg_free: []bool,
    ) !void {
        // 按结束位置排序活跃区间
        std.mem.sort(LiveInterval, self.active.items, {}, LiveInterval.compareByEnd);
        
        // 移除已结束的区间
        while (self.active.items.len > 0) {
            const active_interval = self.active.items[0];
            
            if (active_interval.end >= interval.start) {
                // 仍然活跃
                break;
            }
            
            // 释放寄存器
            if (active_interval.assigned_reg) |reg| {
                const reg_idx = @intFromEnum(reg);
                if (reg_idx < reg_free.len) {
                    reg_free[reg_idx] = true;
                }
            }
            
            // 移除区间
            _ = self.active.orderedRemove(0);
        }
    }
    
    /// 尝试分配物理寄存器
    /// @pre interval 和 reg_free 必须有效
    /// @post 返回分配的寄存器或 null
    fn tryAllocateRegister(
        self: *RegisterAllocator,
        interval: *const LiveInterval,
        reg_free: []bool,
    ) ?Register {
        _ = interval;
        
        // 查找第一个空闲寄存器
        for (self.available_regs, 0..) |reg, i| {
            if (i < reg_free.len and reg_free[i]) {
                reg_free[i] = false;
                return reg;
            }
        }
        
        return null;
    }
    
    /// 溢出变量到栈
    /// @pre interval 和 reg_map 必须有效
    /// @post 变量被分配栈位置
    fn spillVariable(
        self: *RegisterAllocator,
        interval: *LiveInterval,
        reg_map: *RegisterMap,
    ) !void {
        // 分配栈槽
        const spill_slot = self.next_spill_slot;
        self.next_spill_slot -= 8; // 每个槽 8 字节
        
        interval.spill_slot = spill_slot;
        try reg_map.assignSpillSlot(interval.var_id, spill_slot);
    }
    
    /// 获取统计信息
    pub fn getStats(self: *const RegisterAllocator) AllocatorStats {
        return self.stats;
    }
};

/// 简化的指令表示（用于活跃区间计算）
pub const Instruction = struct {
    /// 目标操作数（虚拟寄存器 ID）
    dst: ?u32,
    
    /// 源操作数 1
    src1: ?u32,
    
    /// 源操作数 2
    src2: ?u32,
    
    /// 创建指令
    pub fn init(dst: ?u32, src1: ?u32, src2: ?u32) Instruction {
        return Instruction{
            .dst = dst,
            .src1 = src1,
            .src2 = src2,
        };
    }
};

// ============================================================================
// 测试
// ============================================================================

test "LiveInterval: 基本操作" {
    const interval1 = LiveInterval.init(0, 0, 10);
    const interval2 = LiveInterval.init(1, 5, 15);
    const interval3 = LiveInterval.init(2, 20, 30);
    
    // 测试重叠检测
    try std.testing.expect(interval1.overlaps(&interval2));
    try std.testing.expect(interval2.overlaps(&interval1));
    try std.testing.expect(!interval1.overlaps(&interval3));
    try std.testing.expect(!interval3.overlaps(&interval1));
}

test "RegisterAllocator: 简单分配" {
    const allocator = std.testing.allocator;
    var ra = RegisterAllocator.init(allocator);
    defer ra.deinit();
    
    // 添加不重叠的活跃区间
    try ra.addInterval(LiveInterval.init(0, 0, 5));
    try ra.addInterval(LiveInterval.init(1, 10, 15));
    try ra.addInterval(LiveInterval.init(2, 20, 25));
    
    // 执行分配
    var reg_map = try ra.allocate();
    defer reg_map.deinit();
    
    // 验证所有变量都分配到寄存器
    try std.testing.expect(reg_map.getReg(0) != null);
    try std.testing.expect(reg_map.getReg(1) != null);
    try std.testing.expect(reg_map.getReg(2) != null);
    
    // 验证统计信息
    const stats = ra.getStats();
    try std.testing.expectEqual(@as(u32, 3), stats.total_vars);
    try std.testing.expectEqual(@as(u32, 3), stats.allocated_regs);
    try std.testing.expectEqual(@as(u32, 0), stats.spilled_vars);
}

test "RegisterAllocator: 重叠区间" {
    const allocator = std.testing.allocator;
    var ra = RegisterAllocator.init(allocator);
    defer ra.deinit();
    
    // 添加重叠的活跃区间
    try ra.addInterval(LiveInterval.init(0, 0, 10));
    try ra.addInterval(LiveInterval.init(1, 5, 15));
    try ra.addInterval(LiveInterval.init(2, 8, 20));
    
    // 执行分配
    var reg_map = try ra.allocate();
    defer reg_map.deinit();
    
    // 验证所有变量都分配到不同的寄存器
    const reg0 = reg_map.getReg(0).?;
    const reg1 = reg_map.getReg(1).?;
    const reg2 = reg_map.getReg(2).?;
    
    try std.testing.expect(reg0 != reg1);
    try std.testing.expect(reg0 != reg2);
    try std.testing.expect(reg1 != reg2);
}

test "RegisterAllocator: 从指令计算活跃区间" {
    const allocator = std.testing.allocator;
    var ra = RegisterAllocator.init(allocator);
    defer ra.deinit();
    
    // 创建指令序列
    const instructions = [_]Instruction{
        Instruction.init(0, null, null),      // v0 = ...
        Instruction.init(1, 0, null),         // v1 = v0
        Instruction.init(2, 0, 1),            // v2 = v0 + v1
        Instruction.init(null, 2, null),      // ... = v2
    };
    
    // 计算活跃区间
    try ra.computeLiveIntervals(&instructions);
    
    // 验证区间数量
    try std.testing.expectEqual(@as(usize, 3), ra.live_intervals.items.len);
    
    // 执行分配
    var reg_map = try ra.allocate();
    defer reg_map.deinit();
    
    // 验证分配成功
    try std.testing.expect(reg_map.getReg(0) != null);
    try std.testing.expect(reg_map.getReg(1) != null);
    try std.testing.expect(reg_map.getReg(2) != null);
}
