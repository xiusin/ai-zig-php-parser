//! ============================================================================
//! 随机数内置函数 (Random Builtin Functions)
//! ============================================================================
//!
//! 功能：实现PHP随机数相关的内置函数
//!
//! 支持的函数：
//! - rand(): 标准随机数生成
//! - mt_rand(): Mersenne Twister随机数生成
//! - srand(): 设置随机数种子
//! - mt_srand(): 设置MT随机数种子
//! - random_int(): 密码学安全的随机整数
//! - random_bytes(): 密码学安全的随机字节
//!
//! 特性：线程安全，支持线程本地存储
//! 需求：4.1, 4.2, 4.3, 4.4, 4.5, 4.6
//! ============================================================================

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const builtin_registry = @import("builtin_registry.zig");
const BuiltinFunction = builtin_registry.BuiltinFunction;
const BuiltinError = builtin_registry.BuiltinError;
const Category = builtin_registry.Category;

/// 随机数内置函数实现
/// Thread-safe random number generation implementation
/// Provides standard rand(), Mersenne Twister mt_rand(), and cryptographically secure random functions
pub const RandomBuiltins = struct {
    // Thread-local storage for random number generators
    threadlocal var rng: std.Random.DefaultPrng = undefined;
    threadlocal var mt_rng: std.Random.Xoshiro256 = undefined;
    threadlocal var rng_initialized: bool = false;
    threadlocal var mt_initialized: bool = false;
    
    // Global mutex for thread-safe seeding
    var seed_mutex: std.Thread.Mutex = .{};
    var global_seed: u64 = 0;
    
    /// Initialize thread-local RNG if not already done
    fn ensureRngInitialized() void {
        if (!rng_initialized) {
            seed_mutex.lock();
            defer seed_mutex.unlock();
            
            if (global_seed == 0) {
                global_seed = @intCast(std.time.timestamp());
            }
            
            rng = std.Random.DefaultPrng.init(global_seed);
            rng_initialized = true;
        }
    }
    
    /// Initialize thread-local Mersenne Twister if not already done
    fn ensureMtInitialized() void {
        if (!mt_initialized) {
            seed_mutex.lock();
            defer seed_mutex.unlock();
            
            if (global_seed == 0) {
                global_seed = @intCast(std.time.timestamp());
            }
            
            mt_rng = std.Random.Xoshiro256.init(global_seed);
            mt_initialized = true;
        }
    }
    
    /// PHP rand() - Returns random integer using linear congruential generator
    /// Requirements: 2.1, 2.2
    pub fn rand(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;
        
        ensureRngInitialized();
        
        if (args.len == 0) {
            // Return random integer between 0 and RAND_MAX (2^31 - 1)
            const random_val = rng.random().int(i32);
            return Value.initInt(@abs(random_val));
        } else if (args.len == 2) {
            // Get min and max values
            const min_val = switch (args[0].getTag()) {
                .integer => args[0].asInt(),
                .float => @as(i64, @intFromFloat(args[0].asFloat())),
                else => return BuiltinError.InvalidArgumentType,
            };
            
            const max_val = switch (args[1].getTag()) {
                .integer => args[1].asInt(),
                .float => @as(i64, @intFromFloat(args[1].asFloat())),
                else => return BuiltinError.InvalidArgumentType,
            };
            
            if (min_val > max_val) {
                return BuiltinError.InvalidArgumentType;
            }
            
            const random_val = rng.random().intRangeAtMost(i64, min_val, max_val);
            return Value.initInt(random_val);
        } else {
            return BuiltinError.ArgumentCountMismatch;
        }
    }
    
    /// PHP mt_rand() - Returns random integer using Mersenne Twister
    /// Requirements: 2.3, 2.4
    pub fn mt_rand(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;
        
        ensureMtInitialized();
        
        if (args.len == 0) {
            // Return random integer between 0 and MT_RAND_MAX (2^31 - 1)
            const random_val = mt_rng.random().int(i32);
            return Value.initInt(@abs(random_val));
        } else if (args.len == 2) {
            // Get min and max values
            const min_val = switch (args[0].getTag()) {
                .integer => args[0].asInt(),
                .float => @as(i64, @intFromFloat(args[0].asFloat())),
                else => return BuiltinError.InvalidArgumentType,
            };
            
            const max_val = switch (args[1].getTag()) {
                .integer => args[1].asInt(),
                .float => @as(i64, @intFromFloat(args[1].asFloat())),
                else => return BuiltinError.InvalidArgumentType,
            };
            
            if (min_val > max_val) {
                return BuiltinError.InvalidArgumentType;
            }
            
            const random_val = mt_rng.random().intRangeAtMost(i64, min_val, max_val);
            return Value.initInt(random_val);
        } else {
            return BuiltinError.ArgumentCountMismatch;
        }
    }
    
    /// PHP srand() - Seed the random number generator
    /// Requirements: 2.5
    pub fn srand(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;
        
        if (args.len > 1) {
            return BuiltinError.ArgumentCountMismatch;
        }
        
        const seed_val: u64 = if (args.len == 1) blk: {
            switch (args[0].getTag()) {
                .integer => break :blk @intCast(@abs(args[0].asInt())),
                .float => break :blk @as(u64, @intFromFloat(@abs(args[0].asFloat()))),
                else => return BuiltinError.InvalidArgumentType,
            }
        } else @intCast(std.time.timestamp());
        
        seed_mutex.lock();
        defer seed_mutex.unlock();
        
        global_seed = seed_val;
        rng = std.Random.DefaultPrng.init(seed_val);
        rng_initialized = true;
        
        return Value.initNull();
    }
    
    /// PHP mt_srand() - Seed the Mersenne Twister generator
    /// Requirements: 2.6
    pub fn mt_srand(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;
        
        if (args.len > 1) {
            return BuiltinError.ArgumentCountMismatch;
        }
        
        const seed_val: u64 = if (args.len == 1) blk: {
            switch (args[0].getTag()) {
                .integer => break :blk @intCast(@abs(args[0].asInt())),
                .float => break :blk @as(u64, @intFromFloat(@abs(args[0].asFloat()))),
                else => return BuiltinError.InvalidArgumentType,
            }
        } else @intCast(std.time.timestamp());
        
        seed_mutex.lock();
        defer seed_mutex.unlock();
        
        global_seed = seed_val;
        mt_rng = std.Random.Xoshiro256.init(seed_val);
        mt_initialized = true;
        
        return Value.initNull();
    }
    
    /// PHP random_int() - Cryptographically secure random integer
    /// Requirements: 2.7
    pub fn random_int(vm: *anyopaque, args: []const Value) !Value {
        _ = vm;
        
        if (args.len != 2) {
            return BuiltinError.ArgumentCountMismatch;
        }
        
        // Get min and max values
        const min_val = switch (args[0].getTag()) {
            .integer => args[0].asInt(),
            .float => @as(i64, @intFromFloat(args[0].asFloat())),
            else => return BuiltinError.InvalidArgumentType,
        };
        
        const max_val = switch (args[1].getTag()) {
            .integer => args[1].asInt(),
            .float => @as(i64, @intFromFloat(args[1].asFloat())),
            else => return BuiltinError.InvalidArgumentType,
        };
        
        if (min_val > max_val) {
            return BuiltinError.InvalidArgumentType;
        }
        
        // Use cryptographically secure random number generator
        const random_val = std.crypto.random.intRangeAtMost(i64, min_val, max_val);
        return Value.initInt(random_val);
    }
    
    /// PHP random_bytes() - Cryptographically secure random bytes
    /// Requirements: 2.8
    pub fn random_bytes(vm: *anyopaque, args: []const Value) !Value {
        if (args.len != 1) {
            return BuiltinError.ArgumentCountMismatch;
        }
        
        // Get length
        const length = switch (args[0].getTag()) {
            .integer => args[0].asInt(),
            .float => @as(i64, @intFromFloat(args[0].asFloat())),
            else => return BuiltinError.InvalidArgumentType,
        };
        
        if (length < 0) {
            return BuiltinError.InvalidArgumentType;
        }
        
        const len: usize = @intCast(length);
        
        // Get VM allocator
        const VM = @import("vm.zig").VM;
        const vm_ptr = @as(*VM, @ptrCast(@alignCast(vm)));
        
        // Allocate buffer for random bytes
        const buffer = try vm_ptr.allocator.alloc(u8, len);
        
        // Fill with cryptographically secure random bytes
        std.crypto.random.bytes(buffer);
        
        // Create PHP string from bytes
        const php_string = try types.PHPString.init(vm_ptr.allocator, buffer);
        const box = try vm_ptr.allocator.create(types.gc.Box(*types.PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_string,
        };
        
        // Clean up temporary buffer
        vm_ptr.allocator.free(buffer);
        
        return Value.fromBox(box, Value.TYPE_STRING);
    }
    
    /// Get all random builtin functions
    pub fn getAllFunctions() [6]BuiltinFunction {
        return [_]BuiltinFunction{
            BuiltinFunction.init("rand", .random, rand, 0, 2, "Returns random integer using linear congruential generator"),
            BuiltinFunction.init("mt_rand", .random, mt_rand, 0, 2, "Returns random integer using Mersenne Twister"),
            BuiltinFunction.init("srand", .random, srand, 0, 1, "Seed the random number generator"),
            BuiltinFunction.init("mt_srand", .random, mt_srand, 0, 1, "Seed the Mersenne Twister generator"),
            BuiltinFunction.init("random_int", .random, random_int, 2, 2, "Cryptographically secure random integer"),
            BuiltinFunction.init("random_bytes", .random, random_bytes, 1, 1, "Cryptographically secure random bytes"),
        };
    }
    
    /// PHP shuffle() - Randomly shuffle an array (in-place)
    /// Requirements: 4.0
    pub fn shuffle(vm: *anyopaque, args: []const Value) !Value {
        const VM = @import("vm.zig").VM;
        const vm_ptr = @as(*VM, @ptrCast(@alignCast(vm)));
        
        if (args.len < 1) {
            return BuiltinError.ArgumentCountMismatch;
        }
        
        const array_value = args[0];
        
        // Get the array (Box contains PHPArray pointer)
        const array_box = switch (array_value.getTag()) {
            .array => array_value.getAsArray(),
            else => {
                return BuiltinError.InvalidArgumentType;
            },
        };
        
        // Get the actual PHPArray from the box
        const php_array = array_box.data;
        
        // Get count
        const count = php_array.getElements().count();
        if (count <= 1) {
            return Value.initBool(true);
        }
        
        // Collect all entries into a slice
        var entries = try vm_ptr.allocator.alloc(struct { key: types.ArrayKey, value: Value }, count);
        defer vm_ptr.allocator.free(entries);
        
        var idx: usize = 0;
        var iter = php_array.getElements().iterator();
        while (iter.next()) |entry| {
            entries[idx].key = entry.key_ptr.*;
            entries[idx].value = entry.value_ptr.*;
            idx += 1;
        }
        
        // Fisher-Yates shuffle
        ensureMtInitialized();
        const random = mt_rng.random();
        
        var i: usize = count;
        while (i > 1) {
            i -= 1;
            const j = random.intRangeAtMost(usize, 0, i - 1);
            if (i != j) {
                const temp = entries[i];
                entries[i] = entries[j];
                entries[j] = temp;
            }
        }
        
        // Clear array and release old values
        var clear_iter = php_array.getElements().iterator();
        while (clear_iter.next()) |entry| {
            entry.value_ptr.release(vm_ptr.allocator);
            if (entry.key_ptr.* == .string) {
                entry.key_ptr.string.release(vm_ptr.allocator);
            }
        }
        php_array.getElements().clearRetainingCapacity();
        
        // Re-insert shuffled entries
        for (entries) |*e| {
            // Retain for the new insertion
            _ = e.value.retain();
            if (e.key == .string) {
                e.key.string.retain();
            }
            php_array.getElements().putAssumeCapacity(e.key, e.value);
        }
        
        return Value.initBool(true);
    }
    
    /// PHP array_rand() - Pick one or more random keys from an array
    /// Requirements: 4.0
    pub fn array_rand(vm: *anyopaque, args: []const Value) !Value {
        const VM = @import("vm.zig").VM;
        const vm_ptr = @as(*VM, @ptrCast(@alignCast(vm)));
        
        if (args.len < 1) {
            return BuiltinError.ArgumentCountMismatch;
        }
        
        const array_value = args[0];
        const num_req = if (args.len > 1) blk: {
            switch (args[1].getTag()) {
                .integer => break :blk @as(usize, @intCast(args[1].asInt())),
                .float => break :blk @as(usize, @intCast(@as(i64, @intFromFloat(args[1].asFloat())))),
                else => return BuiltinError.InvalidArgumentType,
            }
        } else 1;
        
        // Get the array
        if (array_value.getTag() != .array) {
            return BuiltinError.InvalidArgumentType;
        }
        
        const array_box = array_value.getAsArray();
        const php_array = array_box.data;
        const count = php_array.getElements().count();
        
        if (count == 0) {
            return BuiltinError.InvalidArgumentType;
        }
        
        if (num_req > count) {
            return BuiltinError.InvalidArgumentType;
        }
        
        ensureMtInitialized();
        const random = mt_rng.random();
        
        // Collect all keys
        var keys = try vm_ptr.allocator.alloc(types.ArrayKey, count);
        defer vm_ptr.allocator.free(keys);
        
        var idx: usize = 0;
        var iterator = php_array.getElements().iterator();
        while (iterator.next()) |entry| {
            keys[idx] = entry.key_ptr.*;
            idx += 1;
        }
        
        // If requesting only 1 key
        if (num_req == 1) {
            const random_idx = @as(usize, @intCast(random.intRangeAtMost(i32, 0, @as(i32, @intCast(count - 1)))));
            const selected_key = keys[random_idx];
            
            return switch (selected_key) {
                .integer => Value.initInt(selected_key.integer),
                .string => |s| blk: {
                    const box = try vm_ptr.allocator.create(types.gc.Box(*types.PHPString));
                    box.* = .{
                        .ref_count = 1,
                        .gc_info = .{},
                        .data = try types.PHPString.init(vm_ptr.allocator, s.data),
                    };
                    break :blk Value.fromBox(box, Value.TYPE_STRING);
                },
            };
        }
        
        // If requesting multiple keys, return array of keys
        var result_array = try vm_ptr.allocator.create(types.PHPArray);
        errdefer {
            result_array.deinit(vm_ptr.allocator);
            vm_ptr.allocator.destroy(result_array);
        }
        result_array.* = types.PHPArray.init(vm_ptr.allocator);
        
        // Fisher-Yates shuffle indices and take first num_req
        var indices = try vm_ptr.allocator.alloc(usize, count);
        defer vm_ptr.allocator.free(indices);
        
        for (0..count) |i| {
            indices[i] = i;
        }
        
        var i = count;
        while (i > 0) {
            i -= 1;
            const j = @as(usize, @intCast(random.intRangeAtMost(i32, 0, @as(i32, @intCast(i)))));
            if (i != j) {
                const temp = indices[i];
                indices[i] = indices[j];
                indices[j] = temp;
            }
        }
        
        // Add first num_req keys to result
        for (0..num_req) |k| {
            const selected_key = keys[indices[k]];
            const key_value = switch (selected_key) {
                .integer => Value.initInt(selected_key.integer),
                .string => |s| blk: {
                    const box = try vm_ptr.allocator.create(types.gc.Box(*types.PHPString));
                    box.* = .{
                        .ref_count = 1,
                        .gc_info = .{},
                        .data = try types.PHPString.init(vm_ptr.allocator, s.data),
                    };
                    break :blk Value.fromBox(box, Value.TYPE_STRING);
                },
            };
            try result_array.push(vm_ptr.allocator, key_value);
        }
        
        const box = try vm_ptr.allocator.create(types.gc.Box(*types.PHPArray));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_array,
        };
        
        return Value.fromBox(box, Value.TYPE_ARRAY);
    }
};

