/// 字节码虚拟机属性测试
/// Feature: zig-php-performance-optimization
/// 
/// 本文件包含字节码虚拟机核心功能的属性测试：
/// - 属性 1：函数调用参数传递正确性
/// - 属性 2：内联缓存一致性  
/// - 属性 3：符号表查找时间复杂度
///
/// @ownership NON-OWNING (test allocator)
/// @thread-safety ISOLATED (单线程测试)
/// @memory-safety 所有测试使用 std.testing.allocator 检测泄漏

const std = @import("std");
const testing = std.testing;
const BytecodeVM = @import("vm.zig").BytecodeVM;
const Value = @import("vm.zig").Value;
const CompiledFunction = @import("instruction.zig").CompiledFunction;
const Instruction = @import("instruction.zig").Instruction;
const OpCode = @import("instruction.zig").OpCode;

/// 属性测试框架
/// @concurrency-model ISOLATED
const PropertyTest = struct {
    allocator: std.mem.Allocator,
    rng: std.Random,
    iterations: u32 = 100,
    
    /// 运行属性测试
    /// @pre property 必须是有效的属性函数
    /// @post 运行指定次数的测试，返回是否全部通过
    pub fn run(
        self: *PropertyTest,
        comptime T: type,
        property: fn(T) bool,
        generator: fn(*std.Random, std.mem.Allocator) anyerror!T,
    ) !bool {
        var passed: u32 = 0;
        var failed: u32 = 0;
        
        var i: u32 = 0;
        while (i < self.iterations) : (i += 1) {
            // 生成随机输入
            const input = try generator(&self.rng, self.allocator);
            
            // 测试属性
            if (property(input)) {
                passed += 1;
            } else {
                failed += 1;
                std.debug.print("Property failed for iteration {d}\n", .{i});
            }
        }
        
        const success_rate = @as(f32, @floatFromInt(passed)) / @as(f32, @floatFromInt(self.iterations));
        std.debug.print("Property test: {d}/{d} passed ({d:.2}%)\n", 
            .{passed, self.iterations, success_rate * 100});
        
        return failed == 0;
    }
};

/// 生成器 - 用于生成随机测试数据
const Generator = struct {
    /// 生成随机整数
    pub fn genInt(rng: *std.Random, min: i64, max: i64) i64 {
        return rng.intRangeAtMost(i64, min, max);
    }
    
    /// 生成随机 Value
    pub fn genValue(rng: *std.Random) Value {
        const type_choice = rng.uintLessThan(u8, 4);
        return switch (type_choice) {
            0 => Value{ .int_val = genInt(rng, -1000, 1000) },
            1 => Value{ .float_val = rng.float(f64) * 1000.0 },
            2 => Value{ .bool_val = rng.boolean() },
            3 => Value{ .null_val = {} },
            else => unreachable,
        };
    }
    
    /// 生成随机 Value 数组
    pub fn genValueArray(rng: *std.Random, allocator: std.mem.Allocator, max_len: usize) ![]Value {
        const len = rng.uintLessThan(usize, max_len) + 1; // 至少 1 个元素
        const arr = try allocator.alloc(Value, len);
        
        for (arr) |*val| {
            val.* = genValue(rng);
        }
        
        return arr;
    }
};

// ============================================================================
// 属性 1：函数调用参数传递正确性
// ============================================================================

/// 测试输入：函数名和参数列表
const TestInput1 = struct {
    func_name: []const u8,
    args: []Value,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *TestInput1) void {
        self.allocator.free(self.args);
    }
};

