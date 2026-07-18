//! AOT 编译器性能测试框架
//!
//! 提供 AOT 编译器的完整性能测试功能，包括：
//! - 编译时间测量
//! - 可执行文件大小测量
//! - 启动时间测量
//! - 执行时间测量
//!
//! ## 功能特性
//! - 自动化测试执行
//! - 多次迭代和预热支持
//! - 统计分析（平均值、中位数、标准差）
//! - 多格式报告导出（JSON、CSV、Markdown）
//! - 与原生 PHP 性能对比
//! - 性能回归检测
//!
//! ## 使用示例
//!
//! ```zig
//! var framework = try AOTBenchmarkFramework.init(allocator, .{
//!     .warmup_iterations = 10,
//!     .test_iterations = 100,
//!     .timeout_ms = 60000,
//! });
//! defer framework.deinit();
//!
//! const result = try framework.runFullBenchmark("test.php");
//! try framework.generateReport(result, "aot_report.md", .markdown);
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;

/// 0.16 兼容：获取 Io 实例
inline fn getIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

/// 0.16 兼容：获取当前工作目录
inline fn getCwd() std.Io.Dir {
    return std.Io.Dir.cwd();
}

/// 0.16 兼容：获取毫秒时间戳（替代 std.time.milliTimestamp）
inline fn milliTimestamp() i64 {
    return std.Io.Timestamp.now(getIo(), .real).toMilliseconds();
}

/// 0.16 兼容：获取微秒时间戳（替代 std.time.microTimestamp）
inline fn microTimestamp() i64 {
    const ts = std.Io.Timestamp.now(getIo(), .real);
    return @intCast(@divTrunc(ts.nanoseconds, 1000));
}

/// 0.16 兼容：获取秒级时间戳（替代 std.time.timestamp）
inline fn unixTimestamp() i64 {
    const ts = std.Io.Timestamp.now(getIo(), .real);
    return @intCast(@divTrunc(ts.nanoseconds, std.time.ns_per_s));
}

/// 0.16 兼容：获取纳秒时间戳（替代 std.time.nanoTimestamp）
inline fn nanoTimestamp() i128 {
    return @intCast(std.Io.Timestamp.now(getIo(), .real).nanoseconds);
}

/// 0.16 兼容：运行命令（替代 std.ChildProcess.exec）
fn runCommand(allocator: Allocator, argv: []const []const u8) !struct { exit_code: u8, stdout: []u8, stderr: []u8 } {
    const result = std.process.run(allocator, getIo(), .{
        .argv = argv,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    }) catch |err| {
        return err;
    };

    const exit_code: u8 = switch (result.term) {
        .exited => |code| code,
        else => 255,
    };

    return .{ .exit_code = exit_code, .stdout = result.stdout, .stderr = result.stderr };
}

/// AOT 性能测试配置
pub const AOTBenchmarkConfig = struct {
    /// 预热迭代次数
    warmup_iterations: u32 = 10,
    /// 测试迭代次数
    test_iterations: u32 = 100,
    /// 超时时间（毫秒）
    timeout_ms: u64 = 60000,
    /// 是否启用详细日志
    verbose: bool = false,
    /// PHP 可执行文件路径
    php_executable: []const u8 = "php",
    /// AOT 编译器路径
    aot_compiler: []const u8 = "./zig-php-aot",
    /// 临时目录
    temp_dir: []const u8 = "/tmp/aot_benchmark",
    /// 编译优化级别
    optimize_level: []const u8 = "ReleaseFast",
};

