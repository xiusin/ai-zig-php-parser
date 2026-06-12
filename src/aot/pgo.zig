const std = @import("std");
const Allocator = std.mem.Allocator;

/// 性能配置文件
pub const Profile = struct {
    function_frequencies: std.StringHashMap(u64),
    branch_frequencies: std.AutoHashMap(*Branch, BranchProfile),
    call_edge_frequencies: std.AutoHashMap(*PGOCallEdge, u64),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Profile {
        return Profile{
            .function_frequencies = std.StringHashMap(u64).init(allocator),
            .branch_frequencies = std.AutoHashMap(*Branch, BranchProfile).init(allocator),
            .call_edge_frequencies = std.AutoHashMap(*PGOCallEdge, u64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Profile) void {
        self.function_frequencies.deinit();
        self.branch_frequencies.deinit();
        self.call_edge_frequencies.deinit();
    }

    pub fn recordFunctionExecution(self: *Profile, func_name: []const u8) !void {
        const entry = try self.function_frequencies.getOrPut(func_name);
        if (!entry.found_existing) {
            entry.value_ptr.* = 0;
        }
        entry.value_ptr.* += 1;
    }

    pub fn recordBranchExecution(self: *Profile, branch: *Branch, taken: bool) !void {
        const entry = try self.branch_frequencies.getOrPut(branch);
        if (!entry.found_existing) {
            entry.value_ptr.* = BranchProfile{ .taken_count = 0, .not_taken_count = 0 };
        }
        if (taken) {
            entry.value_ptr.taken_count += 1;
        } else {
            entry.value_ptr.not_taken_count += 1;
        }
    }
};

/// 分支表示
pub const Branch = struct {
    id: u32,
    location: []const u8,
};

/// 分支配置文件
pub const BranchProfile = struct {
    taken_count: u64,
    not_taken_count: u64,

    pub fn probability(self: BranchProfile) f64 {
        const total = self.taken_count + self.not_taken_count;
        if (total == 0) return 0.5;
        return @as(f64, @floatFromInt(self.taken_count)) / @as(f64, @floatFromInt(total));
    }
};

/// 调用边（PGO）
pub const PGOCallEdge = struct {
    from: []const u8,
    to: []const u8,
};

/// 函数信息
pub const FunctionInfo = struct {
    name: []const u8,
    frequency: u64,
    size: usize,
};

/// PGO 优化器
pub const ProfileGuidedOptimizer = struct {
    profile: *Profile,
    allocator: Allocator,

    pub fn init(allocator: Allocator, profile: *Profile) ProfileGuidedOptimizer {
        return ProfileGuidedOptimizer{
            .profile = profile,
            .allocator = allocator,
        };
    }

    /// 基于频率的代码布局
    pub fn frequencyBasedLayout(self: *ProfileGuidedOptimizer) !std.ArrayList(FunctionInfo) {
        var hot_functions = try std.ArrayList(FunctionInfo).initCapacity(self.allocator, 0);

        var it = self.profile.function_frequencies.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* > 1000) {
                try hot_functions.append(self.allocator, FunctionInfo{
                    .name = entry.key_ptr.*,
                    .frequency = entry.value_ptr.*,
                    .size = 0,
                });
            }
        }

        // 按频率排序
        const Context = struct {
            pub fn lessThan(_: @This(), a: FunctionInfo, b: FunctionInfo) bool {
                return a.frequency > b.frequency;
            }
        };
        std.mem.sort(FunctionInfo, hot_functions.items, Context{}, Context.lessThan);

        return hot_functions;
    }

    /// 基于分支预测的优化
    pub fn branchPredictionOptimization(self: *ProfileGuidedOptimizer) !std.ArrayList(BranchOptimization) {
        var optimizations = try std.ArrayList(BranchOptimization).initCapacity(self.allocator, 0);

        var it = self.profile.branch_frequencies.iterator();
        while (it.next()) |entry| {
            const prob = entry.value_ptr.probability();
            if (prob > 0.9) {
                try optimizations.append(self.allocator, BranchOptimization{
                    .branch = entry.key_ptr.*,
                    .layout = .taken_first,
                    .probability = prob,
                });
            } else if (prob < 0.1) {
                try optimizations.append(self.allocator, BranchOptimization{
                    .branch = entry.key_ptr.*,
                    .layout = .not_taken_first,
                    .probability = prob,
                });
            }
        }

        return optimizations;
    }

    /// 基于调用频率的内联决策
    pub fn profileGuidedInlining(self: *ProfileGuidedOptimizer) !std.ArrayList(InlineDecision) {
        var decisions = try std.ArrayList(InlineDecision).initCapacity(self.allocator, 0);

        var it = self.profile.call_edge_frequencies.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* > 100) {
                try decisions.append(self.allocator, InlineDecision{
                    .caller = entry.key_ptr.from,
                    .callee = entry.key_ptr.to,
                    .frequency = entry.value_ptr.*,
                    .should_inline = true,
                });
            }
        }

        return decisions;
    }
};

/// 分支优化
pub const BranchOptimization = struct {
    branch: *Branch,
    layout: BranchLayout,
    probability: f64,
};

pub const BranchLayout = enum {
    taken_first,
    not_taken_first,
};

/// 内联决策
pub const InlineDecision = struct {
    caller: []const u8,
    callee: []const u8,
    frequency: u64,
    should_inline: bool,
};