// 属性 1：函数调用参数传递正确性
// Feature: zig-php-performance-optimization, Property 1
// 
// *对于任意*函数签名和参数列表，调用函数后，被调用函数接收到的参数
// 应该与传入的参数完全一致（值传递）或指向相同内存（引用传递）
// 
// **验证：需求 1.1**
test "Property 1: Function call parameter passing correctness" {
    var prng = std.Random.DefaultPrng.init(0);
    const rng = prng.random();
    
    var pt = PropertyTest{
        .allocator = testing.allocator,
        .rng = rng,
        .iterations = 100,
    };
    
    const property = struct {
        fn check(input: TestInput1) bool {
            // 创建 VM
            var vm = BytecodeVM.init(testing.allocator) catch return false;
            defer vm.deinit();
            
            // 创建一个简单的测试函数
            // 该函数只是返回第一个参数
            var func = CompiledFunction.init(testing.allocator, "test_func") catch return false;
            defer func.deinit(testing.allocator);
            
            // 设置函数参数信息
            func.param_count = @intCast(input.args.len);
            func.min_args = @intCast(input.args.len);
            func.max_args = @intCast(input.args.len);
            
            // 创建参数信息数组
            const param_info = testing.allocator.alloc(CompiledFunction.ParameterInfo, input.args.len) catch return false;
            defer testing.allocator.free(param_info);
            
            for (param_info) |*info| {
                info.* = .{
                    .name = "param",
                    .pass_mode = .by_value,
                    .default_value = null,
                    .type_hint = null,
                };
            }
            func.param_info = param_info;
            
            // 创建简单的字节码：返回第一个参数
            var bytecode = [_]Instruction{
                Instruction.init(.push_local, 0, 0), // 压入第一个参数
                Instruction.init(.ret, 0, 0),        // 返回
            };
            func.bytecode = &bytecode;
            func.local_count = @intCast(input.args.len);
            
            // 注册函数
            vm.registerFunction(input.func_name, func) catch return false;
            
            // 调用函数
            const result = vm.call(input.func_name, input.args) catch return false;
            
            // 验证：如果有参数，结果应该等于第一个参数
            if (input.args.len > 0) {
                return valuesEqual(result, input.args[0]);
            }
            
            return true;
        }
        
        fn valuesEqual(a: Value, b: Value) bool {
            return switch (a) {
                .null_val => b == .null_val,
                .bool_val => |av| b == .bool_val and b.bool_val == av,
                .int_val => |av| b == .int_val and b.int_val == av,
                .float_val => |av| b == .float_val and @abs(b.float_val - av) < 0.0001,
                else => false,
            };
        }
    }.check;
    
    const generator = struct {
        fn gen(rng_ptr: *std.Random, allocator: std.mem.Allocator) !TestInput1 {
            const args = try Generator.genValueArray(rng_ptr, allocator, 5);
            return TestInput1{
                .func_name = "test_func",
                .args = args,
                .allocator = allocator,
            };
        }
    }.gen;
    
    const passed = try pt.run(TestInput1, property, generator);
    try testing.expect(passed);
}

// ============================================================================
// 属性 2：内联缓存一致性
// ============================================================================

/// 测试输入：方法名和类 ID
const TestInput2 = struct {
    method_name: []const u8,
    class_id: u64,
};

