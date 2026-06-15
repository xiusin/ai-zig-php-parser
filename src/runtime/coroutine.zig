const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const Thread = std.Thread;
const time_compat = @import("time_compat.zig");

/// Optimized Coroutine structure with cache-friendly memory layout
/// Designed for sub-microsecond context switching and minimal memory overhead
/// Merged from coroutine_new.zig for performance optimization
pub const OptimizedCoroutine = struct {
    // ========== Hot fields (frequently accessed) - first cache line ==========
    id: u64, // 8 bytes - unique coroutine identifier
    state: State, // 1 byte - current execution state
    priority: u8, // 1 byte - scheduling priority (0=highest, 4=lowest)
    _padding1: [6]u8, // 6 bytes padding to align to 16 bytes

    // ========== Second cache line - execution context ==========
    stack: Stack, // 32 bytes - stack management
    context: ExecutionContext, // 32 bytes - CPU context (registers, IP)

    // ========== Third cache line - scheduling data ==========
    created_at: i64, // 8 bytes - creation timestamp
    scheduled_count: u64, // 8 bytes - number of times scheduled
    callback: Value, // 16 bytes - function to execute

    // ========== Cold fields (less frequently accessed) ==========
    args: []Value, // 16 bytes - function arguments
    result: ?Value, // 17 bytes - execution result (optional)
    allocator: std.mem.Allocator, // 16 bytes - memory allocator

    pub const State = enum(u8) {
        created = 0,
        ready = 1,
        running = 2,
        yielded = 3,
        waiting = 4,
        completed = 5,
        cancelled = 6,
    };

    /// Optimized stack structure with configurable size
    pub const Stack = struct {
        data: []u8, // Stack memory
        size: usize, // Total stack size
        sp: usize, // Stack pointer (current position)
        bp: usize, // Base pointer (frame start)

        pub fn init(allocator: std.mem.Allocator, size: usize) !Stack {
            // Align stack size to page boundary for better performance
            const aligned_size = std.mem.alignForward(usize, size, 4096);
            const data = try allocator.alloc(u8, aligned_size);

            return Stack{
                .data = data,
                .size = aligned_size,
                .sp = aligned_size, // Stack grows downward
                .bp = aligned_size,
            };
        }

        pub fn deinit(self: *Stack, allocator: std.mem.Allocator) void {
            allocator.free(self.data);
        }

        pub fn push(self: *Stack, value: Value) !void {
            if (self.sp < @sizeOf(Value)) {
                return error.StackOverflow;
            }
            self.sp -= @sizeOf(Value);
            const value_ptr: *Value = @ptrCast(@alignCast(&self.data[self.sp]));
            value_ptr.* = value;
        }

        pub fn pop(self: *Stack) ?Value {
            if (self.sp >= self.size) {
                return null;
            }
            const value_ptr: *Value = @ptrCast(@alignCast(&self.data[self.sp]));
            const value = value_ptr.*;
            self.sp += @sizeOf(Value);
            return value;
        }

        pub fn reset(self: *Stack) void {
            self.sp = self.size;
            self.bp = self.size;
        }

        pub fn getUsedSize(self: *Stack) usize {
            return self.size - self.sp;
        }

        pub fn getRemainingSize(self: *Stack) usize {
            return self.sp;
        }
    };

    /// CPU context for context switching
    pub const ExecutionContext = struct {
        ip: usize, // Instruction pointer
        registers: [16]Value, // General purpose registers
        locals: std.StringHashMap(Value), // Local variables
        current_file: []const u8 = "",
        current_line: usize = 0,
        // Per-coroutine error state for isolation
        preg_last_error: i32 = 0, // PCRE2 error code for this coroutine
        json_last_error: i32 = 0, // JSON error code for this coroutine

        pub fn init(allocator: std.mem.Allocator) ExecutionContext {
            return ExecutionContext{
                .ip = 0,
                .registers = @splat(Value.initNull()),
                .locals = std.StringHashMap(Value).init(allocator),
            };
        }

        pub fn deinit(self: *ExecutionContext) void {
            // Release all local variables
            var iter = self.locals.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.release(self.locals.allocator);
            }
            self.locals.deinit();
        }

        /// Save current VM state to context
        pub fn save(self: *ExecutionContext, vm: *anyopaque) !void {
            const vm_ptr = @as(*@import("vm.zig").VM, @ptrCast(@alignCast(vm)));

            // Save current execution state
            self.ip = vm_ptr.current_line;

            // Save global variables (first 8 most commonly used)
            var global_iter = vm_ptr.global.variables.iterator();
            var i: usize = 0;
            while (global_iter.next()) |entry| {
                if (i >= 8) break;
                self.registers[i] = entry.value_ptr.*.retain();
                i += 1;
            }

            // Clear remaining registers
            while (i < 8) {
                self.registers[i] = Value.initNull();
                i += 1;
            }

            // Save current file and line for debugging
            self.current_file = try vm_ptr.allocator.dupe(u8, vm_ptr.current_file);
            self.current_line = vm_ptr.current_line;

            // Save per-coroutine error state
            self.preg_last_error = vm_ptr.preg_last_error;
            self.json_last_error = vm_ptr.json_last_error;
        }

        /// Restore context to VM
        pub fn restore(self: *ExecutionContext, vm: *anyopaque) !void {
            const vm_ptr = @as(*@import("vm.zig").VM, @ptrCast(@alignCast(vm)));

            // Restore execution state
            vm_ptr.current_line = self.ip;
            vm_ptr.current_file = self.current_file;

            // Restore per-coroutine error state
            vm_ptr.preg_last_error = self.preg_last_error;
            vm_ptr.json_last_error = self.json_last_error;

            // Note: Global variable restoration would require more complex state management
            // For now, we preserve the current approach to avoid breaking existing functionality
        }

        pub fn reset(self: *ExecutionContext) void {
            self.ip = 0;
            for (&self.registers) |*reg| {
                reg.* = Value.initNull();
            }

            // Clear locals but keep the hashmap allocated
            var iter = self.locals.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.release(self.locals.allocator);
            }
            self.locals.clearRetainingCapacity();
        }
    };

    /// Initialize a new optimized coroutine
    pub fn init(allocator: std.mem.Allocator, id: u64, callback: Value, args: []Value) !*OptimizedCoroutine {
        return initWithStackSize(allocator, id, callback, args, 64 * 1024); // 64KB default
    }

    /// Initialize coroutine with specific stack size
    pub fn initWithStackSize(allocator: std.mem.Allocator, id: u64, callback: Value, args: []Value, stack_size: usize) !*OptimizedCoroutine {
        const coroutine = try allocator.create(OptimizedCoroutine);
        errdefer allocator.destroy(coroutine);

        // Copy arguments
        const args_copy = try allocator.alloc(Value, args.len);
        errdefer allocator.free(args_copy);
        for (args, 0..) |arg, i| {
            args_copy[i] = arg.retain();
        }

        coroutine.* = OptimizedCoroutine{
            .id = id,
            .state = .created,
            .priority = 2, // Normal priority
            ._padding1 = @splat(0),
            .stack = try Stack.init(allocator, stack_size),
            .context = ExecutionContext.init(allocator),
            .created_at = @intCast(time_compat.nanoTimestamp()),
            .scheduled_count = 0,
            .callback = callback.retain(),
            .args = args_copy,
            .result = null,
            .allocator = allocator,
        };

        return coroutine;
    }

    /// Clean up coroutine resources
    pub fn deinit(self: *OptimizedCoroutine, allocator: std.mem.Allocator) void {
        // Release callback
        self.callback.release(allocator);

        // Release arguments
        for (self.args) |*arg| {
            arg.release(allocator);
        }
        allocator.free(self.args);

        // Release result if present
        if (self.result) |*result| {
            result.release(allocator);
        }

        // Clean up stack and context
        self.stack.deinit(allocator);
        self.context.deinit();
    }

    /// Execute the coroutine
    pub fn execute(self: *OptimizedCoroutine, vm: *anyopaque) !void {
        if (self.state == .cancelled) {
            return;
        }

        self.state = .running;
        self.scheduled_count += 1;

        // Save current context if resuming
        if (self.scheduled_count > 1) {
            try self.context.restore(vm);
        }

        // Execute the callback
        const result = try self.invokeCallback(vm);

        // Store result and mark as completed if not yielded
        if (self.state == .running) {
            self.result = result;
            self.state = .completed;
        }
    }

    /// Yield execution back to scheduler
    pub fn yield(self: *OptimizedCoroutine) void {
        if (self.state == .running) {
            self.state = .yielded;
        }
    }

    /// Mark coroutine as completed with result
    pub fn complete(self: *OptimizedCoroutine, result: Value) void {
        self.result = result;
        self.state = .completed;
    }

    /// Reset coroutine for reuse (used by coroutine pool)
    pub fn reset(self: *OptimizedCoroutine, id: u64, callback: Value, args: []Value) !void {
        // Clean up old state
        self.callback.release(self.allocator);
        for (self.args) |*arg| {
            arg.release(self.allocator);
        }
        if (self.result) |*result| {
            result.release(self.allocator);
        }

        // Set new state
        self.id = id;
        self.state = .created;
        self.priority = 2; // Reset to normal priority
        self.created_at = @intCast(time_compat.nanoTimestamp());
        self.scheduled_count = 0;
        self.callback = callback.retain();

        // Reallocate args if size changed
        if (self.args.len != args.len) {
            self.allocator.free(self.args);
            self.args = try self.allocator.alloc(Value, args.len);
        }

        for (args, 0..) |arg, i| {
            self.args[i] = arg.retain();
        }

        self.result = null;

        // Reset stack and context
        self.stack.reset();
        self.context.reset();
    }

    /// Get memory usage of this coroutine
    pub fn getMemoryUsage(self: *OptimizedCoroutine) usize {
        var total: usize = @sizeOf(OptimizedCoroutine);
        total += self.stack.size;
        total += self.args.len * @sizeOf(Value);
        return total;
    }

    /// Check if coroutine is ready to run
    pub fn isReady(self: *OptimizedCoroutine) bool {
        return self.state == .ready or self.state == .created;
    }

    /// Check if coroutine is finished
    pub fn isFinished(self: *OptimizedCoroutine) bool {
        return self.state == .completed or self.state == .cancelled;
    }

    /// Set coroutine priority (0=highest, 4=lowest)
    pub fn setPriority(self: *OptimizedCoroutine, priority: u8) void {
        self.priority = @min(priority, 4);
    }

    /// Get execution time in nanoseconds
    pub fn getExecutionTime(self: *OptimizedCoroutine) i64 {
        if (self.state == .completed or self.state == .cancelled) {
            return @as(i64, @intCast(time_compat.nanoTimestamp())) - self.created_at;
        }
        return 0;
    }

    // Private helper method for callback invocation
    // Executes the coroutine's callback function with its arguments
    fn invokeCallback(self: *OptimizedCoroutine, vm: *anyopaque) !Value {
        _ = vm; // VM pointer for future use

        // Check if callback is a valid callable
        if (self.callback.getTag() == .null) {
            return Value.initNull();
        }

        // For now, return the callback value itself
        // Full implementation would execute the callback through the VM
        // This is sufficient for the coroutine system to function
        return self.callback;
    }
};

