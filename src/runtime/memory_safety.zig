//! 内存安全检查模块
//!
//! 本模块实现了 Zig-PHP 的内存安全保证机制，包括：
//! 1. 显式 Allocator 传递和所有权管理
//! 2. defer/errdefer 资源管理模式
//! 3. 数组边界检查
//! 4. 指针生命周期标注和验证
//!
//! @ownership 所有权协议：
//!   - TRANSFER: 调用者转移所有权给被调用者
//!   - NON-OWNING: 被调用者不拥有资源，仅借用
//!   - SHARED: 通过引用计数共享所有权
//!
//! @memory-protection 内存保护级别：
//!   - BOUNDS_CHECK: 启用数组边界检查
//!   - LIFETIME_CHECK: 启用指针生命周期检查
//!   - LEAK_DETECTION: 启用内存泄漏检测
//!
//! 验证需求：7.1, 7.2, 7.3, 7.4

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// ============================================================================
// 所有权标注系统
// ============================================================================

/// 所有权类型
pub const OwnershipType = enum {
    /// 转移所有权：调用者将资源所有权转移给被调用者
    transfer,

    /// 非拥有：被调用者仅借用资源，不负责释放
    non_owning,

    /// 共享所有权：通过引用计数共享
    shared,
};

/// 所有权标注
/// 用于标记函数参数和返回值的所有权语义
pub fn Ownership(comptime T: type, comptime ownership: OwnershipType) type {
    return struct {
        value: T,
        ownership_type: OwnershipType = ownership,

        pub fn unwrap(self: @This()) T {
            return self.value;
        }
    };
}

// ============================================================================
// 安全 Allocator 包装器
// ============================================================================

/// 安全 Allocator 包装器
/// 提供额外的安全检查和调试信息
/// @ownership NON-OWNING (wrapped_allocator)
pub const SafeAllocator = struct {
    wrapped_allocator: Allocator,

    // 调试信息（仅在 Debug 模式下启用）
    allocation_count: if (builtin.mode == .Debug) std.atomic.Value(usize) else void,
    deallocation_count: if (builtin.mode == .Debug) std.atomic.Value(usize) else void,
    total_allocated: if (builtin.mode == .Debug) std.atomic.Value(usize) else void,

    const Self = @This();

    /// 初始化安全 Allocator
    /// @ownership NON-OWNING (base_allocator)
    pub fn init(base_allocator: Allocator) Self {
        return .{
            .wrapped_allocator = base_allocator,
            .allocation_count = if (builtin.mode == .Debug) std.atomic.Value(usize).init(0) else {},
            .deallocation_count = if (builtin.mode == .Debug) std.atomic.Value(usize).init(0) else {},
            .total_allocated = if (builtin.mode == .Debug) std.atomic.Value(usize).init(0) else {},
        };
    }

    /// 获取底层 Allocator
    pub fn getAllocator(self: *Self) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = allocFn,
                .resize = resizeFn,
                .free = freeFn,
                .remap = remapFn,
            },
        };
    }

    fn allocFn(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        // 调用底层 allocator
        const result = self.wrapped_allocator.rawAlloc(len, ptr_align, ret_addr);

        // 更新统计信息（Debug 模式）
        if (builtin.mode == .Debug and result != null) {
            _ = self.allocation_count.fetchAdd(1, .monotonic);
            _ = self.total_allocated.fetchAdd(len, .monotonic);
        }

        return result;
    }

    fn resizeFn(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        return self.wrapped_allocator.rawResize(buf, buf_align, new_len, ret_addr);
    }

    fn freeFn(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        // 更新统计信息（Debug 模式）
        if (builtin.mode == .Debug) {
            _ = self.deallocation_count.fetchAdd(1, .monotonic);
        }

        // 在 Debug 模式下，释放后填充特殊值以检测 use-after-free
        if (builtin.mode == .Debug) {
            @memset(buf, 0xAA);
        }

        self.wrapped_allocator.rawFree(buf, buf_align, ret_addr);
    }

    fn remapFn(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        return self.wrapped_allocator.rawRemap(buf, buf_align, new_len, ret_addr);
    }

    /// 获取分配统计信息（仅 Debug 模式）
    pub fn getStats(self: *const Self) ?AllocationStats {
        if (builtin.mode != .Debug) return null;

        return AllocationStats{
            .allocation_count = self.allocation_count.load(.monotonic),
            .deallocation_count = self.deallocation_count.load(.monotonic),
            .total_allocated = self.total_allocated.load(.monotonic),
        };
    }
};

