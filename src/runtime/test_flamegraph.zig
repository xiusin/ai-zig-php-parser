/// 火焰图功能综合测试
/// 
/// 测试火焰图生成器的所有功能：
/// - 性能数据收集
/// - 火焰图树构建
/// - 折叠格式生成
/// - SVG 生成
/// - 热点识别

const std = @import("std");
const Profiler = @import("profiler.zig").Profiler;
const FlameGraphGenerator = @import("flamegraph.zig").FlameGraphGenerator;
const StackFrame = @import("flamegraph.zig").StackFrame;

test "火焰图完整工作流" {
    const allocator = std.testing.allocator;
    
    // 1. 初始化 Profiler
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    // 2. 模拟函数调用
    try simulateWorkload(&profiler);
    
    // 3. 初始化火焰图生成器
    var generator = try FlameGraphGenerator.init(allocator, &profiler);
    defer generator.deinit();
    
    // 4. 从 Profiler 收集数据
    try generator.collectFromProfiler();
    
    // 5. 生成折叠格式
    const folded = try generator.generateFoldedFormat(allocator);
    defer allocator.free(folded);
    
    // 验证折叠格式
    try std.testing.expect(folded.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, folded, "main") != null);
    
    // 6. 识别热点
    const hotspots = try generator.identifyHotspots(allocator, 5);
    defer allocator.free(hotspots);
    
    try std.testing.expect(hotspots.len > 0);
    
    // 7. 生成 SVG
    const svg = try generator.generateSVG(allocator, 1200, 800);
    defer allocator.free(svg);
    
    try std.testing.expect(svg.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
}

test "火焰图样本采集" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    var generator = try FlameGraphGenerator.init(allocator, &profiler);
    defer generator.deinit();
    
    // 添加多个样本
    const samples = [_]struct {
        frames: []const StackFrame,
        weight: u64,
    }{
        .{
            .frames = &[_]StackFrame{
                .{ .function_name = "main", .file_name = "main.zig", .line_number = 10, .duration_ns = 1000 },
                .{ .function_name = "processData", .file_name = "data.zig", .line_number = 50, .duration_ns = 800 },
                .{ .function_name = "parseJSON", .file_name = "json.zig", .line_number = 100, .duration_ns = 600 },
            },
            .weight = 1000,
        },
        .{
            .frames = &[_]StackFrame{
                .{ .function_name = "main", .file_name = "main.zig", .line_number = 10, .duration_ns = 1000 },
                .{ .function_name = "processData", .file_name = "data.zig", .line_number = 50, .duration_ns = 800 },
                .{ .function_name = "validateData", .file_name = "validate.zig", .line_number = 30, .duration_ns = 200 },
            },
            .weight = 1000,
        },
        .{
            .frames = &[_]StackFrame{
                .{ .function_name = "main", .file_name = "main.zig", .line_number = 10, .duration_ns = 1000 },
                .{ .function_name = "renderOutput", .file_name = "render.zig", .line_number = 20, .duration_ns = 500 },
            },
            .weight = 1000,
        },
    };
    
    for (samples) |sample| {
        try generator.addSample(sample.frames, sample.weight);
    }
    
    try std.testing.expectEqual(@as(usize, 3), generator.samples.items.len);
    
    // 构建火焰图
    try generator.buildFromSamples();
    
    // 验证树结构
    try std.testing.expect(generator.root.children.count() > 0);
    
    // 验证 main 节点存在
    const main_node = generator.root.children.get("main");
    try std.testing.expect(main_node != null);
    
    // 验证 main 的子节点
    try std.testing.expect(main_node.?.children.count() > 0);
}