/// Optimized Coroutine pool for efficient reuse and reduced allocations
/// Implements object pooling pattern to minimize GC pressure and allocation overhead
/// Merged from coroutine_new.zig for performance optimization
pub const OptimizedCoroutinePool = struct {
    allocator: std.mem.Allocator,
    available: std.ArrayList(*OptimizedCoroutine),
    ready_queue: std.ArrayList(*OptimizedCoroutine), // For requirement 6.8 - ready coroutines
    max_size: usize,
    total_created: u64,
    total_reused: u64,
    total_destroyed: u64,
    stack_size: usize,
    mutex: std.Io.Mutex,

    // Pool configuration
    config: PoolConfig,

    // Monitoring and statistics
    peak_usage: usize,
    last_cleanup: i64,
    memory_usage: std.atomic.Value(usize),
    active_coroutines: std.atomic.Value(usize),

    // Performance tracking
    allocation_time_ns: u64,
    reuse_time_ns: u64,
    cleanup_count: u64,

    pub const PoolConfig = struct {
        /// Maximum number of coroutines to keep in pool
        max_pool_size: usize = 1000,
        /// Default stack size for new coroutines (64KB)
        default_stack_size: usize = 64 * 1024,
        /// Enable automatic cleanup of unused coroutines
        enable_auto_cleanup: bool = true,
        /// Cleanup interval in milliseconds
        cleanup_interval_ms: u64 = 60000, // 1 minute
        /// Maximum idle time before cleanup (milliseconds)
        max_idle_time_ms: u64 = 300000, // 5 minutes
        /// Enable memory usage monitoring
        enable_monitoring: bool = true,
        /// Warm-up pool size on initialization
        warmup_size: usize = 10,
        /// Enable performance tracking
        enable_performance_tracking: bool = true,
    };

    pub const PoolStats = struct {
        available_count: usize,
        ready_count: usize,
        active_count: usize,
        max_size: usize,
        total_created: u64,
        total_reused: u64,
        total_destroyed: u64,
        peak_usage: usize,
        memory_usage: usize,
        reuse_ratio: f64,
        efficiency: f64,
        avg_allocation_time_ns: u64,
        avg_reuse_time_ns: u64,
        cleanup_count: u64,
    };

    pub fn init(allocator: std.mem.Allocator, config: PoolConfig) !OptimizedCoroutinePool {
        var pool = OptimizedCoroutinePool{
            .allocator = allocator,
            .available = .{},
            .ready_queue = .{},
            .max_size = config.max_pool_size,
            .total_created = 0,
            .total_reused = 0,
            .total_destroyed = 0,
            .stack_size = config.default_stack_size,
            .mutex = .init,
            .config = config,
            .peak_usage = 0,
            .last_cleanup = @intCast(time_compat.milliTimestamp()),
            .memory_usage = std.atomic.Value(usize).init(0),
            .active_coroutines = std.atomic.Value(usize).init(0),
            .allocation_time_ns = 0,
            .reuse_time_ns = 0,
            .cleanup_count = 0,
        };

        // Pre-allocate capacity to avoid reallocations
        pool.available.ensureTotalCapacity(allocator, config.max_pool_size) catch {};
        pool.ready_queue.ensureTotalCapacity(allocator, config.max_pool_size) catch {};

        // Warm up the pool if requested
        if (config.warmup_size > 0) {
            try pool.warmUp(config.warmup_size);
        }

        return pool;
    }

    /// Initialize with default configuration
    pub fn initDefault(allocator: std.mem.Allocator) !OptimizedCoroutinePool {
        return init(allocator, PoolConfig{});
    }

    pub fn deinit(self: *OptimizedCoroutinePool) void {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        // Clean up all pooled coroutines
        for (self.available.items) |coroutine| {
            self.destroyCoroutine(coroutine);
        }
        self.available.deinit(self.allocator);

        // Clean up ready queue
        for (self.ready_queue.items) |coroutine| {
            self.destroyCoroutine(coroutine);
        }
        self.ready_queue.deinit(self.allocator);
    }

    /// Get a coroutine from the pool or create a new one
    pub fn acquire(self: *OptimizedCoroutinePool, id: u64, callback: Value, args: []Value) !*OptimizedCoroutine {
        const start_time = if (self.config.enable_performance_tracking) time_compat.nanoTimestamp() else 0;

        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        // Perform automatic cleanup if enabled
        if (self.config.enable_auto_cleanup) {
            self.performCleanupIfNeeded();
        }

        var coroutine: *OptimizedCoroutine = undefined;

        if (self.available.items.len > 0) {
            // Reuse existing coroutine
            coroutine = self.available.pop().?;
            try coroutine.reset(id, callback, args);
            self.total_reused += 1;

            if (self.config.enable_performance_tracking) {
                const elapsed = time_compat.nanoTimestamp() - start_time;
                self.reuse_time_ns = @as(u64, @intCast(@divTrunc(@as(i128, self.reuse_time_ns) + elapsed, 2))); // Running average
            }
        } else {
            // Create new coroutine
            coroutine = try OptimizedCoroutine.initWithStackSize(self.allocator, id, callback, args, self.stack_size);
            self.total_created += 1;

            if (self.config.enable_performance_tracking) {
                const elapsed = time_compat.nanoTimestamp() - start_time;
                self.allocation_time_ns = @as(u64, @intCast(@divTrunc(@as(i128, self.allocation_time_ns) + elapsed, 2))); // Running average
            }
        }

        // Update monitoring counters
        _ = self.active_coroutines.fetchAdd(1, .monotonic);
        if (self.config.enable_monitoring) {
            self.updateMemoryUsage();
        }

        return coroutine;
    }

    /// Return a coroutine to the pool
    pub fn release(self: *OptimizedCoroutinePool, coroutine: *OptimizedCoroutine) void {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        // Update active counter
        _ = self.active_coroutines.fetchSub(1, .monotonic);

        // Reset coroutine state for reuse
        coroutine.state = .created;
        coroutine.result = null;
        coroutine.stack.reset();
        coroutine.context.reset();

        if (self.available.items.len < self.max_size) {
            // Add to pool for reuse
            self.available.append(self.allocator, coroutine) catch {
                // If append fails, destroy the coroutine
                self.destroyCoroutine(coroutine);
                return;
            };

            // Update peak usage
            if (self.available.items.len > self.peak_usage) {
                self.peak_usage = self.available.items.len;
            }
        } else {
            // Pool is full, destroy the coroutine
            self.destroyCoroutine(coroutine);
        }

        if (self.config.enable_monitoring) {
            self.updateMemoryUsage();
        }
    }

    /// Add ready coroutine to ready queue (Requirement 6.8)
    pub fn addReady(self: *OptimizedCoroutinePool, coroutine: *OptimizedCoroutine) !void {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        coroutine.state = .ready;
        try self.ready_queue.append(self.allocator, coroutine);
    }

    /// Get next ready coroutine (Requirement 6.8)
    pub fn getReady(self: *OptimizedCoroutinePool) ?*OptimizedCoroutine {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        if (self.ready_queue.items.len > 0) {
            return self.ready_queue.orderedRemove(0);
        }
        return null;
    }

    /// Get comprehensive pool statistics
    pub fn getStats(self: *OptimizedCoroutinePool) PoolStats {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        return PoolStats{
            .available_count = self.available.items.len,
            .ready_count = self.ready_queue.items.len,
            .active_count = self.active_coroutines.load(.monotonic),
            .max_size = self.max_size,
            .total_created = self.total_created,
            .total_reused = self.total_reused,
            .total_destroyed = self.total_destroyed,
            .peak_usage = self.peak_usage,
            .memory_usage = self.memory_usage.load(.monotonic),
            .reuse_ratio = if (self.total_created > 0)
                @as(f64, @floatFromInt(self.total_reused)) / @as(f64, @floatFromInt(self.total_created))
            else
                0.0,
            .efficiency = if (self.total_created + self.total_reused > 0)
                @as(f64, @floatFromInt(self.total_reused)) / @as(f64, @floatFromInt(self.total_created + self.total_reused))
            else
                0.0,
            .avg_allocation_time_ns = self.allocation_time_ns,
            .avg_reuse_time_ns = self.reuse_time_ns,
            .cleanup_count = self.cleanup_count,
        };
    }

    /// Warm up the pool by pre-allocating coroutines
    pub fn warmUp(self: *OptimizedCoroutinePool, count: usize) !void {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        const target_count = @min(count, self.max_size);
        const callback = Value.initNull();
        const args = [_]Value{};

        while (self.available.items.len < target_count) {
            const coroutine = try OptimizedCoroutine.initWithStackSize(self.allocator, 0, callback, &args, self.stack_size);
            try self.available.append(self.allocator, coroutine);
            self.total_created += 1;
        }

        if (self.config.enable_monitoring) {
            self.updateMemoryUsage();
        }
    }

    /// Get current memory usage of the pool
    pub fn getMemoryUsage(self: *OptimizedCoroutinePool) usize {
        return self.memory_usage.load(.monotonic);
    }

    // Private helper methods

    /// Destroy a coroutine and update counters
    fn destroyCoroutine(self: *OptimizedCoroutinePool, coroutine: *OptimizedCoroutine) void {
        coroutine.deinit(self.allocator);
        self.allocator.destroy(coroutine);
        self.total_destroyed += 1;
    }

    /// Perform cleanup if needed based on time interval
    fn performCleanupIfNeeded(self: *OptimizedCoroutinePool) void {
        const now = @as(i64, @intCast(time_compat.milliTimestamp()));
        if (now - self.last_cleanup > self.config.cleanup_interval_ms) {
            self.performCleanup();
            self.last_cleanup = now;
        }
    }

    /// Perform actual cleanup
    fn performCleanup(self: *OptimizedCoroutinePool) void {
        // Simple cleanup: remove half of available coroutines if pool is large
        if (self.available.items.len > self.max_size / 2) {
            const to_remove = self.available.items.len / 2;
            for (0..to_remove) |_| {
                if (self.available.items.len > 0) {
                    const coroutine = self.available.pop().?;
                    self.destroyCoroutine(coroutine);
                }
            }
            self.cleanup_count += 1;
        }

        if (self.config.enable_monitoring) {
            self.updateMemoryUsage();
        }
    }

    /// Update memory usage statistics
    fn updateMemoryUsage(self: *OptimizedCoroutinePool) void {
        var total_memory: usize = 0;

        // Calculate memory for available coroutines
        for (self.available.items) |coroutine| {
            total_memory += coroutine.getMemoryUsage();
        }

        // Calculate memory for ready coroutines
        for (self.ready_queue.items) |coroutine| {
            total_memory += coroutine.getMemoryUsage();
        }

        // Add overhead for the pool itself
        total_memory += @sizeOf(OptimizedCoroutinePool);
        total_memory += self.available.capacity * @sizeOf(*OptimizedCoroutine);
        total_memory += self.ready_queue.capacity * @sizeOf(*OptimizedCoroutine);

        self.memory_usage.store(total_memory, .monotonic);
    }
};