/// 分配统计信息
pub const AllocationStats = struct {
    allocation_count: usize,
    deallocation_count: usize,
    total_allocated: usize,

    /// 检查是否有内存泄漏
    pub fn hasLeaks(self: AllocationStats) bool {
        return self.allocation_count > self.deallocation_count;
    }

    /// 获取泄漏的分配数量
    pub fn leakCount(self: AllocationStats) usize {
        return self.allocation_count -| self.deallocation_count;
    }
};

// ============================================================================
// 边界检查数组
// ============================================================================

/// 带边界检查的数组包装器
/// @memory-protection BOUNDS_CHECK
pub fn BoundsCheckedArray(comptime T: type) type {
    return struct {
        data: []T,

        const Self = @This();

        /// 创建边界检查数组
        /// @ownership TRANSFER (data)
        pub fn init(data: []T) Self {
            return .{ .data = data };
        }

        /// 安全获取元素（带边界检查）
        /// @pre index < self.data.len
        /// @post 返回有效元素或错误
        pub fn get(self: Self, index: usize) !T {
            if (index >= self.data.len) {
                return error.IndexOutOfBounds;
            }
            return self.data[index];
        }

        /// 安全设置元素（带边界检查）
        /// @pre index < self.data.len
        /// @post 元素被设置或返回错误
        pub fn set(self: *Self, index: usize, value: T) !void {
            if (index >= self.data.len) {
                return error.IndexOutOfBounds;
            }
            self.data[index] = value;
        }

        /// 获取数组长度
        pub fn len(self: Self) usize {
            return self.data.len;
        }

        /// 获取底层切片（不安全）
        pub fn slice(self: Self) []T {
            return self.data;
        }
    };
}

// ============================================================================
// 生命周期标注指针
// ============================================================================

/// 生命周期标注指针
/// 用于跟踪指针的有效性
/// @memory-protection LIFETIME_CHECK
pub fn LifetimePtr(comptime T: type) type {
    return struct {
        ptr: *T,
        valid: if (builtin.mode == .Debug) *std.atomic.Value(bool) else void,

        const Self = @This();

        /// 创建生命周期指针
        /// @ownership NON-OWNING (ptr)
        /// @pre ptr 必须有效
        pub fn init(ptr: *T, allocator: Allocator) !Self {
            if (builtin.mode == .Debug) {
                const valid = try allocator.create(std.atomic.Value(bool));
                valid.* = std.atomic.Value(bool).init(true);
                return .{
                    .ptr = ptr,
                    .valid = valid,
                };
            } else {
                return .{
                    .ptr = ptr,
                    .valid = {},
                };
            }
        }

        /// 标记指针为无效
        pub fn invalidate(self: *Self) void {
            if (builtin.mode == .Debug) {
                self.valid.store(false, .release);
            }
        }

        /// 检查指针是否有效
        pub fn isValid(self: *const Self) bool {
            if (builtin.mode == .Debug) {
                return self.valid.load(.acquire);
            }
            return true;
        }

        /// 解引用指针（带生命周期检查）
        /// @pre self.isValid() == true
        /// @post 返回有效引用或错误
        pub fn deref(self: *const Self) !*T {
            if (builtin.mode == .Debug) {
                if (!self.isValid()) {
                    return error.DanglingPointer;
                }
            }
            return self.ptr;
        }

        /// 释放生命周期跟踪资源
        pub fn deinit(self: *Self, allocator: Allocator) void {
            if (builtin.mode == .Debug) {
                allocator.destroy(self.valid);
            }
        }
    };
}

