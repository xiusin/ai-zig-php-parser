/// JIT 内联决策引擎
/// 
/// 基于成本分析决定是否内联函数调用，提升 JIT 代码性能。
/// 
/// @concurrency-model ISOLATED (单线程访问)
/// @ownership NON-OWNING (allocator)
/// @memory-safety 所有内存操作通过显式 allocator

const std = @import("std");

/// 内联成本模型
pub const InlineCost = struct {
    /// 指令数量
    instruction_count: u32,
    /// 调用深度
    call_depth: u32,
    /// 循环嵌套深度
    loop_depth: u32,
    /// 是否包含异常处理
    has_exception_handling: bool,
    /// 是否包含复杂控制流
    has_complex_control_flow: bool,
    
    /// 计算总成本
    /// @post 返回加权成本值
    pub fn totalCost(self: *const InlineCost) u32 {
        var cost: u32 = self.instruction_count;
        
        // 调用深度惩罚（每层 +20）
        cost += self.call_depth * 20;
        
        // 循环嵌套惩罚（每层 +50）
        cost += self.loop_depth * 50;
        
        // 异常处理惩罚 (+100)
        if (self.has_exception_handling) {
            cost += 100;
        }
        
        // 复杂控制流惩罚 (+30)
        if (self.has_complex_control_flow) {
            cost += 30;
        }
        
        return cost;
    }
    
    /// 判断是否为简单函数（适合内联）
    pub fn isSimple(self: *const InlineCost) bool {
        return self.instruction_count <= 10 and
               self.call_depth == 0 and
               self.loop_depth == 0 and
               !self.has_exception_handling and
               !self.has_complex_control_flow;
    }
};

/// 内联收益模型
pub const InlineBenefit = struct {
    /// 调用频率（每秒调用次数）
    call_frequency: u32,
    /// 参数传递开销节省
    parameter_overhead_saved: u32,
    /// 返回值处理开销节省
    return_overhead_saved: u32,
    /// 寄存器分配改进
    register_allocation_improvement: u32,
    /// 常量传播机会
    constant_propagation_opportunities: u32,
    
    /// 计算总收益
    /// @post 返回加权收益值
    pub fn totalBenefit(self: *const InlineBenefit) u32 {
        var benefit: u32 = 0;
        
        // 调用频率权重（每次调用节省 10 个周期）
        benefit += self.call_frequency * 10;
        
        // 参数传递开销
        benefit += self.parameter_overhead_saved * 5;
        
        // 返回值处理开销
        benefit += self.return_overhead_saved * 5;
        
        // 寄存器分配改进
        benefit += self.register_allocation_improvement * 15;
        
        // 常量传播机会
        benefit += self.constant_propagation_opportunities * 20;
        
        return benefit;
    }
};

/// 内联决策配置
pub const InlineConfig = struct {
    /// 最大内联成本阈值
    max_inline_cost: u32 = 100,
    /// 最小收益/成本比
    min_benefit_cost_ratio: f32 = 1.5,
    /// 最大内联深度
    max_inline_depth: u32 = 3,
    /// 最大函数大小（指令数）
    max_function_size: u32 = 50,
    /// 是否启用激进内联
    aggressive_inlining: bool = false,
    
    /// 默认配置
    pub fn default() InlineConfig {
        return .{};
    }
    
    /// 保守配置（更少内联）
    pub fn conservative() InlineConfig {
        return .{
            .max_inline_cost = 50,
            .min_benefit_cost_ratio = 2.0,
            .max_inline_depth = 2,
            .max_function_size = 30,
            .aggressive_inlining = false,
        };
    }
    
    /// 激进配置（更多内联）
    pub fn aggressive() InlineConfig {
        return .{
            .max_inline_cost = 200,
            .min_benefit_cost_ratio = 1.2,
            .max_inline_depth = 5,
            .max_function_size = 100,
            .aggressive_inlining = true,
        };
    }
};

