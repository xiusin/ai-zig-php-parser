const std = @import("std");

/// 参数传递优化器 - 复杂类型指针传参优化
/// 
/// 设计目标：
/// 1. 类型大小分类 - 根据类型大小决定传递方式
/// 2. 传递方式决策 - 值传递/引用传递/COW传递
/// 3. 可变性分析 - 检测参数是否被修改
/// 4. 运行时大小检查 - 处理动态大小类型

/// 类型大小分类
pub const SizeCategory = enum {
    /// 小类型 (<=16字节) - 直接值传递
    small,
    /// 中等类型 (17-64字节) - 可选值传递或引用
    medium,
    /// 大类型 (65-256字节) - 引用传递
    large,
    /// 超大类型 (>256字节) - 必须引用传递
    huge,
    /// 动态大小 - 运行时决定
    dynamic,

    /// 根据字节大小获取分类
    pub fn fromSize(size: usize) SizeCategory {
        if (size <= 16) return .small;
        if (size <= 64) return .medium;
        if (size <= 256) return .large;
        return .huge;
    }
};

/// 参数传递方式
pub const PassingMethod = enum {
    /// 值传递 - 复制整个值
    by_value,
    /// 引用传递 - 传递指针，调用者可修改
    by_reference,
    /// 只读引用 - 传递指针，不可修改
    by_const_reference,
    /// Copy-on-Write - 共享直到修改
    by_cow,
    /// 移动语义 - 转移所有权
    by_move,
};


/// 参数修饰符
pub const ParameterModifier = packed struct {
    /// 是否为引用参数 (&$param)
    is_reference: bool = false,
    /// 是否为只读参数
    is_readonly: bool = false,
    /// 是否可变参数 (...$args)
    is_variadic: bool = false,
    /// 是否有默认值
    has_default: bool = false,
    /// 是否可为null
    is_nullable: bool = false,
    _padding: u3 = 0,
};

/// 类型传递信息
pub const TypePassingInfo = struct {
    /// 类型名称
    type_name: []const u8,
    /// 静态大小（如果已知）
    static_size: ?usize,
    /// 大小分类
    size_category: SizeCategory,
    /// 推荐的传递方式
    recommended_method: PassingMethod,
    /// 是否包含指针/引用
    contains_pointers: bool,
    /// 是否为不可变类型
    is_immutable: bool,
    /// 是否支持COW
    supports_cow: bool,

    /// 创建基本类型的传递信息
    pub fn forPrimitive(type_name: []const u8, size: usize) TypePassingInfo {
        return TypePassingInfo{
            .type_name = type_name,
            .static_size = size,
            .size_category = SizeCategory.fromSize(size),
            .recommended_method = .by_value,
            .contains_pointers = false,
            .is_immutable = true,
            .supports_cow = false,
        };
    }

    /// 创建字符串类型的传递信息
    pub fn forString() TypePassingInfo {
        return TypePassingInfo{
            .type_name = "string",
            .static_size = null, // 动态大小
            .size_category = .dynamic,
            .recommended_method = .by_cow,
            .contains_pointers = true,
            .is_immutable = false,
            .supports_cow = true,
        };
    }

    /// 创建数组类型的传递信息
    pub fn forArray() TypePassingInfo {
        return TypePassingInfo{
            .type_name = "array",
            .static_size = null, // 动态大小
            .size_category = .dynamic,
            .recommended_method = .by_cow,
            .contains_pointers = true,
            .is_immutable = false,
            .supports_cow = true,
        };
    }

    /// 创建对象类型的传递信息
    pub fn forObject(class_name: []const u8) TypePassingInfo {
        return TypePassingInfo{
            .type_name = class_name,
            .static_size = null,
            .size_category = .dynamic,
            .recommended_method = .by_reference,
            .contains_pointers = true,
            .is_immutable = false,
            .supports_cow = false,
        };
    }
};


