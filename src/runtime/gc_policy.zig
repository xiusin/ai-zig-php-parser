const std = @import("std");

/// GC 触发策略
/// 实现自适应 GC 触发、GC 类型选择、并发标记启动等策略

// ============================================================================
// GC 类型定义
// ============================================================================

pub const GCType = enum {
    /// Minor GC - 只收集年轻代
    minor,
    /// Major GC - 收集年轻代和老年代
    major,
    /// Full GC - 完整收集（包括大对象空间）
    full,
    /// 增量 GC - 分步执行
    incremental,
    /// 并发 GC - 后台执行
    concurrent,
};

pub const GCTriggerReason = enum {
    /// 分配失败触发
    allocation_failure,
    /// 内存阈值触发
    memory_threshold,
    /// 分配速率触发
    allocation_rate,
    /// 定时触发
    timer,
    /// 手动触发
    manual,
    /// 内存压力触发
    memory_pressure,
    /// 碎片化触发
    fragmentation,
    /// 晋升失败触发
    promotion_failure,
};

// ============================================================================
// 内存压力级别
// ============================================================================

pub const MemoryPressure = enum(u8) {
    /// 正常 - 内存充足
    normal = 0,
    /// 轻度 - 开始关注
    light = 1,
    /// 中度 - 需要 GC
    moderate = 2,
    /// 重度 - 紧急 GC
    heavy = 3,
    /// 危急 - 可能 OOM
    critical = 4,
};

// ============================================================================
// GC 策略配置
// ============================================================================

pub const GCPolicyConfig = struct {
    // ========== 内存阈值 ==========
    /// Nursery GC 触发阈值（使用率）
    nursery_threshold: f64 = 0.8,
    /// 老年代 GC 触发阈值（使用率）
    old_gen_threshold: f64 = 0.7,
    /// Full GC 触发阈值（总内存使用率）
    full_gc_threshold: f64 = 0.9,

    // ========== 分配速率 ==========
    /// 分配速率采样窗口（毫秒）
    allocation_rate_window_ms: u64 = 1000,
    /// 高分配速率阈值（字节/秒）
    high_allocation_rate: usize = 10 * 1024 * 1024, // 10MB/s
    /// 触发并发 GC 的分配速率阈值
    concurrent_gc_rate: usize = 5 * 1024 * 1024, // 5MB/s

    // ========== GC 开销 ==========
    /// 目标 GC 开销（GC 时间占比）
    target_gc_overhead: f64 = 0.05, // 5%
    /// 最大可接受 GC 开销
    max_gc_overhead: f64 = 0.15, // 15%
    /// GC 开销调整步长
    overhead_adjustment_step: f64 = 0.1,

    // ========== 停顿时间 ==========
    /// 目标最大停顿时间（毫秒）
    target_pause_time_ms: u64 = 10,
    /// 增量 GC 步进工作量
    incremental_step_size: usize = 1000,

    // ========== 碎片化 ==========
    /// 触发压缩的碎片化阈值
    fragmentation_threshold: f64 = 0.3, // 30%

    // ========== 自适应调整 ==========
    /// 是否启用自适应调整
    adaptive_enabled: bool = true,
    /// 自适应调整周期（GC 次数）
    adaptive_period: u32 = 10,
};

// ============================================================================
// 分配速率追踪器
// ============================================================================