/// 编译时间统计
pub const CompileTimeStats = struct {
    /// 平均编译时间（毫秒）
    mean_ms: f64,
    /// 中位数编译时间（毫秒）
    median_ms: f64,
    /// 标准差（毫秒）
    std_dev_ms: f64,
    /// 最小编译时间（毫秒）
    min_ms: u64,
    /// 最大编译时间（毫秒）
    max_ms: u64,
    /// 迭代次数
    iterations: u32,

    pub fn compute(samples: []const u64) CompileTimeStats {
        if (samples.len == 0) {
            return .{
                .mean_ms = 0,
                .median_ms = 0,
                .std_dev_ms = 0,
                .min_ms = 0,
                .max_ms = 0,
                .iterations = 0,
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

        return .{
            .mean_ms = mean,
            .median_ms = median,
            .std_dev_ms = std_dev,
            .min_ms = samples[0],
            .max_ms = samples[samples.len - 1],
            .iterations = @intCast(samples.len),
        };
    }
};

/// 可执行文件大小统计
pub const ExecutableSizeStats = struct {
    /// 可执行文件大小（字节）
    size_bytes: u64,
    /// 文本段大小（字节）
    text_size_bytes: u64,
    /// 数据段大小（字节）
    data_size_bytes: u64,
    /// BSS 段大小（字节）
    bss_size_bytes: u64,

    pub fn measure(executable_path: []const u8) !ExecutableSizeStats {
        const file = try getCwd().openFile(getIo(), executable_path, .{});
        defer file.close(getIo());

        const stat = try file.stat(getIo());

        // 完整实现：解析可执行文件格式
        var header_buf: [64]u8 = undefined;
        _ = file.readPositionalAll(getIo(), &header_buf, 0) catch {
            // 文件太小，回退到简单实现
            return .{
                .size_bytes = stat.size,
                .text_size_bytes = 0,
                .data_size_bytes = 0,
                .bss_size_bytes = 0,
            };
        };

        // 检测文件格式
        if (std.mem.eql(u8, header_buf[0..4], "\x7fELF")) {
            // ELF 格式（Linux）
            return try parseELF(file, stat.size);
        } else if (
            (std.mem.eql(u8, header_buf[0..4], "\xfe\xed\xfa\xce") or
                std.mem.eql(u8, header_buf[0..4], "\xce\xfa\xed\xfe") or
                std.mem.eql(u8, header_buf[0..4], "\xfe\xed\xfa\xcf") or
                std.mem.eql(u8, header_buf[0..4], "\xcf\xfa\xed\xfe")))
        {
            // Mach-O 格式（macOS）
            return try parseMachO(file, stat.size);
        } else if (std.mem.eql(u8, header_buf[0..2], "MZ")) {
            // PE 格式（Windows）
            return try parsePE(file, stat.size);
        }

        // 未知格式，回退到简单实现
        return .{
            .size_bytes = stat.size,
            .text_size_bytes = 0,
            .data_size_bytes = 0,
            .bss_size_bytes = 0,
        };
    }

    /// 解析 ELF 格式（Linux）
    fn parseELF(file: std.Io.File, total_size: u64) !ExecutableSizeStats {
        var header: [64]u8 = undefined;
        _ = try file.readPositionalAll(getIo(), &header, 0);

        // 检查是 32 位还是 64 位
        const is_64bit = header[4] == 2;

        var text_size: u64 = 0;
        var data_size: u64 = 0;
        var bss_size: u64 = 0;

        if (is_64bit) {
            // 64 位 ELF
            const shoff = std.mem.readInt(u64, header[40..48], .little);
            const shentsize = std.mem.readInt(u16, header[58..60], .little);
            const shnum = std.mem.readInt(u16, header[60..62], .little);

            // 读取段头字符串表索引
            const shstrndx = std.mem.readInt(u16, header[62..64], .little);

            // 读取段头字符串表
            var shstrtab_header: [64]u8 = undefined;
            _ = try file.readPositionalAll(getIo(), &shstrtab_header, shoff + @as(u64, shstrndx) * @as(u64, shentsize));

            const shstrtab_offset = std.mem.readInt(u64, shstrtab_header[24..32], .little);
            const shstrtab_size = std.mem.readInt(u64, shstrtab_header[32..40], .little);

            // 读取段头字符串表内容
            const shstrtab = try std.heap.page_allocator.alloc(u8, @intCast(shstrtab_size));
            defer std.heap.page_allocator.free(shstrtab);

            _ = try file.readPositionalAll(getIo(), shstrtab, shstrtab_offset);

            // 遍历所有段头
            var i: u16 = 0;
            while (i < shnum) : (i += 1) {
                var sh: [64]u8 = undefined;
                _ = try file.readPositionalAll(getIo(), &sh, shoff + @as(u64, i) * @as(u64, shentsize));

                const name_offset = std.mem.readInt(u32, sh[0..4], .little);
                const sh_size = std.mem.readInt(u64, sh[32..40], .little);
                const sh_type = std.mem.readInt(u32, sh[4..8], .little);

                // 获取段名称
                if (name_offset < shstrtab.len) {
                    const name_end = std.mem.indexOfScalar(u8, shstrtab[name_offset..], 0) orelse (shstrtab.len - name_offset);
                    const name = shstrtab[name_offset..][0..name_end];

                    if (std.mem.eql(u8, name, ".text")) {
                        text_size = sh_size;
                    } else if (std.mem.eql(u8, name, ".data") or std.mem.eql(u8, name, ".rodata")) {
                        data_size += sh_size;
                    } else if (std.mem.eql(u8, name, ".bss")) {
                        bss_size = sh_size;
                    }
                }

                // SHT_NOBITS 类型的段（如 .bss）不占用文件空间
                if (sh_type == 8) { // SHT_NOBITS
                    // BSS 段已经在上面处理了
                }
            }
        }

        return .{
            .size_bytes = total_size,
            .text_size_bytes = text_size,
            .data_size_bytes = data_size,
            .bss_size_bytes = bss_size,
        };
    }

    /// 解析 Mach-O 格式（macOS）
    fn parseMachO(file: std.Io.File, total_size: u64) !ExecutableSizeStats {
        var header: [32]u8 = undefined;
        _ = try file.readPositionalAll(getIo(), &header, 0);

        const magic = std.mem.readInt(u32, header[0..4], .little);
        const is_64bit = (magic == 0xfeedfacf or magic == 0xcffaedfe);

        var text_size: u64 = 0;
        var data_size: u64 = 0;
        var bss_size: u64 = 0;

        if (is_64bit) {
            const ncmds = std.mem.readInt(u32, header[16..20], .little);
            var offset: u64 = 32; // Mach-O 64 位头大小

            var i: u32 = 0;
            while (i < ncmds) : (i += 1) {
                var cmd_header: [8]u8 = undefined;
                _ = try file.readPositionalAll(getIo(), &cmd_header, offset);

                const cmd = std.mem.readInt(u32, cmd_header[0..4], .little);
                const cmdsize = std.mem.readInt(u32, cmd_header[4..8], .little);

                // LC_SEGMENT_64 = 0x19
                if (cmd == 0x19) {
                    var segment: [72]u8 = undefined;
                    _ = try file.readPositionalAll(getIo(), &segment, offset);

                    const segname = segment[8..24];
                    const vmsize = std.mem.readInt(u64, segment[40..48], .little);
                    const filesize = std.mem.readInt(u64, segment[48..56], .little);

                    // 检查段名称
                    if (std.mem.startsWith(u8, segname, "__TEXT")) {
                        text_size += filesize;
                    } else if (std.mem.startsWith(u8, segname, "__DATA")) {
                        data_size += filesize;
                    }

                    // BSS 通常在 __DATA 段中，vmsize > filesize 的部分
                    if (vmsize > filesize) {
                        bss_size += (vmsize - filesize);
                    }
                }

                offset += cmdsize;
            }
        }

        return .{
            .size_bytes = total_size,
            .text_size_bytes = text_size,
            .data_size_bytes = data_size,
            .bss_size_bytes = bss_size,
        };
    }

    /// 解析 PE 格式（Windows）
    fn parsePE(file: std.Io.File, total_size: u64) !ExecutableSizeStats {
        // 读取 DOS 头
        var dos_header: [64]u8 = undefined;
        _ = try file.readPositionalAll(getIo(), &dos_header, 0);

        // 获取 PE 头偏移
        const pe_offset = std.mem.readInt(u32, dos_header[60..64], .little);

        // 读取 PE 头
        var pe_sig: [4]u8 = undefined;
        _ = try file.readPositionalAll(getIo(), &pe_sig, pe_offset);

        if (!std.mem.eql(u8, &pe_sig, "PE\x00\x00")) {
            return error.InvalidPEFormat;
        }

        // 读取 COFF 头
        var coff_header: [20]u8 = undefined;
        _ = try file.readPositionalAll(getIo(), &coff_header, pe_offset + 4);

        const num_sections = std.mem.readInt(u16, coff_header[2..4], .little);
        const opt_header_size = std.mem.readInt(u16, coff_header[16..18], .little);

        var text_size: u64 = 0;
        var data_size: u64 = 0;
        var bss_size: u64 = 0;

        // 读取段表
        var i: u16 = 0;
        while (i < num_sections) : (i += 1) {
            var section: [40]u8 = undefined;
            _ = try file.readPositionalAll(getIo(), &section, pe_offset + 24 + @as(u64, opt_header_size) + @as(u64, i) * 40);

            const name = section[0..8];
            const virtual_size = std.mem.readInt(u32, section[8..12], .little);
            const size_of_raw_data = std.mem.readInt(u32, section[16..20], .little);

            // 检查段名称
            if (std.mem.startsWith(u8, name, ".text")) {
                text_size += size_of_raw_data;
            } else if (std.mem.startsWith(u8, name, ".data") or std.mem.startsWith(u8, name, ".rdata")) {
                data_size += size_of_raw_data;
            } else if (std.mem.startsWith(u8, name, ".bss")) {
                bss_size += virtual_size;
            }
        }

        return .{
            .size_bytes = total_size,
            .text_size_bytes = text_size,
            .data_size_bytes = data_size,
            .bss_size_bytes = bss_size,
        };
    }
};

/// 启动时间统计
pub const StartupTimeStats = struct {
    /// 平均启动时间（微秒）
    mean_us: f64,
    /// 中位数启动时间（微秒）
    median_us: f64,
    /// 标准差（微秒）
    std_dev_us: f64,
    /// 最小启动时间（微秒）
    min_us: u64,
    /// 最大启动时间（微秒）
    max_us: u64,
    /// 迭代次数
    iterations: u32,

    pub fn compute(samples: []const u64) StartupTimeStats {
        if (samples.len == 0) {
            return .{
                .mean_us = 0,
                .median_us = 0,
                .std_dev_us = 0,
                .min_us = 0,
                .max_us = 0,
                .iterations = 0,
            };
        }

        var sum: u128 = 0;
        for (samples) |sample| {
            sum += sample;
        }
        const mean = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(samples.len));

        var variance_sum: f64 = 0;
        for (samples) |sample| {
            const diff = @as(f64, @floatFromInt(sample)) - mean;
            variance_sum += diff * diff;
        }
        const variance = variance_sum / @as(f64, @floatFromInt(samples.len));
        const std_dev = @sqrt(variance);

        const median_idx = samples.len / 2;
        const median = if (samples.len % 2 == 0)
            @as(f64, @floatFromInt(samples[median_idx - 1] + samples[median_idx])) / 2.0
        else
            @as(f64, @floatFromInt(samples[median_idx]));

        return .{
            .mean_us = mean,
            .median_us = median,
            .std_dev_us = std_dev,
            .min_us = samples[0],
            .max_us = samples[samples.len - 1],
            .iterations = @intCast(samples.len),
        };
    }
};

/// 执行时间统计
pub const ExecutionTimeStats = struct {
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

    pub fn compute(samples: []const u64) ExecutionTimeStats {
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
            };
        }

        var sum: u128 = 0;
        for (samples) |sample| {
            sum += sample;
        }
        const mean = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(samples.len));

        var variance_sum: f64 = 0;
        for (samples) |sample| {
            const diff = @as(f64, @floatFromInt(sample)) - mean;
            variance_sum += diff * diff;
        }
        const variance = variance_sum / @as(f64, @floatFromInt(samples.len));
        const std_dev = @sqrt(variance);

        const median_idx = samples.len / 2;
        const median = if (samples.len % 2 == 0)
            @as(f64, @floatFromInt(samples[median_idx - 1] + samples[median_idx])) / 2.0
        else
            @as(f64, @floatFromInt(samples[median_idx]));

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
        };
    }
};

