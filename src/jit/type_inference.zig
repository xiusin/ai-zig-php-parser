/// 类型推断引擎
///
/// 基于运行时 profile 数据推断变量类型，为 JIT 编译器提供类型特化优化的依据。
///
/// @concurrency-model ISOLATED (单线程访问)
/// @ownership NON-OWNING (allocator)
/// @memory-safety 所有内存操作通过显式 allocator
const std = @import("std");

/// 类型信息
pub const TypeInfo = enum {
    unknown,
    int,
    float,
    bool,
    string,
    array,
    object,
    null_type,
    dynamic, // 混合类型

    /// 判断是否为基本类型
    pub fn isPrimitive(self: TypeInfo) bool {
        return switch (self) {
            .int, .float, .bool, .null_type => true,
            else => false,
        };
    }

    /// 判断是否为引用类型
    pub fn isReference(self: TypeInfo) bool {
        return switch (self) {
            .string, .array, .object => true,
            else => false,
        };
    }
};

/// 类型观察记录
/// @memory-layout 紧凑布局以优化缓存
pub const TypeObservation = struct {
    type_info: TypeInfo,
    count: u32,

    pub fn init(type_info: TypeInfo) TypeObservation {
        return .{
            .type_info = type_info,
            .count = 1,
        };
    }
};

/// 类型 Profile
/// 记录变量在运行时观察到的类型分布
pub const TypeProfile = struct {
    allocator: std.mem.Allocator,
    var_name: []const u8,
    observations: std.ArrayList(TypeObservation),
    total_observations: u32,
    confidence: f32,

    /// @pre allocator 必须有效
    /// @post 返回初始化的 TypeProfile
    pub fn init(allocator: std.mem.Allocator, var_name: []const u8) !TypeProfile {
        return TypeProfile{
            .allocator = allocator,
            .var_name = try allocator.dupe(u8, var_name),
            .observations = .{},
            .total_observations = 0,
            .confidence = 0.0,
        };
    }

    /// @pre self 必须已初始化
    /// @post 释放所有资源
    pub fn deinit(self: *TypeProfile) void {
        self.allocator.free(self.var_name);
        self.observations.deinit(self.allocator);
    }

    /// 记录类型观察
    /// @pre type_info 必须有效
    /// @post 更新观察统计
    pub fn recordObservation(self: *TypeProfile, type_info: TypeInfo) !void {
        // 查找是否已存在该类型的观察
        for (self.observations.items) |*obs| {
            if (obs.type_info == type_info) {
                obs.count += 1;
                self.total_observations += 1;
                try self.updateConfidence();
                return;
            }
        }

        // 新类型，添加观察记录
        try self.observations.append(self.allocator, TypeObservation.init(type_info));
        self.total_observations += 1;
        try self.updateConfidence();
    }

    /// 获取最可能的类型
    /// @post 返回出现频率最高的类型
    pub fn getMostLikelyType(self: *const TypeProfile) ?TypeInfo {
        if (self.observations.items.len == 0) {
            return null;
        }

        var max_count: u32 = 0;
        var most_likely: TypeInfo = .unknown;

        for (self.observations.items) |obs| {
            if (obs.count > max_count) {
                max_count = obs.count;
                most_likely = obs.type_info;
            }
        }

        return most_likely;
    }

    /// 获取类型分布
    /// @post 返回各类型的出现概率
    pub fn getTypeDistribution(self: *const TypeProfile, allocator: std.mem.Allocator) !std.AutoHashMap(TypeInfo, f32) {
        var distribution = std.AutoHashMap(TypeInfo, f32).init(allocator);

        if (self.total_observations == 0) {
            return distribution;
        }

        const total_f = @as(f32, @floatFromInt(self.total_observations));

        for (self.observations.items) |obs| {
            const probability = @as(f32, @floatFromInt(obs.count)) / total_f;
            try distribution.put(obs.type_info, probability);
        }

        return distribution;
    }

    /// 更新置信度
    /// 置信度 = 最常见类型的频率
    fn updateConfidence(self: *TypeProfile) !void {
        if (self.total_observations == 0) {
            self.confidence = 0.0;
            return;
        }

        var max_count: u32 = 0;
        for (self.observations.items) |obs| {
            if (obs.count > max_count) {
                max_count = obs.count;
            }
        }

        self.confidence = @as(f32, @floatFromInt(max_count)) / @as(f32, @floatFromInt(self.total_observations));
    }

    /// 判断是否为单态类型（只观察到一种类型）
    pub fn isMonomorphic(self: *const TypeProfile) bool {
        return self.observations.items.len == 1;
    }

    /// 判断是否为多态类型（观察到多种类型）
    pub fn isPolymorphic(self: *const TypeProfile) bool {
        return self.observations.items.len > 1;
    }
};