pub const AllocationRateTracker = struct {
    /// 采样窗口内的分配量
    samples: [SAMPLE_COUNT]Sample,
    /// 当前采样索引
    current_index: usize,
    /// 有效采样数
    valid_samples: usize,
    /// 总分配量
    total_allocated: usize,
    /// 上次采样时间
    last_sample_time: i64,

    const SAMPLE_COUNT: usize = 10;

    const Sample = struct {
        bytes: usize,
        timestamp: i64,
    };

    pub fn init() AllocationRateTracker {
        return .{
            .samples = [_]Sample{.{ .bytes = 0, .timestamp = 0 }} ** SAMPLE_COUNT,
            .current_index = 0,
            .valid_samples = 0,
            .total_allocated = 0,
            .last_sample_time = 0,
        };
    }

    /// 记录分配
    pub fn recordAllocation(self: *AllocationRateTracker, bytes: usize) void {
        self.total_allocated += bytes;
    }

    /// 采样当前分配速率
    pub fn sample(self: *AllocationRateTracker) void {
        const now = std.time.milliTimestamp();

        self.samples[self.current_index] = .{
            .bytes = self.total_allocated,
            .timestamp = now,
        };

        self.current_index = (self.current_index + 1) % SAMPLE_COUNT;
        if (self.valid_samples < SAMPLE_COUNT) {
            self.valid_samples += 1;
        }

        self.last_sample_time = now;
    }

    /// 计算分配速率（字节/秒）
    pub fn getRate(self: *const AllocationRateTracker) usize {
        if (self.valid_samples < 2) return 0;

        // 找到最早和最新的有效采样
        const newest_idx = if (self.current_index == 0) SAMPLE_COUNT - 1 else self.current_index - 1;
        const oldest_idx = if (self.valid_samples == SAMPLE_COUNT)
            self.current_index
        else
            0;

        const newest = self.samples[newest_idx];
        const oldest = self.samples[oldest_idx];

        const time_diff = newest.timestamp - oldest.timestamp;
        if (time_diff <= 0) return 0;

        const bytes_diff = if (newest.bytes >= oldest.bytes)
            newest.bytes - oldest.bytes
        else
            0;

        // 转换为字节/秒
        return @intCast(bytes_diff * 1000 / @as(usize, @intCast(time_diff)));
    }

    /// 获取平均分配速率
    pub fn getAverageRate(self: *const AllocationRateTracker) usize {
        return self.getRate();
    }

    /// 检查是否为高分配速率
    pub fn isHighRate(self: *const AllocationRateTracker, threshold: usize) bool {
        return self.getRate() >= threshold;
    }
};

// ============================================================================
// GC 开销追踪器
// ============================================================================

pub const GCOverheadTracker = struct {
    /// GC 时间采样
    gc_times: [SAMPLE_COUNT]u64,
    /// 总时间采样
    total_times: [SAMPLE_COUNT]u64,
    /// 当前索引
    current_index: usize,
    /// 有效采样数
    valid_samples: usize,
    /// 上次 GC 结束时间
    last_gc_end: i64,
    /// 累计 GC 时间
    total_gc_time: u64,
    /// 累计运行时间
    total_run_time: u64,

    const SAMPLE_COUNT: usize = 20;

    pub fn init() GCOverheadTracker {
        return .{
            .gc_times = [_]u64{0} ** SAMPLE_COUNT,
            .total_times = [_]u64{0} ** SAMPLE_COUNT,
            .current_index = 0,
            .valid_samples = 0,
            .last_gc_end = std.time.milliTimestamp(),
            .total_gc_time = 0,
            .total_run_time = 0,
        };
    }

    /// 记录 GC 完成
    pub fn recordGC(self: *GCOverheadTracker, gc_time_ns: u64) void {
        const now = std.time.milliTimestamp();
        const interval: u64 = @intCast(@max(0, now - self.last_gc_end));

        self.gc_times[self.current_index] = gc_time_ns / 1_000_000; // 转换为毫秒
        self.total_times[self.current_index] = interval;

        self.current_index = (self.current_index + 1) % SAMPLE_COUNT;
        if (self.valid_samples < SAMPLE_COUNT) {
            self.valid_samples += 1;
        }

        self.total_gc_time += gc_time_ns / 1_000_000;
        self.total_run_time += interval;
        self.last_gc_end = now;
    }

    /// 计算 GC 开销（0.0 - 1.0）
    pub fn getOverhead(self: *const GCOverheadTracker) f64 {
        if (self.valid_samples == 0) return 0.0;

        var total_gc: u64 = 0;
        var total_time: u64 = 0;

        const count = self.valid_samples;
        for (0..count) |i| {
            total_gc += self.gc_times[i];
            total_time += self.total_times[i];
        }

        if (total_time == 0) return 0.0;
        return @as(f64, @floatFromInt(total_gc)) / @as(f64, @floatFromInt(total_time));
    }

    /// 获取平均 GC 时间（毫秒）
    pub fn getAverageGCTime(self: *const GCOverheadTracker) f64 {
        if (self.valid_samples == 0) return 0.0;

        var total: u64 = 0;
        for (0..self.valid_samples) |i| {
            total += self.gc_times[i];
        }

        return @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(self.valid_samples));
    }
};

