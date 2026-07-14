//! 哈希内置函数实现模块
//! 从 stdlib.zig 拆分而来 — 包含 SHA256/SHA512/hash/hash_algos 函数
//! 注意：md5Fn 和 sha1Fn 在 stdlib_string.zig 中

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const exceptions = @import("exceptions.zig");
const ExceptionFactory = exceptions.ExceptionFactory;
const VM = @import("vm.zig").VM;

// 字符串函数模块（hashFn 引用 md5Fn/sha1Fn）
const stdlib_string = @import("stdlib_string.zig");

// Hash Function Implementations
pub fn sha256Fn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const raw_output = if (args.len > 1) args[1].toBool() else false;

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "sha256() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const input = str.getAsString().data.data;
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(input);
    var hash: [32]u8 = undefined;
    hasher.final(&hash);

    if (raw_output) {
        const result_str = try PHPString.init(vm.allocator, &hash);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    } else {
        var hex_buffer: [64]u8 = undefined;
        const hex_chars = "0123456789abcdef";
        for (hash, 0..) |byte, i| {
            hex_buffer[i * 2] = hex_chars[byte >> 4];
            hex_buffer[i * 2 + 1] = hex_chars[byte & 0x0f];
        }

        const result_str = try PHPString.init(vm.allocator, &hex_buffer);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    }
}

pub fn sha512Fn(vm: *VM, args: []const Value) !Value {
    const str = args[0];
    const raw_output = if (args.len > 1) args[1].toBool() else false;

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "sha512() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const input = str.getAsString().data.data;
    var hasher = std.crypto.hash.sha2.Sha512.init(.{});
    hasher.update(input);
    var hash: [64]u8 = undefined;
    hasher.final(&hash);

    if (raw_output) {
        const result_str = try PHPString.init(vm.allocator, &hash);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    } else {
        var hex_buffer: [128]u8 = undefined;
        const hex_chars = "0123456789abcdef";
        for (hash, 0..) |byte, i| {
            hex_buffer[i * 2] = hex_chars[byte >> 4];
            hex_buffer[i * 2 + 1] = hex_chars[byte & 0x0f];
        }

        const result_str = try PHPString.init(vm.allocator, &hex_buffer);

        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_str,
        };

        return Value.fromBox(box, Value.TYPE_STRING);
    }
}

pub fn hashFn(vm: *VM, args: []const Value) !Value {
    const algo = args[0];
    const data = args[1];
    const raw_output = if (args.len > 2) args[2].toBool() else false;

    if (algo.getTag() != .string or data.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "hash() expects parameters 1 and 2 to be strings", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const algorithm = algo.getAsString().data.data;

    if (std.mem.eql(u8, algorithm, "md5")) {
        return stdlib_string.md5Fn(vm, &[_]Value{ data, Value.initBool(raw_output) });
    } else if (std.mem.eql(u8, algorithm, "sha1")) {
        return stdlib_string.sha1Fn(vm, &[_]Value{ data, Value.initBool(raw_output) });
    } else if (std.mem.eql(u8, algorithm, "sha256")) {
        return sha256Fn(vm, &[_]Value{ data, Value.initBool(raw_output) });
    } else if (std.mem.eql(u8, algorithm, "sha512")) {
        return sha512Fn(vm, &[_]Value{ data, Value.initBool(raw_output) });
    } else {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "hash(): Unknown hashing algorithm", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }
}

pub fn hashAlgosFn(vm: *VM, args: []const Value) !Value {
    _ = args;

    var result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    const algorithms = [_][]const u8{ "md5", "sha1", "sha256", "sha512" };

    for (algorithms) |algo| {
        const algo_str = try Value.initString(vm.allocator, algo);
        try result_array.push(vm.allocator, algo_str);
        vm.releaseValue(algo_str);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

/// crc32() — 计算 CRC32 校验和
pub fn crc32Fn(vm: *VM, args: []const Value) !Value {
    const str = args[0];

    if (str.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "crc32() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const input = str.getAsString().data.data;

    // CRC32 with standard polynomial (0xEDB88320 reflected)
    var crc: u32 = 0xFFFFFFFF;
    for (input) |byte| {
        crc ^= byte;
        var i: usize = 0;
        while (i < 8) : (i += 1) {
            if (crc & 1 != 0) {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc >>= 1;
            }
        }
    }
    crc ^= 0xFFFFFFFF;

    // PHP returns CRC32 as a signed integer on 32-bit, unsigned on 64-bit
    // We return as unsigned since we use i64
    return Value.initInt(@intCast(crc));
}

// ============================================================================
// 单元测试
// ============================================================================

test "stdlib_hash: handler functions exist" {
    _ = &sha256Fn;
    _ = &sha512Fn;
    _ = &hashFn;
    _ = &hashAlgosFn;
}

test "stdlib_hash: SHA256 output size" {
    // SHA256 产生 32 字节哈希，hex 编码为 64 字符
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("test");
    var hash: [32]u8 = undefined;
    hasher.final(&hash);
    try std.testing.expectEqual(@as(usize, 32), hash.len);
}

test "stdlib_hash: SHA512 output size" {
    // SHA512 产生 64 字节哈希，hex 编码为 128 字符
    var hasher = std.crypto.hash.sha2.Sha512.init(.{});
    hasher.update("test");
    var hash: [64]u8 = undefined;
    hasher.final(&hash);
    try std.testing.expectEqual(@as(usize, 64), hash.len);
}

test "stdlib_hash: SHA256 hex encoding correctness" {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("hello");
    var hash: [32]u8 = undefined;
    hasher.final(&hash);

    var hex_buffer: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex_buffer[i * 2] = hex_chars[byte >> 4];
        hex_buffer[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    // SHA256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
    try std.testing.expectEqualStrings("2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", &hex_buffer);
}

test "stdlib_hash: SHA512 hex encoding produces correct length" {
    var hasher = std.crypto.hash.sha2.Sha512.init(.{});
    hasher.update("test");
    var hash: [64]u8 = undefined;
    hasher.final(&hash);

    var hex_buffer: [128]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        hex_buffer[i * 2] = hex_chars[byte >> 4];
        hex_buffer[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    // hex 编码长度应该是 128 字符
    try std.testing.expectEqual(@as(usize, 128), hex_buffer.len);
}

test "stdlib_hash: SHA256 deterministic" {
    var hasher1 = std.crypto.hash.sha2.Sha256.init(.{});
    hasher1.update("deterministic");
    var hash1: [32]u8 = undefined;
    hasher1.final(&hash1);

    var hasher2 = std.crypto.hash.sha2.Sha256.init(.{});
    hasher2.update("deterministic");
    var hash2: [32]u8 = undefined;
    hasher2.final(&hash2);

    try std.testing.expect(std.mem.eql(u8, &hash1, &hash2));
}