/// 内联决策结果
pub const InlineDecision = enum {
    /// 应该内联
    should_inline,
    /// 不应该内联
    should_not_inline,
    /// 可选内联（边界情况）
    optional_inline,
    
    pub fn shouldInline(self: InlineDecision) bool {
        return self == .should_inline;
    }
};

/// 内联决策原因
pub const InlineReason = struct {
    decision: InlineDecision,
    cost: u32,
    benefit: u32,
    reason: []const u8,
    
    pub fn format(
        self: InlineReason,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("InlineDecision: {s} (cost={d}, benefit={d}, reason=\"{s}\")", .{
            @tagName(self.decision),
            self.cost,
            self.benefit,
            self.reason,
        });
    }
};

/// 内联决策引擎
/// @concurrency-model ISOLATED
/// @ownership NON-OWNING (allocator)
pub const InlineDecisionEngine = struct {
    allocator: std.mem.Allocator,
    config: InlineConfig,
    
    // 统计信息
    total_decisions: u64 = 0,
    inline_decisions: u64 = 0,
    no_inline_decisions: u64 = 0,
    optional_inline_decisions: u64 = 0,
    
    /// @pre allocator 必须有效
    /// @post 返回初始化的 InlineDecisionEngine 实例
    pub fn init(allocator: std.mem.Allocator, config: InlineConfig) InlineDecisionEngine {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }
    
    /// 决定是否内联函数
    /// @pre cost 和 benefit 必须有效
    /// @post 返回内联决策和原因
    pub fn decide(
        self: *InlineDecisionEngine,
        cost: InlineCost,
        benefit: InlineBenefit,
        current_depth: u32,
    ) InlineReason {
        self.total_decisions += 1;
        
        const total_cost = cost.totalCost();
        const total_benefit = benefit.totalBenefit();
        
        // 规则 1: 超过最大深度
        if (current_depth >= self.config.max_inline_depth) {
            self.no_inline_decisions += 1;
            return .{
                .decision = .should_not_inline,
                .cost = total_cost,
                .benefit = total_benefit,
                .reason = "超过最大内联深度",
            };
        }
        
        // 规则 2: 超过最大函数大小
        if (cost.instruction_count > self.config.max_function_size) {
            self.no_inline_decisions += 1;
            return .{
                .decision = .should_not_inline,
                .cost = total_cost,
                .benefit = total_benefit,
                .reason = "函数太大",
            };
        }
        
        // 规则 3: 简单函数总是内联
        if (cost.isSimple()) {
            self.inline_decisions += 1;
            return .{
                .decision = .should_inline,
                .cost = total_cost,
                .benefit = total_benefit,
                .reason = "简单函数",
            };
        }
        
        // 规则 4: 成本超过阈值
        if (total_cost > self.config.max_inline_cost) {
            self.no_inline_decisions += 1;
            return .{
                .decision = .should_not_inline,
                .cost = total_cost,
                .benefit = total_benefit,
                .reason = "成本过高",
            };
        }
        
        // 规则 5: 收益/成本比分析
        const benefit_cost_ratio = if (total_cost > 0)
            @as(f32, @floatFromInt(total_benefit)) / @as(f32, @floatFromInt(total_cost))
        else
            0.0;
        
        if (benefit_cost_ratio >= self.config.min_benefit_cost_ratio) {
            self.inline_decisions += 1;
            return .{
                .decision = .should_inline,
                .cost = total_cost,
                .benefit = total_benefit,
                .reason = "收益/成本比高",
            };
        }
        
        // 规则 6: 激进模式
        if (self.config.aggressive_inlining and benefit_cost_ratio >= 1.0) {
            self.optional_inline_decisions += 1;
            return .{
                .decision = .optional_inline,
                .cost = total_cost,
                .benefit = total_benefit,
                .reason = "激进模式：收益大于成本",
            };
        }
        
        // 默认：不内联
        self.no_inline_decisions += 1;
        return .{
            .decision = .should_not_inline,
            .cost = total_cost,
            .benefit = total_benefit,
            .reason = "收益不足",
        };
    }
    
    /// 快速决策（仅基于成本）
    /// @pre cost 必须有效
    /// @post 返回快速决策结果
    pub fn quickDecide(
        self: *InlineDecisionEngine,
        cost: InlineCost,
        current_depth: u32,
    ) InlineDecision {
        // 超过深度限制
        if (current_depth >= self.config.max_inline_depth) {
            return .should_not_inline;
        }
        
        // 简单函数
        if (cost.isSimple()) {
            return .should_inline;
        }
        
        // 成本检查
        const total_cost = cost.totalCost();
        if (total_cost <= self.config.max_inline_cost / 2) {
            return .should_inline;
        } else if (total_cost > self.config.max_inline_cost) {
            return .should_not_inline;
        } else {
            return .optional_inline;
        }
    }
    
    /// 获取内联率
    /// @post 返回内联决策的比例 (0.0 - 1.0)
    pub fn getInlineRate(self: *const InlineDecisionEngine) f32 {
        if (self.total_decisions == 0) {
            return 0.0;
        }
        return @as(f32, @floatFromInt(self.inline_decisions)) / 
               @as(f32, @floatFromInt(self.total_decisions));
    }
    
    /// 打印统计信息
    pub fn printStats(self: *const InlineDecisionEngine) void {
        std.debug.print("=== 内联决策引擎统计 ===\n", .{});
        std.debug.print("总决策次数: {d}\n", .{self.total_decisions});
        std.debug.print("内联决策: {d} ({d:.2}%)\n", .{
            self.inline_decisions,
            self.getInlineRate() * 100.0,
        });
        std.debug.print("不内联决策: {d} ({d:.2}%)\n", .{
            self.no_inline_decisions,
            @as(f32, @floatFromInt(self.no_inline_decisions)) / 
            @as(f32, @floatFromInt(self.total_decisions)) * 100.0,
        });
        std.debug.print("可选内联决策: {d} ({d:.2}%)\n", .{
            self.optional_inline_decisions,
            @as(f32, @floatFromInt(self.optional_inline_decisions)) / 
            @as(f32, @floatFromInt(self.total_decisions)) * 100.0,
        });
    }
    
    /// 重置统计信息
    pub fn resetStats(self: *InlineDecisionEngine) void {
        self.total_decisions = 0;
        self.inline_decisions = 0;
        self.no_inline_decisions = 0;
        self.optional_inline_decisions = 0;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "InlineCost 计算" {
    const cost = InlineCost{
        .instruction_count = 10,
        .call_depth = 1,
        .loop_depth = 0,
        .has_exception_handling = false,
        .has_complex_control_flow = false,
    };
    
    const total = cost.totalCost();
    try std.testing.expectEqual(@as(u32, 30), total); // 10 + 1*20
}

test "InlineCost 简单函数判断" {
    const simple = InlineCost{
        .instruction_count = 5,
        .call_depth = 0,
        .loop_depth = 0,
        .has_exception_handling = false,
        .has_complex_control_flow = false,
    };
    
    try std.testing.expect(simple.isSimple());
    
    const complex = InlineCost{
        .instruction_count = 20,
        .call_depth = 1,
        .loop_depth = 0,
        .has_exception_handling = false,
        .has_complex_control_flow = false,
    };
    
    try std.testing.expect(!complex.isSimple());
}

test "InlineBenefit 计算" {
    const benefit = InlineBenefit{
        .call_frequency = 100,
        .parameter_overhead_saved = 2,
        .return_overhead_saved = 1,
        .register_allocation_improvement = 3,
        .constant_propagation_opportunities = 2,
    };
    
    const total = benefit.totalBenefit();
    // 100*10 + 2*5 + 1*5 + 3*15 + 2*20 = 1000 + 10 + 5 + 45 + 40 = 1100
    try std.testing.expectEqual(@as(u32, 1100), total);
}

test "InlineDecisionEngine 简单函数" {
    const allocator = std.testing.allocator;
    var engine = InlineDecisionEngine.init(allocator, InlineConfig.default());
    
    const cost = InlineCost{
        .instruction_count = 5,
        .call_depth = 0,
        .loop_depth = 0,
        .has_exception_handling = false,
        .has_complex_control_flow = false,
    };
    
    const benefit = InlineBenefit{
        .call_frequency = 10,
        .parameter_overhead_saved = 1,
        .return_overhead_saved = 1,
        .register_allocation_improvement = 1,
        .constant_propagation_opportunities = 1,
    };
    
    const reason = engine.decide(cost, benefit, 0);
    try std.testing.expectEqual(InlineDecision.should_inline, reason.decision);
}

test "InlineDecisionEngine 成本过高" {
    const allocator = std.testing.allocator;
    var engine = InlineDecisionEngine.init(allocator, InlineConfig.default());
    
    const cost = InlineCost{
        .instruction_count = 60, // 超过 max_function_size (50)
        .call_depth = 0,
        .loop_depth = 0,
        .has_exception_handling = false,
        .has_complex_control_flow = false,
    };
    
    const benefit = InlineBenefit{
        .call_frequency = 100,
        .parameter_overhead_saved = 2,
        .return_overhead_saved = 1,
        .register_allocation_improvement = 3,
        .constant_propagation_opportunities = 2,
    };
    
    const reason = engine.decide(cost, benefit, 0);
    try std.testing.expectEqual(InlineDecision.should_not_inline, reason.decision);
}

test "InlineDecisionEngine 深度限制" {
    const allocator = std.testing.allocator;
    var engine = InlineDecisionEngine.init(allocator, InlineConfig.default());
    
    const cost = InlineCost{
        .instruction_count = 5,
        .call_depth = 0,
        .loop_depth = 0,
        .has_exception_handling = false,
        .has_complex_control_flow = false,
    };
    
    const benefit = InlineBenefit{
        .call_frequency = 100,
        .parameter_overhead_saved = 2,
        .return_overhead_saved = 1,
        .register_allocation_improvement = 3,
        .constant_propagation_opportunities = 2,
    };
    
    // 深度 0: 应该内联
    const reason1 = engine.decide(cost, benefit, 0);
    try std.testing.expectEqual(InlineDecision.should_inline, reason1.decision);
    
    // 深度 3: 超过限制，不应该内联
    const reason2 = engine.decide(cost, benefit, 3);
    try std.testing.expectEqual(InlineDecision.should_not_inline, reason2.decision);
}

test "InlineDecisionEngine 统计" {
    const allocator = std.testing.allocator;
    var engine = InlineDecisionEngine.init(allocator, InlineConfig.default());
    
    const simple_cost = InlineCost{
        .instruction_count = 5,
        .call_depth = 0,
        .loop_depth = 0,
        .has_exception_handling = false,
        .has_complex_control_flow = false,
    };
    
    const complex_cost = InlineCost{
        .instruction_count = 60,
        .call_depth = 0,
        .loop_depth = 0,
        .has_exception_handling = false,
        .has_complex_control_flow = false,
    };
    
    const benefit = InlineBenefit{
        .call_frequency = 10,
        .parameter_overhead_saved = 1,
        .return_overhead_saved = 1,
        .register_allocation_improvement = 1,
        .constant_propagation_opportunities = 1,
    };
    
    // 5 个简单函数（应该内联）
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        _ = engine.decide(simple_cost, benefit, 0);
    }
    
    // 3 个复杂函数（不应该内联）
    i = 0;
    while (i < 3) : (i += 1) {
        _ = engine.decide(complex_cost, benefit, 0);
    }
    
    try std.testing.expectEqual(@as(u64, 8), engine.total_decisions);
    try std.testing.expectEqual(@as(u64, 5), engine.inline_decisions);
    try std.testing.expectEqual(@as(u64, 3), engine.no_inline_decisions);
    
    const rate = engine.getInlineRate();
    try std.testing.expect(rate >= 0.6 and rate <= 0.65); // 5/8 = 0.625
}