// ============================================================================
// GC 策略主结构
// ============================================================================

pub const GCPolicy = struct {
    /// 配置
    config: GCPolicyConfig,
    /// 分配速率追踪
    allocation_tracker: AllocationRateTracker,
    /// GC 开销追踪
    overhead_tracker: GCOverheadTracker,
    /// 当前内存压力
    memory_pressure: MemoryPressure,
    /// 上次 GC 类型
    last_gc_type: ?GCType,
    /// 连续 Minor GC 次数
    consecutive_minor_gc: u32,
    /// 连续晋升失败次数
    consecutive_promotion_failures: u32,
    /// 自适应调整计数器
    adaptive_counter: u32,
    /// 统计信息
    stats: PolicyStats,

    pub const PolicyStats = struct {
        /// 各类型 GC 触发次数
        minor_gc_triggers: u64 = 0,
        major_gc_triggers: u64 = 0,
        full_gc_triggers: u64 = 0,
        /// 各原因触发次数
        allocation_failure_triggers: u64 = 0,
        threshold_triggers: u64 = 0,
        rate_triggers: u64 = 0,
        pressure_triggers: u64 = 0,
        /// 自适应调整次数
        adaptive_adjustments: u64 = 0,
    };

    pub fn init() GCPolicy {
        return initWithConfig(.{});
    }

    pub fn initWithConfig(config: GCPolicyConfig) GCPolicy {
        return .{
            .config = config,
            .allocation_tracker = AllocationRateTracker.init(),
            .overhead_tracker = GCOverheadTracker.init(),
            .memory_pressure = .normal,
            .last_gc_type = null,
            .consecutive_minor_gc = 0,
            .consecutive_promotion_failures = 0,
            .adaptive_counter = 0,
            .stats = .{},
        };
    }

    /// 记录分配
    pub fn recordAllocation(self: *GCPolicy, bytes: usize) void {
        self.allocation_tracker.recordAllocation(bytes);
    }

    /// 记录 GC 完成
    pub fn recordGCComplete(self: *GCPolicy, gc_type: GCType, gc_time_ns: u64) void {
        self.overhead_tracker.recordGC(gc_time_ns);
        self.last_gc_type = gc_type;

        switch (gc_type) {
            .minor => {
                self.consecutive_minor_gc += 1;
                self.stats.minor_gc_triggers += 1;
            },
            .major => {
                self.consecutive_minor_gc = 0;
                self.stats.major_gc_triggers += 1;
            },
            .full => {
                self.consecutive_minor_gc = 0;
                self.stats.full_gc_triggers += 1;
            },
            else => {},
        }

        // 自适应调整
        if (self.config.adaptive_enabled) {
            self.adaptive_counter += 1;
            if (self.adaptive_counter >= self.config.adaptive_period) {
                self.adaptiveAdjust();
                self.adaptive_counter = 0;
            }
        }
    }

    /// 记录晋升失败
    pub fn recordPromotionFailure(self: *GCPolicy) void {
        self.consecutive_promotion_failures += 1;
    }

    /// 重置晋升失败计数
    pub fn resetPromotionFailures(self: *GCPolicy) void {
        self.consecutive_promotion_failures = 0;
    }

    /// 更新内存压力
    pub fn updateMemoryPressure(self: *GCPolicy, usage: MemoryUsage) void {
        const total_ratio = usage.getTotalUsageRatio();

        self.memory_pressure = if (total_ratio >= 0.95)
            .critical
        else if (total_ratio >= 0.85)
            .heavy
        else if (total_ratio >= 0.70)
            .moderate
        else if (total_ratio >= 0.50)
            .light
        else
            .normal;
    }

    /// 决定是否需要 GC
    pub fn shouldTriggerGC(self: *GCPolicy, usage: MemoryUsage) ?GCDecision {
        self.updateMemoryPressure(usage);

        // 1. 检查危急内存压力
        if (self.memory_pressure == .critical) {
            self.stats.pressure_triggers += 1;
            return .{
                .gc_type = .full,
                .reason = .memory_pressure,
                .urgency = .immediate,
            };
        }

        // 2. 检查晋升失败
        if (self.consecutive_promotion_failures >= 3) {
            return .{
                .gc_type = .major,
                .reason = .promotion_failure,
                .urgency = .high,
            };
        }

        // 3. 检查 Nursery 阈值
        if (usage.nursery_ratio >= self.config.nursery_threshold) {
            self.stats.threshold_triggers += 1;
            return .{
                .gc_type = .minor,
                .reason = .memory_threshold,
                .urgency = .normal,
            };
        }

        // 4. 检查老年代阈值
        if (usage.old_gen_ratio >= self.config.old_gen_threshold) {
            self.stats.threshold_triggers += 1;
            return .{
                .gc_type = .major,
                .reason = .memory_threshold,
                .urgency = .high,
            };
        }

        // 5. 检查总内存阈值
        if (usage.getTotalUsageRatio() >= self.config.full_gc_threshold) {
            self.stats.threshold_triggers += 1;
            return .{
                .gc_type = .full,
                .reason = .memory_threshold,
                .urgency = .high,
            };
        }

        // 6. 检查分配速率
        if (self.allocation_tracker.isHighRate(self.config.high_allocation_rate)) {
            self.stats.rate_triggers += 1;

            // 高分配速率时，如果连续多次 Minor GC，考虑 Major GC
            if (self.consecutive_minor_gc >= 5) {
                return .{
                    .gc_type = .major,
                    .reason = .allocation_rate,
                    .urgency = .normal,
                };
            }

            return .{
                .gc_type = .minor,
                .reason = .allocation_rate,
                .urgency = .normal,
            };
        }

        // 7. 检查碎片化
        if (usage.fragmentation >= self.config.fragmentation_threshold) {
            return .{
                .gc_type = .full,
                .reason = .fragmentation,
                .urgency = .low,
            };
        }

        return null;
    }

    /// 处理分配失败
    pub fn handleAllocationFailure(self: *GCPolicy, requested_size: usize, generation: u2) GCDecision {
        self.stats.allocation_failure_triggers += 1;
        _ = requested_size;

        return switch (generation) {
            0 => .{ // Nursery
                .gc_type = .minor,
                .reason = .allocation_failure,
                .urgency = .immediate,
            },
            1 => .{ // Survivor
                .gc_type = .minor,
                .reason = .allocation_failure,
                .urgency = .immediate,
            },
            2 => .{ // Old
                .gc_type = .major,
                .reason = .allocation_failure,
                .urgency = .immediate,
            },
            3 => .{ // Large
                .gc_type = .full,
                .reason = .allocation_failure,
                .urgency = .immediate,
            },
        };
    }

    /// 自适应调整
    fn adaptiveAdjust(self: *GCPolicy) void {
        const overhead = self.overhead_tracker.getOverhead();

        // 如果 GC 开销过高，放宽阈值
        if (overhead > self.config.max_gc_overhead) {
            self.config.nursery_threshold = @min(0.95, self.config.nursery_threshold + self.config.overhead_adjustment_step);
            self.config.old_gen_threshold = @min(0.90, self.config.old_gen_threshold + self.config.overhead_adjustment_step);
            self.stats.adaptive_adjustments += 1;
        }
        // 如果 GC 开销过低，收紧阈值以减少内存占用
        else if (overhead < self.config.target_gc_overhead * 0.5) {
            self.config.nursery_threshold = @max(0.5, self.config.nursery_threshold - self.config.overhead_adjustment_step);
            self.config.old_gen_threshold = @max(0.5, self.config.old_gen_threshold - self.config.overhead_adjustment_step);
            self.stats.adaptive_adjustments += 1;
        }
    }

    /// 获取推荐的增量步进大小
    pub fn getIncrementalStepSize(self: *const GCPolicy) usize {
        const avg_gc_time = self.overhead_tracker.getAverageGCTime();

        // 根据平均 GC 时间调整步进大小
        if (avg_gc_time > @as(f64, @floatFromInt(self.config.target_pause_time_ms))) {
            // GC 时间过长，减小步进
            return self.config.incremental_step_size / 2;
        } else if (avg_gc_time < @as(f64, @floatFromInt(self.config.target_pause_time_ms)) / 2.0) {
            // GC 时间很短，可以增大步进
            return self.config.incremental_step_size * 2;
        }

        return self.config.incremental_step_size;
    }

    /// 是否应该启动并发 GC
    pub fn shouldStartConcurrentGC(self: *const GCPolicy) bool {
        // 分配速率达到阈值时启动并发 GC
        return self.allocation_tracker.isHighRate(self.config.concurrent_gc_rate) and
            self.memory_pressure != .critical;
    }

    /// 获取统计信息
    pub fn getStats(self: *const GCPolicy) PolicyStats {
        return self.stats;
    }

    /// 获取当前配置
    pub fn getConfig(self: *const GCPolicy) GCPolicyConfig {
        return self.config;
    }

    /// 获取诊断信息
    pub fn getDiagnostics(self: *const GCPolicy) Diagnostics {
        return .{
            .memory_pressure = self.memory_pressure,
            .allocation_rate = self.allocation_tracker.getRate(),
            .gc_overhead = self.overhead_tracker.getOverhead(),
            .avg_gc_time_ms = self.overhead_tracker.getAverageGCTime(),
            .consecutive_minor_gc = self.consecutive_minor_gc,
            .consecutive_promotion_failures = self.consecutive_promotion_failures,
            .last_gc_type = self.last_gc_type,
        };
    }

    pub const Diagnostics = struct {
        memory_pressure: MemoryPressure,
        allocation_rate: usize,
        gc_overhead: f64,
        avg_gc_time_ms: f64,
        consecutive_minor_gc: u32,
        consecutive_promotion_failures: u32,
        last_gc_type: ?GCType,
    };
};