/// 推断规则
pub const InferenceRule = struct {
    name: []const u8,
    min_confidence: f32,
    min_observations: u32,

    /// 检查规则是否满足
    pub fn isSatisfied(self: *const InferenceRule, profile: *const TypeProfile) bool {
        return profile.confidence >= self.min_confidence and
            profile.total_observations >= self.min_observations;
    }
};

/// 类型推断引擎
/// @concurrency-model ISOLATED
/// @ownership NON-OWNING (allocator)
pub const TypeInference = struct {
    allocator: std.mem.Allocator,

    // 类型 profile 数据：变量名 -> TypeProfile
    type_profiles: std.StringHashMap(TypeProfile),

    // 推断规则
    inference_rules: []const InferenceRule,

    // 统计信息
    total_inferences: u64,
    successful_inferences: u64,

    /// 默认推断规则
    const DEFAULT_RULES = [_]InferenceRule{
        // 高置信度规则：95% 以上，至少 10 次观察
        .{
            .name = "high_confidence",
            .min_confidence = 0.95,
            .min_observations = 10,
        },
        // 中置信度规则：85% 以上，至少 20 次观察
        .{
            .name = "medium_confidence",
            .min_confidence = 0.85,
            .min_observations = 20,
        },
        // 低置信度规则：75% 以上，至少 50 次观察
        .{
            .name = "low_confidence",
            .min_confidence = 0.75,
            .min_observations = 50,
        },
    };

    /// @pre allocator 必须有效
    /// @post 返回初始化的 TypeInference 实例
    pub fn init(allocator: std.mem.Allocator) TypeInference {
        return TypeInference{
            .allocator = allocator,
            .type_profiles = std.StringHashMap(TypeProfile).init(allocator),
            .inference_rules = &DEFAULT_RULES,
            .total_inferences = 0,
            .successful_inferences = 0,
        };
    }

    /// @pre self 必须已初始化
    /// @post 释放所有资源
    pub fn deinit(self: *TypeInference) void {
        var iter = self.type_profiles.valueIterator();
        while (iter.next()) |profile| {
            profile.deinit();
        }
        self.type_profiles.deinit();
    }

    /// 记录变量类型观察
    /// @pre var_name 和 type_info 必须有效
    /// @post 更新对应变量的 type profile
    pub fn recordTypeObservation(self: *TypeInference, var_name: []const u8, type_info: TypeInfo) !void {
        // 获取或创建 profile
        const gop = try self.type_profiles.getOrPut(var_name);
        if (!gop.found_existing) {
            gop.value_ptr.* = try TypeProfile.init(self.allocator, var_name);
        }

        // 记录观察
        try gop.value_ptr.recordObservation(type_info);
    }

    /// 推断变量类型
    /// @pre var_name 必须有效
    /// @post 返回推断的类型信息，如果无法推断则返回 .dynamic
    pub fn inferType(self: *TypeInference, var_name: []const u8) TypeInfo {
        self.total_inferences += 1;

        const profile = self.type_profiles.get(var_name) orelse {
            // 没有 profile 数据，返回动态类型
            return .dynamic;
        };

        // 检查推断规则
        for (self.inference_rules) |rule| {
            if (rule.isSatisfied(&profile)) {
                // 规则满足，使用最可能的类型
                if (profile.getMostLikelyType()) |type_info| {
                    self.successful_inferences += 1;
                    return type_info;
                }
            }
        }

        // 所有规则都不满足，返回动态类型
        return .dynamic;
    }

    /// 推断函数参数类型
    /// @pre param_names 必须有效
    /// @post 返回推断的参数类型数组
    pub fn inferParameterTypes(self: *TypeInference, param_names: []const []const u8) ![]TypeInfo {
        var types: std.ArrayList(TypeInfo) = .{};
        errdefer types.deinit(self.allocator);

        for (param_names) |param_name| {
            const inferred_type = self.inferType(param_name);
            try types.append(self.allocator, inferred_type);
        }

        return types.toOwnedSlice(self.allocator);
    }

    /// 批量推断多个变量的类型
    /// @pre var_names 必须有效
    /// @post 返回变量名到类型的映射
    pub fn inferTypes(self: *TypeInference, var_names: []const []const u8) !std.StringHashMap(TypeInfo) {
        var result = std.StringHashMap(TypeInfo).init(self.allocator);
        errdefer result.deinit();

        for (var_names) |var_name| {
            const inferred_type = self.inferType(var_name);
            try result.put(var_name, inferred_type);
        }

        return result;
    }

    /// 获取推断准确率
    /// @post 返回成功推断的比例 (0.0 - 1.0)
    pub fn getAccuracy(self: *const TypeInference) f32 {
        if (self.total_inferences == 0) {
            return 0.0;
        }
        return @as(f32, @floatFromInt(self.successful_inferences)) /
            @as(f32, @floatFromInt(self.total_inferences));
    }

    /// 获取变量的 type profile
    /// @pre var_name 必须有效
    /// @post 返回对应的 TypeProfile，如果不存在则返回 null
    pub fn getTypeProfile(self: *const TypeInference, var_name: []const u8) ?*const TypeProfile {
        return self.type_profiles.getPtr(var_name);
    }

    /// 清除所有 profile 数据
    /// @post 所有 profile 数据被清除
    pub fn clearProfiles(self: *TypeInference) void {
        var iter = self.type_profiles.valueIterator();
        while (iter.next()) |profile| {
            profile.deinit();
        }
        self.type_profiles.clearRetainingCapacity();
        self.total_inferences = 0;
        self.successful_inferences = 0;
    }

    /// 打印统计信息
    pub fn printStats(self: *const TypeInference, debug_module: anytype) !void {
        _ = debug_module;
        std.debug.print("=== 类型推断引擎统计 ===\n", .{});
        std.debug.print("总推断次数: {d}\n", .{self.total_inferences});
        std.debug.print("成功推断次数: {d}\n", .{self.successful_inferences});
        std.debug.print("推断准确率: {d:.2}%\n", .{self.getAccuracy() * 100.0});
        std.debug.print("Profile 数量: {d}\n", .{self.type_profiles.count()});

        // 打印每个变量的 profile
        var iter = self.type_profiles.iterator();
        while (iter.next()) |entry| {
            const profile = entry.value_ptr;
            std.debug.print("\n变量: {s}\n", .{profile.var_name});
            std.debug.print("  总观察次数: {d}\n", .{profile.total_observations});
            std.debug.print("  置信度: {d:.2}%\n", .{profile.confidence * 100.0});
            std.debug.print("  最可能类型: {s}\n", .{@tagName(profile.getMostLikelyType() orelse .unknown)});
            std.debug.print("  类型分布:\n", .{});

            for (profile.observations.items) |obs| {
                const percentage = @as(f32, @floatFromInt(obs.count)) /
                    @as(f32, @floatFromInt(profile.total_observations)) * 100.0;
                std.debug.print("    {s}: {d} ({d:.2}%)\n", .{
                    @tagName(obs.type_info),
                    obs.count,
                    percentage,
                });
            }
        }
    }
};