/// 参数分析结果
pub const ParameterAnalysis = struct {
    /// 参数索引
    index: u16,
    /// 参数名称
    name: []const u8,
    /// 类型传递信息
    type_info: TypePassingInfo,
    /// 参数修饰符
    modifiers: ParameterModifier,
    /// 是否在函数体内被修改
    is_modified: bool,
    /// 是否逃逸（被存储到外部）
    escapes: bool,
    /// 最终决定的传递方式
    final_method: PassingMethod,

    /// 根据分析结果决定最终传递方式
    pub fn determinePassingMethod(self: *ParameterAnalysis) void {
        // 如果显式声明为引用，使用引用传递
        if (self.modifiers.is_reference) {
            self.final_method = .by_reference;
            return;
        }

        // 如果是只读且支持COW，使用COW
        if (self.modifiers.is_readonly and self.type_info.supports_cow) {
            self.final_method = .by_cow;
            return;
        }

        // 如果参数未被修改且支持COW，使用COW
        if (!self.is_modified and self.type_info.supports_cow) {
            self.final_method = .by_cow;
            return;
        }

        // 如果参数被修改但不逃逸，可以使用值传递（如果大小合适）
        if (self.is_modified and !self.escapes) {
            if (self.type_info.static_size) |size| {
                if (size <= 64) {
                    self.final_method = .by_value;
                    return;
                }
            }
        }

        // 默认使用推荐的传递方式
        self.final_method = self.type_info.recommended_method;
    }
};

/// 函数签名分析结果
pub const FunctionSignatureAnalysis = struct {
    /// 函数名称
    function_name: []const u8,
    /// 参数分析列表
    parameters: std.ArrayListUnmanaged(ParameterAnalysis),
    /// 返回值类型信息
    return_type_info: ?TypePassingInfo,
    /// 是否可以应用RVO
    can_apply_rvo: bool,
    /// 是否为纯函数（无副作用）
    is_pure: bool,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) FunctionSignatureAnalysis {
        _ = allocator;
        return FunctionSignatureAnalysis{
            .function_name = name,
            .parameters = .{},
            .return_type_info = null,
            .can_apply_rvo = false,
            .is_pure = true,
        };
    }

    pub fn deinit(self: *FunctionSignatureAnalysis, allocator: std.mem.Allocator) void {
        self.parameters.deinit(allocator);
    }

    pub fn addParameter(self: *FunctionSignatureAnalysis, allocator: std.mem.Allocator, param: ParameterAnalysis) !void {
        try self.parameters.append(allocator, param);
    }
};