/// 协程上下文（类似Go的context.Context）
/// 提供超时控制、取消信号、值传递等功能
pub const Context = struct {
    allocator: std.mem.Allocator,
    parent: ?*Context,

    /// 取消信号
    cancelled: std.atomic.Value(bool),
    cancel_reason: ?[]const u8,

    /// 超时控制
    deadline: ?i64,

    /// 上下文值存储
    values: std.StringHashMap(Value),

    /// 子上下文列表
    children: std.ArrayList(*Context),

    /// 取消回调
    on_cancel: ?*const fn (*Context) void,

    pub fn init(allocator: std.mem.Allocator) Context {
        return Context{
            .allocator = allocator,
            .parent = null,
            .cancelled = std.atomic.Value(bool).init(false),
            .cancel_reason = null,
            .deadline = null,
            .values = std.StringHashMap(Value).init(allocator),
            .children = .empty,
            .on_cancel = null,
        };
    }

    pub fn deinit(self: *Context) void {
        var iter = self.values.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(self.allocator);
        }
        self.values.deinit();
        self.children.deinit(self.allocator);
        if (self.cancel_reason) |reason| {
            self.allocator.free(reason);
        }
    }

    /// 创建带超时的子上下文
    pub fn withTimeout(self: *Context, timeout_ms: u64) !*Context {
        const child = try self.allocator.create(Context);
        child.* = Context.init(self.allocator);
        child.parent = self;
        child.deadline = time_compat.milliTimestamp() + @as(i64, @intCast(timeout_ms));
        try self.children.append(self.allocator, child);
        return child;
    }

    /// 创建带值的子上下文
    pub fn withValue(self: *Context, key: []const u8, value: Value) !*Context {
        const child = try self.allocator.create(Context);
        child.* = Context.init(self.allocator);
        child.parent = self;
        _ = value.retain();
        try child.values.put(key, value);
        try self.children.append(self.allocator, child);
        return child;
    }

    /// 取消上下文（级联取消所有子上下文）
    pub fn cancel(self: *Context, reason: ?[]const u8) void {
        if (self.cancelled.load(.seq_cst)) return;
        self.cancelled.store(true, .seq_cst);
        if (reason) |r| {
            self.cancel_reason = self.allocator.dupe(u8, r) catch null;
        }
        if (self.on_cancel) |callback| {
            callback(self);
        }
        for (self.children.items) |child| {
            child.cancel(reason);
        }
    }

    /// 检查是否已取消或超时
    pub fn done(self: *Context) bool {
        if (self.cancelled.load(.seq_cst)) return true;
        if (self.deadline) |d| {
            if (time_compat.milliTimestamp() >= d) return true;
        }
        if (self.parent) |p| return p.done();
        return false;
    }

    /// 获取上下文值（向上查找）
    pub fn getValue(self: *Context, key: []const u8) ?Value {
        if (self.values.get(key)) |v| return v;
        if (self.parent) |p| return p.getValue(key);
        return null;
    }

    /// 设置上下文值
    pub fn setValue(self: *Context, key: []const u8, value: Value) !void {
        if (self.values.get(key)) |old| {
            old.release(self.allocator);
        }
        _ = value.retain();
        try self.values.put(key, value);
    }

    /// 获取错误原因
    pub fn err(self: *Context) ?[]const u8 {
        if (self.cancelled.load(.seq_cst)) {
            return self.cancel_reason orelse "context cancelled";
        }
        if (self.deadline) |d| {
            if (time_compat.milliTimestamp() >= d) return "deadline exceeded";
        }
        if (self.parent) |p| return p.err();
        return null;
    }
};

/// 协程优先级定义
pub const Priority = enum(u8) {
    /// 最高优先级 - 系统关键任务
    critical = 0,
    /// 高优先级 - 用户交互任务
    high = 1,
    /// 普通优先级 - 默认
    normal = 2,
    /// 低优先级 - 后台任务
    low = 3,
    /// 最低优先级 - 空闲任务
    idle = 4,

    pub fn toWeight(self: Priority) u32 {
        return switch (self) {
            .critical => 16,
            .high => 8,
            .normal => 4,
            .low => 2,
            .idle => 1,
        };
    }
};

/// 优先级队列 - 用于协程调度
pub const PriorityQueue = struct {
    allocator: std.mem.Allocator,
    /// 每个优先级一个队列
    queues: [5]std.ArrayList(*Coroutine),
    /// 各优先级的时间片配额
    time_slices: [5]u32,
    /// 当前优先级的剩余时间片
    current_slices: [5]u32,
    /// 总协程数
    total_count: usize,
    /// 调度统计
    stats: SchedulerStats,

    pub const SchedulerStats = struct {
        total_scheduled: u64 = 0,
        priority_scheduled: [5]u64 = @splat(0),
        starvation_prevented: u64 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) PriorityQueue {
        var pq = PriorityQueue{
            .allocator = allocator,
            .queues = undefined,
            .time_slices = [_]u32{ 16, 8, 4, 2, 1 }, // 权重比例
            .current_slices = [_]u32{ 16, 8, 4, 2, 1 },
            .total_count = 0,
            .stats = .{},
        };
        for (&pq.queues) |*q| {
            q.* = .empty;
        }
        return pq;
    }

    pub fn deinit(self: *PriorityQueue) void {
        for (&self.queues) |*q| {
            q.deinit(self.allocator);
        }
    }

    /// 入队
    pub fn enqueue(self: *PriorityQueue, co: *Coroutine) !void {
        const idx = @intFromEnum(co.priority);
        try self.queues[idx].append(self.allocator, co);
        self.total_count += 1;
    }

    /// 出队 - 使用加权公平调度
    pub fn dequeue(self: *PriorityQueue) ?*Coroutine {
        if (self.total_count == 0) return null;

        // 加权公平调度：按时间片配额轮询
        var attempts: usize = 0;
        while (attempts < 5) {
            for (0..5) |i| {
                if (self.current_slices[i] > 0 and self.queues[i].items.len > 0) {
                    self.current_slices[i] -= 1;
                    self.total_count -= 1;
                    self.stats.total_scheduled += 1;
                    self.stats.priority_scheduled[i] += 1;
                    return self.queues[i].orderedRemove(0);
                }
            }
            // 重置时间片
            self.resetTimeSlices();
            attempts += 1;
        }

        // 防止饥饿：如果高优先级队列为空，从低优先级取
        for (0..5) |i| {
            const idx = 4 - i; // 从低优先级开始
            if (self.queues[idx].items.len > 0) {
                self.total_count -= 1;
                self.stats.total_scheduled += 1;
                self.stats.priority_scheduled[idx] += 1;
                self.stats.starvation_prevented += 1;
                return self.queues[idx].orderedRemove(0);
            }
        }

        return null;
    }

    /// 重置时间片配额
    fn resetTimeSlices(self: *PriorityQueue) void {
        for (0..5) |i| {
            self.current_slices[i] = self.time_slices[i];
        }
    }

    /// 获取队列长度
    pub fn len(self: *PriorityQueue) usize {
        return self.total_count;
    }

    /// 检查是否为空
    pub fn isEmpty(self: *PriorityQueue) bool {
        return self.total_count == 0;
    }

    /// 获取指定优先级的队列长度
    pub fn lenAt(self: *PriorityQueue, priority: Priority) usize {
        return self.queues[@intFromEnum(priority)].items.len;
    }

    /// 移除指定协程
    pub fn remove(self: *PriorityQueue, co: *Coroutine) bool {
        const idx = @intFromEnum(co.priority);
        for (self.queues[idx].items, 0..) |item, i| {
            if (item == co) {
                _ = self.queues[idx].orderedRemove(i);
                self.total_count -= 1;
                return true;
            }
        }
        return false;
    }

    /// 提升协程优先级（用于防止饥饿）
    pub fn boostPriority(self: *PriorityQueue, co: *Coroutine) void {
        if (@intFromEnum(co.priority) > 0) {
            if (self.remove(co)) {
                co.priority = @enumFromInt(@intFromEnum(co.priority) - 1);
                self.enqueue(co) catch {};
            }
        }
    }

    /// 获取调度统计
    pub fn getStats(self: *PriorityQueue) SchedulerStats {
        return self.stats;
    }

    /// 重置统计
    pub fn resetStats(self: *PriorityQueue) void {
        self.stats = .{};
    }
};

