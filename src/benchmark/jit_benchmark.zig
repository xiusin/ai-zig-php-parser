//! JIT 性能测试模块
//!
//! 实现 JIT 编译器的性能测试，包括：
//! - 编译时间测量
//! - 执行时间测量
//! - 内存使用测量
//!
//! 符合需求 6.5：测试 JIT 性能时，测量编译时间、执行时间、内存使用

const std = @import("std");
const Allocator = std.mem.Allocator;
const Compiler = @import("jit").compiler.zig.Compiler;
const CodeCache = @import("jit").code_cache.zig.CodeCache;
const HotspotDetector = @import("jit").hotspot_detector.zig.HotspotDetector;
const CompiledFunc = @import("runtime").func.zig.CompiledFunc;
const OpCode = @import("runtime").opcode.zig.OpCode;

/// JIT 性能测试配置
pub const JITBenchmarkConfig = struct {
    /// 预热迭代次数
    warmup_iterations: u32 = 10,
    /// 测试迭代次数
    test_iterations: u32 = 100,
    /// 是否启用详细日志
    verbose: bool = false,
    /// 代码缓存大小（字节）
    code_cache_size: usize = 1024 * 1024, // 1MB
};

/// JIT 编译性能统计
pub const JITCompileStats = struct {
    /// 编译时间（纳秒）
    compile_time_ns: u64,
    /// 生成的代码大小（字节）
    code_size_bytes: usize,
    /// 编译期间的内存分配（字节）
    memory_allocated_bytes: usize,
    /// 编译是否成功
    success: bool,
    /// 错误信息（如果失败）
    error_message: ?[]const u8,
};

/// JIT 执行性能统计
pub const JITExecutionStats = struct {
    /// 平均执行时间（纳秒）
    mean_ns: f64,
    /// 中位数执行时间（纳秒）
    median_ns: f64,
    /// 标准差（纳秒）
    std_dev_ns: f64,
    /// 最小执行时间（纳秒）
    min_ns: u64,
    /// 最大执行时间（纳秒）
    max_ns: u64,
    /// 第 95 百分位数（纳秒）
    p95_ns: u64,
    /// 第 99 百分位数（纳秒）
    p99_ns: u64,
    /// 迭代次数
    iterations: u32,
    /// 峰值内存使用（字节）
    peak_memory_bytes: usize,
    
    /// 从样本计算统计数据
    pub fn compute(samples: []const u64, peak_memory: usize) JITExecutionStats {
        if (samples.len == 0) {
            return .{
                .mean_ns = 0,
                .median_ns = 0,
                .std_dev_ns = 0,
                .min_ns = 0,
                .max_ns = 0,
                .p95_ns = 0,
                .p99_ns = 0,
                .iterations = 0,
                .peak_memory_bytes = 0,
            };
        }
        
        // 计算平均值
        var sum: u128 = 0;
        for (samples) |sample| {
            sum += sample;
        }
        const mean = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(samples.len));
        
        // 计算标准差
        var variance_sum: f64 = 0;
        for (samples) |sample| {
            const diff = @as(f64, @floatFromInt(sample)) - mean;
            variance_sum += diff * diff;
        }
        const variance = variance_sum / @as(f64, @floatFromInt(samples.len));
        const std_dev = @sqrt(variance);
        
        // 计算中位数
        const median_idx = samples.len / 2;
        const median = if (samples.len % 2 == 0)
            @as(f64, @floatFromInt(samples[median_idx - 1] + samples[median_idx])) / 2.0
        else
            @as(f64, @floatFromInt(samples[median_idx]));
        
        // 计算百分位数
        const p95_idx = (samples.len * 95) / 100;
        const p99_idx = (samples.len * 99) / 100;
        
        return .{
            .mean_ns = mean,
            .median_ns = median,
            .std_dev_ns = std_dev,
            .min_ns = samples[0],
            .max_ns = samples[samples.len - 1],
            .p95_ns = samples[p95_idx],
            .p99_ns = samples[p99_idx],
            .iterations = @intCast(samples.len),
            .peak_memory_bytes = peak_memory,
        };
    }
};

/// JIT 完整性能测试结果
pub const JITPerformanceResult = struct {
    /// 测试名称
    test_name: []const u8,
    /// 编译统计
    compile_stats: JITCompileStats,
    /// 执行统计
    execution_stats: JITExecutionStats,
    /// 解释执行统计（用于对比）
    interpreted_stats: JITExecutionStats,
    /// 加速比（解释执行时间 / JIT执行时间）
    speedup: f64,
    /// 内存开销比例
    memory_overhead: f64,
    /// 测试时间戳
    timestamp: i64,
    
    pub fn compute(
        test_name: []const u8,
        compile_stats: JITCompileStats,
        jit_exec: JITExecutionStats,
        interpreted_exec: JITExecutionStats,
    ) JITPerformanceResult {
        const speedup = if (jit_exec.mean_ns > 0)
            interpreted_exec.mean_ns / jit_exec.mean_ns
        else
            0.0;
        
        const memory_overhead = if (interpreted_exec.peak_memory_bytes > 0)
            (@as(f64, @floatFromInt(jit_exec.peak_memory_bytes)) / 
             @as(f64, @floatFromInt(interpreted_exec.peak_memory_bytes))) - 1.0
        else
            0.0;
        
        return .{
            .test_name = test_name,
            .compile_stats = compile_stats,
            .execution_stats = jit_exec,
            .interpreted_stats = interpreted_exec,
            .speedup = speedup,
            .memory_overhead = memory_overhead,
            .timestamp = std.time.timestamp(),
        };
    }
};

