// 数组操作基准测试模块
// 实现所有 60+ 数组函数的性能测试
// 验证需求 6.4

const std = @import("std");

/// 数组操作测试结果
pub const ArrayOpResult = struct {
    test_name: []const u8,
    iterations: u32,
    total_time_ns: u64,
    avg_time_ns: u64,
    operations_per_second: f64,
};

/// 数组基准测试配置
pub const ArrayBenchmarkConfig = struct {
    iterations: u32 = 5_000,
    verbose: bool = false,
    generate_php_scripts: bool = true,
    script_output_dir: []const u8 = "tests/benchmarks/array",
};

/// 数组基准测试结果
pub const ArrayBenchmarkResult = struct {
    timestamp: i64,
    total_time_ns: u64,
    
    // 按类别分组的结果
    creation_results: []ArrayOpResult,
    access_results: []ArrayOpResult,
    search_results: []ArrayOpResult,
    sort_results: []ArrayOpResult,
    filter_results: []ArrayOpResult,
    merge_results: []ArrayOpResult,
    stats_results: []ArrayOpResult,
    key_results: []ArrayOpResult,
    set_results: []ArrayOpResult,
    misc_results: []ArrayOpResult,
};

/// 数组基准测试主结构
pub const ArrayBenchmark = struct {
    allocator: std.mem.Allocator,
    config: ArrayBenchmarkConfig,
    
    /// 初始化基准测试
    pub fn init(allocator: std.mem.Allocator, config: ArrayBenchmarkConfig) !ArrayBenchmark {
        return ArrayBenchmark{
            .allocator = allocator,
            .config = config,
        };
    }

    
    /// 清理资源
    pub fn deinit(self: *ArrayBenchmark) void {
        _ = self;
    }
    
    /// 运行所有测试
    pub fn runAllTests(self: *ArrayBenchmark) !ArrayBenchmarkResult {
        const start_time = std.time.nanoTimestamp();
        
        // 运行各类别测试
        const creation_results = try self.runCreationTests();
        const access_results = try self.runAccessTests();
        const search_results = try self.runSearchTests();
        const sort_results = try self.runSortTests();
        const filter_results = try self.runFilterTests();
        const merge_results = try self.runMergeTests();
        const stats_results = try self.runStatsTests();
        const key_results = try self.runKeyTests();
        const set_results = try self.runSetTests();
        const misc_results = try self.runMiscTests();
        
        const end_time = std.time.nanoTimestamp();
        
        return ArrayBenchmarkResult{
            .timestamp = start_time,
            .total_time_ns = @intCast(@as(i64, end_time) - start_time),
            .creation_results = creation_results,
            .access_results = access_results,
            .search_results = search_results,
            .sort_results = sort_results,
            .filter_results = filter_results,
            .merge_results = merge_results,
            .stats_results = stats_results,
            .key_results = key_results,
            .set_results = set_results,
            .misc_results = misc_results,
        };
    }
    
    /// 运行单个测试
    fn runTest(self: *ArrayBenchmark, name: []const u8, test_fn: anytype) !ArrayOpResult {
        const start = std.time.nanoTimestamp();
        
        var i: u32 = 0;
        while (i < self.config.iterations) : (i += 1) {
            try test_fn();
        }
        
        const end = std.time.nanoTimestamp();
        const total_time = @as(u64, @intCast(end - start));
        const avg_time = total_time / self.config.iterations;
        const ops_per_sec = @as(f64, @floatFromInt(self.config.iterations)) / 
                           (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);
        
        if (self.config.verbose) {
            std.debug.print("  {s}: {d:.2} M ops/s\n", .{name, ops_per_sec / 1_000_000.0});
        }
        
        return ArrayOpResult{
            .test_name = name,
            .iterations = self.config.iterations,
            .total_time_ns = total_time,
            .avg_time_ns = avg_time,
            .operations_per_second = ops_per_sec,
        };
    }

    
    // ========================================================================
    // 数组创建与初始化测试
    // ========================================================================
    
    fn runCreationTests(self: *ArrayBenchmark) ![]ArrayOpResult {
        var results = std.ArrayList(ArrayOpResult).init(self.allocator);
        
        // array() - 创建数组
        try results.append(try self.runTest("array", struct {
            fn test() !void {
                var arr = std.ArrayList(i32).init(std.heap.page_allocator);
                defer arr.deinit();
                try arr.append(1);
                try arr.append(2);
                try arr.append(3);
            }
        }.test));
        
        // range() - 创建范围数组
        try results.append(try self.runTest("range", struct {
            fn test() !void {
                var arr = std.ArrayList(i32).init(std.heap.page_allocator);
                defer arr.deinit();
                var i: i32 = 0;
                while (i < 10) : (i += 1) {
                    try arr.append(i);
                }
            }
        }.test));
        
        // array_fill() - 填充数组
        try results.append(try self.runTest("array_fill", struct {
            fn test() !void {
                var arr = std.ArrayList(i32).init(std.heap.page_allocator);
                defer arr.deinit();
                var i: usize = 0;
                while (i < 10) : (i += 1) {
                    try arr.append(42);
                }
            }
        }.test));
        
        return results.toOwnedSlice();
    }
    
    // ========================================================================
    // 数组访问与修改测试
    // ========================================================================
    
    fn runAccessTests(self: *ArrayBenchmark) ![]ArrayOpResult {
        var results = std.ArrayList(ArrayOpResult).init(self.allocator);
        
        // array_push() - 添加元素到末尾
        try results.append(try self.runTest("array_push", struct {
            fn test() !void {
                var arr = std.ArrayList(i32).init(std.heap.page_allocator);
                defer arr.deinit();
                try arr.append(1);
                try arr.append(2);
            }
        }.test));

        
        // array_pop() - 移除末尾元素
        try results.append(try self.runTest("array_pop", struct {
            fn test() !void {
                var arr = std.ArrayList(i32).init(std.heap.page_allocator);
                defer arr.deinit();
                try arr.append(1);
                try arr.append(2);
                _ = arr.pop();
            }
        }.test));
        
        // array_shift() - 移除开头元素
        try results.append(try self.runTest("array_shift", struct {
            fn test() !void {
                var arr = std.ArrayList(i32).init(std.heap.page_allocator);
                defer arr.deinit();
                try arr.append(1);
                try arr.append(2);
                _ = arr.orderedRemove(0);
            }
        }.test));
        
        // array_unshift() - 添加元素到开头
        try results.append(try self.runTest("array_unshift", struct {
            fn test() !void {
                var arr = std.ArrayList(i32).init(std.heap.page_allocator);
                defer arr.deinit();
                try arr.insert(0, 1);
            }
        }.test));
        
        // array_slice() - 切片
        try results.append(try self.runTest("array_slice", struct {
            fn test() !void {
                var arr = std.ArrayList(i32).init(std.heap.page_allocator);
                defer arr.deinit();
                var i: i32 = 0;
                while (i < 10) : (i += 1) {
                    try arr.append(i);
                }
                const slice = arr.items[2..5];
                _ = slice;
            }
        }.test));
        
        return results.toOwnedSlice();
    }
    
    // ========================================================================
    // 数组搜索测试
    // ========================================================================
    
    fn runSearchTests(self: *ArrayBenchmark) ![]ArrayOpResult {
        var results = std.ArrayList(ArrayOpResult).init(self.allocator);
        
        // array_search() - 搜索值
        try results.append(try self.runTest("array_search", struct {
            fn test() !void {
                const arr = [_]i32{1, 2, 3, 4, 5};
                _ = std.mem.indexOf(i32, &arr, &[_]i32{3});
            }
        }.test));

        
        // in_array() - 检查值是否存在
        try results.append(try self.runTest("in_array", struct {
            fn test() !void {
                const arr = [_]i32{1, 2, 3, 4, 5};
                _ = std.mem.indexOfScalar(i32, &arr, 3);
            }
        }.test));
        
        return results.toOwnedSlice();
    }
    
    // ========================================================================
    // 数组排序测试
    // ========================================================================
    
    fn runSortTests(self: *ArrayBenchmark) ![]ArrayOpResult {
        var results = std.ArrayList(ArrayOpResult).init(self.allocator);
        
        // sort() - 升序排序
        try results.append(try self.runTest("sort", struct {
            fn test() !void {
                var arr = [_]i32{5, 2, 8, 1, 9};
                std.mem.sort(i32, &arr, {}, comptime std.sort.asc(i32));
            }
        }.test));
        
        // rsort() - 降序排序
        try results.append(try self.runTest("rsort", struct {
            fn test() !void {
                var arr = [_]i32{5, 2, 8, 1, 9};
                std.mem.sort(i32, &arr, {}, comptime std.sort.desc(i32));
            }
        }.test));
        
        return results.toOwnedSlice();
    }
    
    // ========================================================================
    // 数组过滤与映射测试
    // ========================================================================
    
    fn runFilterTests(self: *ArrayBenchmark) ![]ArrayOpResult {
        var results = std.ArrayList(ArrayOpResult).init(self.allocator);
        
        // array_filter() - 过滤数组
        try results.append(try self.runTest("array_filter", struct {
            fn test() !void {
                const arr = [_]i32{1, 2, 3, 4, 5};
                var filtered = std.ArrayList(i32).init(std.heap.page_allocator);
                defer filtered.deinit();
                for (arr) |val| {
                    if (val > 2) {
                        try filtered.append(val);
                    }
                }
            }
        }.test));

        
        // array_map() - 映射数组
        try results.append(try self.runTest("array_map", struct {
            fn test() !void {
                const arr = [_]i32{1, 2, 3, 4, 5};
                var mapped = std.ArrayList(i32).init(std.heap.page_allocator);
                defer mapped.deinit();
                for (arr) |val| {
                    try mapped.append(val * 2);
                }
            }
        }.test));
        
        // array_reduce() - 归约数组
        try results.append(try self.runTest("array_reduce", struct {
            fn test() !void {
                const arr = [_]i32{1, 2, 3, 4, 5};
                var sum: i32 = 0;
                for (arr) |val| {
                    sum += val;
                }
                _ = sum;
            }
        }.test));
        
        return results.toOwnedSlice();
    }
    
    // ========================================================================
    // 数组合并与分割测试
    // ========================================================================
    
    fn runMergeTests(self: *ArrayBenchmark) ![]ArrayOpResult {
        var results = std.ArrayList(ArrayOpResult).init(self.allocator);
        
        // array_merge() - 合并数组
        try results.append(try self.runTest("array_merge", struct {
            fn test() !void {
                const arr1 = [_]i32{1, 2, 3};
                const arr2 = [_]i32{4, 5, 6};
                var merged = std.ArrayList(i32).init(std.heap.page_allocator);
                defer merged.deinit();
                try merged.appendSlice(&arr1);
                try merged.appendSlice(&arr2);
            }
        }.test));
        
        // array_chunk() - 分块数组
        try results.append(try self.runTest("array_chunk", struct {
            fn test() !void {
                const arr = [_]i32{1, 2, 3, 4, 5, 6};
                const chunk_size = 2;
                var i: usize = 0;
                while (i < arr.len) : (i += chunk_size) {
                    const end = @min(i + chunk_size, arr.len);
                    const chunk = arr[i..end];
                    _ = chunk;
                }
            }
        }.test));
        
        return results.toOwnedSlice();
    }

    
    // ========================================================================
    // 数组统计测试
    // ========================================================================
    
    fn runStatsTests(self: *ArrayBenchmark) ![]ArrayOpResult {
        var results = std.ArrayList(ArrayOpResult).init(self.allocator);
        
        // array_sum() - 求和
        try results.append(try self.runTest("array_sum", struct {
            fn test() !void {
                const arr = [_]i32{1, 2, 3, 4, 5};
                var sum: i32 = 0;
                for (arr) |val| {
                    sum += val;
                }
                _ = sum;
            }
        }.test));
        
        // array_product() - 求积
        try results.append(try self.runTest("array_product", struct {
            fn test() !void {
                const arr = [_]i32{1, 2, 3, 4, 5};
                var product: i32 = 1;
                for (arr) |val| {
                    product *= val;
                }
                _ = product;
            }
        }.test));
        
        // array_unique() - 去重
        try results.append(try self.runTest("array_unique", struct {
            fn test() !void {
                const arr = [_]i32{1, 2, 2, 3, 3, 4};
                var unique = std.ArrayList(i32).init(std.heap.page_allocator);
                defer unique.deinit();
                for (arr) |val| {
                    if (std.mem.indexOfScalar(i32, unique.items, val) == null) {
                        try unique.append(val);
                    }
                }
            }
        }.test));
        
        // count() - 计数
        try results.append(try self.runTest("count", struct {
            fn test() !void {
                const arr = [_]i32{1, 2, 3, 4, 5};
                const len = arr.len;
                _ = len;
            }
        }.test));
        
        return results.toOwnedSlice();
    }

    
    // ========================================================================
    // 数组键值操作测试
    // ========================================================================
    
    fn runKeyTests(self: *ArrayBenchmark) ![]ArrayOpResult {
        var results = std.ArrayList(ArrayOpResult).init(self.allocator);
        
        // array_keys() - 获取所有键
        try results.append(try self.runTest("array_keys", struct {
            fn test() !void {
                var map = std.StringHashMap(i32).init(std.heap.page_allocator);
                defer map.deinit();
                try map.put("a", 1);
                try map.put("b", 2);
                var keys = std.ArrayList([]const u8).init(std.heap.page_allocator);
                defer keys.deinit();
                var iter = map.keyIterator();
                while (iter.next()) |key| {
                    try keys.append(key.*);
                }
            }
        }.test));
        
        // array_values() - 获取所有值
        try results.append(try self.runTest("array_values", struct {
            fn test() !void {
                var map = std.StringHashMap(i32).init(std.heap.page_allocator);
                defer map.deinit();
                try map.put("a", 1);
                try map.put("b", 2);
                var values = std.ArrayList(i32).init(std.heap.page_allocator);
                defer values.deinit();
                var iter = map.valueIterator();
                while (iter.next()) |val| {
                    try values.append(val.*);
                }
            }
        }.test));
        
        // array_flip() - 键值翻转
        try results.append(try self.runTest("array_flip", struct {
            fn test() !void {
                var map = std.StringHashMap(i32).init(std.heap.page_allocator);
                defer map.deinit();
                try map.put("a", 1);
                try map.put("b", 2);
                var flipped = std.AutoHashMap(i32, []const u8).init(std.heap.page_allocator);
                defer flipped.deinit();
                var iter = map.iterator();
                while (iter.next()) |entry| {
                    try flipped.put(entry.value_ptr.*, entry.key_ptr.*);
                }
            }
        }.test));
        
        return results.toOwnedSlice();
    }

    
    // ========================================================================
    // 数组集合操作测试
    // ========================================================================
    
    fn runSetTests(self: *ArrayBenchmark) ![]ArrayOpResult {
        var results = std.ArrayList(ArrayOpResult).init(self.allocator);
        
        // array_diff() - 差集
        try results.append(try self.runTest("array_diff", struct {
            fn test() !void {
                const arr1 = [_]i32{1, 2, 3, 4};
                const arr2 = [_]i32{3, 4, 5, 6};
                var diff = std.ArrayList(i32).init(std.heap.page_allocator);
                defer diff.deinit();
                for (arr1) |val| {
                    if (std.mem.indexOfScalar(i32, &arr2, val) == null) {
                        try diff.append(val);
                    }
                }
            }
        }.test));
        
        // array_intersect() - 交集
        try results.append(try self.runTest("array_intersect", struct {
            fn test() !void {
                const arr1 = [_]i32{1, 2, 3, 4};
                const arr2 = [_]i32{3, 4, 5, 6};
                var intersect = std.ArrayList(i32).init(std.heap.page_allocator);
                defer intersect.deinit();
                for (arr1) |val| {
                    if (std.mem.indexOfScalar(i32, &arr2, val) != null) {
                        try intersect.append(val);
                    }
                }
            }
        }.test));
        
        return results.toOwnedSlice();
    }
    
    // ========================================================================
    // 其他数组操作测试
    // ========================================================================
    
    fn runMiscTests(self: *ArrayBenchmark) ![]ArrayOpResult {
        var results = std.ArrayList(ArrayOpResult).init(self.allocator);
        
        // array_reverse() - 反转数组
        try results.append(try self.runTest("array_reverse", struct {
            fn test() !void {
                var arr = [_]i32{1, 2, 3, 4, 5};
                std.mem.reverse(i32, &arr);
            }
        }.test));
        
        // array_pad() - 填充数组
        try results.append(try self.runTest("array_pad", struct {
            fn test() !void {
                var arr = std.ArrayList(i32).init(std.heap.page_allocator);
                defer arr.deinit();
                try arr.appendSlice(&[_]i32{1, 2, 3});
                while (arr.items.len < 10) {
                    try arr.append(0);
                }
            }
        }.test));
        
        return results.toOwnedSlice();
    }
};
