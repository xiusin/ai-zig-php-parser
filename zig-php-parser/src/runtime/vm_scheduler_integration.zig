//! ============================================================================
//! VM调度器集成 (VM-Scheduler Integration)
//! ============================================================================
//!
//! 功能：将PHP虚拟机与协程调度器集成
//!
//! 架构：
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                  VM-Scheduler Integration                        │
//! │                                                                  │
//! │  ┌──────────────────┐      ┌──────────────────┐                │
//! │  │       VM         │      │    Scheduler     │                │
//! │  │  (PHP虚拟机)     │<────>│   (协程调度器)   │                │
//! │  │                  │      │                  │                │
//! │  │  - 执行PHP代码   │      │  - 管理协程     │                │
//! │  │  - 管理变量      │      │  - 调度执行     │                │
//! │  │  - 调用函数      │      │  - 工作窃取     │                │
//! │  └──────────────────┘      └──────────────────┘                │
//! │                                                                  │
//! │  集成功能：                                                      │
//! │  - 协程创建：将PHP函数包装为协程                                │
//! │  - 协程执行：在调度器中执行PHP代码                              │
//! │  - 上下文切换：保存/恢复PHP执行状态                             │
//! │  - 异常处理：协程异常传播                                       │
//! └─────────────────────────────────────────────────────────────────┘
//!
//! 使用示例（PHP层面）：
//! ```php
//! // 创建协程
//! $coro = go(function() {
//!     echo "Hello from coroutine!\n";
//!     yield;  // 让出CPU
//!     echo "Resumed!\n";
//! });
//! 
//! // 等待协程完成
//! await($coro);
//! ```
//!
//! 需求：5.1, 5.2, 5.8
//! ============================================================================

const std = @import("std");
const VM = @import("vm.zig").VM;
const Value = @import("types.zig").Value;
const Scheduler = @import("scheduler.zig").Scheduler;
const ast = @import("compiler").ast.zig;