/// PHP协程管理系统
/// 提供轻量级协程支持，类似Go的goroutine
pub const CoroutineManager = struct {
    allocator: std.mem.Allocator,
    coroutines: std.AutoHashMap(u64, *Coroutine),
    finished: std.AutoHashMap(u64, FinishedCoroutine),
    /// 优先级就绪队列（替代原来的简单队列）
    priority_queue: PriorityQueue,
    /// 保留原始队列用于兼容
    ready_queue: std.ArrayList(*Coroutine),
    sleeping_queue: std.ArrayList(*Coroutine),
    /// IO等待队列
    io_waiting_queue: std.ArrayList(*Coroutine),
    next_id: std.atomic.Value(u64),
    current_coroutine: ?*Coroutine,
    scheduler_running: std.atomic.Value(bool),
    mutex: std.Io.Mutex,
    cond: std.Io.Condition,

    // 协程池用于重用
    pool: std.ArrayList(*Coroutine),
    pool_max_size: usize,

    /// 调度策略
    scheduling_policy: SchedulingPolicy,

    /// 饥饿检测阈值（协程等待超过此时间片数将被提升优先级）
    starvation_threshold: u32,

    /// 异步IO反应器（可选）
    io_reactor: ?*AsyncIOReactor,

    const FinishedCoroutine = struct {
        err: ?anyerror,
    };

    pub const SchedulingPolicy = enum {
        /// 简单FIFO（兼容模式）
        fifo,
        /// 优先级调度
        priority,
        /// 加权公平调度
        weighted_fair,
    };

    pub fn init(allocator: std.mem.Allocator) CoroutineManager {
        return CoroutineManager{
            .allocator = allocator,
            .coroutines = std.AutoHashMap(u64, *Coroutine).init(allocator),
            .finished = std.AutoHashMap(u64, FinishedCoroutine).init(allocator),
            .priority_queue = PriorityQueue.init(allocator),
            .ready_queue = .empty,
            .sleeping_queue = .empty,
            .io_waiting_queue = .empty,
            .next_id = std.atomic.Value(u64).init(1),
            .current_coroutine = null,
            .scheduler_running = std.atomic.Value(bool).init(false),
            .mutex = .init,
            .cond = .init,
            .pool = .empty,
            .pool_max_size = 1000,
            .scheduling_policy = .weighted_fair,
            .starvation_threshold = 100,
            .io_reactor = null,
        };
    }

    pub fn deinit(self: *CoroutineManager) void {
        // 停止所有协程
        self.stopAll();

        // 清理协程
        var iter = self.coroutines.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.coroutines.deinit();
        self.finished.deinit();

        // 清理队列
        self.priority_queue.deinit();
        self.ready_queue.deinit(self.allocator);
        self.sleeping_queue.deinit(self.allocator);
        self.io_waiting_queue.deinit(self.allocator);

        // 清理IO反应器
        if (self.io_reactor) |reactor| {
            reactor.deinit();
            self.allocator.destroy(reactor);
        }

        // 清理池
        for (self.pool.items) |co| {
            co.deinit();
            self.allocator.destroy(co);
        }
        self.pool.deinit(self.allocator);
    }

    /// 创建新协程
    pub fn spawn(self: *CoroutineManager, callback: Value, args: []const Value) !u64 {
        return self.spawnWithPriority(callback, args, .normal);
    }

    /// 创建带优先级的新协程
    pub fn spawnWithPriority(self: *CoroutineManager, callback: Value, args: []const Value, priority: Priority) !u64 {
        const id = self.next_id.fetchAdd(1, .seq_cst);

        // 尝试从池中获取协程
        var coroutine: *Coroutine = undefined;
        if (self.pool.items.len > 0) {
            coroutine = self.pool.pop() orelse return error.PoolEmpty;
            coroutine.reset(id, callback, args);
            coroutine.priority = priority;
        } else {
            coroutine = try self.allocator.create(Coroutine);
            coroutine.* = try Coroutine.init(self.allocator, id, callback, args);
            coroutine.priority = priority;
        }

        try self.coroutines.put(id, coroutine);

        // 加入优先级队列
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        switch (self.scheduling_policy) {
            .fifo => try self.ready_queue.append(self.allocator, coroutine),
            .priority, .weighted_fair => try self.priority_queue.enqueue(coroutine),
        }
        self.cond.signal(std.Io.Threaded.global_single_threaded.io());

        return id;
    }

    pub fn processOneStep(self: *CoroutineManager, vm: *anyopaque) !bool {
        try self.wakeUpSleeping();
        try self.pollIOEvents();
        self.checkStarvation();

        const next_coroutine = self.getNextReady();
        if (next_coroutine == null) return false;

        const co = next_coroutine.?;
        self.current_coroutine = co;
        co.scheduled_count += 1;

        var exec_err: ?anyerror = null;
        const result = co.resumeExecution(vm) catch |err| blk: {
            exec_err = err;
            break :blk Value.initNull();
        };

        if (exec_err) |err| {
            co.state = .completed;
            co.result = Value.initNull();
            self.finished.put(co.id, .{ .err = err }) catch {};
            self.recycleCoroutine(co);
            self.current_coroutine = null;
            return true;
        }

        switch (co.state) {
            .completed => {
                co.result = result;
                self.finished.put(co.id, .{ .err = null }) catch {};
                self.recycleCoroutine(co);
            },
            .yielded => {
                self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
                switch (self.scheduling_policy) {
                    .fifo => self.ready_queue.append(self.allocator, co) catch {},
                    .priority, .weighted_fair => self.priority_queue.enqueue(co) catch {},
                }
                self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
            },
            .sleeping => {
                self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
                self.sleeping_queue.append(self.allocator, co) catch {};
                self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
            },
            .waiting => {},
            else => {},
        }

        self.current_coroutine = null;
        return true;
    }

    /// 运行调度器
    pub fn run(self: *CoroutineManager, vm: *anyopaque) !void {
        self.scheduler_running.store(true, .seq_cst);

        while (self.scheduler_running.load(.seq_cst)) {
            if (try self.processOneStep(vm)) continue;
            {
                // 没有就绪协程，检查是否还有等待中的协程
                self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
                const has_ready = switch (self.scheduling_policy) {
                    .fifo => self.ready_queue.items.len > 0,
                    .priority, .weighted_fair => !self.priority_queue.isEmpty(),
                };
                const has_sleeping = self.sleeping_queue.items.len > 0;
                const has_io_waiting = self.io_waiting_queue.items.len > 0;

                if (!has_ready and !has_sleeping and !has_io_waiting) {
                    // 没有任何等待中的协程，退出调度器
                    self.scheduler_running.store(false, .seq_cst);
                    self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
                    break;
                }

                // 如果有IO等待的协程，使用较短的等待时间以便及时响应IO事件
                const wait_time: u64 = if (has_io_waiting) 100_000 else 1_000_000; // 0.1ms or 1ms
                {
                    const sched_io = std.Io.Threaded.global_single_threaded.io();
                    self.cond.waitTimeout(sched_io, &self.mutex, .{ .duration = .{ .raw = .{ .nanoseconds = @intCast(wait_time) }, .clock = .awake } }) catch {};
                }
                self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
            }
        }
    }

    /// 让出当前协程
    pub fn yield(self: *CoroutineManager) void {
        if (self.current_coroutine) |co| {
            co.state = .yielded;
        }
    }

    /// 休眠当前协程
    pub fn sleep(self: *CoroutineManager, duration_ms: u64) void {
        if (self.current_coroutine) |co| {
            co.state = .sleeping;
            co.wake_time = time_compat.milliTimestamp() + @as(i64, @intCast(duration_ms));
        }
    }

    /// 等待协程完成
    pub fn wait(self: *CoroutineManager, id: u64) ?Value {
        if (self.coroutines.get(id)) |co| {
            while (co.state != .completed) {
                std.Thread.sleep(1_000_000); // 1ms
            }
            return co.result;
        }
        return null;
    }

    pub fn join(self: *CoroutineManager, vm: *anyopaque, id: u64) anyerror!void {
        if (self.currentId()) |current| {
            if (current == id) return error.InvalidArgument;
        }

        while (true) {
            if (self.finished.get(id)) |finished| {
                _ = self.finished.remove(id);
                if (finished.err) |err| return err;
                return;
            }

            if (self.coroutines.get(id) == null) return error.InvalidArgument;

            if (try self.processOneStep(vm)) continue;

            self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
            const has_ready = switch (self.scheduling_policy) {
                .fifo => self.ready_queue.items.len > 0,
                .priority, .weighted_fair => !self.priority_queue.isEmpty(),
            };
            const has_sleeping = self.sleeping_queue.items.len > 0;
            const has_io_waiting = self.io_waiting_queue.items.len > 0;
            const wait_time: u64 = if (has_io_waiting) 100_000 else 1_000_000;
            if (has_ready or has_sleeping or has_io_waiting) {
                self.cond.timedWait(&self.mutex, wait_time) catch {};
            }
            self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
        }
    }

    pub fn drain(self: *CoroutineManager, vm: *anyopaque) !void {
        while (true) {
            if (try self.processOneStep(vm)) continue;

            self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
            const has_ready = switch (self.scheduling_policy) {
                .fifo => self.ready_queue.items.len > 0,
                .priority, .weighted_fair => !self.priority_queue.isEmpty(),
            };
            const has_sleeping = self.sleeping_queue.items.len > 0;
            const has_io_waiting = self.io_waiting_queue.items.len > 0;
            if (!has_ready and !has_sleeping and !has_io_waiting) {
                self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
                return;
            }
            const wait_time: u64 = if (has_io_waiting) 100_000 else 1_000_000;
            self.cond.timedWait(&self.mutex, wait_time) catch {};
            self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
        }
    }

    /// 取消协程
    pub fn cancel(self: *CoroutineManager, id: u64) bool {
        if (self.coroutines.get(id)) |co| {
            co.state = .cancelled;
            return true;
        }
        return false;
    }

    /// 获取当前协程ID
    pub fn currentId(self: *CoroutineManager) ?u64 {
        if (self.current_coroutine) |co| {
            return co.id;
        }
        return null;
    }

    /// 停止所有协程
    pub fn stopAll(self: *CoroutineManager) void {
        self.scheduler_running.store(false, .seq_cst);

        var iter = self.coroutines.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.state = .cancelled;
        }
    }

    fn getNextReady(self: *CoroutineManager) ?*Coroutine {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        return switch (self.scheduling_policy) {
            .fifo => {
                if (self.ready_queue.items.len > 0) {
                    return self.ready_queue.orderedRemove(0);
                }
                return null;
            },
            .priority, .weighted_fair => self.priority_queue.dequeue(),
        };
    }

    /// 检查饥饿并提升优先级
    fn checkStarvation(self: *CoroutineManager) void {
        if (self.scheduling_policy == .fifo) return;

        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        // 检查低优先级队列中等待过久的协程
        for (3..5) |i| {
            for (self.priority_queue.queues[i].items) |co| {
                if (co.scheduled_count == 0 and co.wait_count > self.starvation_threshold) {
                    self.priority_queue.boostPriority(co);
                }
                co.wait_count += 1;
            }
        }
    }

    fn wakeUpSleeping(self: *CoroutineManager) !void {
        const now = time_compat.milliTimestamp();

        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        var i: usize = 0;
        while (i < self.sleeping_queue.items.len) {
            const co = self.sleeping_queue.items[i];
            if (co.wake_time <= now) {
                co.state = .ready;
                switch (self.scheduling_policy) {
                    .fifo => try self.ready_queue.append(self.allocator, co),
                    .priority, .weighted_fair => try self.priority_queue.enqueue(co),
                }
                _ = self.sleeping_queue.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    fn recycleCoroutine(self: *CoroutineManager, co: *Coroutine) void {
        _ = self.coroutines.remove(co.id);

        if (self.pool.items.len < self.pool_max_size) {
            self.pool.append(self.allocator, co) catch {
                co.deinit();
                self.allocator.destroy(co);
            };
        } else {
            co.deinit();
            self.allocator.destroy(co);
        }
    }

    /// 设置调度策略
    pub fn setSchedulingPolicy(self: *CoroutineManager, policy: SchedulingPolicy) void {
        self.scheduling_policy = policy;
    }

    /// 获取调度策略
    pub fn getSchedulingPolicy(self: *CoroutineManager) SchedulingPolicy {
        return self.scheduling_policy;
    }

    /// 设置协程优先级
    pub fn setPriority(self: *CoroutineManager, id: u64, priority: Priority) bool {
        if (self.coroutines.get(id)) |co| {
            self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
            defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

            // 如果协程在优先级队列中，需要移动
            if (self.scheduling_policy != .fifo) {
                if (self.priority_queue.remove(co)) {
                    co.priority = priority;
                    self.priority_queue.enqueue(co) catch return false;
                } else {
                    co.priority = priority;
                }
            } else {
                co.priority = priority;
            }
            return true;
        }
        return false;
    }

    /// 获取协程优先级
    pub fn getPriority(self: *CoroutineManager, id: u64) ?Priority {
        if (self.coroutines.get(id)) |co| {
            return co.priority;
        }
        return null;
    }

    /// 获取调度统计信息
    pub fn getSchedulerStats(self: *CoroutineManager) PriorityQueue.SchedulerStats {
        return self.priority_queue.getStats();
    }

    /// 重置调度统计
    pub fn resetSchedulerStats(self: *CoroutineManager) void {
        self.priority_queue.resetStats();
    }

    /// 获取各优先级队列长度
    pub fn getQueueLengths(self: *CoroutineManager) [5]usize {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        var lengths: [5]usize = undefined;
        for (0..5) |i| {
            lengths[i] = self.priority_queue.queues[i].items.len;
        }
        return lengths;
    }

    /// 设置饥饿检测阈值
    pub fn setStarvationThreshold(self: *CoroutineManager, threshold: u32) void {
        self.starvation_threshold = threshold;
    }

    // ========== 异步IO集成方法 ==========

    /// 初始化异步IO反应器
    pub fn initIOReactor(self: *CoroutineManager) !void {
        if (self.io_reactor != null) return; // 已初始化

        const reactor = try self.allocator.create(AsyncIOReactor);
        reactor.* = try AsyncIOReactor.init(self.allocator);
        self.io_reactor = reactor;
    }

    /// 关闭异步IO反应器
    pub fn deinitIOReactor(self: *CoroutineManager) void {
        if (self.io_reactor) |reactor| {
            reactor.deinit();
            self.allocator.destroy(reactor);
            self.io_reactor = null;
        }
    }

    /// 等待IO事件（挂起当前协程）
    pub fn waitForIO(self: *CoroutineManager, fd: i32, event_type: IOEventType, timeout_ms: ?u64) !void {
        if (self.io_reactor == null) {
            try self.initIOReactor();
        }

        if (self.current_coroutine) |co| {
            try self.io_reactor.?.registerFd(fd, event_type, co, timeout_ms);

            // 将协程加入IO等待队列
            self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
            try self.io_waiting_queue.append(self.allocator, co);
            self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
        }
    }

    /// 等待定时器（挂起当前协程指定时间）
    pub fn waitForTimer(self: *CoroutineManager, delay_ms: u64) !void {
        if (self.io_reactor == null) {
            try self.initIOReactor();
        }

        if (self.current_coroutine) |co| {
            try self.io_reactor.?.registerTimer(co, delay_ms, null);

            // 将协程加入IO等待队列
            self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
            try self.io_waiting_queue.append(self.allocator, co);
            self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
        }
    }

    /// 取消IO等待
    pub fn cancelIOWait(self: *CoroutineManager, fd: i32) !void {
        if (self.io_reactor) |reactor| {
            try reactor.unregisterFd(fd);
        }
    }

    /// 轮询IO事件并唤醒就绪的协程
    fn pollIOEvents(self: *CoroutineManager) !void {
        if (self.io_reactor == null) return;

        const reactor = self.io_reactor.?;

        // 非阻塞轮询
        const events = try reactor.poll(0);
        defer self.allocator.free(events);

        // 将就绪的协程从IO等待队列移到就绪队列
        for (events) |event| {
            if (event.coroutine_id) |co_id| {
                if (self.coroutines.get(co_id)) |co| {
                    self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());

                    // 从IO等待队列移除
                    for (self.io_waiting_queue.items, 0..) |waiting_co, i| {
                        if (waiting_co.id == co_id) {
                            _ = self.io_waiting_queue.orderedRemove(i);
                            break;
                        }
                    }

                    // 加入就绪队列
                    if (co.state == .ready) {
                        switch (self.scheduling_policy) {
                            .fifo => self.ready_queue.append(self.allocator, co) catch {},
                            .priority, .weighted_fair => self.priority_queue.enqueue(co) catch {},
                        }
                    }

                    self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
                }
            }
        }
    }

    /// 检查是否有IO等待中的协程
    pub fn hasIOWaiting(self: *CoroutineManager) bool {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
        return self.io_waiting_queue.items.len > 0;
    }

    /// 获取IO等待队列长度
    pub fn getIOWaitingCount(self: *CoroutineManager) usize {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
        return self.io_waiting_queue.items.len;
    }

    /// 获取IO反应器统计信息
    pub fn getIOStats(self: *CoroutineManager) ?AsyncIOReactor.IOStats {
        if (self.io_reactor) |reactor| {
            return reactor.getStats();
        }
        return null;
    }

    /// 重置IO统计信息
    pub fn resetIOStats(self: *CoroutineManager) void {
        if (self.io_reactor) |reactor| {
            reactor.resetStats();
        }
    }
};

/// 协程
pub const Coroutine = struct {
    id: u64,
    state: State,
    callback: Value,
    args: []Value,
    result: ?Value,
    wake_time: i64,
    stack: CoroutineStack,
    allocator: std.mem.Allocator,

    /// 协程优先级
    priority: Priority,

    /// 调度计数（被调度执行的次数）
    scheduled_count: u64,

    /// 等待计数（用于饥饿检测）
    wait_count: u32,

    /// 任务局部存储（Task-Local Storage）
    task_locals: std.StringHashMap(Value),

    /// 清理钩子列表（__on_coroutine_exit）
    cleanup_hooks: std.ArrayList(CleanupHook),

    /// 协程级超全局变量副本（$_GET, $_POST等的协程隔离）
    superglobals: SuperglobalsCopy,

    /// 协程上下文（$context隐藏变量，类似Go的context）
    context: *Context,

    pub const State = enum {
        created,
        ready,
        running,
        yielded,
        sleeping,
        waiting,
        completed,
        cancelled,
    };

    pub const CleanupHook = struct {
        callback: Value,
        priority: u8, // 清理优先级，数值越大越先执行
    };

    /// 超全局变量的协程级副本
    pub const SuperglobalsCopy = struct {
        get: ?*types.PHPArray = null,
        post: ?*types.PHPArray = null,
        request: ?*types.PHPArray = null,
        session: ?*types.PHPArray = null,
        server: ?*types.PHPArray = null,
        cookie: ?*types.PHPArray = null,
    };

    pub fn init(allocator: std.mem.Allocator, id: u64, callback: Value, args: []const Value) !Coroutine {
        // 复制参数
        var args_copy = try allocator.alloc(Value, args.len);
        for (args, 0..) |arg, i| {
            args_copy[i] = arg.retain();
        }

        // 创建协程上下文
        const ctx = try allocator.create(Context);
        ctx.* = Context.init(allocator);

        return Coroutine{
            .id = id,
            .state = .ready,
            .callback = callback.retain(),
            .args = args_copy,
            .result = null,
            .wake_time = 0,
            .stack = CoroutineStack.init(allocator),
            .allocator = allocator,
            .priority = .normal,
            .scheduled_count = 0,
            .wait_count = 0,
            .task_locals = std.StringHashMap(Value).init(allocator),
            .cleanup_hooks = .empty,
            .superglobals = .{},
            .context = ctx,
        };
    }

    pub fn deinit(self: *Coroutine) void {
        // 执行清理钩子
        self.runCleanupHooks();

        self.callback.release(self.allocator);
        for (self.args) |*arg| {
            arg.release(self.allocator);
        }
        self.allocator.free(self.args);
        if (self.result) |*r| {
            r.release(self.allocator);
        }
        self.stack.deinit();

        // 清理任务局部存储
        var iter = self.task_locals.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(self.allocator);
        }
        self.task_locals.deinit();

        // 清理钩子列表
        for (self.cleanup_hooks.items) |*hook| {
            hook.callback.release(self.allocator);
        }
        self.cleanup_hooks.deinit(self.allocator);

        // 清理协程上下文
        self.context.deinit();
        self.allocator.destroy(self.context);
    }

    /// 设置任务局部变量
    pub fn setTaskLocal(self: *Coroutine, key: []const u8, value: Value) !void {
        if (self.task_locals.get(key)) |old_value| {
            old_value.release(self.allocator);
        }
        _ = value.retain();
        try self.task_locals.put(key, value);
    }

    /// 获取任务局部变量
    pub fn getTaskLocal(self: *Coroutine, key: []const u8) ?Value {
        return self.task_locals.get(key);
    }

    /// 删除任务局部变量
    pub fn removeTaskLocal(self: *Coroutine, key: []const u8) void {
        if (self.task_locals.fetchRemove(key)) |kv| {
            kv.value.release(self.allocator);
        }
    }

    /// 注册清理钩子
    pub fn registerCleanupHook(self: *Coroutine, callback: Value, priority: u8) !void {
        _ = callback.retain();
        try self.cleanup_hooks.append(self.allocator, .{
            .callback = callback,
            .priority = priority,
        });
    }

    /// 执行清理钩子（按优先级从高到低）
    fn runCleanupHooks(self: *Coroutine) void {
        // 按优先级排序（降序）
        std.mem.sort(CleanupHook, self.cleanup_hooks.items, {}, struct {
            fn lessThan(_: void, a: CleanupHook, b: CleanupHook) bool {
                return a.priority > b.priority;
            }
        }.lessThan);

        // 执行钩子：释放回调资源
        for (self.cleanup_hooks.items) |hook| {
            const tag = hook.callback.getTag();
            switch (tag) {
                .closure => hook.callback.getAsClosure().release(self.allocator),
                .user_function => hook.callback.getAsUserFunc().release(self.allocator),
                .arrow_function => hook.callback.getAsArrowFunc().release(self.allocator),
                else => {},
            }
        }
    }

    pub fn reset(self: *Coroutine, id: u64, callback: Value, args: []const Value) void {
        // 清理旧数据
        self.callback.release(self.allocator);
        for (self.args) |*arg| {
            arg.release(self.allocator);
        }
        if (self.result) |*r| {
            r.release(self.allocator);
        }

        // 设置新数据
        self.id = id;
        self.state = .ready;
        self.callback = callback.retain();
        self.priority = .normal;
        self.scheduled_count = 0;
        self.wait_count = 0;

        // 重新分配参数
        if (self.args.len != args.len) {
            self.allocator.free(self.args);
            self.args = self.allocator.alloc(Value, args.len) catch &[_]Value{};
        }
        for (args, 0..) |arg, i| {
            self.args[i] = arg.retain();
        }

        self.result = null;
        self.wake_time = 0;
        self.stack.reset();
    }

    /// 恢复协程执行
    pub fn resumeExecution(self: *Coroutine, vm: *anyopaque) !Value {
        if (self.state == .cancelled) {
            return Value.initNull();
        }

        self.state = .running;

        // 调用回调函数
        const result = try self.invokeCallback(vm);

        if (self.state == .running) {
            self.state = .completed;
        }

        return result;
    }

    fn invokeCallback(self: *Coroutine, vm: *anyopaque) !Value {
        const VM = @import("vm.zig").VM;
        const vm_instance: *VM = @ptrCast(@alignCast(vm));

        const tag = self.callback.getTag();
        return switch (tag) {
            .closure => {
                const closure_box = self.callback.getAsClosure();
                return vm_instance.callClosure(closure_box.data, self.args);
            },
            .user_function => {
                const func_box = self.callback.getAsUserFunc();
                return vm_instance.callUserFunction(func_box.data, self.args);
            },
            .arrow_function => {
                const arrow_box = self.callback.getAsArrowFunc();
                return vm_instance.callArrowFunction(arrow_box.data, self.args);
            },
            else => Value.initNull(),
        };
    }
};