/// AOT 完整测试结果
pub const AOTBenchmarkResult = struct {
    /// 测试名称
    test_name: []const u8,
    /// 编译时间统计
    compile_time: CompileTimeStats,
    /// 可执行文件大小统计
    executable_size: ExecutableSizeStats,
    /// 启动时间统计
    startup_time: StartupTimeStats,
    /// 执行时间统计（AOT）
    aot_execution_time: ExecutionTimeStats,
    /// 执行时间统计（PHP）
    php_execution_time: ExecutionTimeStats,
    /// 加速比（PHP时间 / AOT时间）
    speedup: f64,
    /// 测试时间戳
    timestamp: i64,

    pub fn compute(
        test_name: []const u8,
        compile_time: CompileTimeStats,
        executable_size: ExecutableSizeStats,
        startup_time: StartupTimeStats,
        aot_exec: ExecutionTimeStats,
        php_exec: ExecutionTimeStats,
    ) AOTBenchmarkResult {
        const speedup = if (aot_exec.mean_ns > 0)
            php_exec.mean_ns / aot_exec.mean_ns
        else
            0.0;

        return .{
            .test_name = test_name,
            .compile_time = compile_time,
            .executable_size = executable_size,
            .startup_time = startup_time,
            .aot_execution_time = aot_exec,
            .php_execution_time = php_exec,
            .speedup = speedup,
            .timestamp = unixTimestamp(),
        };
    }
};