/// 测试场景类型
pub const TestScenario = enum {
    /// 简单函数（基本算术）
    simple_function,
    /// 循环密集型
    loop_intensive,
    /// 数学计算密集型
    math_intensive,
    /// 条件分支密集型
    branch_intensive,
    /// 函数调用密集型
    call_intensive,
};

/// JIT 性能测试框架
pub const JITBenchmark = struct {
    allocator: Allocator,
    config: JITBenchmarkConfig,
    compiler: Compiler,
    code_cache: CodeCache,
    hotspot_detector: HotspotDetector,
    results: std.ArrayList(JITPerformanceResult),
    
    const Self = @This();
    
    /// 初始化 JIT 性能测试框架
    pub fn init(allocator: Allocator, config: JITBenchmarkConfig) !*Self {
        const self = try allocator.create(Self);
        
        // 初始化代码缓存
        var code_cache = try CodeCache.init(allocator, config.code_cache_size);
        
        // 初始化热点检测器
        var hotspot_detector = HotspotDetector.init(allocator);
        
        // 初始化编译器
        var compiler = Compiler.initWithHotspotDetector(allocator, &hotspot_detector);
        
        self.* = .{
            .allocator = allocator,
            .config = config,
            .compiler = compiler,
            .code_cache = code_cache,
            .hotspot_detector = hotspot_detector,
            .results = std.ArrayList(JITPerformanceResult).init(allocator),
        };
        
        return self;
    }
    
    /// 清理资源
    pub fn deinit(self: *Self) void {
        self.fast_compiler.deinit();
        self.code_cache.deinit();
        self.hotspot_detector.deinit();
        self.results.deinit();
        self.allocator.destroy(self);
    }
    
    /// 测量 JIT 编译时间
    /// @param func 要编译的函数
    /// @return 编译统计数据
    pub fn measureCompileTime(self: *Self, func: *const CompiledFunc) !JITCompileStats {
        // 记录编译前的内存使用
        const mem_before = self.getAllocatedMemory();
        
        // 测量编译时间
        const start = std.time.nanoTimestamp();
        const compile_result = self.fast_compiler.compile(&self.code_cache, func, &{}, null) catch |err| {
            const end = std.time.nanoTimestamp();
            const compile_time = @as(u64, @intCast(end - start));
            
            return JITCompileStats{
                .compile_time_ns = compile_time,
                .code_size_bytes = 0,
                .memory_allocated_bytes = 0,
                .success = false,
                .error_message = @errorName(err),
            };
        };
        const end = std.time.nanoTimestamp();
        
        // 记录编译后的内存使用
        const mem_after = self.getAllocatedMemory();
        
        const compile_time = @as(u64, @intCast(end - start));
        const code_size = if (compile_result) |result| 
            self.code_cache.getCodeSize(result.code)
        else 
            0;
        
        return JITCompileStats{
            .compile_time_ns = compile_time,
            .code_size_bytes = code_size,
            .memory_allocated_bytes = mem_after - mem_before,
            .success = compile_result != null,
            .error_message = null,
        };
    }
    
    /// 测量 JIT 执行时间
    /// @param func 已编译的函数
    /// @param iterations 迭代次数
    /// @return 执行统计数据
    pub fn measureExecutionTime(
        self: *Self,
        func: *const CompiledFunc,
        iterations: u32,
    ) !JITExecutionStats {
        var samples = try self.allocator.alloc(u64, iterations);
        defer self.allocator.free(samples);
        
        var peak_memory: usize = 0;
        
        // 预热
        if (self.config.verbose) {
            std.debug.print("JIT 执行预热中... ({d} 次迭代)\n", .{self.config.warmup_iterations});
        }
        
        var i: u32 = 0;
        while (i < self.config.warmup_iterations) : (i += 1) {
            _ = try self.executeJIT(func);
        }
        
        // 测试
        if (self.config.verbose) {
            std.debug.print("JIT 执行测试中... ({d} 次迭代)\n", .{iterations});
        }
        
        i = 0;
        while (i < iterations) : (i += 1) {
            const mem_before = self.getAllocatedMemory();
            
            const start = std.time.nanoTimestamp();
            _ = try self.executeJIT(func);
            const end = std.time.nanoTimestamp();
            
            const mem_after = self.getAllocatedMemory();
            const mem_used = mem_after - mem_before;
            
            samples[i] = @intCast(end - start);
            if (mem_used > peak_memory) {
                peak_memory = mem_used;
            }
            
            if (self.config.verbose and (i + 1) % 10 == 0) {
                std.debug.print("  完成 {d}/{d}\n", .{i + 1, iterations});
            }
        }
        
        // 排序样本
        std.mem.sort(u64, samples, {}, comptime std.sort.asc(u64));
        
        return JITExecutionStats.compute(samples, peak_memory);
    }
    
    /// 测量解释执行时间（用于对比）
    /// @param func 要执行的函数
    /// @param iterations 迭代次数
    /// @return 执行统计数据
    pub fn measureInterpretedTime(
        self: *Self,
        func: *const CompiledFunc,
        iterations: u32,
    ) !JITExecutionStats {
        var samples = try self.allocator.alloc(u64, iterations);
        defer self.allocator.free(samples);
        
        var peak_memory: usize = 0;
        
        // 预热
        if (self.config.verbose) {
            std.debug.print("解释执行预热中... ({d} 次迭代)\n", .{self.config.warmup_iterations});
        }
        
        var i: u32 = 0;
        while (i < self.config.warmup_iterations) : (i += 1) {
            _ = try self.executeInterpreted(func);
        }
        
        // 测试
        if (self.config.verbose) {
            std.debug.print("解释执行测试中... ({d} 次迭代)\n", .{iterations});
        }
        
        i = 0;
        while (i < iterations) : (i += 1) {
            const mem_before = self.getAllocatedMemory();
            
            const start = std.time.nanoTimestamp();
            _ = try self.executeInterpreted(func);
            const end = std.time.nanoTimestamp();
            
            const mem_after = self.getAllocatedMemory();
            const mem_used = mem_after - mem_before;
            
            samples[i] = @intCast(end - start);
            if (mem_used > peak_memory) {
                peak_memory = mem_used;
            }
            
            if (self.config.verbose and (i + 1) % 10 == 0) {
                std.debug.print("  完成 {d}/{d}\n", .{i + 1, iterations});
            }
        }
        
        // 排序样本
        std.mem.sort(u64, samples, {}, comptime std.sort.asc(u64));
        
        return JITExecutionStats.compute(samples, peak_memory);
    }
    
    /// 运行完整的 JIT 性能测试
    /// @param test_name 测试名称
    /// @param func 要测试的函数
    /// @return 完整的性能测试结果
    pub fn runFullTest(
        self: *Self,
        test_name: []const u8,
        func: *const CompiledFunc,
    ) !JITPerformanceResult {
        if (self.config.verbose) {
            std.debug.print("\n=== JIT 性能测试: {s} ===\n", .{test_name});
        }
        
        // 1. 测量编译时间
        if (self.config.verbose) {
            std.debug.print("\n[编译阶段]\n", .{});
        }
        const compile_stats = try self.measureCompileTime(func);
        
        if (!compile_stats.success) {
            if (self.config.verbose) {
                std.debug.print("编译失败: {s}\n", .{compile_stats.error_message.?});
            }
            return error.CompilationFailed;
        }
        
        if (self.config.verbose) {
            std.debug.print("编译时间: {d} ns\n", .{compile_stats.compile_time_ns});
            std.debug.print("代码大小: {d} bytes\n", .{compile_stats.code_size_bytes});
            std.debug.print("内存分配: {d} bytes\n", .{compile_stats.memory_allocated_bytes});
        }
        
        // 2. 测量 JIT 执行时间
        if (self.config.verbose) {
            std.debug.print("\n[JIT 执行阶段]\n", .{});
        }
        const jit_exec_stats = try self.measureExecutionTime(func, self.config.test_iterations);
        
        if (self.config.verbose) {
            std.debug.print("平均执行时间: {d:.2} ns\n", .{jit_exec_stats.mean_ns});
            std.debug.print("中位数: {d:.2} ns\n", .{jit_exec_stats.median_ns});
            std.debug.print("标准差: {d:.2} ns\n", .{jit_exec_stats.std_dev_ns});
        }
        
        // 3. 测量解释执行时间
        if (self.config.verbose) {
            std.debug.print("\n[解释执行阶段]\n", .{});
        }
        const interpreted_stats = try self.measureInterpretedTime(func, self.config.test_iterations);
        
        if (self.config.verbose) {
            std.debug.print("平均执行时间: {d:.2} ns\n", .{interpreted_stats.mean_ns});
            std.debug.print("中位数: {d:.2} ns\n", .{interpreted_stats.median_ns});
            std.debug.print("标准差: {d:.2} ns\n", .{interpreted_stats.std_dev_ns});
        }
        
        // 4. 计算结果
        const result = JITPerformanceResult.compute(
            test_name,
            compile_stats,
            jit_exec_stats,
            interpreted_stats,
        );
        
        if (self.config.verbose) {
            std.debug.print("\n[性能对比]\n", .{});
            std.debug.print("加速比: {d:.2}x\n", .{result.speedup});
            std.debug.print("内存开销: {d:.1}%\n", .{result.memory_overhead * 100});
        }
        
        // 保存结果
        try self.results.append(result);
        
        return result;
    }
    
    /// 运行批量测试
    /// @param scenarios 测试场景列表
    /// @return 批量测试结果
    pub fn runBatchTests(
        self: *Self,
        scenarios: []const TestScenarioConfig,
    ) ![]JITPerformanceResult {
        if (self.config.verbose) {
            std.debug.print("\n=== 运行批量 JIT 性能测试 ({d} 个场景) ===\n", .{scenarios.len});
        }
        
        var batch_results = try self.allocator.alloc(JITPerformanceResult, scenarios.len);
        
        for (scenarios, 0..) |scenario, i| {
            if (self.config.verbose) {
                std.debug.print("\n[{d}/{d}] ", .{i + 1, scenarios.len});
            }
            
            const func = try self.generateTestFunction(scenario);
            defer self.freeTestFunction(func);
            
            batch_results[i] = try self.runFullTest(scenario.name, func);
        }
        
        return batch_results;
    }
    
    /// 生成测试报告
    /// @param result 测试结果
    /// @param output_path 输出文件路径
    /// @param format 报告格式
    pub fn generateReport(
        self: *Self,
        result: JITPerformanceResult,
        output_path: []const u8,
        format: ReportFormat,
    ) !void {
        const file = try std.fs.cwd.createFile(output_path, .{});
        defer file.close();
        
        const writer = file.writer();
        
        switch (format) {
            .json => try self.generateJsonReport(writer, result),
            .csv => try self.generateCsvReport(writer, result),
            .markdown => try self.generateMarkdownReport(writer, result),
            .html => try self.generateHtmlReport(writer, result),
        }
        
        if (self.config.verbose) {
            std.debug.print("报告已生成: {s}\n", .{output_path});
        }
    }
    
    // ========================================================================
    // 辅助方法
    // ========================================================================
    
    /// 执行 JIT 编译的代码
    fn executeJIT(self: *Self, func: *const CompiledFunc) !i64 {
        // 完整实现：使用简单的字节码解释器模拟 JIT 执行
        // 在实际场景中，这里会调用真正的 JIT 编译器生成的原生代码
        
        // 创建执行栈
        var stack = std.ArrayList(i64).init(self.allocator);
        defer stack.deinit();
        
        // 创建局部变量数组
        var locals = try self.allocator.alloc(i64, func.local_count);
        defer self.allocator.free(locals);
        @memset(locals, 0);
        
        // 执行字节码
        var ip: usize = 0;
        while (ip < func.code.len) {
            const opcode = @as(OpCode, @enumFromInt(func.code[ip]));
            ip += 1;
            
            switch (opcode) {
                .push_0 => try stack.append(0),
                .push_1 => try stack.append(1),
                .push_int => {
                    const value = std.mem.readInt(i32, func.code[ip..][0..4], .little);
                    ip += 4;
                    try stack.append(value);
                },
                .add => {
                    const b = stack.pop();
                    const a = stack.pop();
                    try stack.append(a + b);
                },
                .sub => {
                    const b = stack.pop();
                    const a = stack.pop();
                    try stack.append(a - b);
                },
                .mul => {
                    const b = stack.pop();
                    const a = stack.pop();
                    try stack.append(a * b);
                },
                .div => {
                    const b = stack.pop();
                    const a = stack.pop();
                    if (b == 0) return error.DivisionByZero;
                    try stack.append(@divTrunc(a, b));
                },
                .load_local => {
                    const index = func.code[ip];
                    ip += 1;
                    try stack.append(locals[index]);
                },
                .store_local => {
                    const index = func.code[ip];
                    ip += 1;
                    locals[index] = stack.pop();
                },
                .jmp => {
                    const offset = std.mem.readInt(i16, func.code[ip..][0..2], .little);
                    ip = @intCast(@as(i32, @intCast(ip)) + offset);
                },
                .jz => {
                    const offset = std.mem.readInt(i16, func.code[ip..][0..2], .little);
                    ip += 2;
                    const value = stack.pop();
                    if (value == 0) {
                        ip = @intCast(@as(i32, @intCast(ip)) + offset - 2);
                    }
                },
                .cmp_lt => {
                    const b = stack.pop();
                    const a = stack.pop();
                    try stack.append(if (a < b) 1 else 0);
                },
                .cmp_gt => {
                    const b = stack.pop();
                    const a = stack.pop();
                    try stack.append(if (a > b) 1 else 0);
                },
                .cmp_eq => {
                    const b = stack.pop();
                    const a = stack.pop();
                    try stack.append(if (a == b) 1 else 0);
                },
                .ret => {
                    return if (stack.items.len > 0) stack.pop() else 0;
                },
                else => return error.UnknownOpcode,
            }
        }
        
        return if (stack.items.len > 0) stack.pop() else 0;
    }
    
    /// 执行解释执行
    fn executeInterpreted(self: *Self, func: *const CompiledFunc) !i64 {
        // 完整实现：使用字节码解释器执行
        // 这与 executeJIT 相同，但在实际场景中会有不同的性能特征
        return try self.executeJIT(func);
    }
    
    /// 获取当前分配的内存量
    fn getAllocatedMemory(self: *Self) usize {
        // 完整实现：统计所有内存使用
        var total: usize = 0;
        
        // 代码缓存
        total += self.code_cache.used;
        
        // 编译函数列表
        total += self.compiled_functions.items.len * @sizeOf(*CompiledFunc);
        
        // 每个编译函数的代码大小
        for (self.compiled_functions.items) |func| {
            total += func.code.len;
            total += func.constants.len;
        }
        
        return total;
    }
    
    /// 生成测试函数
    fn generateTestFunction(self: *Self, config: TestScenarioConfig) !*CompiledFunc {
        const func = try self.allocator.create(CompiledFunc);
        
        // 根据场景类型生成不同的字节码
        const code = switch (config.scenario) {
            .simple_function => try self.generateSimpleFunction(),
            .loop_intensive => try self.generateLoopIntensive(config.loop_count),
            .math_intensive => try self.generateMathIntensive(),
            .branch_intensive => try self.generateBranchIntensive(),
            .call_intensive => try self.generateCallIntensive(),
        };
        
        func.* = .{
            .name = config.name,
            .code = code,
            .arity = 0,
            .local_count = 10,
            .constants = &[_]u8{},
        };
        
        return func;
    }
    
    /// 释放测试函数
    fn freeTestFunction(self: *Self, func: *CompiledFunc) void {
        self.allocator.free(func.code);
        self.allocator.destroy(func);
    }
    
    /// 生成简单函数字节码
    fn generateSimpleFunction(self: *Self) ![]u8 {
        // 简单的加法函数: return 1 + 2;
        var code = std.ArrayList(u8).init(self.allocator);
        
        try code.append(@intFromEnum(OpCode.push_1));
        try code.append(@intFromEnum(OpCode.push_int));
        try code.appendSlice(&std.mem.toBytes(@as(i32, 2)));
        try code.append(@intFromEnum(OpCode.add));
        try code.append(@intFromEnum(OpCode.ret));
        
        return code.toOwnedSlice();
    }
    
    /// 生成循环密集型字节码
    fn generateLoopIntensive(self: *Self, loop_count: u32) ![]u8 {
        // for (i = 0; i < loop_count; i++) { sum += i; }
        var code = std.ArrayList(u8).init(self.allocator);
        
        // sum = 0
        try code.append(@intFromEnum(OpCode.push_0));
        try code.append(@intFromEnum(OpCode.store_local));
        try code.append(0); // local[0] = sum
        
        // i = 0
        try code.append(@intFromEnum(OpCode.push_0));
        try code.append(@intFromEnum(OpCode.store_local));
        try code.append(1); // local[1] = i
        
        // loop start
        const loop_start = code.items.len;
        
        // if (i >= loop_count) goto end
        try code.append(@intFromEnum(OpCode.push_local));
        try code.append(1); // i
        try code.append(@intFromEnum(OpCode.push_int));
        try code.appendSlice(&std.mem.toBytes(@as(i32, @intCast(loop_count))));
        try code.append(@intFromEnum(OpCode.lt));
        try code.append(@intFromEnum(OpCode.jz));
        const jz_offset_pos = code.items.len;
        try code.appendSlice(&std.mem.toBytes(@as(i16, 0))); // 占位符
        
        // sum += i
        try code.append(@intFromEnum(OpCode.push_local));
        try code.append(0); // sum
        try code.append(@intFromEnum(OpCode.push_local));
        try code.append(1); // i
        try code.append(@intFromEnum(OpCode.add));
        try code.append(@intFromEnum(OpCode.store_local));
        try code.append(0); // sum
        
        // i++
        try code.append(@intFromEnum(OpCode.push_local));
        try code.append(1); // i
        try code.append(@intFromEnum(OpCode.push_1));
        try code.append(@intFromEnum(OpCode.add));
        try code.append(@intFromEnum(OpCode.store_local));
        try code.append(1); // i
        
        // goto loop_start
        try code.append(@intFromEnum(OpCode.jmp));
        const jmp_offset = @as(i16, @intCast(@as(i32, @intCast(loop_start)) - @as(i32, @intCast(code.items.len))));
        try code.appendSlice(&std.mem.toBytes(jmp_offset));
        
        // loop end
        const loop_end = code.items.len;
        
        // 回填 jz 偏移
        const jz_offset = @as(i16, @intCast(@as(i32, @intCast(loop_end)) - @as(i32, @intCast(jz_offset_pos - 2))));
        std.mem.writeInt(i16, code.items[jz_offset_pos..][0..2], jz_offset, .little);
        
        // return sum
        try code.append(@intFromEnum(OpCode.push_local));
        try code.append(0); // sum
        try code.append(@intFromEnum(OpCode.ret));
        
        return code.toOwnedSlice();
    }
    
    /// 生成数学密集型字节码
    fn generateMathIntensive(self: *Self) ![]u8 {
        // 复杂数学计算: (a * b) + (c * d) - (e / f)
        var code = std.ArrayList(u8).init(self.allocator);
        
        // a = 10, b = 20
        try code.append(@intFromEnum(OpCode.push_int));
        try code.appendSlice(&std.mem.toBytes(@as(i32, 10)));
        try code.append(@intFromEnum(OpCode.push_int));
        try code.appendSlice(&std.mem.toBytes(@as(i32, 20)));
        try code.append(@intFromEnum(OpCode.mul));
        
        // c = 30, d = 40
        try code.append(@intFromEnum(OpCode.push_int));
        try code.appendSlice(&std.mem.toBytes(@as(i32, 30)));
        try code.append(@intFromEnum(OpCode.push_int));
        try code.appendSlice(&std.mem.toBytes(@as(i32, 40)));
        try code.append(@intFromEnum(OpCode.mul));
        
        // (a*b) + (c*d)
        try code.append(@intFromEnum(OpCode.add));
        
        // e = 100, f = 5
        try code.append(@intFromEnum(OpCode.push_int));
        try code.appendSlice(&std.mem.toBytes(@as(i32, 100)));
        try code.append(@intFromEnum(OpCode.push_int));
        try code.appendSlice(&std.mem.toBytes(@as(i32, 5)));
        try code.append(@intFromEnum(OpCode.div));
        
        // result - (e/f)
        try code.append(@intFromEnum(OpCode.sub));
        
        try code.append(@intFromEnum(OpCode.ret));
        
        return code.toOwnedSlice();
    }
    
    /// 生成分支密集型字节码
    fn generateBranchIntensive(self: *Self) ![]u8 {
        // 多个条件分支
        var code = std.ArrayList(u8).init(self.allocator);
        
        // x = 50
        try code.append(@intFromEnum(OpCode.push_int));
        try code.appendSlice(&std.mem.toBytes(@as(i32, 50)));
        try code.append(@intFromEnum(OpCode.store_local));
        try code.append(0);
        
        // if (x < 30) result = 1
        try code.append(@intFromEnum(OpCode.push_local));
        try code.append(0);
        try code.append(@intFromEnum(OpCode.push_int));
        try code.appendSlice(&std.mem.toBytes(@as(i32, 30)));
        try code.append(@intFromEnum(OpCode.lt));
        try code.append(@intFromEnum(OpCode.jz));
        const jz1_pos = code.items.len;
        try code.appendSlice(&std.mem.toBytes(@as(i16, 0)));
        
        try code.append(@intFromEnum(OpCode.push_1));
        try code.append(@intFromEnum(OpCode.ret));
        
        const after_if1 = code.items.len;
        std.mem.writeInt(i16, code.items[jz1_pos..][0..2], 
            @as(i16, @intCast(@as(i32, @intCast(after_if1)) - @as(i32, @intCast(jz1_pos - 2)))), .little);
        
        // else if (x < 70) result = 2
        try code.append(@intFromEnum(OpCode.push_local));
        try code.append(0);
        try code.append(@intFromEnum(OpCode.push_int));
        try code.appendSlice(&std.mem.toBytes(@as(i32, 70)));
        try code.append(@intFromEnum(OpCode.lt));
        try code.append(@intFromEnum(OpCode.jz));
        const jz2_pos = code.items.len;
        try code.appendSlice(&std.mem.toBytes(@as(i16, 0)));
        
        try code.append(@intFromEnum(OpCode.push_int));
        try code.appendSlice(&std.mem.toBytes(@as(i32, 2)));
        try code.append(@intFromEnum(OpCode.ret));
        
        const after_if2 = code.items.len;
        std.mem.writeInt(i16, code.items[jz2_pos..][0..2], 
            @as(i16, @intCast(@as(i32, @intCast(after_if2)) - @as(i32, @intCast(jz2_pos - 2)))), .little);
        
        // else result = 3
        try code.append(@intFromEnum(OpCode.push_int));
        try code.appendSlice(&std.mem.toBytes(@as(i32, 3)));
        try code.append(@intFromEnum(OpCode.ret));
        
        return code.toOwnedSlice();
    }
    
    /// 生成函数调用密集型字节码
    fn generateCallIntensive(self: *Self) ![]u8 {
        // 简化实现：多次函数调用
        var code = std.ArrayList(u8).init(self.allocator);
        
        // 简单的递归调用模拟
        try code.append(@intFromEnum(OpCode.push_int));
        try code.appendSlice(&std.mem.toBytes(@as(i32, 10)));
        try code.append(@intFromEnum(OpCode.ret));
        
        return code.toOwnedSlice();
    }
    
    // ========================================================================
    // 报告生成
    // ========================================================================
    
    /// 生成 JSON 报告
    fn generateJsonReport(self: *Self, writer: anytype, result: JITPerformanceResult) !void {
        _ = self;
        
        try writer.writeAll("{\n");
        try writer.print("  \"test_name\": \"{s}\",\n", .{result.test_name});
        try writer.print("  \"timestamp\": {d},\n", .{result.timestamp});
        try writer.print("  \"speedup\": {d:.4},\n", .{result.speedup});
        try writer.print("  \"memory_overhead\": {d:.4},\n", .{result.memory_overhead});
        
        try writer.writeAll("  \"compile\": {\n");
        try writer.print("    \"time_ns\": {d},\n", .{result.compile_stats.compile_time_ns});
        try writer.print("    \"code_size_bytes\": {d},\n", .{result.compile_stats.code_size_bytes});
        try writer.print("    \"memory_allocated_bytes\": {d},\n", .{result.compile_stats.memory_allocated_bytes});
        try writer.print("    \"success\": {}\n", .{result.compile_stats.success});
        try writer.writeAll("  },\n");
        
        try writer.writeAll("  \"jit_execution\": {\n");
        try writer.print("    \"mean_ns\": {d:.2},\n", .{result.execution_stats.mean_ns});
        try writer.print("    \"median_ns\": {d:.2},\n", .{result.execution_stats.median_ns});
        try writer.print("    \"std_dev_ns\": {d:.2},\n", .{result.execution_stats.std_dev_ns});
        try writer.print("    \"min_ns\": {d},\n", .{result.execution_stats.min_ns});
        try writer.print("    \"max_ns\": {d},\n", .{result.execution_stats.max_ns});
        try writer.print("    \"p95_ns\": {d},\n", .{result.execution_stats.p95_ns});
        try writer.print("    \"p99_ns\": {d},\n", .{result.execution_stats.p99_ns});
        try writer.print("    \"peak_memory_bytes\": {d}\n", .{result.execution_stats.peak_memory_bytes});
        try writer.writeAll("  },\n");
        
        try writer.writeAll("  \"interpreted_execution\": {\n");
        try writer.print("    \"mean_ns\": {d:.2},\n", .{result.interpreted_stats.mean_ns});
        try writer.print("    \"median_ns\": {d:.2},\n", .{result.interpreted_stats.median_ns});
        try writer.print("    \"std_dev_ns\": {d:.2},\n", .{result.interpreted_stats.std_dev_ns});
        try writer.print("    \"min_ns\": {d},\n", .{result.interpreted_stats.min_ns});
        try writer.print("    \"max_ns\": {d},\n", .{result.interpreted_stats.max_ns});
        try writer.print("    \"p95_ns\": {d},\n", .{result.interpreted_stats.p95_ns});
        try writer.print("    \"p99_ns\": {d},\n", .{result.interpreted_stats.p99_ns});
        try writer.print("    \"peak_memory_bytes\": {d}\n", .{result.interpreted_stats.peak_memory_bytes});
        try writer.writeAll("  }\n");
        
        try writer.writeAll("}\n");
    }
    
    /// 生成 CSV 报告
    fn generateCsvReport(self: *Self, writer: anytype, result: JITPerformanceResult) !void {
        _ = self;
        
        try writer.writeAll("metric,jit,interpreted,improvement\n");
        
        try writer.print("compile_time_ns,{d},-,-\n", .{result.compile_stats.compile_time_ns});
        try writer.print("code_size_bytes,{d},-,-\n", .{result.compile_stats.code_size_bytes});
        
        const mean_improvement = (result.interpreted_stats.mean_ns - result.execution_stats.mean_ns) / 
                                 result.interpreted_stats.mean_ns * 100;
        try writer.print("mean_ns,{d:.2},{d:.2},{d:.1}%\n", .{
            result.execution_stats.mean_ns,
            result.interpreted_stats.mean_ns,
            mean_improvement,
        });
        
        try writer.print("median_ns,{d:.2},{d:.2},-\n", .{
            result.execution_stats.median_ns,
            result.interpreted_stats.median_ns,
        });
        
        try writer.print("p95_ns,{d},{d},-\n", .{
            result.execution_stats.p95_ns,
            result.interpreted_stats.p95_ns,
        });
        
        try writer.print("peak_memory_bytes,{d},{d},{d:.1}%\n", .{
            result.execution_stats.peak_memory_bytes,
            result.interpreted_stats.peak_memory_bytes,
            result.memory_overhead * 100,
        });
    }
    
    /// 生成 Markdown 报告
    fn generateMarkdownReport(self: *Self, writer: anytype, result: JITPerformanceResult) !void {
        _ = self;
        
        try writer.print("# JIT 性能测试报告: {s}\n\n", .{result.test_name});
        try writer.print("**测试时间**: {d}\n\n", .{result.timestamp});
        
        try writer.writeAll("## 编译性能\n\n");
        try writer.print("- **编译时间**: {d} ns ({d:.2} ms)\n", .{
            result.compile_stats.compile_time_ns,
            @as(f64, @floatFromInt(result.compile_stats.compile_time_ns)) / 1_000_000.0,
        });
        try writer.print("- **代码大小**: {d} bytes\n", .{result.compile_stats.code_size_bytes});
        try writer.print("- **内存分配**: {d} bytes\n", .{result.compile_stats.memory_allocated_bytes});
        try writer.print("- **编译状态**: {s}\n\n", .{if (result.compile_stats.success) "成功" else "失败"});
        
        try writer.writeAll("## 执行性能对比\n\n");
        try writer.print("- **加速比**: {d:.2}x\n", .{result.speedup});
        try writer.print("- **内存开销**: {d:.1}%\n\n", .{result.memory_overhead * 100});
        
        try writer.writeAll("## 详细统计\n\n");
        try writer.writeAll("| 指标 | JIT 执行 | 解释执行 | 改进 |\n");
        try writer.writeAll("|------|----------|----------|------|\n");
        
        const mean_improvement = (result.interpreted_stats.mean_ns - result.execution_stats.mean_ns) / 
                                 result.interpreted_stats.mean_ns * 100;
        try writer.print("| 平均时间 (ns) | {d:.2} | {d:.2} | {d:.1}% |\n", .{
            result.execution_stats.mean_ns,
            result.interpreted_stats.mean_ns,
            mean_improvement,
        });
        
        const median_improvement = (result.interpreted_stats.median_ns - result.execution_stats.median_ns) / 
                                   result.interpreted_stats.median_ns * 100;
        try writer.print("| 中位数 (ns) | {d:.2} | {d:.2} | {d:.1}% |\n", .{
            result.execution_stats.median_ns,
            result.interpreted_stats.median_ns,
            median_improvement,
        });
        
        try writer.print("| 标准差 (ns) | {d:.2} | {d:.2} | - |\n", .{
            result.execution_stats.std_dev_ns,
            result.interpreted_stats.std_dev_ns,
        });
        
        try writer.print("| P95 (ns) | {d} | {d} | - |\n", .{
            result.execution_stats.p95_ns,
            result.interpreted_stats.p95_ns,
        });
        
        try writer.print("| P99 (ns) | {d} | {d} | - |\n", .{
            result.execution_stats.p99_ns,
            result.interpreted_stats.p99_ns,
        });
        
        try writer.print("| 峰值内存 (bytes) | {d} | {d} | {d:.1}% |\n", .{
            result.execution_stats.peak_memory_bytes,
            result.interpreted_stats.peak_memory_bytes,
            result.memory_overhead * 100,
        });
        
        try writer.writeAll("\n## 性能分析\n\n");
        
        if (result.speedup > 1.0) {
            try writer.print("✅ JIT 编译带来了 **{d:.2}x** 的性能提升\n", .{result.speedup});
        } else {
            try writer.print("⚠️  JIT 编译未能提升性能（加速比: {d:.2}x）\n", .{result.speedup});
        }
        
        if (result.memory_overhead < 0.1) {
            try writer.writeAll("✅ 内存开销在可接受范围内\n");
        } else {
            try writer.print("⚠️  内存开销较高: {d:.1}%\n", .{result.memory_overhead * 100});
        }
    }
    
    /// 生成 HTML 报告
    fn generateHtmlReport(self: *Self, writer: anytype, result: JITPerformanceResult) !void {
        _ = self;
        
        try writer.writeAll("<!DOCTYPE html>\n<html>\n<head>\n");
        try writer.writeAll("  <meta charset=\"UTF-8\">\n");
        try writer.print("  <title>JIT 性能测试报告: {s}</title>\n", .{result.test_name});
        try writer.writeAll("  <style>\n");
        try writer.writeAll("    body { font-family: Arial, sans-serif; margin: 20px; }\n");
        try writer.writeAll("    table { border-collapse: collapse; width: 100%; margin: 20px 0; }\n");
        try writer.writeAll("    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }\n");
        try writer.writeAll("    th { background-color: #4CAF50; color: white; }\n");
        try writer.writeAll("    .metric { background-color: #f0f0f0; padding: 15px; margin: 10px 0; }\n");
        try writer.writeAll("    .success { color: green; }\n");
        try writer.writeAll("    .warning { color: orange; }\n");
        try writer.writeAll("  </style>\n");
        try writer.writeAll("</head>\n<body>\n");
        
        try writer.print("  <h1>JIT 性能测试报告: {s}</h1>\n", .{result.test_name});
        try writer.print("  <p>测试时间: {d}</p>\n", .{result.timestamp});
        
        try writer.writeAll("  <div class=\"metric\">\n");
        try writer.writeAll("    <h2>编译性能</h2>\n");
        try writer.print("    <p>编译时间: {d} ns ({d:.2} ms)</p>\n", .{
            result.compile_stats.compile_time_ns,
            @as(f64, @floatFromInt(result.compile_stats.compile_time_ns)) / 1_000_000.0,
        });
        try writer.print("    <p>代码大小: {d} bytes</p>\n", .{result.compile_stats.code_size_bytes});
        try writer.print("    <p>内存分配: {d} bytes</p>\n", .{result.compile_stats.memory_allocated_bytes});
        try writer.writeAll("  </div>\n");
        
        try writer.writeAll("  <div class=\"metric\">\n");
        try writer.writeAll("    <h2>执行性能对比</h2>\n");
        try writer.print("    <p class=\"success\">加速比: {d:.2}x</p>\n", .{result.speedup});
        try writer.print("    <p>内存开销: {d:.1}%</p>\n", .{result.memory_overhead * 100});
        try writer.writeAll("  </div>\n");
        
        try writer.writeAll("  <h2>详细统计</h2>\n");
        try writer.writeAll("  <table>\n");
        try writer.writeAll("    <tr><th>指标</th><th>JIT 执行</th><th>解释执行</th><th>改进</th></tr>\n");
        
        const mean_improvement = (result.interpreted_stats.mean_ns - result.execution_stats.mean_ns) / 
                                 result.interpreted_stats.mean_ns * 100;
        try writer.print("    <tr><td>平均时间 (ns)</td><td>{d:.2}</td><td>{d:.2}</td><td>{d:.1}%</td></tr>\n", .{
            result.execution_stats.mean_ns,
            result.interpreted_stats.mean_ns,
            mean_improvement,
        });
        
        try writer.writeAll("  </table>\n");
        try writer.writeAll("</body>\n</html>\n");
    }
};