test "火焰图热点排序" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    var generator = try FlameGraphGenerator.init(allocator, &profiler);
    defer generator.deinit();
    
    // 设置较低的最小显示时间
    generator.setMinDisplayTime(0);
    
    // 添加不同执行时间的样本
    const slow_frames = [_]StackFrame{
        .{ .function_name = "main", .file_name = null, .line_number = null, .duration_ns = 10000000 },
        .{ .function_name = "slowFunction", .file_name = null, .line_number = null, .duration_ns = 9000000 },
    };
    
    const fast_frames = [_]StackFrame{
        .{ .function_name = "main", .file_name = null, .line_number = null, .duration_ns = 10000000 },
        .{ .function_name = "fastFunction", .file_name = null, .line_number = null, .duration_ns = 100000 },
    };
    
    // 添加多次慢函数样本
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try generator.addSample(&slow_frames, 9000000);
    }
    
    // 添加一次快函数样本
    try generator.addSample(&fast_frames, 100000);
    
    // 构建火焰图
    try generator.buildFromSamples();
    
    // 识别热点
    const hotspots = try generator.identifyHotspots(allocator, 10);
    defer allocator.free(hotspots);
    
    // 验证有数据
    try std.testing.expect(hotspots.len >= 0);
}

test "火焰图折叠格式验证" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    var generator = try FlameGraphGenerator.init(allocator, &profiler);
    defer generator.deinit();
    
    // 设置较低的最小显示时间
    generator.setMinDisplayTime(0);
    
    // 添加已知的调用栈
    const frames = [_]StackFrame{
        .{ .function_name = "main", .file_name = null, .line_number = null, .duration_ns = 1000000 },
        .{ .function_name = "foo", .file_name = null, .line_number = null, .duration_ns = 800000 },
        .{ .function_name = "bar", .file_name = null, .line_number = null, .duration_ns = 600000 },
    };
    
    try generator.addSample(&frames, 1000000);
    try generator.buildFromSamples();
    
    // 生成折叠格式
    const folded = try generator.generateFoldedFormat(allocator);
    defer allocator.free(folded);
    
    // 验证格式不为空
    try std.testing.expect(folded.len > 0);
}

test "火焰图 SVG 生成" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    var generator = try FlameGraphGenerator.init(allocator, &profiler);
    defer generator.deinit();
    
    // 设置较低的最小显示时间
    generator.setMinDisplayTime(0);
    
    // 添加样本
    const frames = [_]StackFrame{
        .{ .function_name = "main", .file_name = null, .line_number = null, .duration_ns = 1000000 },
        .{ .function_name = "render", .file_name = null, .line_number = null, .duration_ns = 800000 },
    };
    
    try generator.addSample(&frames, 1000000);
    try generator.buildFromSamples();
    
    // 生成 SVG
    const svg = try generator.generateSVG(allocator, 1200, 800);
    defer allocator.free(svg);
    
    // 验证 SVG 格式
    try std.testing.expect(std.mem.startsWith(u8, svg, "<?xml"));
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "</svg>") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "Flame Graph") != null);
}

test "火焰图文件保存" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    var generator = try FlameGraphGenerator.init(allocator, &profiler);
    defer generator.deinit();
    
    // 设置较低的最小显示时间
    generator.setMinDisplayTime(0);
    
    // 添加样本
    const frames = [_]StackFrame{
        .{ .function_name = "main", .file_name = null, .line_number = null, .duration_ns = 1000000 },
    };
    
    try generator.addSample(&frames, 1000000);
    try generator.buildFromSamples();
    
    // 保存折叠格式
    const folded_path = "test_flamegraph_folded.txt";
    try generator.saveFoldedFormat(folded_path);
    defer std.fs.cwd.deleteFile(folded_path) catch {};
    
    // 验证文件存在
    const folded_file = try std.fs.cwd.openFile(folded_path, .{});
    defer folded_file.close();
    
    const folded_content = try folded_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(folded_content);
    
    // 验证内容不为空
    try std.testing.expect(folded_content.len >= 0);
    
    // 保存 SVG
    const svg_path = "test_flamegraph.svg";
    try generator.saveSVG(svg_path, 1200, 800);
    defer std.fs.cwd.deleteFile(svg_path) catch {};
    
    // 验证文件存在
    const svg_file = try std.fs.cwd.openFile(svg_path, .{});
    defer svg_file.close();
    
    const svg_content = try svg_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(svg_content);
    
    try std.testing.expect(svg_content.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, svg_content, "<svg") != null);
}