/// 参数优化器
pub const ParameterOptimizer = struct {
    allocator: std.mem.Allocator,
    /// 类型信息缓存
    type_cache: std.StringHashMapUnmanaged(TypePassingInfo),
    /// 函数分析缓存
    function_cache: std.StringHashMapUnmanaged(FunctionSignatureAnalysis),
    /// 统计信息
    stats: OptimizationStats,

    pub const OptimizationStats = struct {
        /// 分析的函数数量
        functions_analyzed: u32 = 0,
        /// 分析的参数数量
        parameters_analyzed: u32 = 0,
        /// 优化为COW的参数数量
        cow_optimizations: u32 = 0,
        /// 优化为引用传递的参数数量
        ref_optimizations: u32 = 0,
        /// 应用RVO的函数数量
        rvo_applied: u32 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) ParameterOptimizer {
        var optimizer = ParameterOptimizer{
            .allocator = allocator,
            .type_cache = .{},
            .function_cache = .{},
            .stats = .{},
        };
        // 初始化内置类型缓存
        optimizer.initBuiltinTypes() catch {};
        return optimizer;
    }

    pub fn deinit(self: *ParameterOptimizer) void {
        self.type_cache.deinit(self.allocator);
        var iter = self.function_cache.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.function_cache.deinit(self.allocator);
    }

    /// 初始化内置类型的传递信息
    fn initBuiltinTypes(self: *ParameterOptimizer) !void {
        // 基本类型
        try self.type_cache.put(self.allocator, "int", TypePassingInfo.forPrimitive("int", 8));
        try self.type_cache.put(self.allocator, "float", TypePassingInfo.forPrimitive("float", 8));
        try self.type_cache.put(self.allocator, "bool", TypePassingInfo.forPrimitive("bool", 1));
        try self.type_cache.put(self.allocator, "null", TypePassingInfo.forPrimitive("null", 0));

        // 复杂类型
        try self.type_cache.put(self.allocator, "string", TypePassingInfo.forString());
        try self.type_cache.put(self.allocator, "array", TypePassingInfo.forArray());
    }

    /// 获取类型的传递信息
    pub fn getTypeInfo(self: *ParameterOptimizer, type_name: []const u8) TypePassingInfo {
        if (self.type_cache.get(type_name)) |info| {
            return info;
        }
        // 未知类型默认为对象
        return TypePassingInfo.forObject(type_name);
    }

    /// 注册自定义类型
    pub fn registerType(self: *ParameterOptimizer, type_name: []const u8, info: TypePassingInfo) !void {
        try self.type_cache.put(self.allocator, type_name, info);
    }


    /// 分析参数的可变性
    pub fn analyzeParameterMutability(
        self: *ParameterOptimizer,
        param_name: []const u8,
        function_body: ?*anyopaque, // AST节点
    ) MutabilityAnalysis {
        _ = self;
        _ = function_body;
        // 简化实现：遍历函数体AST，检查参数是否被修改
        // 完整实现需要：
        // 1. 检查赋值语句左侧
        // 2. 检查引用传递给其他函数
        // 3. 检查数组/对象属性修改
        return MutabilityAnalysis{
            .param_name = param_name,
            .is_modified = false, // 保守假设
            .modification_points = &[_]u32{},
            .escapes = false,
            .escape_reason = null,
        };
    }

    /// 分析函数签名
    pub fn analyzeFunction(
        self: *ParameterOptimizer,
        function_name: []const u8,
        param_names: []const []const u8,
        param_types: []const []const u8,
        param_modifiers: []const ParameterModifier,
        return_type: ?[]const u8,
    ) !FunctionSignatureAnalysis {
        var analysis = FunctionSignatureAnalysis.init(self.allocator, function_name);

        // 分析每个参数
        for (param_names, 0..) |name, i| {
            const type_name = if (i < param_types.len) param_types[i] else "mixed";
            const modifiers = if (i < param_modifiers.len) param_modifiers[i] else ParameterModifier{};

            const type_info = self.getTypeInfo(type_name);
            const mutability = self.analyzeParameterMutability(name, null);

            var param_analysis = ParameterAnalysis{
                .index = @intCast(i),
                .name = name,
                .type_info = type_info,
                .modifiers = modifiers,
                .is_modified = mutability.is_modified,
                .escapes = mutability.escapes,
                .final_method = .by_value,
            };

            // 决定最终传递方式
            param_analysis.determinePassingMethod();

            // 更新统计
            self.stats.parameters_analyzed += 1;
            switch (param_analysis.final_method) {
                .by_cow => self.stats.cow_optimizations += 1,
                .by_reference, .by_const_reference => self.stats.ref_optimizations += 1,
                else => {},
            }

            try analysis.addParameter(self.allocator, param_analysis);
        }

        // 分析返回值
        if (return_type) |rt| {
            analysis.return_type_info = self.getTypeInfo(rt);
            // 检查是否可以应用RVO
            if (analysis.return_type_info) |rti| {
                analysis.can_apply_rvo = rti.size_category != .small and
                    !rti.contains_pointers;
                if (analysis.can_apply_rvo) {
                    self.stats.rvo_applied += 1;
                }
            }
        }

        self.stats.functions_analyzed += 1;

        // 缓存分析结果
        try self.function_cache.put(self.allocator, function_name, analysis);

        return analysis;
    }

    /// 获取缓存的函数分析结果
    pub fn getCachedAnalysis(self: *ParameterOptimizer, function_name: []const u8) ?*FunctionSignatureAnalysis {
        return self.function_cache.getPtr(function_name);
    }

    /// 获取统计信息
    pub fn getStats(self: *const ParameterOptimizer) OptimizationStats {
        return self.stats;
    }

    /// 生成优化报告
    pub fn generateReport(self: *const ParameterOptimizer, allocator: std.mem.Allocator) ![]u8 {
        var report = std.ArrayListUnmanaged(u8){};

        try report.appendSlice(allocator, "=== Parameter Optimization Report ===\n");
        try std.fmt.format(report.writer(allocator), "Functions analyzed: {d}\n", .{self.stats.functions_analyzed});
        try std.fmt.format(report.writer(allocator), "Parameters analyzed: {d}\n", .{self.stats.parameters_analyzed});
        try std.fmt.format(report.writer(allocator), "COW optimizations: {d}\n", .{self.stats.cow_optimizations});
        try std.fmt.format(report.writer(allocator), "Reference optimizations: {d}\n", .{self.stats.ref_optimizations});
        try std.fmt.format(report.writer(allocator), "RVO applied: {d}\n", .{self.stats.rvo_applied});

        return report.toOwnedSlice(allocator);
    }
};