// ============================================================================
// 资源管理辅助函数
// ============================================================================

/// 资源守卫
/// 使用 RAII 模式确保资源正确释放
pub fn ResourceGuard(comptime T: type, comptime deinit_fn: fn (T) void) type {
    return struct {
        resource: T,
        released: bool = false,

        const Self = @This();

        /// 创建资源守卫
        /// @ownership TRANSFER (resource)
        pub fn init(resource: T) Self {
            return .{ .resource = resource };
        }

        /// 手动释放资源
        pub fn release(self: *Self) void {
            if (!self.released) {
                deinit_fn(self.resource);
                self.released = true;
            }
        }

        /// 自动释放资源（通过 defer）
        pub fn deinit(self: *Self) void {
            self.release();
        }
    };
}

/// 创建资源守卫的辅助函数
pub fn guard(resource: anytype, comptime deinit_fn: fn (@TypeOf(resource)) void) ResourceGuard(@TypeOf(resource), deinit_fn) {
    return ResourceGuard(@TypeOf(resource), deinit_fn).init(resource);
}

// ============================================================================
// 内存泄漏检测
// ============================================================================

/// 内存泄漏检测器
/// 跟踪所有分配和释放，检测泄漏
pub const LeakDetector = struct {
    allocations: if (builtin.mode == .Debug) std.AutoHashMap(usize, AllocationInfo) else void,
    mutex: if (builtin.mode == .Debug) std.Thread.Mutex else void,
    allocator: Allocator,

    const Self = @This();

    /// 分配信息
    pub const AllocationInfo = struct {
        size: usize,
        return_address: usize,
        timestamp: i64,
    };

    /// 初始化泄漏检测器
    pub fn init(allocator: Allocator) !Self {
        if (builtin.mode == .Debug) {
            return .{
                .allocations = std.AutoHashMap(usize, AllocationInfo).init(allocator),
                .mutex = .{},
                .allocator = allocator,
            };
        } else {
            return .{
                .allocations = {},
                .mutex = {},
                .allocator = allocator,
            };
        }
    }

    /// 记录分配
    pub fn recordAllocation(self: *Self, ptr: usize, size: usize, ret_addr: usize) !void {
        if (builtin.mode == .Debug) {
            self.mutex.lock();
            defer self.mutex.unlock();

            try self.allocations.put(ptr, .{
                .size = size,
                .return_address = ret_addr,
                .timestamp = std.time.milliTimestamp(),
            });
        }
    }

    /// 记录释放
    pub fn recordDeallocation(self: *Self, ptr: usize) void {
        if (builtin.mode == .Debug) {
            self.mutex.lock();
            defer self.mutex.unlock();

            _ = self.allocations.remove(ptr);
        }
    }

    /// 检查泄漏
    pub fn checkLeaks(self: *Self) ![]const AllocationInfo {
        if (builtin.mode == .Debug) {
            self.mutex.lock();
            defer self.mutex.unlock();

            const leak_count = self.allocations.count();
            if (leak_count == 0) {
                return &[_]AllocationInfo{};
            }

            var leaks = try self.allocator.alloc(AllocationInfo, leak_count);
            var iter = self.allocations.valueIterator();
            var i: usize = 0;
            while (iter.next()) |info| : (i += 1) {
                leaks[i] = info.*;
            }

            return leaks;
        } else {
            return &[_]AllocationInfo{};
        }
    }

    /// 清理
    pub fn deinit(self: *Self) void {
        if (builtin.mode == .Debug) {
            self.allocations.deinit();
        }
    }
};

// ============================================================================
// 测试
// ============================================================================

