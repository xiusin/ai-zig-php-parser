// 简单的循环优化器 - 检测简单的for循环并使用FastValue优化
const std = @import("std");
const ast = @import("../compiler/ast.zig");
const types = @import("types.zig");
const Value = types.Value;

pub const LoopOptimizer = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) LoopOptimizer {
        return .{ .allocator = allocator };
    }
    
    /// 检测简单的整数累加循环并优化
    /// 模式: for ($i = start; $i < end; $i++) { $sum = $sum + $i; }
    pub fn tryOptimizeLoop(
        self: *LoopOptimizer,
        start: i64,
        end: i64,
        step: i64,
    ) ?i64 {
        _ = self;
        // 只优化简单的递增循环
        if (step != 1) return null;
        if (start < 0 or end < 0) return null;
        if (end - start > 10_000_000) return null; // 避免过大的循环
        
        // 使用数学公式: sum(0..n-1) = n*(n-1)/2
        if (start == 0) {
            const n = end;
            return @divTrunc(n * (n - 1), 2);
        }
        
        return null;
    }
    
    /// 执行优化的整数循环
    pub fn executeOptimizedLoop(
        self: *LoopOptimizer,
        start: i64,
        end: i64,
        initial_sum: i64,
    ) i64 {
        _ = self;
        var sum = initial_sum;
        var i = start;
        
        // 展开循环以提高性能
        const unroll_factor = 4;
        const end_unrolled = end - (end - start) % unroll_factor;
        
        while (i < end_unrolled) : (i += unroll_factor) {
            sum +%= i;
            sum +%= i + 1;
            sum +%= i + 2;
            sum +%= i + 3;
        }
        
        while (i < end) : (i += 1) {
            sum +%= i;
        }
        
        return sum;
    }
};
