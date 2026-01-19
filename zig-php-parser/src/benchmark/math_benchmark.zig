//! 数学运算性能测试
//!
//! 实现完整的数学运算性能测试，包括：
//! - 整数运算（加减乘除、位运算、模运算）
//! - 浮点运算（加减乘除、三角函数、指数对数）
//! - 数学函数（sqrt、pow、abs、round等）
//! - 复数运算（加减乘除、共轭、模）
//! - 矩阵运算（加减、乘法、转置、行列式）
//!
//! ## 需求
//! - 需求 6.2：测试数学运算时，覆盖整数、浮点、复数、矩阵等所有类型
//! - 每个测试执行 100,000 次迭代
//! - 与原生 PHP 进行性能对比
//! - 目标：整数运算达到原生 PHP 的 120%，浮点运算达到 110%
//!
//! ## 使用示例
//!
//! ```zig
//! var benchmark = try MathBenchmark.init(allocator);
//! defer benchmark.deinit();
//!
//! const result = try benchmark.runAllTests();
//! try benchmark.generateReport(result, "math_report.md");
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const framework = @import("framework.zig");

/// 数学运算测试配置
pub const MathBenchmarkConfig = struct {
    /// 迭代次数
    iterations: u32 = 100_000,
    /// 是否启用详细日志
    verbose: bool = false,
    /// 是否生成 PHP 测试脚本
    generate_php_scripts: bool = true,
    /// 测试脚本输出目录
    script_output_dir: []const u8 = "tests/benchmarks/math",
};

/// 整数运算测试结果
pub const IntegerOpResult = struct {
    test_name: []const u8,
    operations_per_second: f64,
    total_time_ns: u64,
    iterations: u32,
};

/// 浮点运算测试结果
pub const FloatOpResult = struct {
    test_name: []const u8,
    operations_per_second: f64,
    total_time_ns: u64,
    iterations: u32,
};

/// 数学函数测试结果
pub const MathFuncResult = struct {
    test_name: []const u8,
    operations_per_second: f64,
    total_time_ns: u64,
    iterations: u32,
};

/// 复数运算测试结果
pub const ComplexOpResult = struct {
    test_name: []const u8,
    operations_per_second: f64,
    total_time_ns: u64,
    iterations: u32,
};

/// 矩阵运算测试结果
pub const MatrixOpResult = struct {
    test_name: []const u8,
    operations_per_second: f64,
    total_time_ns: u64,
    iterations: u32,
};

/// 数学运算测试套件结果
pub const MathBenchmarkResult = struct {
    integer_results: []IntegerOpResult,
    float_results: []FloatOpResult,
    math_func_results: []MathFuncResult,
    complex_results: []ComplexOpResult,
    matrix_results: []MatrixOpResult,
    total_time_ns: u64,
    timestamp: i64,
};