/// 可变性分析结果
pub const MutabilityAnalysis = struct {
    /// 参数名称
    param_name: []const u8,
    /// 是否被修改
    is_modified: bool,
    /// 修改点（字节码偏移）
    modification_points: []const u32,
    /// 是否逃逸
    escapes: bool,
    /// 逃逸原因
    escape_reason: ?EscapeReason,

    pub const EscapeReason = enum {
        /// 存储到全局变量
        stored_to_global,
        /// 存储到对象属性
        stored_to_property,
        /// 作为引用传递给其他函数
        passed_by_reference,
        /// 被闭包捕获
        captured_by_closure,
        /// 作为返回值
        returned,
    };
};

/// 运行时大小检查生成器
pub const RuntimeSizeChecker = struct {
    allocator: std.mem.Allocator,
    /// 大小阈值（字节）
    size_threshold: usize,

    pub fn init(allocator: std.mem.Allocator, threshold: usize) RuntimeSizeChecker {
        return RuntimeSizeChecker{
            .allocator = allocator,
            .size_threshold = threshold,
        };
    }

    /// 生成运行时大小检查代码
    /// 返回：(小于阈值时的代码, 大于等于阈值时的代码)
    pub fn generateSizeCheck(
        self: *RuntimeSizeChecker,
        param_name: []const u8,
    ) SizeCheckResult {
        return SizeCheckResult{
            .param_name = param_name,
            .threshold = self.size_threshold,
            .small_path_method = .by_value,
            .large_path_method = .by_cow,
        };
    }

    /// 估算动态类型的大小
    pub fn estimateSize(self: *RuntimeSizeChecker, type_tag: TypeTag) usize {
        _ = self;
        return switch (type_tag) {
            .null_type => 0,
            .bool_type => 1,
            .int_type => 8,
            .float_type => 8,
            .string_type => 64, // 平均估计
            .array_type => 256, // 平均估计
            .object_type => 128, // 平均估计
            else => 64,
        };
    }

    pub const TypeTag = enum {
        null_type,
        bool_type,
        int_type,
        float_type,
        string_type,
        array_type,
        object_type,
        struct_type,
        closure_type,
        resource_type,
    };
};

/// 大小检查结果
pub const SizeCheckResult = struct {
    param_name: []const u8,
    threshold: usize,
    small_path_method: PassingMethod,
    large_path_method: PassingMethod,
};


// ============================================================
// 单元测试
// ============================================================

