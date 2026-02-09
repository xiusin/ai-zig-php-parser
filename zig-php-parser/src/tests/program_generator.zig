const std = @import("std");
const Allocator = std.mem.Allocator;

/// 随机程序生成器
pub const ProgramGenerator = struct {
    allocator: Allocator,
    rng: std.Random.DefaultPrng,

    pub fn init(allocator: Allocator, seed: u64) ProgramGenerator {
        return ProgramGenerator{
            .allocator = allocator,
            .rng = std.Random.DefaultPrng.init(seed),
        };
    }

    /// 生成随机程序
    pub fn generate(self: *ProgramGenerator) !Program {
        const random = self.rng.random();
        
        const num_functions = random.intRangeAtMost(usize, 1, 5);
        var functions = try std.ArrayList(Function).initCapacity(self.allocator, num_functions);
        
        var i: usize = 0;
        while (i < num_functions) : (i += 1) {
            try functions.append(self.allocator, try self.generateFunction());
        }
        
        return Program{
            .functions = functions,
            .allocator = self.allocator,
        };
    }

    fn generateFunction(self: *ProgramGenerator) !Function {
        const random = self.rng.random();
        
        const num_statements = random.intRangeAtMost(usize, 1, 10);
        var statements = try std.ArrayList(Statement).initCapacity(self.allocator, num_statements);
        
        var i: usize = 0;
        while (i < num_statements) : (i += 1) {
            try statements.append(self.allocator, try self.generateStatement());
        }
        
        return Function{
            .name = try self.generateName(),
            .statements = statements,
            .allocator = self.allocator,
        };
    }

    fn generateStatement(self: *ProgramGenerator) !Statement {
        const random = self.rng.random();
        const kind = random.intRangeAtMost(u8, 0, 2);
        
        return switch (kind) {
            0 => Statement{ .assignment = .{
                .var_name = try self.generateName(),
                .value = random.int(i32),
            } },
            1 => Statement{ .return_stmt = .{
                .value = random.int(i32),
            } },
            else => Statement{ .call = .{
                .func_name = try self.generateName(),
            } },
        };
    }

    fn generateName(self: *ProgramGenerator) ![]const u8 {
        const random = self.rng.random();
        const names = [_][]const u8{ "foo", "bar", "baz", "qux", "test" };
        const idx = random.intRangeAtMost(usize, 0, names.len - 1);
        return names[idx];
    }
};

/// 程序表示
pub const Program = struct {
    functions: std.ArrayList(Function),
    allocator: Allocator,

    pub fn deinit(self: *Program) void {
        for (self.functions.items) |*func| {
            func.deinit();
        }
        self.functions.deinit(self.allocator);
    }
};

/// 函数表示
pub const Function = struct {
    name: []const u8,
    statements: std.ArrayList(Statement),
    allocator: Allocator,

    pub fn deinit(self: *Function) void {
        self.statements.deinit(self.allocator);
    }
};

/// 语句表示
pub const Statement = union(enum) {
    assignment: struct {
        var_name: []const u8,
        value: i32,
    },
    return_stmt: struct {
        value: i32,
    },
    call: struct {
        func_name: []const u8,
    },
};

/// 执行结果
pub const ExecutionResult = struct {
    return_value: i32,
    side_effects: std.ArrayList(SideEffect),
    allocator: Allocator,

    pub fn init(allocator: Allocator) !ExecutionResult {
        return ExecutionResult{
            .return_value = 0,
            .side_effects = try std.ArrayList(SideEffect).initCapacity(allocator, 0),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ExecutionResult) void {
        self.side_effects.deinit(self.allocator);
    }

    pub fn equals(self: *ExecutionResult, other: *ExecutionResult) bool {
        if (self.return_value != other.return_value) return false;
        if (self.side_effects.items.len != other.side_effects.items.len) return false;
        
        for (self.side_effects.items, 0..) |effect, i| {
            if (!effect.equals(other.side_effects.items[i])) return false;
        }
        
        return true;
    }
};

/// 副作用
pub const SideEffect = struct {
    kind: SideEffectKind,
    value: i32,

    pub fn equals(self: SideEffect, other: SideEffect) bool {
        return self.kind == other.kind and self.value == other.value;
    }
};

pub const SideEffectKind = enum {
    print,
    write,
};