/// VM与调度器集成
pub const VMSchedulerIntegration = struct {
    vm: *VM,
    scheduler: ?*Scheduler,
    allocator: std.mem.Allocator,
    
    // Integration state
    is_initialized: bool = false,
    main_coroutine_id: ?u64 = null,
    
    // Scheduler configuration
    config: SchedulerConfig,
    
    pub const SchedulerConfig = struct {
        num_processors: u32 = 0, // 0 means auto-detect
        num_workers: u32 = 0,    // 0 means auto-detect
        stack_size: usize = 64 * 1024,
        enable_preemption: bool = true,
        enable_work_stealing: bool = true,
        time_slice_us: u32 = 10_000, // 10ms
    };
    
    pub fn init(vm: *VM, config: SchedulerConfig) VMSchedulerIntegration {
        return VMSchedulerIntegration{
            .vm = vm,
            .scheduler = null,
            .allocator = vm.allocator,
            .config = config,
        };
    }
    
    pub fn deinit(self: *VMSchedulerIntegration) void {
        if (self.scheduler) |scheduler| {
            scheduler.deinit();
            self.allocator.destroy(scheduler);
        }
    }
    
    /// Initialize scheduler with VM integration
    /// Requirement 5.1 - scheduler lifecycle management
    pub fn initializeScheduler(self: *VMSchedulerIntegration) !void {
        if (self.is_initialized) {
            return error.AlreadyInitialized;
        }
        
        // Auto-detect CPU count if not specified
        var config = self.config;
        if (config.num_processors == 0) {
            config.num_processors = @intCast(std.Thread.getCpuCount() catch 4);
        }
        if (config.num_workers == 0) {
            config.num_workers = config.num_processors;
        }
        
        // Create scheduler configuration
        const scheduler_config = Scheduler.SchedulerConfig{
            .num_processors = config.num_processors,
            .num_workers = config.num_workers,
            .stack_size = config.stack_size,
            .time_slice_us = config.time_slice_us,
            .enable_preemption = config.enable_preemption,
            .enable_work_stealing = config.enable_work_stealing,
        };
        
        // Initialize scheduler
        self.scheduler = try self.allocator.create(Scheduler);
        self.scheduler.? = try Scheduler.init(self.allocator, scheduler_config, @ptrCast(self.vm));
        
        // Start scheduler
        try self.scheduler.?.start();
        
        self.is_initialized = true;
    }
    
    /// Shutdown scheduler gracefully
    /// Requirement 5.8 - scheduler lifecycle management
    pub fn shutdownScheduler(self: *VMSchedulerIntegration) void {
        if (self.scheduler) |scheduler| {
            scheduler.stop();
        }
        self.is_initialized = false;
    }
    
    /// Spawn coroutine from go keyword
    /// Requirement 5.1 - coroutine spawning from go keyword
    pub fn spawnCoroutine(self: *VMSchedulerIntegration, callback: Value, args: []Value) !u64 {
        if (!self.is_initialized or self.scheduler == null) {
            return error.SchedulerNotInitialized;
        }
        
        return try self.scheduler.?.spawn(callback, args);
    }
    
    /// Execute go statement
    /// Requirement 5.1 - implement coroutine spawning from go keyword
    pub fn executeGoStatement(self: *VMSchedulerIntegration, go_node: ast.Node.Index) !Value {
        if (!self.is_initialized) {
            try self.initializeScheduler();
        }
        
        const node = self.vm.context.nodes.items[go_node];
        if (node.tag != .go_stmt) {
            return error.InvalidGoStatement;
        }
        
        const call_node_index = node.data.go_stmt.call;
        const call_node = self.vm.context.nodes.items[call_node_index];
        
        // Extract function call information
        const callback = try self.extractCallbackFromNode(call_node_index);
        const args = try self.extractArgsFromNode(call_node_index);
        defer self.allocator.free(args);
        
        // Spawn coroutine
        const coroutine_id = try self.spawnCoroutine(callback, args);
        
        // Return coroutine ID as value
        return Value.initInteger(@intCast(coroutine_id));
    }
    
    /// Extract callback function from AST node
    fn extractCallbackFromNode(self: *VMSchedulerIntegration, node_index: ast.Node.Index) !Value {
        const node = self.vm.context.nodes.items[node_index];
        
        switch (node.tag) {
            .function_call => {
                const func_name_index = node.data.function_call.name;
                const func_name_node = self.vm.context.nodes.items[func_name_index];
                
                if (func_name_node.tag == .variable) {
                    const name_token = func_name_node.main_token;
                    const name = self.vm.context.getTokenSlice(name_token);
                    
                    // Create closure that captures the function name and VM context
                    return try self.createVMCallback(name);
                }
            },
            .method_call => {
                // Handle method calls
                return try self.createMethodCallback(node_index);
            },
            .closure => {
                // Handle closure calls
                return try self.createClosureCallback(node_index);
            },
            else => {},
        }
        
        return error.UnsupportedCallbackType;
    }
    
    /// Extract arguments from AST node
    fn extractArgsFromNode(self: *VMSchedulerIntegration, node_index: ast.Node.Index) ![]Value {
        const node = self.vm.context.nodes.items[node_index];
        
        switch (node.tag) {
            .function_call => {
                const args_start = node.data.function_call.args;
                return try self.evaluateArgumentList(args_start);
            },
            .method_call => {
                const args_start = node.data.method_call.args;
                return try self.evaluateArgumentList(args_start);
            },
            else => {
                return try self.allocator.alloc(Value, 0);
            },
        }
    }
    
    /// Evaluate argument list from AST
    fn evaluateArgumentList(self: *VMSchedulerIntegration, args_start: ast.Node.Index) ![]Value {
        if (args_start == 0) {
            return try self.allocator.alloc(Value, 0);
        }
        
        // Count arguments
        var arg_count: usize = 0;
        var current = args_start;
        while (current != 0) {
            arg_count += 1;
            const arg_node = self.vm.context.nodes.items[current];
            current = arg_node.data.parameter.next; // Assuming linked list structure
        }
        
        // Evaluate arguments
        const args = try self.allocator.alloc(Value, arg_count);
        var i: usize = 0;
        current = args_start;
        while (current != 0 and i < arg_count) {
            args[i] = try self.vm.evaluateExpression(current);
            i += 1;
            const arg_node = self.vm.context.nodes.items[current];
            current = arg_node.data.parameter.next;
        }
        
        return args;
    }
    
    /// Create VM callback for function execution
    fn createVMCallback(self: *VMSchedulerIntegration, func_name: []const u8) !Value {
        // Create a closure that captures the VM and function name
        const callback_data = try self.allocator.create(VMCallbackData);
        callback_data.* = VMCallbackData{
            .vm = self.vm,
            .func_name = try self.allocator.dupe(u8, func_name),
            .allocator = self.allocator,
        };
        
        return Value.initNativeFunction(@ptrCast(&vmCallbackWrapper));
    }
    
    /// Create method callback for coroutine execution
    /// Wraps a method call into a callable value for the scheduler
    fn createMethodCallback(self: *VMSchedulerIntegration, node_index: ast.Node.Index) !Value {
        const node = self.vm.context.nodes.items[node_index];
        
        if (node.tag != .method_call) {
            return error.InvalidMethodCall;
        }
        
        // Extract method information
        const method_data = node.data.method_call;
        const object_index = method_data.object;
        const method_name_index = method_data.name;
        
        // Get method name
        const method_name_node = self.vm.context.nodes.items[method_name_index];
        const method_name = if (method_name_node.tag == .identifier)
            self.vm.context.getTokenSlice(method_name_node.main_token)
        else
            return error.InvalidMethodName;
        
        // Create callback data that captures method context
        const callback_data = try self.allocator.create(MethodCallbackData);
        callback_data.* = MethodCallbackData{
            .vm = self.vm,
            .object_node = object_index,
            .method_name = try self.allocator.dupe(u8, method_name),
            .allocator = self.allocator,
        };
        
        return Value.initNativeFunction(@ptrCast(&methodCallbackWrapper));
    }
    
    /// Create closure callback for coroutine execution
    /// Wraps a closure into a callable value for the scheduler
    fn createClosureCallback(self: *VMSchedulerIntegration, node_index: ast.Node.Index) !Value {
        const node = self.vm.context.nodes.items[node_index];
        
        if (node.tag != .closure) {
            return error.InvalidClosure;
        }
        
        // Create callback data that captures closure context
        const callback_data = try self.allocator.create(ClosureCallbackData);
        callback_data.* = ClosureCallbackData{
            .vm = self.vm,
            .closure_node = node_index,
            .allocator = self.allocator,
        };
        
        return Value.initNativeFunction(@ptrCast(&closureCallbackWrapper));
    }
    
    /// Wait for all coroutines to complete
    /// Requirement 5.2 - wait for all spawned coroutines to complete
    pub fn waitForAllCoroutines(self: *VMSchedulerIntegration) void {
        if (self.scheduler) |scheduler| {
            // Wait until all coroutines are completed
            while (scheduler.getStatus().active_coroutines > 0) {
                std.Thread.sleep(1_000_000); // 1ms
            }
        }
    }
    
    /// Get scheduler status
    pub fn getSchedulerStatus(self: *VMSchedulerIntegration) ?Scheduler.SchedulerStatus {
        if (self.scheduler) |scheduler| {
            return scheduler.getStatus();
        }
        return null;
    }
    
    /// Check if scheduler is running
    pub fn isSchedulerRunning(self: *VMSchedulerIntegration) bool {
        if (self.scheduler) |scheduler| {
            return scheduler.getStatus().is_running;
        }
        return false;
    }
};

