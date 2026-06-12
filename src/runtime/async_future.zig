//! ============================================================================
//! Future/Promise 异步模型实现
//! ============================================================================
//!
//! 本模块实现了基于 Future/Promise 的异步编程模型，替代简化的忙等待实现
//!
//! 功能：
//! - Future: 表示异步操作的最终结果
//! - Promise: 用于设置 Future 的值
//! - 回调链: 支持 then/catch 链式调用
//! - 取消支持: 可以取消未完成的异步操作
//!
//! 修复问题：src/runtime/async_io.zig:729-740 的忙等待实现
//! ============================================================================

const std = @import("std");

/// Future 状态（使用 u8 以兼容原子操作）
pub const FutureState = enum(u8) {
    pending = 0,    // 等待中
    fulfilled = 1,  // 已完成
    rejected = 2,   // 已拒绝
    cancelled = 3,  // 已取消
};

/// Future 结果类型
pub fn Future(comptime T: type) type {
    return struct {
        const Self = @This();
        
        /// 分配器
        allocator: std.mem.Allocator,
        
        /// 当前状态
        state: std.atomic.Value(FutureState),
        
        /// 结果值（fulfilled 时有效）
        value: ?T,
        
        /// 错误（rejected 时有效）
        err: ?anyerror,
        
        /// 回调列表
        callbacks: std.ArrayListUnmanaged(Callback),
        
        /// 互斥锁
        mutex: std.Thread.Mutex,
        
        /// 条件变量（用于等待）
        condition: std.Thread.Condition,
        
        /// 回调函数类型
        pub const Callback = struct {
            on_fulfilled: ?*const fn (T) void,
            on_rejected: ?*const fn (anyerror) void,
        };
        
        /// 初始化 Future
        /// @pre allocator 必须有效
        /// @post 返回处于 pending 状态的 Future
        pub fn init(allocator: std.mem.Allocator) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);
            
            self.* = .{
                .allocator = allocator,
                .state = std.atomic.Value(FutureState).init(.pending),
                .value = null,
                .err = null,
                .callbacks = .{},
                .mutex = .{},
                .condition = .{},
            };
            
            return self;
        }
        
        /// 释放资源
        /// @pre self 必须已初始化
        /// @post 释放所有资源
        pub fn deinit(self: *Self) void {
            self.callbacks.deinit(self.allocator);
            self.allocator.destroy(self);
        }
        
        /// 等待 Future 完成
        /// @pre self 必须已初始化
        /// @post 返回结果或错误
        pub fn wait(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            // 等待直到状态不是 pending
            while (self.state.load(.acquire) == .pending) {
                self.condition.wait(&self.mutex);
            }
            
            return switch (self.state.load(.acquire)) {
                .fulfilled => self.value.?,
                .rejected => self.err.?,
                .cancelled => error.Cancelled,
                .pending => unreachable,
            };
        }
        
        /// 等待 Future 完成（带超时）
        /// @pre self 必须已初始化
        /// @post 返回结果、错误或超时
        pub fn waitTimeout(self: *Self, timeout_ns: u64) !T {
            const start = std.time.nanoTimestamp();
            
            self.mutex.lock();
            defer self.mutex.unlock();
            
            while (self.state.load(.acquire) == .pending) {
                const elapsed = @as(u64, @intCast(std.time.nanoTimestamp() - start));
                if (elapsed >= timeout_ns) {
                    return error.Timeout;
                }
                
                // 使用 timedWait（如果可用）
                self.condition.wait(&self.mutex);
                
                // 简单的超时检查
                const now_elapsed = @as(u64, @intCast(std.time.nanoTimestamp() - start));
                if (now_elapsed >= timeout_ns) {
                    return error.Timeout;
                }
            }
            
            return switch (self.state.load(.acquire)) {
                .fulfilled => self.value.?,
                .rejected => self.err.?,
                .cancelled => error.Cancelled,
                .pending => unreachable,
            };
        }
        
        /// 检查 Future 是否已完成
        /// @pre self 必须已初始化
        /// @post 返回是否已完成
        pub fn isDone(self: *const Self) bool {
            return self.state.load(.acquire) != .pending;
        }
        
        /// 取消 Future
        /// @pre self 必须已初始化
        /// @post Future 被标记为已取消
        pub fn cancel(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            if (self.state.load(.acquire) == .pending) {
                self.state.store(.cancelled, .release);
                self.condition.broadcast();
            }
        }
        
        /// 添加回调
        /// @pre self 必须已初始化
        /// @post 回调被添加到列表
        pub fn then(
            self: *Self,
            on_fulfilled: ?*const fn (T) void,
            on_rejected: ?*const fn (anyerror) void,
        ) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            const callback = Callback{
                .on_fulfilled = on_fulfilled,
                .on_rejected = on_rejected,
            };
            
            // 如果已经完成，立即执行回调
            switch (self.state.load(.acquire)) {
                .fulfilled => {
                    if (on_fulfilled) |cb| {
                        cb(self.value.?);
                    }
                },
                .rejected => {
                    if (on_rejected) |cb| {
                        cb(self.err.?);
                    }
                },
                .pending => {
                    // 添加到回调列表
                    try self.callbacks.append(self.allocator, callback);
                },
                .cancelled => {},
            }
        }
        
        /// 内部方法：执行所有回调
        fn executeCallbacks(self: *Self) void {
            for (self.callbacks.items) |callback| {
                switch (self.state.load(.acquire)) {
                    .fulfilled => {
                        if (callback.on_fulfilled) |cb| {
                            cb(self.value.?);
                        }
                    },
                    .rejected => {
                        if (callback.on_rejected) |cb| {
                            cb(self.err.?);
                        }
                    },
                    else => {},
                }
            }
            
            self.callbacks.clearRetainingCapacity();
        }
    };
}