// ============================================================================
// 测试
// ============================================================================

test "TypeInfo 基本功能" {
    const int_type = TypeInfo.int;
    try std.testing.expect(int_type.isPrimitive());
    try std.testing.expect(!int_type.isReference());

    const string_type = TypeInfo.string;
    try std.testing.expect(!string_type.isPrimitive());
    try std.testing.expect(string_type.isReference());
}

test "TypeProfile 初始化和清理" {
    const allocator = std.testing.allocator;

    var profile = try TypeProfile.init(allocator, "test_var");
    defer profile.deinit();

    try std.testing.expectEqualStrings("test_var", profile.var_name);
    try std.testing.expectEqual(@as(u32, 0), profile.total_observations);
    try std.testing.expectEqual(@as(f32, 0.0), profile.confidence);
}

test "TypeProfile 记录观察" {
    const allocator = std.testing.allocator;

    var profile = try TypeProfile.init(allocator, "x");
    defer profile.deinit();

    // 记录多次 int 类型观察
    try profile.recordObservation(.int);
    try profile.recordObservation(.int);
    try profile.recordObservation(.int);

    try std.testing.expectEqual(@as(u32, 3), profile.total_observations);
    try std.testing.expectEqual(@as(usize, 1), profile.observations.items.len);
    try std.testing.expectEqual(TypeInfo.int, profile.getMostLikelyType().?);
    try std.testing.expectEqual(@as(f32, 1.0), profile.confidence);
}