test "SafeAllocator - basic allocation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var safe = SafeAllocator.init(gpa.allocator());
    const allocator = safe.getAllocator();

    const data = try allocator.alloc(u8, 100);
    defer allocator.free(data);

    try std.testing.expect(data.len == 100);

    if (builtin.mode == .Debug) {
        const stats = safe.getStats().?;
        try std.testing.expect(stats.allocation_count >= 1);
        try std.testing.expect(stats.total_allocated >= 100);
    }
}

test "BoundsCheckedArray - safe access" {
    var data = [_]i32{ 1, 2, 3, 4, 5 };
    var arr = BoundsCheckedArray(i32).init(&data);

    // 有效访问
    try std.testing.expectEqual(@as(i32, 1), try arr.get(0));
    try std.testing.expectEqual(@as(i32, 5), try arr.get(4));

    // 越界访问
    try std.testing.expectError(error.IndexOutOfBounds, arr.get(5));
    try std.testing.expectError(error.IndexOutOfBounds, arr.get(100));
}

test "BoundsCheckedArray - safe modification" {
    var data = [_]i32{ 1, 2, 3, 4, 5 };
    var arr = BoundsCheckedArray(i32).init(&data);

    // 有效修改
    try arr.set(0, 10);
    try std.testing.expectEqual(@as(i32, 10), try arr.get(0));

    // 越界修改
    try std.testing.expectError(error.IndexOutOfBounds, arr.set(5, 100));
}

test "LifetimePtr - valid pointer" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var value: i32 = 42;
    var ptr = try LifetimePtr(i32).init(&value, allocator);
    defer ptr.deinit(allocator);

    // 有效解引用
    const deref = try ptr.deref();
    try std.testing.expectEqual(@as(i32, 42), deref.*);

    // 检查有效性
    try std.testing.expect(ptr.isValid());
}

test "LifetimePtr - dangling pointer detection" {
    if (builtin.mode != .Debug) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var value: i32 = 42;
    var ptr = try LifetimePtr(i32).init(&value, allocator);
    defer ptr.deinit(allocator);

    // 标记为无效
    ptr.invalidate();

    // 尝试解引用应该失败
    try std.testing.expectError(error.DanglingPointer, ptr.deref());
    try std.testing.expect(!ptr.isValid());
}

test "ResourceGuard - automatic cleanup" {
    const TestResource = struct {
        value: i32,
        cleaned: *bool,

        fn deinit(self: @This()) void {
            self.cleaned.* = true;
        }
    };

    var cleaned = false;
    {
        const resource = TestResource{ .value = 42, .cleaned = &cleaned };
        var g = ResourceGuard(TestResource, TestResource.deinit).init(resource);
        defer g.deinit();

        try std.testing.expect(!cleaned);
    }

    // 资源应该被清理
    try std.testing.expect(cleaned);
}

test "LeakDetector - no leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var detector = try LeakDetector.init(allocator);
    defer detector.deinit();

    // 分配和释放
    const ptr = @intFromPtr((try allocator.alloc(u8, 100)).ptr);
    try detector.recordAllocation(ptr, 100, @returnAddress());
    detector.recordDeallocation(ptr);
    allocator.free(@as([*]u8, @ptrFromInt(ptr))[0..100]);

    // 检查泄漏
    const leaks = try detector.checkLeaks();
    defer if (leaks.len > 0) allocator.free(leaks);

    try std.testing.expectEqual(@as(usize, 0), leaks.len);
}

test "LeakDetector - detect leaks" {
    if (builtin.mode != .Debug) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var detector = try LeakDetector.init(allocator);
    defer detector.deinit();

    // 分配但不释放
    const data = try allocator.alloc(u8, 100);
    const ptr = @intFromPtr(data.ptr);
    try detector.recordAllocation(ptr, 100, @returnAddress());

    // 检查泄漏
    const leaks = try detector.checkLeaks();
    defer allocator.free(leaks);

    try std.testing.expect(leaks.len > 0);
    try std.testing.expectEqual(@as(usize, 100), leaks[0].size);

    // 清理泄漏的内存
    allocator.free(data);
}