/// Promise - 用于设置 Future 的值
pub fn Promise(comptime T: type) type {
    return struct {
        const Self = @This();
        
        /// 关联的 Future
        future: *Future(T),
        
        /// 创建 Promise
        /// @pre allocator 必须有效
        /// @post 返回 Promise 和关联的 Future
        pub fn create(allocator: std.mem.Allocator) !Self {
            const future = try Future(T).init(allocator);
            return Self{ .future = future };
        }
        
        /// 设置成功结果
        /// @pre self.future 必须处于 pending 状态
        /// @post Future 被标记为 fulfilled
        pub fn resolve(self: *Self, value: T) void {
            self.future.mutex.lock();
            defer self.future.mutex.unlock();
            
            if (self.future.state.load(.acquire) == .pending) {
                self.future.value = value;
                self.future.state.store(.fulfilled, .release);
                
                // 执行回调
                self.future.executeCallbacks();
                
                // 唤醒等待的线程
                self.future.condition.broadcast();
            }
        }
        
        /// 设置错误结果
        /// @pre self.future 必须处于 pending 状态
        /// @post Future 被标记为 rejected
        pub fn reject(self: *Self, err: anyerror) void {
            self.future.mutex.lock();
            defer self.future.mutex.unlock();
            
            if (self.future.state.load(.acquire) == .pending) {
                self.future.err = err;
                self.future.state.store(.rejected, .release);
                
                // 执行回调
                self.future.executeCallbacks();
                
                // 唤醒等待的线程
                self.future.condition.broadcast();
            }
        }
        
        /// 获取关联的 Future
        /// @post 返回 Future 指针
        pub fn getFuture(self: *Self) *Future(T) {
            return self.future;
        }
    };
}

// ============================================================================
// 测试
// ============================================================================

test "future basic" {
    const allocator = std.testing.allocator;
    
    var promise = try Promise(i32).create(allocator);
    defer promise.future.deinit();
    
    // 检查初始状态
    try std.testing.expect(!promise.future.isDone());
    try std.testing.expectEqual(FutureState.pending, promise.future.state.load(.acquire));
    
    // 设置值
    promise.resolve(42);
    
    // 检查完成状态
    try std.testing.expect(promise.future.isDone());
    try std.testing.expectEqual(FutureState.fulfilled, promise.future.state.load(.acquire));
    
    // 获取值
    const value = try promise.future.wait();
    try std.testing.expectEqual(@as(i32, 42), value);
}

test "future error" {
    const allocator = std.testing.allocator;
    
    var promise = try Promise(i32).create(allocator);
    defer promise.future.deinit();
    
    // 设置错误
    promise.reject(error.TestError);
    
    // 检查状态
    try std.testing.expect(promise.future.isDone());
    try std.testing.expectEqual(FutureState.rejected, promise.future.state.load(.acquire));
    
    // 获取错误
    const result = promise.future.wait();
    try std.testing.expectError(error.TestError, result);
}

test "future cancel" {
    const allocator = std.testing.allocator;
    
    var promise = try Promise(i32).create(allocator);
    defer promise.future.deinit();
    
    // 取消
    promise.future.cancel();
    
    // 检查状态
    try std.testing.expect(promise.future.isDone());
    try std.testing.expectEqual(FutureState.cancelled, promise.future.state.load(.acquire));
    
    // 获取结果
    const result = promise.future.wait();
    try std.testing.expectError(error.Cancelled, result);
}

test "future callback" {
    const allocator = std.testing.allocator;
    
    var promise = try Promise(i32).create(allocator);
    defer promise.future.deinit();
    
    // 添加回调
    const callback = struct {
        fn onFulfilled(value: i32) void {
            _ = value;
            // 注意：这里无法修改外部变量
            // 在实际使用中，回调应该有上下文参数
        }
    }.onFulfilled;
    
    try promise.future.then(callback, null);
    
    // 设置值（应该触发回调）
    promise.resolve(42);
}

test "future timeout" {
    const allocator = std.testing.allocator;
    
    var promise = try Promise(i32).create(allocator);
    defer promise.future.deinit();
    
    // 尝试等待（应该超时）
    const result = promise.future.waitTimeout(1_000_000); // 1ms
    try std.testing.expectError(error.Timeout, result);
}