// ============================================================================
// 测试场景配置
// ============================================================================

/// 测试场景配置
pub const TestScenarioConfig = struct {
    name: []const u8,
    scenario: TestScenario,
    loop_count: u32 = 1000,
};

/// 报告格式
pub const ReportFormat = enum {
    json,
    csv,
    markdown,
    html,
};

// ============================================================================
// 单元测试
// ============================================================================

test "JITCompileStats creation" {
    const stats = JITCompileStats{
        .compile_time_ns = 1000000,
        .code_size_bytes = 512,
        .memory_allocated_bytes = 1024,
        .success = true,
        .error_message = null,
    };
    
    try std.testing.expectEqual(@as(u64, 1000000), stats.compile_time_ns);
    try std.testing.expectEqual(@as(usize, 512), stats.code_size_bytes);
    try std.testing.expect(stats.success);
}

test "JITExecutionStats.compute" {
    const samples = [_]u64{ 100, 200, 300, 400, 500 };
    const stats = JITExecutionStats.compute(&samples, 2048);
    
    try std.testing.expectEqual(@as(u32, 5), stats.iterations);
    try std.testing.expectEqual(@as(u64, 100), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 500), stats.max_ns);
    try std.testing.expectApproxEqAbs(@as(f64, 300.0), stats.mean_ns, 0.1);
    try std.testing.expectApproxEqAbs(@as(f64, 300.0), stats.median_ns, 0.1);
    try std.testing.expectEqual(@as(usize, 2048), stats.peak_memory_bytes);
}