/// 数学运算性能测试
/// @ownership NON-OWNING (allocator)
/// @thread-safety ISOLATED
pub const MathBenchmark = struct {
    allocator: Allocator,
    config: MathBenchmarkConfig,
    framework_instance: *framework.BenchmarkFramework,
    
    const Self = @This();
    
    /// 初始化测试
    /// @pre allocator 必须有效
    /// @post 返回初始化的测试实例
    pub fn init(allocator: Allocator, config: MathBenchmarkConfig) !*Self {
        const self = try allocator.create(Self);
        
        // 创建框架实例
        const framework_config = framework.BenchmarkConfig{
            .warmup_iterations = 1000,
            .test_iterations = config.iterations,
            .verbose = config.verbose,
        };
        
        self.* = .{
            .allocator = allocator,
            .config = config,
            .framework_instance = try framework.BenchmarkFramework.init(allocator, framework_config),
        };
        
        // 创建测试脚本目录
        if (config.generate_php_scripts) {
            std.fs.cwd().makePath(config.script_output_dir) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
        }
        
        return self;
    }
    
    /// 清理资源
    /// @pre self 必须已初始化
    /// @post 释放所有资源
    pub fn deinit(self: *Self) void {
        self.framework_instance.deinit();
        self.allocator.destroy(self);
    }
    
    // ========================================================================
    // 整数运算测试
    // ========================================================================
    
    /// 运行所有整数运算测试
    /// @post 返回整数运算测试结果
    pub fn runIntegerTests(self: *Self) ![]IntegerOpResult {
        if (self.config.verbose) {
            std.debug.print("\n=== 整数运算性能测试 ===\n", .{});
        }
        
        var results: std.ArrayList(IntegerOpResult) = .{};
        
        // 加法测试
        try results.append(self.allocator, try self.testIntegerAddition());
        
        // 减法测试
        try results.append(try self.testIntegerSubtraction());
        
        // 乘法测试
        try results.append(try self.testIntegerMultiplication());
        
        // 除法测试
        try results.append(try self.testIntegerDivision());
        
        // 模运算测试
        try results.append(try self.testIntegerModulo());
        
        // 位运算测试
        try results.append(try self.testIntegerBitwise());
        
        // 位移测试
        try results.append(try self.testIntegerShift());
        
        return results.toOwnedSlice();
    }
    
    /// 测试整数加法
    pub fn testIntegerAddition(self: *Self) !IntegerOpResult {
        const test_name = "integer_addition";
        
        if (self.config.generate_php_scripts) {
            try self.generateIntegerAdditionScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var sum: i64 = 0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            sum = sum +% @as(i64, @intCast(i));
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        // 防止编译器优化掉计算
        std.mem.doNotOptimizeAway(&sum);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return IntegerOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试整数减法
    fn testIntegerSubtraction(self: *Self) !IntegerOpResult {
        const test_name = "integer_subtraction";
        
        if (self.config.generate_php_scripts) {
            try self.generateIntegerSubtractionScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var diff: i64 = 1_000_000;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            diff = diff -% @as(i64, @intCast(i % 100));
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&diff);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return IntegerOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试整数乘法
    fn testIntegerMultiplication(self: *Self) !IntegerOpResult {
        const test_name = "integer_multiplication";
        
        if (self.config.generate_php_scripts) {
            try self.generateIntegerMultiplicationScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var product: i64 = 1;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            product = product *% @as(i64, @intCast((i % 100) + 1));
            if (product > 1_000_000) product = 1;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&product);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return IntegerOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试整数除法
    fn testIntegerDivision(self: *Self) !IntegerOpResult {
        const test_name = "integer_division";
        
        if (self.config.generate_php_scripts) {
            try self.generateIntegerDivisionScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var quotient: i64 = 1_000_000;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const divisor = @as(i64, @intCast((i % 99) + 1));
            quotient = @divTrunc(quotient, divisor);
            if (quotient == 0) quotient = 1_000_000;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&quotient);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return IntegerOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试整数模运算
    fn testIntegerModulo(self: *Self) !IntegerOpResult {
        const test_name = "integer_modulo";
        
        if (self.config.generate_php_scripts) {
            try self.generateIntegerModuloScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var remainder: i64 = 0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            remainder = @rem(@as(i64, @intCast(i)), 97);
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&remainder);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return IntegerOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试整数位运算
    fn testIntegerBitwise(self: *Self) !IntegerOpResult {
        const test_name = "integer_bitwise";
        
        if (self.config.generate_php_scripts) {
            try self.generateIntegerBitwiseScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result: i64 = 0xAAAAAAAA;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            result = result ^ @as(i64, @intCast(i));
            result = result & 0xFFFFFFFF;
            result = result | 0x12345678;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return IntegerOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试整数位移
    fn testIntegerShift(self: *Self) !IntegerOpResult {
        const test_name = "integer_shift";
        
        if (self.config.generate_php_scripts) {
            try self.generateIntegerShiftScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result: i64 = 1;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            result = result << @intCast(i % 8);
            result = result >> @intCast(i % 8);
            if (result == 0) result = 1;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return IntegerOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    // ========================================================================
    // 浮点运算测试
    // ========================================================================
    
    /// 运行所有浮点运算测试
    /// @post 返回浮点运算测试结果
    pub fn runFloatTests(self: *Self) ![]FloatOpResult {
        if (self.config.verbose) {
            std.debug.print("\n=== 浮点运算性能测试 ===\n", .{});
        }
        
        var results: std.ArrayList(FloatOpResult) = .{};
        results.allocator = self.allocator;
        
        // 加法测试
        try results.append(try self.testFloatAddition());
        
        // 减法测试
        try results.append(try self.testFloatSubtraction());
        
        // 乘法测试
        try results.append(try self.testFloatMultiplication());
        
        // 除法测试
        try results.append(try self.testFloatDivision());
        
        // 三角函数测试
        try results.append(try self.testFloatTrigonometric());
        
        // 指数对数测试
        try results.append(try self.testFloatExpLog());
        
        return results.toOwnedSlice();
    }
    
    /// 测试浮点加法
    pub fn testFloatAddition(self: *Self) !FloatOpResult {
        const test_name = "float_addition";
        
        if (self.config.generate_php_scripts) {
            try self.generateFloatAdditionScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var sum: f64 = 0.0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            sum += @as(f64, @floatFromInt(i)) * 0.1;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&sum);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return FloatOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试浮点减法
    fn testFloatSubtraction(self: *Self) !FloatOpResult {
        const test_name = "float_subtraction";
        
        if (self.config.generate_php_scripts) {
            try self.generateFloatSubtractionScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var diff: f64 = 1000000.0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            diff -= @as(f64, @floatFromInt(i % 100)) * 0.1;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&diff);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return FloatOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试浮点乘法
    fn testFloatMultiplication(self: *Self) !FloatOpResult {
        const test_name = "float_multiplication";
        
        if (self.config.generate_php_scripts) {
            try self.generateFloatMultiplicationScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var product: f64 = 1.0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            product *= 1.0001;
            if (product > 1000.0) product = 1.0;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&product);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return FloatOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试浮点除法
    fn testFloatDivision(self: *Self) !FloatOpResult {
        const test_name = "float_division";
        
        if (self.config.generate_php_scripts) {
            try self.generateFloatDivisionScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var quotient: f64 = 1000000.0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            quotient /= 1.0001;
            if (quotient < 1.0) quotient = 1000000.0;
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&quotient);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return FloatOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试三角函数
    fn testFloatTrigonometric(self: *Self) !FloatOpResult {
        const test_name = "float_trigonometric";
        
        if (self.config.generate_php_scripts) {
            try self.generateFloatTrigonometricScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result: f64 = 0.0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const angle = @as(f64, @floatFromInt(i)) * 0.001;
            result += @sin(angle) + @cos(angle) + @tan(angle);
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return FloatOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试指数对数
    fn testFloatExpLog(self: *Self) !FloatOpResult {
        const test_name = "float_exp_log";
        
        if (self.config.generate_php_scripts) {
            try self.generateFloatExpLogScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result: f64 = 0.0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const x = @as(f64, @floatFromInt((i % 1000) + 1)) * 0.01;
            result += @exp(x) + @log(x);
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return FloatOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }

    
    // ========================================================================
    // 数学函数测试
    // ========================================================================
    
    /// 运行所有数学函数测试
    /// @post 返回数学函数测试结果
    pub fn runMathFuncTests(self: *Self) ![]MathFuncResult {
        if (self.config.verbose) {
            std.debug.print("\n=== 数学函数性能测试 ===\n", .{});
        }
        
        var results: std.ArrayList(MathFuncResult) = .{};
        results.allocator = self.allocator;
        
        // sqrt 测试
        try results.append(try self.testMathSqrt());
        
        // pow 测试
        try results.append(try self.testMathPow());
        
        // abs 测试
        try results.append(try self.testMathAbs());
        
        // round 测试
        try results.append(try self.testMathRound());
        
        // floor/ceil 测试
        try results.append(try self.testMathFloorCeil());
        
        // min/max 测试
        try results.append(try self.testMathMinMax());
        
        return results.toOwnedSlice();
    }
    
    /// 测试 sqrt
    pub fn testMathSqrt(self: *Self) !MathFuncResult {
        const test_name = "math_sqrt";
        
        if (self.config.generate_php_scripts) {
            try self.generateMathSqrtScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result: f64 = 0.0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            result += @sqrt(@as(f64, @floatFromInt(i + 1)));
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return MathFuncResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试 pow
    fn testMathPow(self: *Self) !MathFuncResult {
        const test_name = "math_pow";
        
        if (self.config.generate_php_scripts) {
            try self.generateMathPowScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result: f64 = 0.0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const base = @as(f64, @floatFromInt((i % 10) + 1));
            result += std.math.pow(f64, base, 2.5);
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return MathFuncResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试 abs
    fn testMathAbs(self: *Self) !MathFuncResult {
        const test_name = "math_abs";
        
        if (self.config.generate_php_scripts) {
            try self.generateMathAbsScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result: f64 = 0.0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const val = @as(f64, @floatFromInt(@as(i64, @intCast(i)))) - 50000.0;
            result += @abs(val);
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return MathFuncResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试 round
    fn testMathRound(self: *Self) !MathFuncResult {
        const test_name = "math_round";
        
        if (self.config.generate_php_scripts) {
            try self.generateMathRoundScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result: f64 = 0.0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const val = @as(f64, @floatFromInt(i)) * 0.123456;
            result += @round(val);
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return MathFuncResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试 floor/ceil
    fn testMathFloorCeil(self: *Self) !MathFuncResult {
        const test_name = "math_floor_ceil";
        
        if (self.config.generate_php_scripts) {
            try self.generateMathFloorCeilScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result: f64 = 0.0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const val = @as(f64, @floatFromInt(i)) * 0.123456;
            result += @floor(val) + @ceil(val);
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return MathFuncResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试 min/max
    fn testMathMinMax(self: *Self) !MathFuncResult {
        const test_name = "math_min_max";
        
        if (self.config.generate_php_scripts) {
            try self.generateMathMinMaxScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result: f64 = 0.0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const a = @as(f64, @floatFromInt(i));
            const b = @as(f64, @floatFromInt((i + 1) % 1000));
            result += @min(a, b) + @max(a, b);
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return MathFuncResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    // ========================================================================
    // 复数运算测试
    // ========================================================================
    
    /// 复数类型
    const Complex = struct {
        real: f64,
        imag: f64,
        
        pub fn add(self: Complex, other: Complex) Complex {
            return .{
                .real = self.real + other.real,
                .imag = self.imag + other.imag,
            };
        }
        
        pub fn sub(self: Complex, other: Complex) Complex {
            return .{
                .real = self.real - other.real,
                .imag = self.imag - other.imag,
            };
        }
        
        pub fn mul(self: Complex, other: Complex) Complex {
            return .{
                .real = self.real * other.real - self.imag * other.imag,
                .imag = self.real * other.imag + self.imag * other.real,
            };
        }
        
        pub fn div(self: Complex, other: Complex) Complex {
            const denom = other.real * other.real + other.imag * other.imag;
            return .{
                .real = (self.real * other.real + self.imag * other.imag) / denom,
                .imag = (self.imag * other.real - self.real * other.imag) / denom,
            };
        }
        
        pub fn conjugate(self: Complex) Complex {
            return .{
                .real = self.real,
                .imag = -self.imag,
            };
        }
        
        pub fn magnitude(self: Complex) f64 {
            return @sqrt(self.real * self.real + self.imag * self.imag);
        }
    };
    
    /// 运行所有复数运算测试
    /// @post 返回复数运算测试结果
    pub fn runComplexTests(self: *Self) ![]ComplexOpResult {
        if (self.config.verbose) {
            std.debug.print("\n=== 复数运算性能测试 ===\n", .{});
        }
        
        var results: std.ArrayList(ComplexOpResult) = .{};
        results.allocator = self.allocator;
        
        // 加法测试
        try results.append(try self.testComplexAddition());
        
        // 减法测试
        try results.append(try self.testComplexSubtraction());
        
        // 乘法测试
        try results.append(try self.testComplexMultiplication());
        
        // 除法测试
        try results.append(try self.testComplexDivision());
        
        // 共轭测试
        try results.append(try self.testComplexConjugate());
        
        // 模测试
        try results.append(try self.testComplexMagnitude());
        
        return results.toOwnedSlice();
    }
    
    /// 测试复数加法
    pub fn testComplexAddition(self: *Self) !ComplexOpResult {
        const test_name = "complex_addition";
        
        if (self.config.generate_php_scripts) {
            try self.generateComplexAdditionScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result = Complex{ .real = 0.0, .imag = 0.0 };
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const c = Complex{
                .real = @as(f64, @floatFromInt(i)) * 0.1,
                .imag = @as(f64, @floatFromInt(i)) * 0.2,
            };
            result = result.add(c);
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return ComplexOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试复数减法
    fn testComplexSubtraction(self: *Self) !ComplexOpResult {
        const test_name = "complex_subtraction";
        
        if (self.config.generate_php_scripts) {
            try self.generateComplexSubtractionScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result = Complex{ .real = 1000000.0, .imag = 1000000.0 };
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const c = Complex{
                .real = @as(f64, @floatFromInt(i % 100)) * 0.1,
                .imag = @as(f64, @floatFromInt(i % 100)) * 0.2,
            };
            result = result.sub(c);
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return ComplexOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试复数乘法
    fn testComplexMultiplication(self: *Self) !ComplexOpResult {
        const test_name = "complex_multiplication";
        
        if (self.config.generate_php_scripts) {
            try self.generateComplexMultiplicationScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result = Complex{ .real = 1.0, .imag = 1.0 };
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const c = Complex{ .real = 1.0001, .imag = 0.0001 };
            result = result.mul(c);
            if (result.magnitude() > 1000.0) {
                result = Complex{ .real = 1.0, .imag = 1.0 };
            }
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return ComplexOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试复数除法
    fn testComplexDivision(self: *Self) !ComplexOpResult {
        const test_name = "complex_division";
        
        if (self.config.generate_php_scripts) {
            try self.generateComplexDivisionScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result = Complex{ .real = 1000000.0, .imag = 1000000.0 };
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const c = Complex{ .real = 1.0001, .imag = 0.0001 };
            result = result.div(c);
            if (result.magnitude() < 1.0) {
                result = Complex{ .real = 1000000.0, .imag = 1000000.0 };
            }
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return ComplexOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试复数共轭
    fn testComplexConjugate(self: *Self) !ComplexOpResult {
        const test_name = "complex_conjugate";
        
        if (self.config.generate_php_scripts) {
            try self.generateComplexConjugateScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result = Complex{ .real = 0.0, .imag = 0.0 };
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const c = Complex{
                .real = @as(f64, @floatFromInt(i)) * 0.1,
                .imag = @as(f64, @floatFromInt(i)) * 0.2,
            };
            result = c.conjugate();
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return ComplexOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试复数模
    fn testComplexMagnitude(self: *Self) !ComplexOpResult {
        const test_name = "complex_magnitude";
        
        if (self.config.generate_php_scripts) {
            try self.generateComplexMagnitudeScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result: f64 = 0.0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const c = Complex{
                .real = @as(f64, @floatFromInt(i)) * 0.1,
                .imag = @as(f64, @floatFromInt(i)) * 0.2,
            };
            result += c.magnitude();
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return ComplexOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }

    
    // ========================================================================
    // 矩阵运算测试
    // ========================================================================
    
    /// 3x3 矩阵类型
    const Matrix3x3 = struct {
        data: [9]f64,
        
        pub fn init(values: [9]f64) Matrix3x3 {
            return .{ .data = values };
        }
        
        pub fn add(self: Matrix3x3, other: Matrix3x3) Matrix3x3 {
            var result: [9]f64 = undefined;
            for (0..9) |i| {
                result[i] = self.data[i] + other.data[i];
            }
            return .{ .data = result };
        }
        
        pub fn sub(self: Matrix3x3, other: Matrix3x3) Matrix3x3 {
            var result: [9]f64 = undefined;
            for (0..9) |i| {
                result[i] = self.data[i] - other.data[i];
            }
            return .{ .data = result };
        }
        
        pub fn mul(self: Matrix3x3, other: Matrix3x3) Matrix3x3 {
            var result: [9]f64 = undefined;
            for (0..3) |i| {
                for (0..3) |j| {
                    var sum: f64 = 0.0;
                    for (0..3) |k| {
                        sum += self.data[i * 3 + k] * other.data[k * 3 + j];
                    }
                    result[i * 3 + j] = sum;
                }
            }
            return .{ .data = result };
        }
        
        pub fn transpose(self: Matrix3x3) Matrix3x3 {
            var result: [9]f64 = undefined;
            for (0..3) |i| {
                for (0..3) |j| {
                    result[j * 3 + i] = self.data[i * 3 + j];
                }
            }
            return .{ .data = result };
        }
        
        pub fn determinant(self: Matrix3x3) f64 {
            const a = self.data[0];
            const b = self.data[1];
            const c = self.data[2];
            const d = self.data[3];
            const e = self.data[4];
            const f = self.data[5];
            const g = self.data[6];
            const h = self.data[7];
            const i = self.data[8];
            
            return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
        }
    };
    
    /// 运行所有矩阵运算测试
    /// @post 返回矩阵运算测试结果
    pub fn runMatrixTests(self: *Self) ![]MatrixOpResult {
        if (self.config.verbose) {
            std.debug.print("\n=== 矩阵运算性能测试 ===\n", .{});
        }
        
        var results: std.ArrayList(MatrixOpResult) = .{};
        results.allocator = self.allocator;
        
        // 加法测试
        try results.append(try self.testMatrixAddition());
        
        // 减法测试
        try results.append(try self.testMatrixSubtraction());
        
        // 乘法测试
        try results.append(try self.testMatrixMultiplication());
        
        // 转置测试
        try results.append(try self.testMatrixTranspose());
        
        // 行列式测试
        try results.append(try self.testMatrixDeterminant());
        
        return results.toOwnedSlice();
    }
    
    /// 测试矩阵加法
    pub fn testMatrixAddition(self: *Self) !MatrixOpResult {
        const test_name = "matrix_addition";
        
        if (self.config.generate_php_scripts) {
            try self.generateMatrixAdditionScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result = Matrix3x3.init([_]f64{0} ** 9);
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const m = Matrix3x3.init([_]f64{
                @as(f64, @floatFromInt(i % 10)), 1.0, 2.0,
                3.0, 4.0, 5.0,
                6.0, 7.0, 8.0,
            });
            result = result.add(m);
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return MatrixOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试矩阵减法
    fn testMatrixSubtraction(self: *Self) !MatrixOpResult {
        const test_name = "matrix_subtraction";
        
        if (self.config.generate_php_scripts) {
            try self.generateMatrixSubtractionScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result = Matrix3x3.init([_]f64{1000000} ** 9);
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const m = Matrix3x3.init([_]f64{
                @as(f64, @floatFromInt(i % 10)), 0.1, 0.2,
                0.3, 0.4, 0.5,
                0.6, 0.7, 0.8,
            });
            result = result.sub(m);
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return MatrixOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试矩阵乘法
    fn testMatrixMultiplication(self: *Self) !MatrixOpResult {
        const test_name = "matrix_multiplication";
        
        if (self.config.generate_php_scripts) {
            try self.generateMatrixMultiplicationScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result = Matrix3x3.init([_]f64{
            1.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            0.0, 0.0, 1.0,
        });
        
        const m = Matrix3x3.init([_]f64{
            1.001, 0.0, 0.0,
            0.0, 1.001, 0.0,
            0.0, 0.0, 1.001,
        });
        
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            result = result.mul(m);
            if (result.data[0] > 1000.0) {
                result = Matrix3x3.init([_]f64{
                    1.0, 0.0, 0.0,
                    0.0, 1.0, 0.0,
                    0.0, 0.0, 1.0,
                });
            }
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return MatrixOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试矩阵转置
    fn testMatrixTranspose(self: *Self) !MatrixOpResult {
        const test_name = "matrix_transpose";
        
        if (self.config.generate_php_scripts) {
            try self.generateMatrixTransposeScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result = Matrix3x3.init([_]f64{0} ** 9);
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const m = Matrix3x3.init([_]f64{
                @as(f64, @floatFromInt(i % 10)), 1.0, 2.0,
                3.0, 4.0, 5.0,
                6.0, 7.0, 8.0,
            });
            result = m.transpose();
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return MatrixOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    /// 测试矩阵行列式
    fn testMatrixDeterminant(self: *Self) !MatrixOpResult {
        const test_name = "matrix_determinant";
        
        if (self.config.generate_php_scripts) {
            try self.generateMatrixDeterminantScript();
        }
        
        const start = std.time.nanoTimestamp();
        
        var result: f64 = 0.0;
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            const m = Matrix3x3.init([_]f64{
                @as(f64, @floatFromInt((i % 10) + 1)), 2.0, 3.0,
                4.0, 5.0, 6.0,
                7.0, 8.0, 9.0,
            });
            result += m.determinant();
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        
        std.mem.doNotOptimizeAway(&result);
        
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{test_name, ops_per_sec / 1_000_000.0});
        }
        
        return MatrixOpResult{
            .test_name = test_name,
            .operations_per_second = ops_per_sec,
            .total_time_ns = total_time,
            .iterations = self.config.iterations,
        };
    }
    
    // ========================================================================
    // 运行所有测试
    // ========================================================================
    
    /// 运行所有数学运算测试
    /// @post 返回完整的测试结果
    pub fn runAllTests(self: *Self) !MathBenchmarkResult {
        if (self.config.verbose) {
            std.debug.print("\n╔════════════════════════════════════════╗\n", .{});
            std.debug.print("║  数学运算性能测试套件                  ║\n", .{});
            std.debug.print("║  迭代次数: {d:>10}                 ║\n", .{self.config.iterations});
            std.debug.print("╚════════════════════════════════════════╝\n", .{});
        }
        
        const start_time = std.time.nanoTimestamp();
        
        // 运行所有测试
        const integer_results = try self.runIntegerTests();
        const float_results = try self.runFloatTests();
        const math_func_results = try self.runMathFuncTests();
        const complex_results = try self.runComplexTests();
        const matrix_results = try self.runMatrixTests();
        
        const end_time = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end_time - start_time));
        
        if (self.config.verbose) {
            std.debug.print("\n总测试时间: {d:.2} 秒\n", .{
                @as(f64, @floatFromInt(total_time)) / 1_000_000_000.0
            });
        }
        
        return MathBenchmarkResult{
            .integer_results = integer_results,
            .float_results = float_results,
            .math_func_results = math_func_results,
            .complex_results = complex_results,
            .matrix_results = matrix_results,
            .total_time_ns = total_time,
            .timestamp = std.time.timestamp(),
        };
    }
    
    // ========================================================================
    // 报告生成
    // ========================================================================
    
    /// 生成 Markdown 报告
    /// @param result 测试结果
    /// @param output_path 输出文件路径
    pub fn generateReport(self: *Self, result: MathBenchmarkResult, output_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();
        
        const writer = file.writer();
        
        try writer.writeAll("# 数学运算性能测试报告\n\n");
        try writer.print("**测试时间**: {d}\n\n", .{result.timestamp});
        try writer.print("**总测试时间**: {d:.2} 秒\n\n", .{
            @as(f64, @floatFromInt(result.total_time_ns)) / 1_000_000_000.0
        });
        try writer.print("**迭代次数**: {d}\n\n", .{self.config.iterations});
        
        // 整数运算结果
        try writer.writeAll("## 整数运算\n\n");
        try writer.writeAll("| 测试名称 | 操作数/秒 (M ops/s) | 总时间 (ms) |\n");
        try writer.writeAll("|----------|---------------------|-------------|\n");
        for (result.integer_results) |r| {
            try writer.print("| {s} | {d:.2} | {d:.2} |\n", .{
                r.test_name,
                r.operations_per_second / 1_000_000.0,
                @as(f64, @floatFromInt(r.total_time_ns)) / 1_000_000.0,
            });
        }
        try writer.writeAll("\n");
        
        // 浮点运算结果
        try writer.writeAll("## 浮点运算\n\n");
        try writer.writeAll("| 测试名称 | 操作数/秒 (M ops/s) | 总时间 (ms) |\n");
        try writer.writeAll("|----------|---------------------|-------------|\n");
        for (result.float_results) |r| {
            try writer.print("| {s} | {d:.2} | {d:.2} |\n", .{
                r.test_name,
                r.operations_per_second / 1_000_000.0,
                @as(f64, @floatFromInt(r.total_time_ns)) / 1_000_000.0,
            });
        }
        try writer.writeAll("\n");
        
        // 数学函数结果
        try writer.writeAll("## 数学函数\n\n");
        try writer.writeAll("| 测试名称 | 操作数/秒 (M ops/s) | 总时间 (ms) |\n");
        try writer.writeAll("|----------|---------------------|-------------|\n");
        for (result.math_func_results) |r| {
            try writer.print("| {s} | {d:.2} | {d:.2} |\n", .{
                r.test_name,
                r.operations_per_second / 1_000_000.0,
                @as(f64, @floatFromInt(r.total_time_ns)) / 1_000_000.0,
            });
        }
        try writer.writeAll("\n");
        
        // 复数运算结果
        try writer.writeAll("## 复数运算\n\n");
        try writer.writeAll("| 测试名称 | 操作数/秒 (M ops/s) | 总时间 (ms) |\n");
        try writer.writeAll("|----------|---------------------|-------------|\n");
        for (result.complex_results) |r| {
            try writer.print("| {s} | {d:.2} | {d:.2} |\n", .{
                r.test_name,
                r.operations_per_second / 1_000_000.0,
                @as(f64, @floatFromInt(r.total_time_ns)) / 1_000_000.0,
            });
        }
        try writer.writeAll("\n");
        
        // 矩阵运算结果
        try writer.writeAll("## 矩阵运算\n\n");
        try writer.writeAll("| 测试名称 | 操作数/秒 (M ops/s) | 总时间 (ms) |\n");
        try writer.writeAll("|----------|---------------------|-------------|\n");
        for (result.matrix_results) |r| {
            try writer.print("| {s} | {d:.2} | {d:.2} |\n", .{
                r.test_name,
                r.operations_per_second / 1_000_000.0,
                @as(f64, @floatFromInt(r.total_time_ns)) / 1_000_000.0,
            });
        }
        try writer.writeAll("\n");
        
        if (self.config.verbose) {
            std.debug.print("报告已生成: {s}\n", .{output_path});
        }
    }
    
    // ========================================================================
    // PHP 脚本生成函数（存根）
    // ========================================================================
    
    // 这些函数用于生成对应的 PHP 测试脚本
    // 实际实现在 math_benchmark_stubs.zig 中
    
    fn generateIntegerAdditionScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateIntegerSubtractionScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateIntegerMultiplicationScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateIntegerDivisionScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateIntegerModuloScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateIntegerBitwiseScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateIntegerShiftScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateFloatAdditionScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateFloatSubtractionScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateFloatMultiplicationScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateFloatDivisionScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateFloatTrigonometricScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateFloatExpLogScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateMathSqrtScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateMathPowScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateMathAbsScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateMathRoundScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateMathFloorCeilScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateMathMinMaxScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateComplexAdditionScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateComplexSubtractionScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateComplexMultiplicationScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateComplexDivisionScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateComplexConjugateScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateComplexMagnitudeScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateMatrixAdditionScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateMatrixSubtractionScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateMatrixMultiplicationScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateMatrixTransposeScript(self: *Self) !void {
        _ = self;
    }
    
    fn generateMatrixDeterminantScript(self: *Self) !void {
        _ = self;
    }
};