/// 报告格式
pub const ReportFormat = enum {
    json,
    csv,
    markdown,
    html,
};

/// AOT 性能测试框架
pub const AOTBenchmarkFramework = struct {
    allocator: Allocator,
    config: AOTBenchmarkConfig,
    results: std.ArrayList(AOTBenchmarkResult),

    const Self = @This();

    /// 初始化框架
    pub fn init(allocator: Allocator, config: AOTBenchmarkConfig) !*Self {
        const self = try allocator.create(Self);
        self.allocator = allocator;
        self.config = config;
        self.results = .empty;

        // 创建临时目录
        getCwd().createDirPath(getIo(), config.temp_dir) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
        };

        return self;
    }

    /// 清理资源
    pub fn deinit(self: *Self) void {
        self.results.deinit(self.allocator);

        // 清理临时目录
        getCwd().deleteTree(getIo(), self.config.temp_dir) catch |err| {
            if (self.config.verbose) {
                std.debug.print("警告: 无法删除临时目录: {s}\n", .{@errorName(err)});
            }
        };

        self.allocator.destroy(self);
    }

    /// 运行完整的 AOT 性能测试
    /// @param source_path PHP 源文件路径
    /// @return 完整测试结果
    pub fn runFullBenchmark(self: *Self, source_path: []const u8) !AOTBenchmarkResult {
        if (self.config.verbose) {
            std.debug.print("\n=== 运行 AOT 性能测试: {s} ===\n", .{source_path});
        }

        // 1. 测量编译时间
        if (self.config.verbose) {
            std.debug.print("\n[1/4] 测量编译时间...\n", .{});
        }
        const compile_time = try self.measureCompileTime(source_path);

        // 2. 测量可执行文件大小
        if (self.config.verbose) {
            std.debug.print("\n[2/4] 测量可执行文件大小...\n", .{});
        }
        const executable_path = try self.getExecutablePath(source_path);
        defer self.allocator.free(executable_path);
        const executable_size = try ExecutableSizeStats.measure(executable_path);

        // 3. 测量启动时间
        if (self.config.verbose) {
            std.debug.print("\n[3/4] 测量启动时间...\n", .{});
        }
        const startup_time = try self.measureStartupTime(executable_path);

        // 4. 测量执行时间
        if (self.config.verbose) {
            std.debug.print("\n[4/4] 测量执行时间...\n", .{});
        }
        const aot_exec_time = try self.measureExecutionTime(executable_path);
        const php_exec_time = try self.measurePHPExecutionTime(source_path);

        // 计算结果
        const result = AOTBenchmarkResult.compute(
            source_path,
            compile_time,
            executable_size,
            startup_time,
            aot_exec_time,
            php_exec_time,
        );

        // 保存结果
        try self.results.append(self.allocator, result);

        if (self.config.verbose) {
            std.debug.print("\n=== 测试完成 ===\n", .{});
            std.debug.print("编译时间: {d:.2} ms\n", .{compile_time.mean_ms});
            std.debug.print("可执行文件大小: {d} bytes\n", .{executable_size.size_bytes});
            std.debug.print("启动时间: {d:.2} μs\n", .{startup_time.mean_us});
            std.debug.print("执行时间 (AOT): {d:.2} ns\n", .{aot_exec_time.mean_ns});
            std.debug.print("执行时间 (PHP): {d:.2} ns\n", .{php_exec_time.mean_ns});
            std.debug.print("加速比: {d:.2}x\n", .{result.speedup});
        }

        return result;
    }

    /// 测量编译时间
    fn measureCompileTime(self: *Self, source_path: []const u8) !CompileTimeStats {
        var samples = try self.allocator.alloc(u64, self.config.test_iterations);
        defer self.allocator.free(samples);

        const output_path = try self.getExecutablePath(source_path);
        defer self.allocator.free(output_path);

        // 预热阶段
        if (self.config.verbose) {
            std.debug.print("  预热中... ({d} 次迭代)\n", .{self.config.warmup_iterations});
        }

        var i: u32 = 0;
        while (i < self.config.warmup_iterations) : (i += 1) {
            _ = try self.compileSource(source_path, output_path);
            // 删除生成的文件
            getCwd().deleteFile(getIo(), output_path) catch {};
        }

        // 测试阶段
        if (self.config.verbose) {
            std.debug.print("  测试中... ({d} 次迭代)\n", .{self.config.test_iterations});
        }

        i = 0;
        while (i < self.config.test_iterations) : (i += 1) {
            const start = milliTimestamp();
            _ = try self.compileSource(source_path, output_path);
            const end = milliTimestamp();

            samples[i] = @intCast(end - start);

            // 删除生成的文件
            getCwd().deleteFile(getIo(), output_path) catch {};

            if (self.config.verbose and (i + 1) % 10 == 0) {
                std.debug.print("    完成 {d}/{d}\n", .{ i + 1, self.config.test_iterations });
            }
        }

        // 排序样本
        std.mem.sort(u64, samples, {}, comptime std.sort.asc(u64));

        return CompileTimeStats.compute(samples);
    }

    /// 编译源文件
    fn compileSource(self: *Self, source_path: []const u8, output_path: []const u8) !void {
        var argv = [_][]const u8{
            self.config.aot_compiler,
            source_path,
            "-o",
            output_path,
            "-O",
            self.config.optimize_level,
        };

        const result = runCommand(self.allocator, &argv) catch |err| {
            if (self.config.verbose) {
                std.debug.print("编译失败: {s}\n", .{@errorName(err)});
            }
            return error.CompilationFailed;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.config.verbose) {
                std.debug.print("编译器退出码: {d}\n", .{result.exit_code});
                std.debug.print("错误输出: {s}\n", .{result.stderr});
            }
            return error.CompilationFailed;
        }
    }

    /// 测量启动时间
    fn measureStartupTime(self: *Self, executable_path: []const u8) !StartupTimeStats {
        var samples = try self.allocator.alloc(u64, self.config.test_iterations);
        defer self.allocator.free(samples);

        // 预热阶段
        if (self.config.verbose) {
            std.debug.print("  预热中... ({d} 次迭代)\n", .{self.config.warmup_iterations});
        }

        var i: u32 = 0;
        while (i < self.config.warmup_iterations) : (i += 1) {
            _ = try self.executeWithStartupMeasurement(executable_path);
        }

        // 测试阶段
        if (self.config.verbose) {
            std.debug.print("  测试中... ({d} 次迭代)\n", .{self.config.test_iterations});
        }

        i = 0;
        while (i < self.config.test_iterations) : (i += 1) {
            samples[i] = try self.executeWithStartupMeasurement(executable_path);

            if (self.config.verbose and (i + 1) % 10 == 0) {
                std.debug.print("    完成 {d}/{d}\n", .{ i + 1, self.config.test_iterations });
            }
        }

        // 排序样本
        std.mem.sort(u64, samples, {}, comptime std.sort.asc(u64));

        return StartupTimeStats.compute(samples);
    }

    /// 执行并测量启动时间（微秒）
    fn executeWithStartupMeasurement(self: *Self, executable_path: []const u8) !u64 {
        // 使用 time 命令或直接测量进程启动时间
        var argv = [_][]const u8{executable_path};

        const start = microTimestamp();

        const result = runCommand(self.allocator, &argv) catch |err| {
            if (self.config.verbose) {
                std.debug.print("执行失败: {s}\n", .{@errorName(err)});
            }
            return error.ExecutionFailed;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        const end = microTimestamp();

        if (result.exit_code != 0) {
            if (self.config.verbose) {
                std.debug.print("程序退出码: {d}\n", .{result.exit_code});
            }
            return error.ExecutionFailed;
        }

        return @intCast(end - start);
    }

    /// 测量执行时间（AOT）
    fn measureExecutionTime(self: *Self, executable_path: []const u8) !ExecutionTimeStats {
        var samples = try self.allocator.alloc(u64, self.config.test_iterations);
        defer self.allocator.free(samples);

        // 预热阶段
        if (self.config.verbose) {
            std.debug.print("  预热中... ({d} 次迭代)\n", .{self.config.warmup_iterations});
        }

        var i: u32 = 0;
        while (i < self.config.warmup_iterations) : (i += 1) {
            _ = try self.executeAndMeasure(executable_path);
        }

        // 测试阶段
        if (self.config.verbose) {
            std.debug.print("  测试中... ({d} 次迭代)\n", .{self.config.test_iterations});
        }

        i = 0;
        while (i < self.config.test_iterations) : (i += 1) {
            samples[i] = try self.executeAndMeasure(executable_path);

            if (self.config.verbose and (i + 1) % 10 == 0) {
                std.debug.print("    完成 {d}/{d}\n", .{ i + 1, self.config.test_iterations });
            }
        }

        // 排序样本
        std.mem.sort(u64, samples, {}, comptime std.sort.asc(u64));

        return ExecutionTimeStats.compute(samples);
    }

    /// 执行并测量时间（纳秒）
    fn executeAndMeasure(self: *Self, executable_path: []const u8) !u64 {
        var argv = [_][]const u8{executable_path};

        const start = nanoTimestamp();

        const result = runCommand(self.allocator, &argv) catch |err| {
            if (self.config.verbose) {
                std.debug.print("执行失败: {s}\n", .{@errorName(err)});
            }
            return error.ExecutionFailed;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        const end = nanoTimestamp();

        if (result.exit_code != 0) {
            return error.ExecutionFailed;
        }

        return @intCast(end - start);
    }

    /// 测量 PHP 执行时间
    fn measurePHPExecutionTime(self: *Self, source_path: []const u8) !ExecutionTimeStats {
        var samples = try self.allocator.alloc(u64, self.config.test_iterations);
        defer self.allocator.free(samples);

        // 预热阶段
        var i: u32 = 0;
        while (i < self.config.warmup_iterations) : (i += 1) {
            _ = try self.executePHP(source_path);
        }

        // 测试阶段
        i = 0;
        while (i < self.config.test_iterations) : (i += 1) {
            samples[i] = try self.executePHP(source_path);
        }

        // 排序样本
        std.mem.sort(u64, samples, {}, comptime std.sort.asc(u64));

        return ExecutionTimeStats.compute(samples);
    }

    /// 执行 PHP 脚本并测量时间
    fn executePHP(self: *Self, source_path: []const u8) !u64 {
        var argv = [_][]const u8{ self.config.php_executable, source_path };

        const start = nanoTimestamp();

        const result = runCommand(self.allocator, &argv) catch |err| {
            if (self.config.verbose) {
                std.debug.print("PHP 执行失败: {s}\n", .{@errorName(err)});
            }
            return error.ExecutionFailed;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        const end = nanoTimestamp();

        if (result.exit_code != 0) {
            return error.ExecutionFailed;
        }

        return @intCast(end - start);
    }

    /// 获取可执行文件路径
    fn getExecutablePath(self: *Self, source_path: []const u8) ![]u8 {
        const basename = std.fs.path.basename(source_path);
        const name_without_ext = if (std.mem.lastIndexOf(u8, basename, ".")) |idx|
            basename[0..idx]
        else
            basename;

        return std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}_aot",
            .{ self.config.temp_dir, name_without_ext },
        );
    }

    /// 生成报告
    pub fn generateReport(
        self: *Self,
        result: AOTBenchmarkResult,
        output_path: []const u8,
        format: ReportFormat,
    ) !void {
        var aw: std.Io.Writer.Allocating = .init(self.allocator);
        defer aw.deinit();
        const writer = &aw.writer;

        switch (format) {
            .json => try self.generateJsonReport(writer, result),
            .csv => try self.generateCsvReport(writer, result),
            .markdown => try self.generateMarkdownReport(writer, result),
            .html => try self.generateHtmlReport(writer, result),
        }

        const file = try getCwd().createFile(getIo(), output_path, .{});
        defer file.close(getIo());
        try file.writeStreamingAll(getIo(), aw.writer.buffer[0..aw.writer.end]);

        if (self.config.verbose) {
            std.debug.print("报告已生成: {s}\n", .{output_path});
        }
    }

    /// 生成 JSON 报告
    fn generateJsonReport(self: *Self, writer: anytype, result: AOTBenchmarkResult) !void {
        _ = self;

        try writer.writeAll("{\n");
        try writer.print("  \"test_name\": \"{s}\",\n", .{result.test_name});
        try writer.print("  \"timestamp\": {d},\n", .{result.timestamp});
        try writer.print("  \"speedup\": {d:.4},\n", .{result.speedup});

        try writer.writeAll("  \"compile_time\": {\n");
        try writer.print("    \"mean_ms\": {d:.2},\n", .{result.compile_time.mean_ms});
        try writer.print("    \"median_ms\": {d:.2},\n", .{result.compile_time.median_ms});
        try writer.print("    \"std_dev_ms\": {d:.2},\n", .{result.compile_time.std_dev_ms});
        try writer.print("    \"min_ms\": {d},\n", .{result.compile_time.min_ms});
        try writer.print("    \"max_ms\": {d}\n", .{result.compile_time.max_ms});
        try writer.writeAll("  },\n");

        try writer.writeAll("  \"executable_size\": {\n");
        try writer.print("    \"size_bytes\": {d}\n", .{result.executable_size.size_bytes});
        try writer.writeAll("  },\n");

        try writer.writeAll("  \"startup_time\": {\n");
        try writer.print("    \"mean_us\": {d:.2},\n", .{result.startup_time.mean_us});
        try writer.print("    \"median_us\": {d:.2},\n", .{result.startup_time.median_us});
        try writer.print("    \"std_dev_us\": {d:.2}\n", .{result.startup_time.std_dev_us});
        try writer.writeAll("  },\n");

        try writer.writeAll("  \"aot_execution_time\": {\n");
        try writer.print("    \"mean_ns\": {d:.2},\n", .{result.aot_execution_time.mean_ns});
        try writer.print("    \"median_ns\": {d:.2},\n", .{result.aot_execution_time.median_ns});
        try writer.print("    \"p95_ns\": {d},\n", .{result.aot_execution_time.p95_ns});
        try writer.print("    \"p99_ns\": {d}\n", .{result.aot_execution_time.p99_ns});
        try writer.writeAll("  },\n");

        try writer.writeAll("  \"php_execution_time\": {\n");
        try writer.print("    \"mean_ns\": {d:.2},\n", .{result.php_execution_time.mean_ns});
        try writer.print("    \"median_ns\": {d:.2}\n", .{result.php_execution_time.median_ns});
        try writer.writeAll("  }\n");

        try writer.writeAll("}\n");
    }

    /// 生成 CSV 报告
    fn generateCsvReport(self: *Self, writer: anytype, result: AOTBenchmarkResult) !void {
        _ = self;

        try writer.writeAll("metric,value,unit\n");
        try writer.print("compile_time_mean,{d:.2},ms\n", .{result.compile_time.mean_ms});
        try writer.print("compile_time_median,{d:.2},ms\n", .{result.compile_time.median_ms});
        try writer.print("compile_time_std_dev,{d:.2},ms\n", .{result.compile_time.std_dev_ms});
        try writer.print("executable_size,{d},bytes\n", .{result.executable_size.size_bytes});
        try writer.print("startup_time_mean,{d:.2},us\n", .{result.startup_time.mean_us});
        try writer.print("startup_time_median,{d:.2},us\n", .{result.startup_time.median_us});
        try writer.print("aot_execution_mean,{d:.2},ns\n", .{result.aot_execution_time.mean_ns});
        try writer.print("aot_execution_median,{d:.2},ns\n", .{result.aot_execution_time.median_ns});
        try writer.print("php_execution_mean,{d:.2},ns\n", .{result.php_execution_time.mean_ns});
        try writer.print("php_execution_median,{d:.2},ns\n", .{result.php_execution_time.median_ns});
        try writer.print("speedup,{d:.4},x\n", .{result.speedup});
    }

    /// 生成 Markdown 报告
    fn generateMarkdownReport(self: *Self, writer: anytype, result: AOTBenchmarkResult) !void {
        _ = self;

        try writer.print("# AOT 性能测试报告: {s}\n\n", .{result.test_name});
        try writer.print("**测试时间**: {d}\n\n", .{result.timestamp});

        try writer.writeAll("## 总体结果\n\n");
        try writer.print("- **加速比**: {d:.2}x\n\n", .{result.speedup});

        try writer.writeAll("## 编译时间\n\n");
        try writer.writeAll("| 指标 | 值 |\n");
        try writer.writeAll("|------|----|\n");
        try writer.print("| 平均值 | {d:.2} ms |\n", .{result.compile_time.mean_ms});
        try writer.print("| 中位数 | {d:.2} ms |\n", .{result.compile_time.median_ms});
        try writer.print("| 标准差 | {d:.2} ms |\n", .{result.compile_time.std_dev_ms});
        try writer.print("| 最小值 | {d} ms |\n", .{result.compile_time.min_ms});
        try writer.print("| 最大值 | {d} ms |\n\n", .{result.compile_time.max_ms});

        try writer.writeAll("## 可执行文件大小\n\n");
        try writer.writeAll("| 指标 | 值 |\n");
        try writer.writeAll("|------|----|\n");
        try writer.print("| 文件大小 | {d} bytes ({d:.2} KB) |\n\n", .{
            result.executable_size.size_bytes,
            @as(f64, @floatFromInt(result.executable_size.size_bytes)) / 1024.0,
        });

        try writer.writeAll("## 启动时间\n\n");
        try writer.writeAll("| 指标 | 值 |\n");
        try writer.writeAll("|------|----|\n");
        try writer.print("| 平均值 | {d:.2} μs |\n", .{result.startup_time.mean_us});
        try writer.print("| 中位数 | {d:.2} μs |\n", .{result.startup_time.median_us});
        try writer.print("| 标准差 | {d:.2} μs |\n\n", .{result.startup_time.std_dev_us});

        try writer.writeAll("## 执行时间对比\n\n");
        try writer.writeAll("| 指标 | AOT | PHP | 改进 |\n");
        try writer.writeAll("|------|-----|-----|------|\n");

        const mean_improvement = (result.php_execution_time.mean_ns - result.aot_execution_time.mean_ns) /
            result.php_execution_time.mean_ns * 100;
        try writer.print("| 平均值 (ns) | {d:.2} | {d:.2} | {d:.1}% |\n", .{
            result.aot_execution_time.mean_ns,
            result.php_execution_time.mean_ns,
            mean_improvement,
        });

        const median_improvement = (result.php_execution_time.median_ns - result.aot_execution_time.median_ns) /
            result.php_execution_time.median_ns * 100;
        try writer.print("| 中位数 (ns) | {d:.2} | {d:.2} | {d:.1}% |\n", .{
            result.aot_execution_time.median_ns,
            result.php_execution_time.median_ns,
            median_improvement,
        });

        try writer.print("| P95 (ns) | {d} | - | - |\n", .{result.aot_execution_time.p95_ns});
        try writer.print("| P99 (ns) | {d} | - | - |\n", .{result.aot_execution_time.p99_ns});
    }

    /// 生成 HTML 报告
    fn generateHtmlReport(self: *Self, writer: anytype, result: AOTBenchmarkResult) !void {
        _ = self;

        try writer.writeAll("<!DOCTYPE html>\n<html>\n<head>\n");
        try writer.writeAll("  <meta charset=\"UTF-8\">\n");
        try writer.print("  <title>AOT 性能测试报告: {s}</title>\n", .{result.test_name});
        try writer.writeAll("  <style>\n");
        try writer.writeAll("    body { font-family: Arial, sans-serif; margin: 20px; }\n");
        try writer.writeAll("    table { border-collapse: collapse; width: 100%; margin: 20px 0; }\n");
        try writer.writeAll("    th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }\n");
        try writer.writeAll("    th { background-color: #4CAF50; color: white; }\n");
        try writer.writeAll("    .metric { font-weight: bold; }\n");
        try writer.writeAll("    .speedup { color: green; font-size: 24px; font-weight: bold; }\n");
        try writer.writeAll("    .section { margin: 30px 0; }\n");
        try writer.writeAll("  </style>\n");
        try writer.writeAll("</head>\n<body>\n");

        try writer.print("  <h1>AOT 性能测试报告: {s}</h1>\n", .{result.test_name});
        try writer.print("  <p>测试时间: {d}</p>\n", .{result.timestamp});

        try writer.writeAll("  <div class=\"section\">\n");
        try writer.writeAll("    <h2>总体结果</h2>\n");
        try writer.print("    <p class=\"speedup\">加速比: {d:.2}x</p>\n", .{result.speedup});
        try writer.writeAll("  </div>\n");

        try writer.writeAll("  <div class=\"section\">\n");
        try writer.writeAll("    <h2>编译时间</h2>\n");
        try writer.writeAll("    <table>\n");
        try writer.writeAll("      <tr><th>指标</th><th>值</th></tr>\n");
        try writer.print("      <tr><td>平均值</td><td>{d:.2} ms</td></tr>\n", .{result.compile_time.mean_ms});
        try writer.print("      <tr><td>中位数</td><td>{d:.2} ms</td></tr>\n", .{result.compile_time.median_ms});
        try writer.print("      <tr><td>标准差</td><td>{d:.2} ms</td></tr>\n", .{result.compile_time.std_dev_ms});
        try writer.writeAll("    </table>\n");
        try writer.writeAll("  </div>\n");

        try writer.writeAll("  <div class=\"section\">\n");
        try writer.writeAll("    <h2>可执行文件大小</h2>\n");
        try writer.writeAll("    <table>\n");
        try writer.writeAll("      <tr><th>指标</th><th>值</th></tr>\n");
        try writer.print("      <tr><td>文件大小</td><td>{d} bytes ({d:.2} KB)</td></tr>\n", .{
            result.executable_size.size_bytes,
            @as(f64, @floatFromInt(result.executable_size.size_bytes)) / 1024.0,
        });
        try writer.writeAll("    </table>\n");
        try writer.writeAll("  </div>\n");

        try writer.writeAll("  <div class=\"section\">\n");
        try writer.writeAll("    <h2>执行时间对比</h2>\n");
        try writer.writeAll("    <table>\n");
        try writer.writeAll("      <tr><th>指标</th><th>AOT</th><th>PHP</th><th>改进</th></tr>\n");

        const mean_improvement = (result.php_execution_time.mean_ns - result.aot_execution_time.mean_ns) /
            result.php_execution_time.mean_ns * 100;
        try writer.print("      <tr><td>平均值 (ns)</td><td>{d:.2}</td><td>{d:.2}</td><td>{d:.1}%</td></tr>\n", .{
            result.aot_execution_time.mean_ns,
            result.php_execution_time.mean_ns,
            mean_improvement,
        });

        try writer.writeAll("    </table>\n");
        try writer.writeAll("  </div>\n");

        try writer.writeAll("</body>\n</html>\n");
    }
};