test "SizeCategory fromSize" {
    try std.testing.expectEqual(SizeCategory.small, SizeCategory.fromSize(8));
    try std.testing.expectEqual(SizeCategory.small, SizeCategory.fromSize(16));
    try std.testing.expectEqual(SizeCategory.medium, SizeCategory.fromSize(32));
    try std.testing.expectEqual(SizeCategory.medium, SizeCategory.fromSize(64));
    try std.testing.expectEqual(SizeCategory.large, SizeCategory.fromSize(128));
    try std.testing.expectEqual(SizeCategory.large, SizeCategory.fromSize(256));
    try std.testing.expectEqual(SizeCategory.huge, SizeCategory.fromSize(512));
}

test "TypePassingInfo forPrimitive" {
    const int_info = TypePassingInfo.forPrimitive("int", 8);
    try std.testing.expectEqualStrings("int", int_info.type_name);
    try std.testing.expectEqual(@as(?usize, 8), int_info.static_size);
    try std.testing.expectEqual(SizeCategory.small, int_info.size_category);
    try std.testing.expectEqual(PassingMethod.by_value, int_info.recommended_method);
    try std.testing.expect(!int_info.contains_pointers);
    try std.testing.expect(int_info.is_immutable);
}

test "TypePassingInfo forString" {
    const str_info = TypePassingInfo.forString();
    try std.testing.expectEqualStrings("string", str_info.type_name);
    try std.testing.expectEqual(@as(?usize, null), str_info.static_size);
    try std.testing.expectEqual(SizeCategory.dynamic, str_info.size_category);
    try std.testing.expectEqual(PassingMethod.by_cow, str_info.recommended_method);
    try std.testing.expect(str_info.supports_cow);
}

test "TypePassingInfo forArray" {
    const arr_info = TypePassingInfo.forArray();
    try std.testing.expectEqualStrings("array", arr_info.type_name);
    try std.testing.expectEqual(SizeCategory.dynamic, arr_info.size_category);
    try std.testing.expectEqual(PassingMethod.by_cow, arr_info.recommended_method);
    try std.testing.expect(arr_info.supports_cow);
}

test "TypePassingInfo forObject" {
    const obj_info = TypePassingInfo.forObject("MyClass");
    try std.testing.expectEqualStrings("MyClass", obj_info.type_name);
    try std.testing.expectEqual(PassingMethod.by_reference, obj_info.recommended_method);
    try std.testing.expect(!obj_info.supports_cow);
}

test "ParameterAnalysis determinePassingMethod reference" {
    var analysis = ParameterAnalysis{
        .index = 0,
        .name = "param",
        .type_info = TypePassingInfo.forString(),
        .modifiers = ParameterModifier{ .is_reference = true },
        .is_modified = false,
        .escapes = false,
        .final_method = .by_value,
    };
    analysis.determinePassingMethod();
    try std.testing.expectEqual(PassingMethod.by_reference, analysis.final_method);
}

test "ParameterAnalysis determinePassingMethod readonly cow" {
    var analysis = ParameterAnalysis{
        .index = 0,
        .name = "param",
        .type_info = TypePassingInfo.forString(),
        .modifiers = ParameterModifier{ .is_readonly = true },
        .is_modified = false,
        .escapes = false,
        .final_method = .by_value,
    };
    analysis.determinePassingMethod();
    try std.testing.expectEqual(PassingMethod.by_cow, analysis.final_method);
}

test "ParameterAnalysis determinePassingMethod unmodified cow" {
    var analysis = ParameterAnalysis{
        .index = 0,
        .name = "param",
        .type_info = TypePassingInfo.forArray(),
        .modifiers = ParameterModifier{},
        .is_modified = false,
        .escapes = false,
        .final_method = .by_value,
    };
    analysis.determinePassingMethod();
    try std.testing.expectEqual(PassingMethod.by_cow, analysis.final_method);
}


test "ParameterOptimizer init and deinit" {
    const allocator = std.testing.allocator;
    var optimizer = ParameterOptimizer.init(allocator);
    defer optimizer.deinit();

    // 检查内置类型已初始化
    const int_info = optimizer.getTypeInfo("int");
    try std.testing.expectEqualStrings("int", int_info.type_name);

    const str_info = optimizer.getTypeInfo("string");
    try std.testing.expectEqualStrings("string", str_info.type_name);
}