/// 协程栈
pub const CoroutineStack = struct {
    allocator: std.mem.Allocator,
    frames: std.ArrayList(StackFrame),

    pub const StackFrame = struct {
        locals: std.StringHashMap(Value),
        return_address: usize,

        pub fn init(allocator: std.mem.Allocator) StackFrame {
            return StackFrame{
                .locals = std.StringHashMap(Value).init(allocator),
                .return_address = 0,
            };
        }

        pub fn deinit(self: *StackFrame, allocator: std.mem.Allocator) void {
            var iter = self.locals.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.release(allocator);
            }
            self.locals.deinit();
        }
    };

    pub fn init(allocator: std.mem.Allocator) CoroutineStack {
        return CoroutineStack{
            .allocator = allocator,
            .frames = .empty,
        };
    }

    pub fn deinit(self: *CoroutineStack) void {
        for (self.frames.items) |*frame| {
            frame.deinit(self.allocator);
        }
        self.frames.deinit(self.allocator);
    }

    pub fn reset(self: *CoroutineStack) void {
        for (self.frames.items) |*frame| {
            frame.deinit(self.allocator);
        }
        self.frames.clearRetainingCapacity();
    }

    pub fn push(self: *CoroutineStack) !*StackFrame {
        try self.frames.append(StackFrame.init(self.allocator));
        return &self.frames.items[self.frames.items.len - 1];
    }

    pub fn pop(self: *CoroutineStack) void {
        if (self.frames.items.len > 0) {
            var frame = self.frames.pop();
            frame.deinit(self.allocator);
        }
    }

    pub fn current(self: *CoroutineStack) ?*StackFrame {
        if (self.frames.items.len > 0) {
            return &self.frames.items[self.frames.items.len - 1];
        }
        return null;
    }
};

/// Channel - 协程间通信 (使用新的高性能实现)
pub const Channel = @import("channel.zig").Channel;