test "RandomBuiltins.rand" {
    const testing = std.testing;
    
    // Mock VM for testing
    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));
    
    // Test rand() with no arguments
    const result1 = try RandomBuiltins.rand(vm_ptr, &[_]Value{});
    try testing.expect(result1.getTag() == .integer);
    try testing.expect(result1.asInt() >= 0);
    
    // Test rand(min, max)
    const min_val = Value.initInt(10);
    const max_val = Value.initInt(20);
    const result2 = try RandomBuiltins.rand(vm_ptr, &[_]Value{ min_val, max_val });
    try testing.expect(result2.getTag() == .integer);
    try testing.expect(result2.asInt() >= 10 and result2.asInt() <= 20);
    
    // Test invalid range
    const invalid_min = Value.initInt(20);
    const invalid_max = Value.initInt(10);
    const result3 = RandomBuiltins.rand(vm_ptr, &[_]Value{ invalid_min, invalid_max });
    try testing.expectError(BuiltinError.InvalidArgumentType, result3);
}

test "RandomBuiltins.mt_rand" {
    const testing = std.testing;
    
    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));
    
    // Test mt_rand() with no arguments
    const result1 = try RandomBuiltins.mt_rand(vm_ptr, &[_]Value{});
    try testing.expect(result1.getTag() == .integer);
    try testing.expect(result1.asInt() >= 0);
    
    // Test mt_rand(min, max)
    const min_val = Value.initInt(5);
    const max_val = Value.initInt(15);
    const result2 = try RandomBuiltins.mt_rand(vm_ptr, &[_]Value{ min_val, max_val });
    try testing.expect(result2.getTag() == .integer);
    try testing.expect(result2.asInt() >= 5 and result2.asInt() <= 15);
}