test "ParameterOptimizer analyzeFunction" {
    const allocator = std.testing.allocator;
    var optimizer = ParameterOptimizer.init(allocator);
    defer optimizer.deinit();

    const param_names = [_][]const u8{ "name", "data", "count" };
    const param_types = [_][]const u8{ "string", "array", "int" };
    const param_modifiers = [_]ParameterModifier{
        ParameterModifier{},
        ParameterModifier{ .is_readonly = true },
        ParameterModifier{},
    };

    const analysis = try optimizer.analyzeFunction(
        "testFunc",
        &param_names,
        &param_types,
        &param_modifiers,
        "string",
    );
    // 注意：不要调用 analysis.deinit()，因为 optimizer.deinit() 会清理缓存

    try std.testing.expectEqual(@as(usize, 3), analysis.parameters.items.len);

    // 第一个参数：string，未修改，应该是COW
    try std.testing.expectEqual(PassingMethod.by_cow, analysis.parameters.items[0].final_method);

    // 第二个参数：array，readonly，应该是COW
    try std.testing.expectEqual(PassingMethod.by_cow, analysis.parameters.items[1].final_method);

    // 第三个参数：int，小类型，应该是值传递
    try std.testing.expectEqual(PassingMethod.by_value, analysis.parameters.items[2].final_method);
}

test "ParameterOptimizer stats" {
    const allocator = std.testing.allocator;
    var optimizer = ParameterOptimizer.init(allocator);
    defer optimizer.deinit();

    const param_names = [_][]const u8{"data"};
    const param_types = [_][]const u8{"array"};
    const param_modifiers = [_]ParameterModifier{ParameterModifier{}};

    _ = try optimizer.analyzeFunction(
        "func1",
        &param_names,
        &param_types,
        &param_modifiers,
        null,
    );
    // 注意：不要调用 analysis.deinit()，因为 optimizer.deinit() 会清理缓存

    const stats = optimizer.getStats();
    try std.testing.expectEqual(@as(u32, 1), stats.functions_analyzed);
    try std.testing.expectEqual(@as(u32, 1), stats.parameters_analyzed);
    try std.testing.expect(stats.cow_optimizations >= 1);
}

test "RuntimeSizeChecker estimateSize" {
    const allocator = std.testing.allocator;
    var checker = RuntimeSizeChecker.init(allocator, 64);

    try std.testing.expectEqual(@as(usize, 0), checker.estimateSize(.null_type));
    try std.testing.expectEqual(@as(usize, 1), checker.estimateSize(.bool_type));
    try std.testing.expectEqual(@as(usize, 8), checker.estimateSize(.int_type));
    try std.testing.expectEqual(@as(usize, 8), checker.estimateSize(.float_type));
    try std.testing.expectEqual(@as(usize, 64), checker.estimateSize(.string_type));
    try std.testing.expectEqual(@as(usize, 256), checker.estimateSize(.array_type));
}

test "RuntimeSizeChecker generateSizeCheck" {
    const allocator = std.testing.allocator;
    var checker = RuntimeSizeChecker.init(allocator, 64);

    const result = checker.generateSizeCheck("myParam");
    try std.testing.expectEqualStrings("myParam", result.param_name);
    try std.testing.expectEqual(@as(usize, 64), result.threshold);
    try std.testing.expectEqual(PassingMethod.by_value, result.small_path_method);
    try std.testing.expectEqual(PassingMethod.by_cow, result.large_path_method);
}

test "FunctionSignatureAnalysis init and deinit" {
    const allocator = std.testing.allocator;
    var analysis = FunctionSignatureAnalysis.init(allocator, "testFunc");
    defer analysis.deinit(allocator);

    try std.testing.expectEqualStrings("testFunc", analysis.function_name);
    try std.testing.expectEqual(@as(usize, 0), analysis.parameters.items.len);
    try std.testing.expect(!analysis.can_apply_rvo);
    try std.testing.expect(analysis.is_pure);
}