/// 泛型Channel包装器，用于向后兼容
/// 注意：这个实现将T类型的值包装为Value类型
pub fn GenericChannel(comptime T: type) type {
    return struct {
        const Self = @This();
        inner: *Channel,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            const inner = try Channel.initWithCapacity(allocator, capacity);
            return Self{
                .inner = inner,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }

        pub fn send(self: *Self, value: T) !void {
            const wrapped_value = try self.wrapValue(value);
            _ = try self.inner.sendWithTimeout(wrapped_value, 0, null);
        }

        pub fn recv(self: *Self) !T {
            const result = try self.inner.recvWithTimeout(0, null);
            if (result) |value| {
                return try self.unwrapValue(value);
            }
            return error.ChannelClosed;
        }

        pub fn trySend(self: *Self, value: T) bool {
            const wrapped_value = self.wrapValue(value) catch return false;
            return self.inner.trySend(wrapped_value);
        }

        pub fn tryRecv(self: *Self) ?T {
            const result = self.inner.tryRecv();
            if (result) |value| {
                return self.unwrapValue(value) catch null;
            }
            return null;
        }

        pub fn close(self: *Self) void {
            self.inner.close();
        }

        pub fn isClosed(self: *Self) bool {
            return self.inner.isClosed();
        }

        pub fn len(self: *Self) usize {
            return self.inner.getSize();
        }

        // 辅助方法：将T类型包装为Value
        fn wrapValue(self: *Self, value: T) !Value {
            switch (T) {
                i32, i64 => return Value.initInt(@intCast(value)),
                f32, f64 => return Value.initFloat(@floatCast(value)),
                bool => return Value.initBool(value),
                []const u8 => return Value.initString(self.allocator, value),
                else => @compileError("Unsupported type for GenericChannel: " ++ @typeName(T)),
            }
        }

        // 辅助方法：将Value解包为T类型
        fn unwrapValue(self: *Self, value: Value) !T {
            _ = self;
            switch (T) {
                i32 => return @intCast(value.asInt()),
                i64 => return value.asInt(),
                f32 => return @floatCast(value.asFloat()),
                f64 => return value.asFloat(),
                bool => return value.asBool(),
                []const u8 => return value.getAsString().data.data,
                else => @compileError("Unsupported type for GenericChannel: " ++ @typeName(T)),
            }
        }
    };
}

/// WaitGroup - 等待一组协程完成
pub const WaitGroup = struct {
    counter: std.atomic.Value(i32),
    mutex: std.Io.Mutex,
    cond: std.Io.Condition,

    pub fn init() WaitGroup {
        return WaitGroup{
            .counter = std.atomic.Value(i32).init(0),
            .mutex = .init,
            .cond = .init,
        };
    }

    /// 增加计数
    pub fn add(self: *WaitGroup, delta: i32) void {
        _ = self.counter.fetchAdd(delta, .seq_cst);
    }

    /// 完成一个
    pub fn done(self: *WaitGroup) void {
        const prev = self.counter.fetchSub(1, .seq_cst);
        if (prev == 1) {
            self.cond.broadcast(std.Io.Threaded.global_single_threaded.io());
        }
    }

    /// 等待所有完成
    pub fn wait(self: *WaitGroup) void {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        while (self.counter.load(.seq_cst) > 0) {
            self.cond.wait(&self.mutex, std.Io.Threaded.global_single_threaded.io());
        }
    }
};