test "RandomBuiltins.srand" {
    const testing = std.testing;
    
    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));
    
    // Test srand() with no arguments (uses current time)
    const result1 = try RandomBuiltins.srand(vm_ptr, &[_]Value{});
    try testing.expect(result1.getTag() == .null);
    
    // Test srand(seed)
    const seed_val = Value.initInt(12345);
    const result2 = try RandomBuiltins.srand(vm_ptr, &[_]Value{seed_val});
    try testing.expect(result2.getTag() == .null);
}

test "RandomBuiltins.mt_srand" {
    const testing = std.testing;
    
    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));
    
    // Test mt_srand() with no arguments
    const result1 = try RandomBuiltins.mt_srand(vm_ptr, &[_]Value{});
    try testing.expect(result1.getTag() == .null);
    
    // Test mt_srand(seed)
    const seed_val = Value.initInt(54321);
    const result2 = try RandomBuiltins.mt_srand(vm_ptr, &[_]Value{seed_val});
    try testing.expect(result2.getTag() == .null);
}

test "RandomBuiltins.random_int" {
    const testing = std.testing;
    
    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));
    
    // Test random_int(min, max)
    const min_val = Value.initInt(100);
    const max_val = Value.initInt(200);
    const result = try RandomBuiltins.random_int(vm_ptr, &[_]Value{ min_val, max_val });
    try testing.expect(result.getTag() == .integer);
    try testing.expect(result.asInt() >= 100 and result.asInt() <= 200);
    
    // Test invalid argument count
    const result2 = RandomBuiltins.random_int(vm_ptr, &[_]Value{min_val});
    try testing.expectError(BuiltinError.ArgumentCountMismatch, result2);
}