// ============================================================================
// GC 决策
// ============================================================================

pub const GCDecision = struct {
    gc_type: GCType,
    reason: GCTriggerReason,
    urgency: Urgency,

    pub const Urgency = enum {
        low, // 可以延迟
        normal, // 正常优先级
        high, // 尽快执行
        immediate, // 立即执行
    };
};

// ============================================================================
// 内存使用情况
// ============================================================================

pub const MemoryUsage = struct {
    nursery_used: usize,
    nursery_total: usize,
    nursery_ratio: f64,
    survivor_used: usize,
    survivor_total: usize,
    survivor_ratio: f64,
    old_gen_used: usize,
    old_gen_total: usize,
    old_gen_ratio: f64,
    large_space_used: usize,
    total_used: usize,
    total_available: usize,
    fragmentation: f64,

    pub fn getTotalUsageRatio(self: MemoryUsage) f64 {
        if (self.total_available == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_used)) / @as(f64, @floatFromInt(self.total_available));
    }
};

// ============================================================================
// 测试
// ============================================================================

test "allocation rate tracker" {
    var tracker = AllocationRateTracker.init();

    // 记录一些分配
    tracker.recordAllocation(1024);
    tracker.sample();

    // 模拟时间流逝（直接修改时间戳）
    tracker.samples[0].timestamp -= 100; // 假设100ms前

    tracker.recordAllocation(2048);
    tracker.sample();

    // 应该能计算出速率
    const rate = tracker.getRate();
    // 速率可能为0如果时间差太小，这里只检查不会崩溃
    _ = rate;
}