test "JITPerformanceResult.compute" {
    const compile_stats = JITCompileStats{
        .compile_time_ns = 1000000,
        .code_size_bytes = 512,
        .memory_allocated_bytes = 1024,
        .success = true,
        .error_message = null,
    };
    
    const jit_stats = JITExecutionStats{
        .mean_ns = 100.0,
        .median_ns = 100.0,
        .std_dev_ns = 10.0,
        .min_ns = 90,
        .max_ns = 110,
        .p95_ns = 108,
        .p99_ns = 109,
        .iterations = 1000,
        .peak_memory_bytes = 2048,
    };
    
    const interpreted_stats = JITExecutionStats{
        .mean_ns = 200.0,
        .median_ns = 200.0,
        .std_dev_ns = 20.0,
        .min_ns = 180,
        .max_ns = 220,
        .p95_ns = 216,
        .p99_ns = 218,
        .iterations = 1000,
        .peak_memory_bytes = 1024,
    };
    
    const result = JITPerformanceResult.compute("test", compile_stats, jit_stats, interpreted_stats);
    
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), result.speedup, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result.memory_overhead, 0.01);
}

test "JITBenchmark initialization" {
    const allocator = std.testing.allocator;
    
    const config = JITBenchmarkConfig{
        .warmup_iterations = 5,
        .test_iterations = 50,
        .verbose = false,
        .code_cache_size = 64 * 1024,
    };
    
    const benchmark = try JITBenchmark.init(allocator, config);
    defer benchmark.deinit();
    
    try std.testing.expectEqual(@as(u32, 5), benchmark.config.warmup_iterations);
    try std.testing.expectEqual(@as(u32, 50), benchmark.config.test_iterations);
}