// ============================================================================
// Main 入口
// ============================================================================

pub fn main(init: std.process.Init.Minimal) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var io_environ: [0:null]?[*:0]u8 = [_:null]?[*:0]u8{};
    var io_threaded = std.Io.Threaded.init(allocator, .{
        .argv0 = .init(.{ .vector = &.{} }),
        .environ = .{ .block = .{ .slice = &io_environ } },
    });
    defer io_threaded.deinit();

    var args_iter = try std.process.Args.Iterator.initAllocator(init.args, allocator);
    defer args_iter.deinit();

    _ = args_iter.next(); // skip program name

    var php_file: ?[]const u8 = null;
    var warmup: u32 = 10;
    var iterations: u32 = 100;
    var verbose = false;

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--warmup")) {
            if (args_iter.next()) |val| {
                warmup = std.fmt.parseInt(u32, val, 10) catch 10;
            }
        } else if (std.mem.eql(u8, arg, "--iterations")) {
            if (args_iter.next()) |val| {
                iterations = std.fmt.parseInt(u32, val, 10) catch 100;
            }
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else if (!std.mem.startsWith(u8, arg, "--")) {
            php_file = arg;
        }
    }

    if (php_file == null) {
        std.debug.print("Usage: aot-benchmark <php_file> [--warmup N] [--iterations N] [--verbose]\n", .{});
        return;
    }

    var framework = try AOTBenchmarkFramework.init(allocator, .{
        .warmup_iterations = warmup,
        .test_iterations = iterations,
        .verbose = verbose,
    });
    defer framework.deinit();

    const result = try framework.runFullBenchmark(php_file.?);

    std.debug.print("\n=== AOT Benchmark Results ===\n", .{});
    std.debug.print("Test: {s}\n", .{result.test_name});
    std.debug.print("Speedup: {d:.2}x\n", .{result.speedup});
    std.debug.print("Compile time (mean): {d:.2} ms\n", .{result.compile_time.mean_ms});
    std.debug.print("Executable size: {d} bytes\n", .{result.executable_size.size_bytes});
    std.debug.print("Startup time (mean): {d:.2} us\n", .{result.startup_time.mean_us});
    std.debug.print("AOT execution (mean): {d:.2} ns\n", .{result.aot_execution_time.mean_ns});
    std.debug.print("PHP execution (mean): {d:.2} ns\n", .{result.php_execution_time.mean_ns});

    const report_path = "aot_benchmark_report.md";
    try framework.generateReport(result, report_path, .markdown);
    std.debug.print("\nReport saved to: {s}\n", .{report_path});
}