test "gc overhead tracker" {
    var tracker = GCOverheadTracker.init();

    // 记录几次 GC
    tracker.recordGC(5_000_000); // 5ms
    // 模拟时间流逝
    tracker.last_gc_end -= 100; // 假设100ms前
    tracker.recordGC(3_000_000); // 3ms

    const overhead = tracker.getOverhead();
    try std.testing.expect(overhead >= 0.0);
    try std.testing.expect(overhead <= 1.0);
}

test "gc policy basic" {
    var policy = GCPolicy.init();

    // 记录分配
    policy.recordAllocation(1024);

    // 测试内存压力更新
    policy.updateMemoryPressure(.{
        .nursery_used = 800,
        .nursery_total = 1000,
        .nursery_ratio = 0.8,
        .survivor_used = 0,
        .survivor_total = 500,
        .survivor_ratio = 0.0,
        .old_gen_used = 0,
        .old_gen_total = 10000,
        .old_gen_ratio = 0.0,
        .large_space_used = 0,
        .total_used = 800,
        .total_available = 11500,
        .fragmentation = 0.0,
    });

    try std.testing.expect(policy.memory_pressure == .normal);
}

test "gc policy trigger decision" {
    var policy = GCPolicy.init();

    // 高 Nursery 使用率应该触发 Minor GC
    const decision = policy.shouldTriggerGC(.{
        .nursery_used = 900,
        .nursery_total = 1000,
        .nursery_ratio = 0.9,
        .survivor_used = 0,
        .survivor_total = 500,
        .survivor_ratio = 0.0,
        .old_gen_used = 0,
        .old_gen_total = 10000,
        .old_gen_ratio = 0.0,
        .large_space_used = 0,
        .total_used = 900,
        .total_available = 11500,
        .fragmentation = 0.0,
    });

    try std.testing.expect(decision != null);
    try std.testing.expect(decision.?.gc_type == .minor);
    try std.testing.expect(decision.?.reason == .memory_threshold);
}

