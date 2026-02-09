const std = @import("std");

/// 分层编译系统
pub const TieredCompilation = struct {
    pub const Tier = enum {
        interpreter,
        baseline_jit,
        optimizing_jit,
    };
    
    pub const CompiledCode = struct {
        machine_code: []const u8,
        entry_point: *const fn () callconv(.c) void,
        code_size: usize,
    };
    
    pub const CompilationState = struct {
        current_tier: Tier,
        execution_count: u32,
        compiled_code: ?*CompiledCode,
        compilation_time_ns: u64,
    };
    
    pub const CompilationStats = struct {
        interpreter_count: u32,
        baseline_count: u32,
        optimizing_count: u32,
        total_compilation_time_ns: u64,
    };
    
    allocator: std.mem.Allocator,
    function_states: std.StringHashMap(CompilationState),
    baseline_threshold: u32 = 100,
    optimizing_threshold: u32 = 10000,
    
    pub fn init(allocator: std.mem.Allocator) TieredCompilation {
        return .{
            .allocator = allocator,
            .function_states = std.StringHashMap(CompilationState).init(allocator),
        };
    }
    
    pub fn deinit(self: *TieredCompilation) void {
        var it = self.function_states.valueIterator();
        while (it.next()) |state| {
            if (state.compiled_code) |code| {
                self.allocator.free(code.machine_code);
                self.allocator.destroy(code);
            }
        }
        self.function_states.deinit();
    }
    
    pub fn recordExecution(self: *TieredCompilation, function_name: []const u8) !bool {
        const entry = try self.function_states.getOrPut(function_name);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{
                .current_tier = .interpreter,
                .execution_count = 0,
                .compiled_code = null,
                .compilation_time_ns = 0,
            };
        }
        
        entry.value_ptr.execution_count += 1;
        return self.shouldUpgrade(entry.value_ptr);
    }
    
    pub fn shouldUpgrade(self: *TieredCompilation, state: *CompilationState) bool {
        return switch (state.current_tier) {
            .interpreter => state.execution_count >= self.baseline_threshold,
            .baseline_jit => state.execution_count >= self.optimizing_threshold,
            .optimizing_jit => false,
        };
    }
    
    pub fn upgrade(self: *TieredCompilation, function_name: []const u8) !void {
        const state = self.function_states.getPtr(function_name) orelse return error.FunctionNotFound;
        
        const next_tier: Tier = switch (state.current_tier) {
            .interpreter => .baseline_jit,
            .baseline_jit => .optimizing_jit,
            .optimizing_jit => return,
        };
        
        const start_time = std.time.nanoTimestamp();
        const compiled = try self.compile(function_name, next_tier);
        const end_time = std.time.nanoTimestamp();
        
        if (state.compiled_code) |old_code| {
            self.allocator.free(old_code.machine_code);
            self.allocator.destroy(old_code);
        }
        
        state.compiled_code = compiled;
        state.current_tier = next_tier;
        state.compilation_time_ns = @intCast(end_time - start_time);
    }
    
    fn compile(self: *TieredCompilation, function_name: []const u8, tier: Tier) !*CompiledCode {
        const code = try self.allocator.create(CompiledCode);
        errdefer self.allocator.destroy(code);
        
        const machine_code = switch (tier) {
            .interpreter => unreachable,
            .baseline_jit => try std.fmt.allocPrint(self.allocator, "; Baseline JIT for {s}\nmov rax, 42\nret\n", .{function_name}),
            .optimizing_jit => try std.fmt.allocPrint(self.allocator, "; Optimizing JIT for {s}\nxor rax, rax\nmov eax, 42\nret\n", .{function_name}),
        };
        
        code.* = .{
            .machine_code = machine_code,
            .entry_point = @ptrCast(@alignCast(machine_code.ptr)),
            .code_size = machine_code.len,
        };
        
        return code;
    }
    
    pub fn getCurrentTier(self: *TieredCompilation, function_name: []const u8) ?Tier {
        const state = self.function_states.get(function_name) orelse return null;
        return state.current_tier;
    }
    
    pub fn getStats(self: *TieredCompilation) CompilationStats {
        var stats = CompilationStats{
            .interpreter_count = 0,
            .baseline_count = 0,
            .optimizing_count = 0,
            .total_compilation_time_ns = 0,
        };
        
        var it = self.function_states.valueIterator();
        while (it.next()) |state| {
            switch (state.current_tier) {
                .interpreter => stats.interpreter_count += 1,
                .baseline_jit => stats.baseline_count += 1,
                .optimizing_jit => stats.optimizing_count += 1,
            }
            stats.total_compilation_time_ns += state.compilation_time_ns;
        }
        
        return stats;
    }
    
    pub fn deoptimize(self: *TieredCompilation, function_name: []const u8) !void {
        const state = self.function_states.getPtr(function_name) orelse return error.FunctionNotFound;
        
        if (state.compiled_code) |code| {
            self.allocator.free(code.machine_code);
            self.allocator.destroy(code);
            state.compiled_code = null;
        }
        
        state.current_tier = .interpreter;
        state.execution_count = 0;
    }
    
    pub fn forceCompile(self: *TieredCompilation, function_name: []const u8, tier: Tier) !void {
        const entry = try self.function_states.getOrPut(function_name);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{
                .current_tier = .interpreter,
                .execution_count = 0,
                .compiled_code = null,
                .compilation_time_ns = 0,
            };
        }
        
        if (tier == .interpreter) {
            try self.deoptimize(function_name);
            return;
        }
        
        const start_time = std.time.nanoTimestamp();
        const compiled = try self.compile(function_name, tier);
        const end_time = std.time.nanoTimestamp();
        
        if (entry.value_ptr.compiled_code) |old_code| {
            self.allocator.free(old_code.machine_code);
            self.allocator.destroy(old_code);
        }
        
        entry.value_ptr.compiled_code = compiled;
        entry.value_ptr.current_tier = tier;
        entry.value_ptr.compilation_time_ns = @intCast(end_time - start_time);
    }
};