test "TypeProfile 多态类型" {
    const allocator = std.testing.allocator;

    var profile = try TypeProfile.init(allocator, "y");
    defer profile.deinit();

    // 记录混合类型
    try profile.recordObservation(.int);
    try profile.recordObservation(.int);
    try profile.recordObservation(.int);
    try profile.recordObservation(.float);
    try profile.recordObservation(.float);

    try std.testing.expectEqual(@as(u32, 5), profile.total_observations);
    try std.testing.expectEqual(@as(usize, 2), profile.observations.items.len);
    try std.testing.expectEqual(TypeInfo.int, profile.getMostLikelyType().?);
    try std.testing.expect(profile.confidence < 1.0);
    try std.testing.expect(profile.confidence >= 0.6);
    try std.testing.expect(profile.isPolymorphic());
}

test "TypeInference 初始化和清理" {
    const allocator = std.testing.allocator;

    var inference = TypeInference.init(allocator);
    defer inference.deinit();

    try std.testing.expectEqual(@as(usize, 0), inference.type_profiles.count());
    try std.testing.expectEqual(@as(u64, 0), inference.total_inferences);
}

test "TypeInference 记录和推断" {
    const allocator = std.testing.allocator;

    var inference = TypeInference.init(allocator);
    defer inference.deinit();

    // 记录足够的观察数据
    var i: usize = 0;
    while (i < 15) : (i += 1) {
        try inference.recordTypeObservation("x", .int);
    }

    // 推断类型
    const inferred = inference.inferType("x");
    try std.testing.expectEqual(TypeInfo.int, inferred);

    // 检查准确率
    const accuracy = inference.getAccuracy();
    try std.testing.expect(accuracy > 0.0);
}

test "TypeInference 推断准确率" {
    const allocator = std.testing.allocator;

    var inference = TypeInference.init(allocator);
    defer inference.deinit();

    // 记录高置信度数据
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        try inference.recordTypeObservation("a", .int);
    }

    // 记录低置信度数据
    i = 0;
    while (i < 5) : (i += 1) {
        try inference.recordTypeObservation("b", .int);
        try inference.recordTypeObservation("b", .float);
    }

    // 推断
    const type_a = inference.inferType("a");
    const type_b = inference.inferType("b");

    try std.testing.expectEqual(TypeInfo.int, type_a);
    try std.testing.expectEqual(TypeInfo.dynamic, type_b); // 置信度不够

    // 准确率应该是 50% (1/2)
    const accuracy = inference.getAccuracy();
    try std.testing.expect(accuracy >= 0.4 and accuracy <= 0.6);
}

test "TypeInference 批量推断" {
    const allocator = std.testing.allocator;

    var inference = TypeInference.init(allocator);
    defer inference.deinit();

    // 记录数据
    var i: usize = 0;
    while (i < 15) : (i += 1) {
        try inference.recordTypeObservation("x", .int);
        try inference.recordTypeObservation("y", .float);
        try inference.recordTypeObservation("z", .string);
    }

    // 批量推断
    const var_names = [_][]const u8{ "x", "y", "z" };
    const types = try inference.inferParameterTypes(&var_names);
    defer allocator.free(types);

    try std.testing.expectEqual(@as(usize, 3), types.len);
    try std.testing.expectEqual(TypeInfo.int, types[0]);
    try std.testing.expectEqual(TypeInfo.float, types[1]);
    try std.testing.expectEqual(TypeInfo.string, types[2]);
}