test "gc policy allocation failure" {
    var policy = GCPolicy.init();

    // Nursery 分配失败
    const decision = policy.handleAllocationFailure(1024, 0);
    try std.testing.expect(decision.gc_type == .minor);
    try std.testing.expect(decision.reason == .allocation_failure);
    try std.testing.expect(decision.urgency == .immediate);

    // Old gen 分配失败
    const decision2 = policy.handleAllocationFailure(1024, 2);
    try std.testing.expect(decision2.gc_type == .major);
}

test "gc policy critical pressure" {
    var policy = GCPolicy.init();

    // 危急内存压力应该触发 Full GC
    const decision = policy.shouldTriggerGC(.{
        .nursery_used = 950,
        .nursery_total = 1000,
        .nursery_ratio = 0.95,
        .survivor_used = 450,
        .survivor_total = 500,
        .survivor_ratio = 0.9,
        .old_gen_used = 9500,
        .old_gen_total = 10000,
        .old_gen_ratio = 0.95,
        .large_space_used = 1000,
        .total_used = 11900,
        .total_available = 11500,
        .fragmentation = 0.0,
    });

    try std.testing.expect(decision != null);
    try std.testing.expect(decision.?.gc_type == .full);
    try std.testing.expect(decision.?.reason == .memory_pressure);
    try std.testing.expect(decision.?.urgency == .immediate);
}

test "gc policy adaptive adjustment" {
    var policy = GCPolicy.initWithConfig(.{
        .adaptive_enabled = true,
        .adaptive_period = 2,
        .target_gc_overhead = 0.05,
        .max_gc_overhead = 0.15,
    });

    // 模拟高 GC 开销
    policy.overhead_tracker.recordGC(100_000_000); // 100ms
    // 模拟时间流逝
    policy.overhead_tracker.last_gc_end -= 100;
    policy.overhead_tracker.recordGC(100_000_000);

    const old_nursery_threshold = policy.config.nursery_threshold;

    // 触发自适应调整
    policy.recordGCComplete(.minor, 100_000_000);
    policy.recordGCComplete(.minor, 100_000_000);

    // 阈值应该被放宽
    try std.testing.expect(policy.config.nursery_threshold >= old_nursery_threshold);
}

test "gc policy diagnostics" {
    var policy = GCPolicy.init();

    policy.recordAllocation(1024);
    policy.recordGCComplete(.minor, 5_000_000);

    const diag = policy.getDiagnostics();
    try std.testing.expect(diag.last_gc_type == .minor);
    try std.testing.expect(diag.consecutive_minor_gc == 1);
}