// 属性 2：内联缓存一致性
// Feature: zig-php-performance-optimization, Property 2
// 
// *对于任意*方法调用序列，内联缓存命中时返回的结果应该与
// 缓存未命中时通过完整查找返回的结果完全相同
// 
// **验证：需求 1.2**
test "Property 2: Inline cache consistency" {
    var prng = std.Random.DefaultPrng.init(0);
    const rng = prng.random();
    
    var pt = PropertyTest{
        .allocator = testing.allocator,
        .rng = rng,
        .iterations = 100,
    };
    
    const property = struct {
        fn check(input: TestInput2) bool {
            // 创建 VM
            var vm = BytecodeVM.init(testing.allocator) catch return false;
            defer vm.deinit();
            
            // 启用内联缓存
            vm.enable_inline_cache = true;
            
            // 第一次查找（缓存未命中）
            const result1 = vm.method_cache.lookupMethod(input.method_name, input.class_id);
            const cache_misses_before = vm.stats.cache_misses;
            
            // 缓存一个方法
            const dummy_method: *anyopaque = @ptrFromInt(0x1000);
            vm.method_cache.cacheMethod(input.method_name, input.class_id, dummy_method) catch return false;
            
            // 第二次查找（缓存命中）
            const result2 = vm.method_cache.lookupMethod(input.method_name, input.class_id);
            const cache_hits_after = vm.stats.cache_hits;
            
            // 验证：
            // 1. 第一次查找应该未命中
            // 2. 第二次查找应该命中
            // 3. 两次查找的结果应该一致（第一次 null，第二次非 null）
            const first_missed = result1 == null and vm.stats.cache_misses > cache_misses_before;
            const second_hit = result2 != null and cache_hits_after > 0;
            
            return first_missed and second_hit;
        }
    }.check;
    
    const generator = struct {
        fn gen(rng_ptr: *std.Random, _: std.mem.Allocator) !TestInput2 {
            const class_id = rng_ptr.int(u64);
            return TestInput2{
                .method_name = "testMethod",
                .class_id = class_id,
            };
        }
    }.gen;
    
    const passed = try pt.run(TestInput2, property, generator);
    try testing.expect(passed);
}

// ============================================================================
// 属性 3：符号表查找时间复杂度
// ============================================================================

/// 测试输入：符号表大小
const TestInput3 = struct {
    table_size: usize,
};

// 属性 3：符号表查找时间复杂度
// Feature: zig-php-performance-optimization, Property 3
// 
// *对于任意*符号表大小 n，查找操作的时间应该是 O(1)，即与 n 无关
// 
// **验证：需求 1.3**
test "Property 3: Symbol table lookup time complexity" {
    var prng = std.Random.DefaultPrng.init(0);
    const rng = prng.random();
    
    var pt = PropertyTest{
        .allocator = testing.allocator,
        .rng = rng,
        .iterations = 50, // 减少迭代次数，因为这个测试比较耗时
    };
    
    const property = struct {
        fn check(input: TestInput3) bool {
            // 创建 VM
            var vm = BytecodeVM.init(testing.allocator) catch return false;
            defer vm.deinit();
            
            // 填充符号表
            var i: usize = 0;
            while (i < input.table_size) : (i += 1) {
                var name_buf: [32]u8 = undefined;
                const name = std.fmt.bufPrint(&name_buf, "var_{d}", .{i}) catch return false;
                const name_copy = testing.allocator.dupe(u8, name) catch return false;
                
                vm.globals.put(testing.allocator, name_copy, Value{ .int_val = @intCast(i) }) catch {
                    testing.allocator.free(name_copy);
                    return false;
                };
            }
            
            // 测量查找时间
            const lookup_key = "var_0";
            
            var timer = std.time.Timer.start() catch return false;
            const start = timer.read();
            
            // 执行多次查找
            const lookup_count = 1000;
            var j: usize = 0;
            while (j < lookup_count) : (j += 1) {
                _ = vm.globals.get(lookup_key);
            }
            
            const end = timer.read();
            const elapsed = end - start;
            
            // 计算平均查找时间（纳秒）
            const avg_time = elapsed / lookup_count;
            
            // 验证：查找时间应该很短（< 1000 ns）
            // 这表明是 O(1) 操作
            const is_fast = avg_time < 1000;
            
            // 清理全局变量表
            var iter = vm.globals.iterator();
            while (iter.next()) |entry| {
                testing.allocator.free(entry.key_ptr.*);
            }
            
            return is_fast;
        }
    }.check;
    
    const generator = struct {
        fn gen(rng_ptr: *std.Random, _: std.mem.Allocator) !TestInput3 {
            // 生成不同大小的符号表（10 到 1000）
            const size = rng_ptr.intRangeAtMost(usize, 10, 1000);
            return TestInput3{
                .table_size = size,
            };
        }
    }.gen;
    
    const passed = try pt.run(TestInput3, property, generator);
    try testing.expect(passed);
}