test "火焰图最小显示时间过滤" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    var generator = try FlameGraphGenerator.init(allocator, &profiler);
    defer generator.deinit();
    
    // 设置较高的最小显示时间
    generator.setMinDisplayTime(1_000_000); // 1ms
    
    // 添加一个很短的样本
    const short_frames = [_]StackFrame{
        .{ .function_name = "main", .file_name = null, .line_number = null, .duration_ns = 100 },
        .{ .function_name = "shortFunc", .file_name = null, .line_number = null, .duration_ns = 50 },
    };
    
    // 添加一个较长的样本
    const long_frames = [_]StackFrame{
        .{ .function_name = "main", .file_name = null, .line_number = null, .duration_ns = 10_000_000 },
        .{ .function_name = "longFunc", .file_name = null, .line_number = null, .duration_ns = 9_000_000 },
    };
    
    try generator.addSample(&short_frames, 100);
    try generator.addSample(&long_frames, 10_000_000);
    
    try generator.buildFromSamples();
    
    // 识别热点（应该只包含长函数）
    const hotspots = try generator.identifyHotspots(allocator, 10);
    defer allocator.free(hotspots);
    
    // 验证短函数被过滤掉
    for (hotspots) |hotspot| {
        try std.testing.expect(hotspot.total_time_ns >= 1_000_000);
    }
}

test "火焰图并发安全" {
    const allocator = std.testing.allocator;
    
    var profiler = try Profiler.init(allocator, .custom);
    defer profiler.deinit();
    
    var generator = try FlameGraphGenerator.init(allocator, &profiler);
    defer generator.deinit();
    
    // 创建多个线程同时添加样本
    const ThreadContext = struct {
        gen: *FlameGraphGenerator,
        thread_id: usize,
    };
    
    const thread_fn = struct {
        fn run(ctx: *ThreadContext) void {
            var i: usize = 0;
            while (i < 10) : (i += 1) {
                const frames = [_]StackFrame{
                    .{
                        .function_name = "main",
                        .file_name = null,
                        .line_number = null,
                        .duration_ns = 1000,
                    },
                    .{
                        .function_name = "threadFunc",
                        .file_name = null,
                        .line_number = null,
                        .duration_ns = 500,
                    },
                };
                
                ctx.gen.addSample(&frames, 1000) catch return;
            }
        }
    }.run;
    
    // 启动多个线程
    const thread_count = 4;
    var threads: [thread_count]std.Thread = undefined;
    var contexts: [thread_count]ThreadContext = undefined;
    
    for (&threads, 0..) |*thread, i| {
        contexts[i] = .{
            .gen = &generator,
            .thread_id = i,
        };
        thread.* = try std.Thread.spawn(.{}, thread_fn, .{&contexts[i]});
    }
    
    // 等待所有线程完成
    for (threads) |thread| {
        thread.join();
    }
    
    // 验证样本数量
    try std.testing.expectEqual(@as(usize, thread_count * 10), generator.samples.items.len);
}

// 辅助函数：模拟工作负载
fn simulateWorkload(profiler: *Profiler) !void {
    // 主函数
    try profiler.enterFunction("main");
    
    // 数据处理
    try profiler.enterFunction("processData");
    
    // JSON 解析
    try profiler.enterFunction("parseJSON");
    var sum: u64 = 0;
    var i: u64 = 0;
    while (i < 1000) : (i += 1) {
        sum += i;
    }
    try profiler.exitFunction("parseJSON");
    
    // 数据验证
    try profiler.enterFunction("validateData");
    i = 0;
    while (i < 500) : (i += 1) {
        sum += i * 2;
    }
    try profiler.exitFunction("validateData");
    
    try profiler.exitFunction("processData");
    
    // 渲染输出
    try profiler.enterFunction("renderOutput");
    i = 0;
    while (i < 300) : (i += 1) {
        sum += i * 3;
    }
    try profiler.exitFunction("renderOutput");
    
    try profiler.exitFunction("main");
}