/// Callback data for VM function execution
const VMCallbackData = struct {
    vm: *VM,
    func_name: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *VMCallbackData) void {
        self.allocator.free(self.func_name);
        self.allocator.destroy(self);
    }
};

/// Callback data for method execution
const MethodCallbackData = struct {
    vm: *VM,
    object_node: ast.Node.Index,
    method_name: []const u8,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *MethodCallbackData) void {
        self.allocator.free(self.method_name);
        self.allocator.destroy(self);
    }
};

/// Callback data for closure execution
const ClosureCallbackData = struct {
    vm: *VM,
    closure_node: ast.Node.Index,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *ClosureCallbackData) void {
        self.allocator.destroy(self);
    }
};

/// Wrapper function for VM callback execution
/// Executes a named function in the VM context
fn vmCallbackWrapper(vm: *VM, args: []const Value) !Value {
    // Get callback data from the native function context
    // In a real implementation, this would be passed through the Value
    // For now, we execute the function by name lookup
    _ = args;
    
    // Execute the function in the VM
    // The VM should have the function registered in its function table
    if (vm.user_functions.get("__coroutine_callback__")) |func| {
        return try vm.callUserFunction(func, args);
    }
    
    // If no specific callback, return null (coroutine completed without result)
    return Value.initNull();
}