test "RandomBuiltins.random_bytes" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Create a minimal VM structure for testing
    const MockVM = struct {
        allocator: std.mem.Allocator,
    };
    
    var mock_vm = MockVM{ .allocator = allocator };
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));
    
    // Test random_bytes(length)
    const length_val = Value.initInt(16);
    const result = try RandomBuiltins.random_bytes(vm_ptr, &[_]Value{length_val});
    try testing.expect(result.getTag() == .string);
    
    const bytes_string = result.getAsString();
    defer bytes_string.release(allocator);
    try testing.expect(bytes_string.data.length == 16);
    
    // Test invalid length
    const invalid_length = Value.initInt(-1);
    const result2 = RandomBuiltins.random_bytes(vm_ptr, &[_]Value{invalid_length});
    try testing.expectError(BuiltinError.InvalidArgumentType, result2);
}

test "RandomBuiltins seeding consistency" {
    const testing = std.testing;
    
    var mock_vm: u8 = 0;
    const vm_ptr = @as(*anyopaque, @ptrCast(&mock_vm));
    
    // Seed both generators with the same value
    const seed_val = Value.initInt(42);
    _ = try RandomBuiltins.srand(vm_ptr, &[_]Value{seed_val});
    _ = try RandomBuiltins.mt_srand(vm_ptr, &[_]Value{seed_val});
    
    // Generate some numbers to verify seeding worked
    const result1 = try RandomBuiltins.rand(vm_ptr, &[_]Value{});
    const result2 = try RandomBuiltins.mt_rand(vm_ptr, &[_]Value{});
    
    try testing.expect(result1.getTag() == .integer);
    try testing.expect(result2.getTag() == .integer);
    
    // Re-seed with same value and verify we get same sequence
    _ = try RandomBuiltins.srand(vm_ptr, &[_]Value{seed_val});
    const result3 = try RandomBuiltins.rand(vm_ptr, &[_]Value{});
    try testing.expect(result3.asInt() == result1.asInt());
}