// ============================================================================
// 测试
// ============================================================================

test "AOT benchmark framework initialization" {
    const allocator = std.testing.allocator;

    var framework = try AOTBenchmarkFramework.init(allocator, .{
        .warmup_iterations = 5,
        .test_iterations = 10,
        .verbose = false,
    });
    defer framework.deinit();

    try std.testing.expect(framework.config.warmup_iterations == 5);
    try std.testing.expect(framework.config.test_iterations == 10);
}

test "CompileTimeStats computation" {
    const samples = [_]u64{ 100, 150, 200, 250, 300 };
    const stats = CompileTimeStats.compute(&samples);

    try std.testing.expect(stats.mean_ms == 200.0);
    try std.testing.expect(stats.median_ms == 200.0);
    try std.testing.expect(stats.min_ms == 100);
    try std.testing.expect(stats.max_ms == 300);
    try std.testing.expect(stats.iterations == 5);
}

test "ExecutionTimeStats computation" {
    const samples = [_]u64{ 1000, 1500, 2000, 2500, 3000 };
    const stats = ExecutionTimeStats.compute(&samples);

    try std.testing.expect(stats.mean_ns == 2000.0);
    try std.testing.expect(stats.median_ns == 2000.0);
    try std.testing.expect(stats.min_ns == 1000);
    try std.testing.expect(stats.max_ns == 3000);
    try std.testing.expect(stats.iterations == 5);
}
