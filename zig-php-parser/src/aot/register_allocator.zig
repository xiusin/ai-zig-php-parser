//! 寄存器分配优化
//!
//! 使用图着色算法进行寄存器分配，减少内存访问

const std = @import("std");
const IR = @import("ir.zig");
const Function = IR.Function;
const Register = IR.Register;

pub const RegisterAllocator = struct {
    allocator: std.mem.Allocator,
    /// 活跃区间
    live_intervals: std.AutoHashMapUnmanaged(u32, Interval),
    /// 寄存器分配结果
    allocation: std.AutoHashMapUnmanaged(u32, u8),
    
    const Interval = struct {
        start: u32,
        end: u32,
    };
    
    pub fn init(allocator: std.mem.Allocator) RegisterAllocator {
        return .{
            .allocator = allocator,
            .live_intervals = .{},
            .allocation = .{},
        };
    }
    
    pub fn deinit(self: *RegisterAllocator) void {
        self.live_intervals.deinit(self.allocator);
        self.allocation.deinit(self.allocator);
    }
    
    /// 线性扫描寄存器分配
    pub fn allocate(self: *RegisterAllocator, func: *Function) !void {
        // 1. 计算活跃区间
        try self.computeLiveIntervals(func);
        
        // 2. 按起始点排序
        var intervals = std.ArrayList(struct { reg: u32, interval: Interval }).init(self.allocator);
        defer intervals.deinit();
        
        var it = self.live_intervals.iterator();
        while (it.next()) |entry| {
            try intervals.append(.{ .reg = entry.key_ptr.*, .interval = entry.value_ptr.* });
        }
        
        std.sort.pdq(
            @TypeOf(intervals.items[0]),
            intervals.items,
            {},
            struct {
                fn lessThan(_: void, a: @TypeOf(intervals.items[0]), b: @TypeOf(intervals.items[0])) bool {
                    return a.interval.start < b.interval.start;
                }
            }.lessThan,
        );
        
        // 3. 线性扫描分配
        var active = std.ArrayList(struct { reg: u32, end: u32, phys: u8 }).init(self.allocator);
        defer active.deinit();
        
        var next_reg: u8 = 0;
        const max_regs: u8 = 16; // 假设有16个物理寄存器
        
        for (intervals.items) |item| {
            // 移除已结束的区间
            var i: usize = 0;
            while (i < active.items.len) {
                if (active.items[i].end < item.interval.start) {
                    _ = active.orderedRemove(i);
                } else {
                    i += 1;
                }
            }
            
            // 分配寄存器
            if (active.items.len < max_regs) {
                const phys_reg = next_reg;
                next_reg = (next_reg + 1) % max_regs;
                try self.allocation.put(self.allocator, item.reg, phys_reg);
                try active.append(.{ .reg = item.reg, .end = item.interval.end, .phys = phys_reg });
            } else {
                // 溢出到内存（简化处理）
                try self.allocation.put(self.allocator, item.reg, 255); // 255 表示溢出
            }
        }
    }
    
    fn computeLiveIntervals(self: *RegisterAllocator, func: *Function) !void {
        self.live_intervals.clearRetainingCapacity();
        
        var pos: u32 = 0;
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                // 更新使用的寄存器的活跃区间
                if (inst.result) |result| {
                    const entry = try self.live_intervals.getOrPut(self.allocator, result.id);
                    if (!entry.found_existing) {
                        entry.value_ptr.* = .{ .start = pos, .end = pos };
                    }
                    entry.value_ptr.end = pos;
                }
                pos += 1;
            }
        }
    }
};