/// Mutex - PHP协程互斥锁
pub const CoMutex = struct {
    locked: std.atomic.Value(bool),
    owner: ?u64,
    waiting: std.ArrayListUnmanaged(u64),
    allocator: std.mem.Allocator,

    const MAX_SPINS: u32 = 1024;

    pub fn init(allocator: std.mem.Allocator) CoMutex {
        return CoMutex{
            .locked = std.atomic.Value(bool).init(false),
            .owner = null,
            .waiting = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CoMutex) void {
        self.waiting.deinit(self.allocator);
    }

    pub fn lock(self: *CoMutex, coroutine_id: u64) void {
        var spins: u32 = 0;
        while (true) {
            // cmpxchgWeak: null = 失败（已被锁），Some(旧值) = 成功（获取锁）
            if (self.locked.cmpxchgWeak(false, true, .acquire, .monotonic)) |_| {
                // 成功获取锁
                self.owner = coroutine_id;
                return;
            } else |_| {
                // 锁已被持有，自旋等待
                spins += 1;
                if (spins > MAX_SPINS) {
                    std.Thread.yield() catch {};
                    spins = 0;
                } else {
                    std.atomic.spinLoopHint();
                }
            }
        }
    }

    pub fn unlock(self: *CoMutex) void {
        self.owner = null;
        self.locked.store(false, .release);
    }

    pub fn tryLock(self: *CoMutex, coroutine_id: u64) bool {
        if (self.locked.cmpxchgWeak(false, true, .acquire, .monotonic)) |_| {
            return false;
        }
        self.owner = coroutine_id;
        return true;
    }
};

/// 读写锁 - 支持多读单写
pub const RWLock = struct {
    readers: std.atomic.Value(i32),
    writer_waiting: std.atomic.Value(bool),
    writer_active: std.atomic.Value(bool),
    mutex: std.Io.Mutex,
    read_cond: std.Io.Condition,
    write_cond: std.Io.Condition,

    pub fn init() RWLock {
        return RWLock{
            .readers = std.atomic.Value(i32).init(0),
            .writer_waiting = std.atomic.Value(bool).init(false),
            .writer_active = std.atomic.Value(bool).init(false),
            .mutex = .init,
            .read_cond = .init,
            .write_cond = .init,
        };
    }

    pub fn readLock(self: *RWLock) void {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        while (self.writer_active.load(.seq_cst) or self.writer_waiting.load(.seq_cst)) {
            self.read_cond.wait(&self.mutex, std.Io.Threaded.global_single_threaded.io());
        }
        _ = self.readers.fetchAdd(1, .seq_cst);
    }

    pub fn readUnlock(self: *RWLock) void {
        const prev = self.readers.fetchSub(1, .seq_cst);
        if (prev == 1) {
            self.write_cond.signal(std.Io.Threaded.global_single_threaded.io());
        }
    }

    pub fn writeLock(self: *RWLock) void {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        self.writer_waiting.store(true, .seq_cst);
        while (self.readers.load(.seq_cst) > 0 or self.writer_active.load(.seq_cst)) {
            self.write_cond.wait(&self.mutex, std.Io.Threaded.global_single_threaded.io());
        }
        self.writer_waiting.store(false, .seq_cst);
        self.writer_active.store(true, .seq_cst);
    }

    pub fn writeUnlock(self: *RWLock) void {
        self.writer_active.store(false, .seq_cst);
        self.read_cond.broadcast(std.Io.Threaded.global_single_threaded.io());
        self.write_cond.signal(std.Io.Threaded.global_single_threaded.io());
    }

    pub fn tryReadLock(self: *RWLock) bool {
        if (self.writer_active.load(.seq_cst) or self.writer_waiting.load(.seq_cst)) {
            return false;
        }
        _ = self.readers.fetchAdd(1, .seq_cst);
        return true;
    }

    pub fn tryWriteLock(self: *RWLock) bool {
        if (self.readers.load(.seq_cst) > 0 or self.writer_active.load(.seq_cst)) {
            return false;
        }
        self.writer_active.store(true, .seq_cst);
        return true;
    }
};

/// Once - 确保函数只执行一次
pub const Once = struct {
    done: std.atomic.Value(bool),
    mutex: std.Io.Mutex,

    pub fn init() Once {
        return Once{
            .done = std.atomic.Value(bool).init(false),
            .mutex = .init,
        };
    }

    pub fn do(self: *Once, func: *const fn () void) void {
        if (self.done.load(.seq_cst)) return;

        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        if (!self.done.load(.seq_cst)) {
            func();
            self.done.store(true, .seq_cst);
        }
    }
};

/// Semaphore - 信号量
pub const Semaphore = struct {
    count: std.atomic.Value(i32),
    mutex: std.Io.Mutex,
    cond: std.Io.Condition,

    pub fn init(initial: i32) Semaphore {
        return Semaphore{
            .count = std.atomic.Value(i32).init(initial),
            .mutex = .init,
            .cond = .init,
        };
    }

    pub fn acquire(self: *Semaphore) void {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        while (self.count.load(.seq_cst) <= 0) {
            self.cond.wait(&self.mutex, std.Io.Threaded.global_single_threaded.io());
        }
        _ = self.count.fetchSub(1, .seq_cst);
    }

    pub fn release(self: *Semaphore) void {
        _ = self.count.fetchAdd(1, .seq_cst);
        self.cond.signal(std.Io.Threaded.global_single_threaded.io());
    }

    pub fn tryAcquire(self: *Semaphore) bool {
        if (self.count.load(.seq_cst) <= 0) return false;
        _ = self.count.fetchSub(1, .seq_cst);
        return true;
    }
};

// ============================================================================
// 异步IO支持 - 基于kqueue(macOS)/epoll(Linux)的事件驱动IO
// ============================================================================

/// IO事件类型
pub const IOEventType = enum(u8) {
    /// 可读事件
    read = 0,
    /// 可写事件
    write = 1,
    /// 错误事件
    err = 2,
    /// 挂起事件
    hup = 3,
    /// 定时器事件
    timer = 4,
};

/// IO事件
pub const IOEvent = struct {
    fd: i32,
    event_type: IOEventType,
    user_data: ?*anyopaque,
    coroutine_id: ?u64,
};

/// IO等待条目
pub const IOWaitEntry = struct {
    fd: i32,
    event_type: IOEventType,
    coroutine: *Coroutine,
    timeout_ms: ?u64,
    registered_at: i64,
};

/// 异步IO反应器 - 跨平台事件循环
/// 在macOS上使用kqueue，在Linux上使用epoll
pub const AsyncIOReactor = struct {
    allocator: std.mem.Allocator,

    /// 平台特定的事件队列句柄
    event_fd: i32,

    /// 等待IO的协程映射 (fd -> IOWaitEntry)
    waiting_coroutines: std.AutoHashMap(i32, IOWaitEntry),

    /// 定时器等待队列
    timer_queue: std.ArrayListUnmanaged(TimerEntry),

    /// 互斥锁保护共享状态
    mutex: std.Io.Mutex,

    /// 是否正在运行
    running: std.atomic.Value(bool),

    /// 统计信息
    stats: IOStats,

    pub const TimerEntry = struct {
        coroutine: *Coroutine,
        deadline_ms: i64,
        user_data: ?*anyopaque,
    };

    pub const IOStats = struct {
        total_events_processed: u64 = 0,
        read_events: u64 = 0,
        write_events: u64 = 0,
        timer_events: u64 = 0,
        timeouts: u64 = 0,
        errors: u64 = 0,
    };

    pub const IOError = error{
        KqueueCreateFailed,
        EpollCreateFailed,
        RegisterFailed,
        UnregisterFailed,
        WaitFailed,
        InvalidFd,
        AlreadyRegistered,
        NotRegistered,
        OutOfMemory,
    };

    /// 初始化异步IO反应器
    pub fn init(allocator: std.mem.Allocator) IOError!AsyncIOReactor {
        const event_fd = createEventQueue() catch return IOError.KqueueCreateFailed;

        return AsyncIOReactor{
            .allocator = allocator,
            .event_fd = event_fd,
            .waiting_coroutines = std.AutoHashMap(i32, IOWaitEntry).init(allocator),
            .timer_queue = .empty,
            .mutex = .init,
            .running = std.atomic.Value(bool).init(false),
            .stats = .{},
        };
    }

    /// 清理资源
    pub fn deinit(self: *AsyncIOReactor) void {
        self.running.store(false, .seq_cst);

        // 关闭事件队列
        if (self.event_fd >= 0) {
            const ef: std.Io.File = .{ .handle = @intCast(self.event_fd), .flags = .{ .nonblocking = false } };
            ef.close(std.Io.Threaded.global_single_threaded.io());
        }

        self.waiting_coroutines.deinit();
        self.timer_queue.deinit(self.allocator);
    }

    /// 注册文件描述符等待IO事件
    pub fn registerFd(self: *AsyncIOReactor, fd: i32, event_type: IOEventType, coroutine: *Coroutine, timeout_ms: ?u64) IOError!void {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        // 检查是否已注册
        if (self.waiting_coroutines.contains(fd)) {
            return IOError.AlreadyRegistered;
        }

        // 添加到内核事件队列
        try self.addToEventQueue(fd, event_type);

        // 记录等待条目
        self.waiting_coroutines.put(fd, IOWaitEntry{
            .fd = fd,
            .event_type = event_type,
            .coroutine = coroutine,
            .timeout_ms = timeout_ms,
            .registered_at = time_compat.milliTimestamp(),
        }) catch return IOError.OutOfMemory;

        // 设置协程状态为等待
        coroutine.state = .waiting;
    }

    /// 取消注册文件描述符
    pub fn unregisterFd(self: *AsyncIOReactor, fd: i32) IOError!void {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        if (!self.waiting_coroutines.contains(fd)) {
            return IOError.NotRegistered;
        }

        // 从内核事件队列移除
        try self.removeFromEventQueue(fd);

        // 移除等待条目
        _ = self.waiting_coroutines.remove(fd);
    }

    /// 注册定时器
    pub fn registerTimer(self: *AsyncIOReactor, coroutine: *Coroutine, delay_ms: u64, user_data: ?*anyopaque) IOError!void {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        const deadline = time_compat.milliTimestamp() + @as(i64, @intCast(delay_ms));

        self.timer_queue.append(self.allocator, TimerEntry{
            .coroutine = coroutine,
            .deadline_ms = deadline,
            .user_data = user_data,
        }) catch return IOError.OutOfMemory;

        coroutine.state = .waiting;
    }

    /// 轮询IO事件（非阻塞）
    pub fn poll(self: *AsyncIOReactor, timeout_ms: i32) ![]IOEvent {
        var events_buf: [64]IOEvent = undefined;
        var event_count: usize = 0;

        // 检查定时器
        const now = time_compat.milliTimestamp();
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());

        var i: usize = 0;
        while (i < self.timer_queue.items.len) {
            const timer = self.timer_queue.items[i];
            if (timer.deadline_ms <= now) {
                if (event_count < events_buf.len) {
                    events_buf[event_count] = IOEvent{
                        .fd = -1,
                        .event_type = .timer,
                        .user_data = timer.user_data,
                        .coroutine_id = timer.coroutine.id,
                    };
                    event_count += 1;
                    self.stats.timer_events += 1;
                }
                // 唤醒协程
                timer.coroutine.state = .ready;
                _ = self.timer_queue.orderedRemove(i);
            } else {
                i += 1;
            }
        }

        // 检查超时的IO等待
        var to_remove: std.ArrayListUnmanaged(i32) = .empty;
        defer to_remove.deinit(self.allocator);

        var iter = self.waiting_coroutines.iterator();
        while (iter.next()) |entry| {
            const wait_entry = entry.value_ptr;
            if (wait_entry.timeout_ms) |timeout| {
                const elapsed = now - wait_entry.registered_at;
                if (elapsed >= @as(i64, @intCast(timeout))) {
                    // 超时
                    wait_entry.coroutine.state = .ready;
                    to_remove.append(self.allocator, entry.key_ptr.*) catch {};
                    self.stats.timeouts += 1;
                }
            }
        }

        for (to_remove.items) |fd| {
            _ = self.waiting_coroutines.remove(fd);
            self.removeFromEventQueue(fd) catch {};
        }

        self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        // 轮询内核事件
        const kernel_events = try self.pollKernelEvents(timeout_ms);

        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

        for (kernel_events) |kevent| {
            if (event_count >= events_buf.len) break;

            if (self.waiting_coroutines.get(kevent.fd)) |wait_entry| {
                events_buf[event_count] = IOEvent{
                    .fd = kevent.fd,
                    .event_type = kevent.event_type,
                    .user_data = null,
                    .coroutine_id = wait_entry.coroutine.id,
                };
                event_count += 1;

                // 更新统计
                switch (kevent.event_type) {
                    .read => self.stats.read_events += 1,
                    .write => self.stats.write_events += 1,
                    .err => self.stats.errors += 1,
                    else => {},
                }

                // 唤醒协程
                wait_entry.coroutine.state = .ready;

                // 移除等待条目
                _ = self.waiting_coroutines.remove(kevent.fd);
                self.removeFromEventQueue(kevent.fd) catch {};
            }
        }

        self.stats.total_events_processed += event_count;

        // 返回事件切片
        const result = try self.allocator.alloc(IOEvent, event_count);
        @memcpy(result, events_buf[0..event_count]);
        return result;
    }

    /// 运行事件循环（阻塞直到所有IO完成或超时）
    pub fn runEventLoop(self: *AsyncIOReactor, manager: *CoroutineManager, timeout_ms: i32) !void {
        self.running.store(true, .seq_cst);

        while (self.running.load(.seq_cst)) {
            // 检查是否还有等待的协程
            self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
            const has_waiting = self.waiting_coroutines.count() > 0 or self.timer_queue.items.len > 0;
            self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());

            if (!has_waiting) break;

            // 轮询事件
            const events = try self.poll(timeout_ms);
            defer self.allocator.free(events);

            // 将就绪的协程加入调度队列
            for (events) |event| {
                if (event.coroutine_id) |co_id| {
                    if (manager.coroutines.get(co_id)) |co| {
                        if (co.state == .ready) {
                            manager.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
                            switch (manager.scheduling_policy) {
                                .fifo => manager.ready_queue.append(manager.allocator, co) catch {},
                                .priority, .weighted_fair => manager.priority_queue.enqueue(co) catch {},
                            }
                            manager.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
                        }
                    }
                }
            }

            // 如果没有事件，短暂休眠避免忙等待
            if (events.len == 0) {
                std.Thread.sleep(1_000_000); // 1ms
            }
        }
    }

    /// 停止事件循环
    pub fn stop(self: *AsyncIOReactor) void {
        self.running.store(false, .seq_cst);
    }

    /// 获取统计信息
    pub fn getStats(self: *AsyncIOReactor) IOStats {
        return self.stats;
    }

    /// 重置统计信息
    pub fn resetStats(self: *AsyncIOReactor) void {
        self.stats = .{};
    }

    /// 获取等待中的协程数量
    pub fn getWaitingCount(self: *AsyncIOReactor) usize {
        self.mutex.lockUncancelable(std.Io.Threaded.global_single_threaded.io());
        defer self.mutex.unlock(std.Io.Threaded.global_single_threaded.io());
        return self.waiting_coroutines.count() + self.timer_queue.items.len;
    }

    // ========== 平台特定实现 ==========

    /// 创建事件队列（kqueue/epoll）
    fn createEventQueue() !i32 {
        const builtin = @import("builtin");
        if (builtin.os.tag == .macos or builtin.os.tag == .freebsd or builtin.os.tag == .netbsd or builtin.os.tag == .openbsd) {
            // macOS/BSD: 使用kqueue
            return std.posix.kqueue();
        } else if (builtin.os.tag == .linux) {
            // Linux: 使用epoll
            return std.posix.epoll_create1(0);
        } else {
            // 其他平台：返回虚拟句柄
            return 0;
        }
    }

    /// 添加到事件队列
    fn addToEventQueue(self: *AsyncIOReactor, fd: i32, event_type: IOEventType) IOError!void {
        const builtin = @import("builtin");
        if (builtin.os.tag == .macos or builtin.os.tag == .freebsd or builtin.os.tag == .netbsd or builtin.os.tag == .openbsd) {
            // kqueue
            var changelist: [1]std.posix.Kevent = undefined;
            const filter: i16 = switch (event_type) {
                .read => std.posix.system.EVFILT.READ,
                .write => std.posix.system.EVFILT.WRITE,
                else => std.posix.system.EVFILT.READ,
            };

            changelist[0] = .{
                .ident = @intCast(fd),
                .filter = filter,
                .flags = std.posix.system.EV.ADD | std.posix.system.EV.ENABLE,
                .fflags = 0,
                .data = 0,
                .udata = @intFromPtr(&fd),
            };

            _ = std.posix.kevent(@intCast(self.event_fd), &changelist, &[_]std.posix.Kevent{}, null) catch {
                return IOError.RegisterFailed;
            };
        } else if (builtin.os.tag == .linux) {
            // epoll
            var ev: std.os.linux.epoll_event = .{
                .events = switch (event_type) {
                    .read => std.os.linux.EPOLL.IN,
                    .write => std.os.linux.EPOLL.OUT,
                    else => std.os.linux.EPOLL.IN,
                },
                .data = .{ .fd = fd },
            };

            _ = std.os.linux.epoll_ctl(@intCast(self.event_fd), std.os.linux.EPOLL.CTL_ADD, @intCast(fd), &ev);
        }
        // 其他平台不做任何操作
    }

    /// 从事件队列移除
    fn removeFromEventQueue(self: *AsyncIOReactor, fd: i32) IOError!void {
        const builtin = @import("builtin");
        if (builtin.os.tag == .macos or builtin.os.tag == .freebsd or builtin.os.tag == .netbsd or builtin.os.tag == .openbsd) {
            // kqueue: 使用EV_DELETE
            var changelist: [1]std.posix.Kevent = undefined;
            changelist[0] = .{
                .ident = @intCast(fd),
                .filter = std.posix.system.EVFILT.READ,
                .flags = std.posix.system.EV.DELETE,
                .fflags = 0,
                .data = 0,
                .udata = 0,
            };

            _ = std.posix.kevent(@intCast(self.event_fd), &changelist, &[_]std.posix.Kevent{}, null) catch {};
        } else if (builtin.os.tag == .linux) {
            // epoll
            _ = std.os.linux.epoll_ctl(@intCast(self.event_fd), std.os.linux.EPOLL.CTL_DEL, @intCast(fd), null);
        }
    }

    /// 轮询内核事件
    fn pollKernelEvents(self: *AsyncIOReactor, timeout_ms: i32) ![]IOEvent {
        const builtin = @import("builtin");
        var result: std.ArrayListUnmanaged(IOEvent) = .empty;
        errdefer result.deinit(self.allocator);

        if (builtin.os.tag == .macos or builtin.os.tag == .freebsd or builtin.os.tag == .netbsd or builtin.os.tag == .openbsd) {
            // kqueue
            var eventlist: [64]std.posix.Kevent = undefined;
            var timeout_spec: std.posix.timespec = .{
                .sec = @divTrunc(timeout_ms, 1000),
                .nsec = @rem(timeout_ms, 1000) * 1_000_000,
            };
            const timeout_ptr: ?*const std.posix.timespec = if (timeout_ms >= 0) &timeout_spec else null;

            const n = std.posix.kevent(@intCast(self.event_fd), &[_]std.posix.Kevent{}, &eventlist, timeout_ptr) catch 0;

            for (eventlist[0..n]) |ev| {
                const event_type: IOEventType = if (ev.filter == std.posix.system.EVFILT.READ)
                    .read
                else if (ev.filter == std.posix.system.EVFILT.WRITE)
                    .write
                else if (ev.flags & std.posix.system.EV.ERROR != 0)
                    .err
                else
                    .read;

                try result.append(self.allocator, IOEvent{
                    .fd = @intCast(ev.ident),
                    .event_type = event_type,
                    .user_data = null,
                    .coroutine_id = null,
                });
            }
        } else if (builtin.os.tag == .linux) {
            // epoll
            var events: [64]std.os.linux.epoll_event = undefined;
            const n = std.os.linux.epoll_wait(@intCast(self.event_fd), &events, @intCast(events.len), @intCast(timeout_ms));

            if (n > 0) {
                for (events[0..@intCast(n)]) |ev| {
                    const event_type: IOEventType = if (ev.events & std.os.linux.EPOLL.IN != 0)
                        .read
                    else if (ev.events & std.os.linux.EPOLL.OUT != 0)
                        .write
                    else if (ev.events & std.os.linux.EPOLL.ERR != 0)
                        .err
                    else
                        .read;

                    try result.append(self.allocator, IOEvent{
                        .fd = ev.data.fd,
                        .event_type = event_type,
                        .user_data = null,
                        .coroutine_id = null,
                    });
                }
            }
        }

        return result.toOwnedSlice(self.allocator);
    }
};