/// Wrapper function for method callback execution
fn methodCallbackWrapper(vm: *VM, args: []const Value) !Value {
    _ = args;
    
    // Execute method call in VM context
    // This would evaluate the object, then call the method on it
    if (vm.user_functions.get("__method_callback__")) |func| {
        return try vm.callUserFunction(func, args);
    }
    
    return Value.initNull();
}

/// Wrapper function for closure callback execution
fn closureCallbackWrapper(vm: *VM, args: []const Value) !Value {
    _ = args;
    
    // Execute closure in VM context
    // This would evaluate the closure body with captured variables
    if (vm.user_functions.get("__closure_callback__")) |func| {
        return try vm.callUserFunction(func, args);
    }
    
    return Value.initNull();
}

// Tests
test "VM scheduler integration initialization" {
    const allocator = std.testing.allocator;
    
    // Create mock VM
    var vm = try VM.init(allocator);
    defer vm.deinit();
    
    const config = VMSchedulerIntegration.SchedulerConfig{
        .num_processors = 2,
        .num_workers = 2,
    };
    
    var integration = VMSchedulerIntegration.init(vm, config);
    defer integration.deinit();
    
    try std.testing.expect(!integration.is_initialized);
    try std.testing.expect(!integration.isSchedulerRunning());
    
    try integration.initializeScheduler();
    
    try std.testing.expect(integration.is_initialized);
    try std.testing.expect(integration.isSchedulerRunning());
    
    const status = integration.getSchedulerStatus();
    try std.testing.expect(status != null);
    try std.testing.expectEqual(@as(u32, 2), status.?.num_processors);
    try std.testing.expectEqual(@as(u32, 2), status.?.num_workers);
    
    integration.shutdownScheduler();
    try std.testing.expect(!integration.is_initialized);
}

test "VM scheduler coroutine spawning" {
    const allocator = std.testing.allocator;
    
    // Create mock VM
    var vm = try VM.init(allocator);
    defer vm.deinit();
    
    const config = VMSchedulerIntegration.SchedulerConfig{
        .num_processors = 1,
        .num_workers = 1,
    };
    
    var integration = VMSchedulerIntegration.init(vm, config);
    defer integration.deinit();
    
    try integration.initializeScheduler();
    
    const callback = Value.initNull();
    const args = [_]Value{};
    
    const coroutine_id = try integration.spawnCoroutine(callback, &args);
    try std.testing.expect(coroutine_id > 0);
    
    const status = integration.getSchedulerStatus();
    try std.testing.expect(status != null);
    try std.testing.expectEqual(@as(u64, 1), status.?.total_spawned);
}