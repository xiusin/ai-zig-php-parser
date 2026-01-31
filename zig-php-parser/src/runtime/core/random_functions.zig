//! 随机数核心函数实现
//!
//! 提供与执行模式无关的随机数生成核心逻辑。
//!
//! @ownership TRANSFER (返回的字节数组由调用者负责释放)
//! @thread-safety ISOLATED (使用线程局部 PRNG)

const std = @import("std");
const Allocator = std.mem.Allocator;
const common = @import("common.zig");
const CoreContext = common.CoreContext;
const CoreError = common.CoreError;

/// 默认 PRNG 类型
const DefaultPrng = std.Random.DefaultPrng;

/// 线程局部随机数生成器状态
threadlocal var thread_prng: ?DefaultPrng = null;

/// 获取或初始化线程局部 PRNG
fn getPrng() *DefaultPrng {
    if (thread_prng == null) {
        const ts = std.time.nanoTimestamp();
        const seed: u64 = @truncate(@as(u128, @bitCast(ts)));
        thread_prng = DefaultPrng.init(seed);
    }
    return &thread_prng.?;
}

/// srand - 设置随机数种子
/// @param seed 种子值
pub fn srand(seed: u64) void {
    thread_prng = DefaultPrng.init(seed);
}

/// mt_srand - 设置 Mersenne Twister 种子（与 srand 相同）
/// @param seed 种子值
pub fn mt_srand(seed: u64) void {
    srand(seed);
}

/// rand - 生成随机整数
/// @param min_val 最小值（可选）
/// @param max_val 最大值（可选）
/// @return 随机整数
pub fn rand(min_val: ?i64, max_val: ?i64) i64 {
    const prng = getPrng();
    const random = prng.random();

    const min = min_val orelse 0;
    const max = max_val orelse std.math.maxInt(i32);

    if (min >= max) return min;

    const range: u64 = @intCast(max - min + 1);
    const rand_val = random.intRangeLessThan(u64, 0, range);
    return min + @as(i64, @intCast(rand_val));
}

/// mt_rand - Mersenne Twister 随机数（与 rand 相同）
/// @param min_val 最小值（可选）
/// @param max_val 最大值（可选）
/// @return 随机整数
pub fn mt_rand(min_val: ?i64, max_val: ?i64) i64 {
    return rand(min_val, max_val);
}

/// random_int - 加密安全随机整数
/// @param min_val 最小值
/// @param max_val 最大值
/// @return 随机整数
pub fn random_int(min_val: i64, max_val: i64) !i64 {
    if (min_val > max_val) return CoreError.InvalidArgument;

    if (min_val == max_val) return min_val;

    const range: u64 = @intCast(max_val - min_val + 1);
    var rand_val: u64 = 0;
    std.crypto.random.bytes(std.mem.asBytes(&rand_val));
    return min_val + @as(i64, @intCast(rand_val % range));
}

/// random_bytes - 生成加密安全随机字节
/// @param ctx 上下文
/// @param length 字节长度
/// @return 随机字节数组（调用者负责释放）
pub fn random_bytes(ctx: *CoreContext, length: usize) ![]u8 {
    if (length == 0) {
        return try ctx.allocator.alloc(u8, 0);
    }

    if (length > 100 * 1024 * 1024) {
        return CoreError.InvalidArgument;
    }

    const result = try ctx.allocator.alloc(u8, length);
    errdefer ctx.allocator.free(result);

    std.crypto.random.bytes(result);
    return result;
}

/// shuffle_array - 随机打乱数组（Fisher-Yates 算法）
/// @param array 要打乱的数组（原地修改）
pub fn shuffle_array(comptime T: type, array: []T) void {
    if (array.len <= 1) return;

    const prng = getPrng();
    const random = prng.random();

    var i: usize = array.len - 1;
    while (i > 0) : (i -= 1) {
        const j = random.intRangeLessThan(usize, 0, i + 1);
        const tmp = array[i];
        array[i] = array[j];
        array[j] = tmp;
    }
}

/// array_rand - 从数组中随机选择索引
/// @param array_len 数组长度
/// @param num 选择数量
/// @return 随机索引数组（调用者负责释放）
pub fn array_rand(ctx: *CoreContext, array_len: usize, num: usize) ![]usize {
    if (array_len == 0 or num == 0) {
        return try ctx.allocator.alloc(usize, 0);
    }

    const actual_num = @min(num, array_len);
    const result = try ctx.allocator.alloc(usize, actual_num);
    errdefer ctx.allocator.free(result);

    if (actual_num == 1) {
        result[0] = rand(0, @as(i64, @intCast(array_len - 1)));
        return result;
    }

    var indices = try ctx.allocator.alloc(usize, array_len);
    defer ctx.allocator.free(indices);

    for (indices, 0..) |*idx, i| {
        idx.* = i;
    }

    shuffle_array(usize, indices);
    @memcpy(result, indices[0..actual_num]);

    return result;
}

/// getrandmax - 获取随机数最大值
/// @return 最大随机数值
pub fn getrandmax() i64 {
    return std.math.maxInt(i32);
}

/// mt_getrandmax - 获取 MT 随机数最大值
/// @return 最大随机数值
pub fn mt_getrandmax() i64 {
    return std.math.maxInt(i32);
}

// ============================================================================
// 测试
// ============================================================================

test "srand and rand" {
    srand(12345);
    const r1 = rand(null, null);

    srand(12345);
    const r2 = rand(null, null);

    try std.testing.expectEqual(r1, r2);
}

test "rand with range" {
    for (0..100) |_| {
        const r = rand(10, 20);
        try std.testing.expect(r >= 10 and r <= 20);
    }
}

test "random_int" {
    for (0..100) |_| {
        const r = try random_int(1, 100);
        try std.testing.expect(r >= 1 and r <= 100);
    }
}

test "random_bytes" {
    var ctx = CoreContext.init(std.testing.allocator);

    const bytes = try random_bytes(&ctx, 16);
    defer ctx.allocator.free(bytes);

    try std.testing.expectEqual(@as(usize, 16), bytes.len);
}

test "shuffle_array" {
    var arr = [_]i32{ 1, 2, 3, 4, 5 };
    srand(42);
    shuffle_array(i32, &arr);

    var sum: i32 = 0;
    for (arr) |v| sum += v;
    try std.testing.expectEqual(@as(i32, 15), sum);
}

test "getrandmax" {
    try std.testing.expectEqual(std.math.maxInt(i32), getrandmax());
}