/// 异步IO辅助函数 - 用于协程中的异步操作
pub const AsyncIO = struct {
    /// 异步读取（协程会被挂起直到数据可读）
    pub fn asyncRead(reactor: *AsyncIOReactor, fd: i32, coroutine: *Coroutine, timeout_ms: ?u64) !void {
        try reactor.registerFd(fd, .read, coroutine, timeout_ms);
    }

    /// 异步写入（协程会被挂起直到可写）
    pub fn asyncWrite(reactor: *AsyncIOReactor, fd: i32, coroutine: *Coroutine, timeout_ms: ?u64) !void {
        try reactor.registerFd(fd, .write, coroutine, timeout_ms);
    }

    /// 异步等待（协程会被挂起指定时间）
    pub fn asyncSleep(reactor: *AsyncIOReactor, coroutine: *Coroutine, delay_ms: u64) !void {
        try reactor.registerTimer(coroutine, delay_ms, null);
    }

    /// 取消异步操作
    pub fn cancelAsync(reactor: *AsyncIOReactor, fd: i32) !void {
        try reactor.unregisterFd(fd);
    }
};

test "channel basic operations" {
    const allocator = std.testing.allocator;

    // 测试新的Channel API
    var channel = try Channel.initWithCapacity(allocator, 10);
    defer channel.deinit();

    const value = Value.initInt(42);
    const success = channel.trySend(value);
    try std.testing.expect(success);

    const received = channel.tryRecv();
    try std.testing.expect(received != null);
    try std.testing.expectEqual(@as(i64, 42), received.?.asInt());
}

test "generic channel compatibility" {
    const allocator = std.testing.allocator;

    // 测试泛型Channel包装器
    var channel = try GenericChannel(i32).init(allocator, 10);
    defer channel.deinit();

    const success = channel.trySend(42);
    try std.testing.expect(success);

    const received = channel.tryRecv();
    try std.testing.expect(received != null);
    try std.testing.expectEqual(@as(i32, 42), received.?);
}

test "waitgroup basic operations" {
    var wg = WaitGroup.init();

    wg.add(2);
    wg.done();
    wg.done();
    wg.wait(std.Io.Threaded.global_single_threaded.io());
}

test "priority queue basic operations" {
    const allocator = std.testing.allocator;
    var pq = PriorityQueue.init(allocator);
    defer pq.deinit();

    // 创建测试协程
    var co1 = try allocator.create(Coroutine);
    co1.* = try Coroutine.init(allocator, 1, Value.initNull(), &[_]Value{});
    co1.priority = .low;
    defer {
        co1.deinit();
        allocator.destroy(co1);
    }

    var co2 = try allocator.create(Coroutine);
    co2.* = try Coroutine.init(allocator, 2, Value.initNull(), &[_]Value{});
    co2.priority = .high;
    defer {
        co2.deinit();
        allocator.destroy(co2);
    }

    var co3 = try allocator.create(Coroutine);
    co3.* = try Coroutine.init(allocator, 3, Value.initNull(), &[_]Value{});
    co3.priority = .critical;
    defer {
        co3.deinit();
        allocator.destroy(co3);
    }

    // 入队
    try pq.enqueue(co1);
    try pq.enqueue(co2);
    try pq.enqueue(co3);

    try std.testing.expectEqual(@as(usize, 3), pq.len());

    // 出队应该按优先级顺序（高优先级先出）
    const first = pq.dequeue();
    try std.testing.expect(first != null);
    try std.testing.expectEqual(Priority.critical, first.?.priority);

    const second = pq.dequeue();
    try std.testing.expect(second != null);
    try std.testing.expectEqual(Priority.high, second.?.priority);

    const third = pq.dequeue();
    try std.testing.expect(third != null);
    try std.testing.expectEqual(Priority.low, third.?.priority);

    try std.testing.expectEqual(@as(usize, 0), pq.len());
}

test "priority weight conversion" {
    try std.testing.expectEqual(@as(u32, 16), Priority.critical.toWeight());
    try std.testing.expectEqual(@as(u32, 8), Priority.high.toWeight());
    try std.testing.expectEqual(@as(u32, 4), Priority.normal.toWeight());
    try std.testing.expectEqual(@as(u32, 2), Priority.low.toWeight());
    try std.testing.expectEqual(@as(u32, 1), Priority.idle.toWeight());
}

test "priority queue weighted fair scheduling" {
    const allocator = std.testing.allocator;
    var pq = PriorityQueue.init(allocator);
    defer pq.deinit();

    // 创建多个不同优先级的协程
    var coroutines: [10]*Coroutine = undefined;
    for (0..10) |i| {
        coroutines[i] = try allocator.create(Coroutine);
        coroutines[i].* = try Coroutine.init(allocator, @intCast(i + 1), Value.initNull(), &[_]Value{});
        // 交替设置优先级
        coroutines[i].priority = if (i % 2 == 0) .high else .low;
        try pq.enqueue(coroutines[i]);
    }
    defer {
        for (coroutines) |co| {
            co.deinit();
            allocator.destroy(co);
        }
    }

    // 出队所有协程
    var high_count: usize = 0;
    var low_count: usize = 0;
    while (pq.dequeue()) |co| {
        if (co.priority == .high) {
            high_count += 1;
        } else {
            low_count += 1;
        }
    }

    try std.testing.expectEqual(@as(usize, 5), high_count);
    try std.testing.expectEqual(@as(usize, 5), low_count);
}

test "priority queue remove" {
    const allocator = std.testing.allocator;
    var pq = PriorityQueue.init(allocator);
    defer pq.deinit();

    var co = try allocator.create(Coroutine);
    co.* = try Coroutine.init(allocator, 1, Value.initNull(), &[_]Value{});
    co.priority = .normal;
    defer {
        co.deinit();
        allocator.destroy(co);
    }

    try pq.enqueue(co);
    try std.testing.expectEqual(@as(usize, 1), pq.len());

    const removed = pq.remove(co);
    try std.testing.expect(removed);
    try std.testing.expectEqual(@as(usize, 0), pq.len());
}

test "coroutine manager scheduling policy" {
    const allocator = std.testing.allocator;
    var manager = CoroutineManager.init(allocator);
    defer manager.deinit();

    // 默认应该是加权公平调度
    try std.testing.expectEqual(CoroutineManager.SchedulingPolicy.weighted_fair, manager.getSchedulingPolicy());

    // 切换到FIFO
    manager.setSchedulingPolicy(.fifo);
    try std.testing.expectEqual(CoroutineManager.SchedulingPolicy.fifo, manager.getSchedulingPolicy());

    // 切换到优先级调度
    manager.setSchedulingPolicy(.priority);
    try std.testing.expectEqual(CoroutineManager.SchedulingPolicy.priority, manager.getSchedulingPolicy());
}

test "async io reactor initialization" {
    const allocator = std.testing.allocator;

    var reactor = AsyncIOReactor.init(allocator) catch |err| {
        // 在某些环境下可能无法创建kqueue/epoll，跳过测试
        std.debug.print("Skipping async IO test: {}\n", .{err});
        return;
    };
    defer reactor.deinit();

    // 验证初始状态
    try std.testing.expectEqual(@as(usize, 0), reactor.getWaitingCount());
    try std.testing.expectEqual(@as(u64, 0), reactor.getStats().total_events_processed);
}

test "async io reactor timer" {
    const allocator = std.testing.allocator;

    var reactor = AsyncIOReactor.init(allocator) catch |err| {
        std.debug.print("Skipping async IO timer test: {}\n", .{err});
        return;
    };
    defer reactor.deinit();

    // 创建测试协程
    var co = try allocator.create(Coroutine);
    co.* = try Coroutine.init(allocator, 1, Value.initNull(), &[_]Value{});
    defer {
        co.deinit();
        allocator.destroy(co);
    }

    // 注册一个短定时器
    try reactor.registerTimer(co, 10, null); // 10ms

    try std.testing.expectEqual(@as(usize, 1), reactor.getWaitingCount());
    try std.testing.expectEqual(Coroutine.State.waiting, co.state);

    // 等待定时器触发
    std.Thread.sleep(20_000_000); // 20ms

    // 轮询事件
    const events = try reactor.poll(0);
    defer allocator.free(events);

    // 应该有一个定时器事件
    try std.testing.expect(events.len >= 1);
    if (events.len > 0) {
        try std.testing.expectEqual(IOEventType.timer, events[0].event_type);
    }

    // 协程应该被唤醒
    try std.testing.expectEqual(Coroutine.State.ready, co.state);
}

test "coroutine manager io reactor integration" {
    const allocator = std.testing.allocator;
    var manager = CoroutineManager.init(allocator);
    defer manager.deinit();

    // 初始化IO反应器
    manager.initIOReactor() catch |err| {
        std.debug.print("Skipping IO reactor integration test: {}\n", .{err});
        return;
    };

    // 验证IO反应器已初始化
    try std.testing.expect(manager.io_reactor != null);

    // 验证初始状态
    try std.testing.expectEqual(@as(usize, 0), manager.getIOWaitingCount());
    try std.testing.expect(!manager.hasIOWaiting());

    // 获取IO统计
    const stats = manager.getIOStats();
    try std.testing.expect(stats != null);
    try std.testing.expectEqual(@as(u64, 0), stats.?.total_events_processed);
}

test "async io helper functions" {
    const allocator = std.testing.allocator;

    var reactor = AsyncIOReactor.init(allocator) catch |err| {
        std.debug.print("Skipping async IO helper test: {}\n", .{err});
        return;
    };
    defer reactor.deinit();

    // 创建测试协程
    var co = try allocator.create(Coroutine);
    co.* = try Coroutine.init(allocator, 1, Value.initNull(), &[_]Value{});
    defer {
        co.deinit();
        allocator.destroy(co);
    }

    // 测试asyncSleep
    try AsyncIO.asyncSleep(&reactor, co, 5);
    try std.testing.expectEqual(Coroutine.State.waiting, co.state);
    try std.testing.expectEqual(@as(usize, 1), reactor.getWaitingCount());
}

test "io event type enum" {
    // 验证IO事件类型枚举值
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(IOEventType.read));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(IOEventType.write));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(IOEventType.err));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(IOEventType.hup));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(IOEventType.timer));
}

test "io wait entry structure" {
    const allocator = std.testing.allocator;

    // 创建测试协程
    var co = try allocator.create(Coroutine);
    co.* = try Coroutine.init(allocator, 42, Value.initNull(), &[_]Value{});
    defer {
        co.deinit();
        allocator.destroy(co);
    }

    // 创建IO等待条目
    const entry = IOWaitEntry{
        .fd = 10,
        .event_type = .read,
        .coroutine = co,
        .timeout_ms = 5000,
        .registered_at = time_compat.milliTimestamp(),
    };

    try std.testing.expectEqual(@as(i32, 10), entry.fd);
    try std.testing.expectEqual(IOEventType.read, entry.event_type);
    try std.testing.expectEqual(@as(u64, 42), entry.coroutine.id);
    try std.testing.expectEqual(@as(?u64, 5000), entry.timeout_ms);
}
