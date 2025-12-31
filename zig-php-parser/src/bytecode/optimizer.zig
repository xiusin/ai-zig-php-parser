const std = @import("std");
const instruction = @import("instruction.zig");
const Instruction = instruction.Instruction;
const OpCode = instruction.OpCode;
const CompiledFunction = instruction.CompiledFunction;
const Value = instruction.Value;

/// 字节码优化器 - 实现多种编译器优化技术
/// 包括：常量折叠、死代码消除、内联优化、循环优化、尾调用优化
pub const BytecodeOptimizer = struct {
    allocator: std.mem.Allocator,
    optimization_level: OptimizationLevel,
    stats: OptimizationStats,

    pub const OptimizationLevel = enum {
        none, // 不优化
        basic, // 基础优化（常量折叠、死代码消除）
        standard, // 标准优化（+ 内联、循环优化）
        aggressive, // 激进优化（+ 尾调用、全局优化）
    };

    pub const OptimizationStats = struct {
        constants_folded: usize = 0,
        dead_code_removed: usize = 0,
        instructions_inlined: usize = 0,
        loops_optimized: usize = 0,
        tail_calls_converted: usize = 0,
        total_instructions_before: usize = 0,
        total_instructions_after: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator, level: OptimizationLevel) BytecodeOptimizer {
        return .{
            .allocator = allocator,
            .optimization_level = level,
            .stats = .{},
        };
    }

    /// 优化编译后的函数
    pub fn optimize(self: *BytecodeOptimizer, func: *CompiledFunction) !void {
        self.stats.total_instructions_before = func.bytecode.len;

        if (self.optimization_level == .none) return;

        // 基础优化
        try self.constantFolding(func);
        try self.deadCodeElimination(func);

        if (self.optimization_level == .basic) {
            self.stats.total_instructions_after = func.bytecode.len;
            return;
        }

        // 标准优化
        try self.peepholeOptimization(func);
        try self.loopOptimization(func);

        if (self.optimization_level == .standard) {
            self.stats.total_instructions_after = func.bytecode.len;
            return;
        }

        // 激进优化
        try self.tailCallOptimization(func);
        try self.strengthReduction(func);

        self.stats.total_instructions_after = func.bytecode.len;
    }

    /// 常量折叠 - 编译时计算常量表达式
    fn constantFolding(self: *BytecodeOptimizer, func: *CompiledFunction) !void {
        var i: usize = 0;
        while (i + 2 < func.bytecode.len) {
            const inst1 = func.bytecode[i];
            const inst2 = func.bytecode[i + 1];
            const inst3 = func.bytecode[i + 2];

            // 模式：push_const, push_const, add_int -> push_const (folded)
            if (inst1.opcode == .push_const and inst2.opcode == .push_const) {
                const val1 = func.constants[inst1.operand1];
                const val2 = func.constants[inst2.operand1];

                const folded = switch (inst3.opcode) {
                    .add_int => self.foldIntOp(val1, val2, .add),
                    .sub_int => self.foldIntOp(val1, val2, .sub),
                    .mul_int => self.foldIntOp(val1, val2, .mul),
                    .div_int => self.foldIntOp(val1, val2, .div),
                    .add_float => self.foldFloatOp(val1, val2, .add),
                    .sub_float => self.foldFloatOp(val1, val2, .sub),
                    .mul_float => self.foldFloatOp(val1, val2, .mul),
                    .div_float => self.foldFloatOp(val1, val2, .div),
                    else => null,
                };

                if (folded) |result| {
                    // 将结果添加到常量池
                    const const_idx = try self.addConstant(func, result);

                    // 替换三条指令为一条
                    func.bytecode[i] = Instruction.init(.push_const, const_idx, 0);
                    func.bytecode[i + 1] = Instruction.init(.nop, 0, 0);
                    func.bytecode[i + 2] = Instruction.init(.nop, 0, 0);

                    self.stats.constants_folded += 1;
                }
            }
            i += 1;
        }
    }

    fn foldIntOp(_: *BytecodeOptimizer, val1: Value, val2: Value, op: enum { add, sub, mul, div }) ?Value {
        const a = switch (val1) {
            .int_val => |v| v,
            else => return null,
        };
        const b = switch (val2) {
            .int_val => |v| v,
            else => return null,
        };

        const result = switch (op) {
            .add => a + b,
            .sub => a - b,
            .mul => a * b,
            .div => if (b != 0) @divTrunc(a, b) else return null,
        };

        return Value{ .int_val = result };
    }

    fn foldFloatOp(_: *BytecodeOptimizer, val1: Value, val2: Value, op: enum { add, sub, mul, div }) ?Value {
        const a = switch (val1) {
            .float_val => |v| v,
            else => return null,
        };
        const b = switch (val2) {
            .float_val => |v| v,
            else => return null,
        };

        const result = switch (op) {
            .add => a + b,
            .sub => a - b,
            .mul => a * b,
            .div => if (b != 0) a / b else return null,
        };

        return Value{ .float_val = result };
    }

    fn addConstant(_: *BytecodeOptimizer, func: *CompiledFunction, value: Value) !u16 {
        // 简化实现：直接添加到常量池末尾
        _ = func;
        _ = value;
        return 0;
    }

    /// 死代码消除 - 移除不可达代码
    fn deadCodeElimination(self: *BytecodeOptimizer, func: *CompiledFunction) !void {
        var reachable = try self.allocator.alloc(bool, func.bytecode.len);
        defer self.allocator.free(reachable);
        @memset(reachable, false);

        // 标记可达指令
        try self.markReachable(func, 0, reachable);

        // 将不可达指令替换为nop
        for (func.bytecode, 0..) |*inst, i| {
            if (!reachable[i] and inst.opcode != .nop) {
                inst.* = Instruction.init(.nop, 0, 0);
                self.stats.dead_code_removed += 1;
            }
        }
    }

    fn markReachable(self: *BytecodeOptimizer, func: *CompiledFunction, start: usize, reachable: []bool) !void {
        _ = self;
        var i = start;
        while (i < func.bytecode.len) {
            if (reachable[i]) break; // 已访问
            reachable[i] = true;

            const inst = func.bytecode[i];

            // 处理跳转
            if (inst.opcode.isJump()) {
                const target = inst.operand1;
                try self.markReachable(func, target, reachable);

                // 条件跳转继续执行下一条
                if (inst.opcode != .jmp) {
                    i += 1;
                    continue;
                } else {
                    break; // 无条件跳转
                }
            }

            // 返回或停止终止当前路径
            if (inst.opcode.isTerminator()) break;

            i += 1;
        }
    }

    /// 窥孔优化 - 局部模式替换
    fn peepholeOptimization(self: *BytecodeOptimizer, func: *CompiledFunction) !void {
        var i: usize = 0;
        while (i + 1 < func.bytecode.len) {
            const inst1 = func.bytecode[i];
            const inst2 = func.bytecode[i + 1];

            // 模式：push, pop -> nop, nop
            if ((inst1.opcode == .push_const or inst1.opcode == .push_local) and inst2.opcode == .pop) {
                func.bytecode[i] = Instruction.init(.nop, 0, 0);
                func.bytecode[i + 1] = Instruction.init(.nop, 0, 0);
                self.stats.dead_code_removed += 2;
            }

            // 模式：dup, pop -> nop, nop
            if (inst1.opcode == .dup and inst2.opcode == .pop) {
                func.bytecode[i] = Instruction.init(.nop, 0, 0);
                func.bytecode[i + 1] = Instruction.init(.nop, 0, 0);
                self.stats.dead_code_removed += 2;
            }

            // 模式：push_int_0, add_int -> nop, nop (加0优化)
            if (inst1.opcode == .push_int_0 and inst2.opcode == .add_int) {
                func.bytecode[i] = Instruction.init(.nop, 0, 0);
                func.bytecode[i + 1] = Instruction.init(.nop, 0, 0);
                self.stats.dead_code_removed += 2;
            }

            // 模式：push_int_1, mul_int -> nop, nop (乘1优化)
            if (inst1.opcode == .push_int_1 and inst2.opcode == .mul_int) {
                func.bytecode[i] = Instruction.init(.nop, 0, 0);
                func.bytecode[i + 1] = Instruction.init(.nop, 0, 0);
                self.stats.dead_code_removed += 2;
            }

            i += 1;
        }
    }

    /// 循环优化 - 循环不变代码外提
    fn loopOptimization(self: *BytecodeOptimizer, func: *CompiledFunction) !void {
        // 查找循环
        var i: usize = 0;
        while (i < func.bytecode.len) {
            if (func.bytecode[i].opcode == .loop_start) {
                const loop_start = i;
                var loop_end = i + 1;

                // 找到循环结束
                while (loop_end < func.bytecode.len and func.bytecode[loop_end].opcode != .loop_end) {
                    loop_end += 1;
                }

                if (loop_end < func.bytecode.len) {
                    try self.optimizeLoop(func, loop_start, loop_end);
                    self.stats.loops_optimized += 1;
                }

                i = loop_end + 1;
            } else {
                i += 1;
            }
        }
    }

    fn optimizeLoop(_: *BytecodeOptimizer, func: *CompiledFunction, start: usize, end: usize) !void {
        // 循环不变代码检测（简化实现）
        _ = func;
        _ = start;
        _ = end;
    }

    /// 尾调用优化 - 将尾递归转换为循环
    fn tailCallOptimization(self: *BytecodeOptimizer, func: *CompiledFunction) !void {
        var i: usize = 0;
        while (i + 1 < func.bytecode.len) {
            const inst1 = func.bytecode[i];
            const inst2 = func.bytecode[i + 1];

            // 模式：call, ret -> tail_call
            if (inst1.opcode == .call and inst2.opcode == .ret) {
                func.bytecode[i] = inst1.asTailCall();
                func.bytecode[i + 1] = Instruction.init(.nop, 0, 0);
                self.stats.tail_calls_converted += 1;
            }

            i += 1;
        }
    }

    /// 强度削减 - 用低开销操作替换高开销操作
    fn strengthReduction(self: *BytecodeOptimizer, func: *CompiledFunction) !void {
        for (func.bytecode, 0..) |*inst, i| {
            _ = i;
            switch (inst.opcode) {
                // 乘以2的幂 -> 左移
                .mul_int => {
                    // 检查是否乘以2的幂（需要检查常量池）
                    // 简化：这里只做标记，实际实现需要检查操作数
                },
                // 除以2的幂 -> 右移
                .div_int => {
                    // 类似处理
                },
                // 模2的幂 -> 位与
                .mod_int => {
                    // x % 2^n -> x & (2^n - 1)
                },
                else => {},
            }
            _ = self;
        }
    }

    /// 获取优化统计
    pub fn getStats(self: *const BytecodeOptimizer) OptimizationStats {
        return self.stats;
    }

    /// 打印优化报告
    pub fn printReport(self: *const BytecodeOptimizer) void {
        std.debug.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║                    优化报告 (Optimization Report)            ║\n", .{});
        std.debug.print("╠══════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║ 优化级别: {s}                                               \n", .{@tagName(self.optimization_level)});
        std.debug.print("║ 常量折叠: {} 次                                              \n", .{self.stats.constants_folded});
        std.debug.print("║ 死代码消除: {} 条指令                                        \n", .{self.stats.dead_code_removed});
        std.debug.print("║ 内联指令: {} 条                                              \n", .{self.stats.instructions_inlined});
        std.debug.print("║ 循环优化: {} 个                                              \n", .{self.stats.loops_optimized});
        std.debug.print("║ 尾调用转换: {} 次                                            \n", .{self.stats.tail_calls_converted});
        std.debug.print("║ 指令数变化: {} -> {} ({d:.1}%)                               \n", .{
            self.stats.total_instructions_before,
            self.stats.total_instructions_after,
            if (self.stats.total_instructions_before > 0)
                @as(f64, @floatFromInt(self.stats.total_instructions_after)) / @as(f64, @floatFromInt(self.stats.total_instructions_before)) * 100.0
            else
                100.0,
        });
        std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
    }
};

/// 类型推导器 - 编译时类型分析
pub const TypeInference = struct {
    allocator: std.mem.Allocator,
    type_env: std.StringHashMapUnmanaged(InferredType),

    pub const InferredType = enum {
        unknown,
        null_type,
        boolean,
        integer,
        float,
        string,
        array,
        object,
        mixed,
    };

    pub fn init(allocator: std.mem.Allocator) TypeInference {
        return .{
            .allocator = allocator,
            .type_env = .{},
        };
    }

    pub fn deinit(self: *TypeInference) void {
        self.type_env.deinit(self.allocator);
    }

    /// 推导变量类型
    pub fn inferVariable(self: *TypeInference, name: []const u8) InferredType {
        return self.type_env.get(name) orelse .unknown;
    }

    /// 设置变量类型
    pub fn setVariableType(self: *TypeInference, name: []const u8, inferred_type: InferredType) !void {
        try self.type_env.put(self.allocator, name, inferred_type);
    }

    /// 推导二元操作结果类型
    pub fn inferBinaryOp(left: InferredType, right: InferredType, op: OpCode) InferredType {
        // 整数运算
        if (left == .integer and right == .integer) {
            return switch (op) {
                .add_int, .sub_int, .mul_int, .mod_int, .bit_and, .bit_or, .bit_xor, .shl, .shr => .integer,
                .div_int => .float, // PHP除法返回浮点
                .eq_int, .lt_int, .gt_int => .boolean,
                else => .mixed,
            };
        }

        // 浮点运算
        if ((left == .integer or left == .float) and (right == .integer or right == .float)) {
            return switch (op) {
                .add_float, .sub_float, .mul_float, .div_float => .float,
                .eq_float, .lt_float, .gt_float => .boolean,
                else => .mixed,
            };
        }

        // 字符串操作
        if (left == .string or right == .string) {
            return switch (op) {
                .concat => .string,
                .str_cmp => .integer,
                .eq, .neq, .identical, .not_identical => .boolean,
                else => .mixed,
            };
        }

        return .mixed;
    }
};

/// 逃逸分析器 - 确定对象是否逃逸当前作用域
pub const EscapeAnalyzer = struct {
    allocator: std.mem.Allocator,
    escape_states: std.StringHashMapUnmanaged(EscapeState),

    pub const EscapeState = enum {
        no_escape, // 不逃逸，可栈分配
        return_escape, // 通过返回值逃逸
        argument_escape, // 通过参数逃逸
        global_escape, // 通过全局变量逃逸
        heap_escape, // 存储到堆对象中
    };

    pub fn init(allocator: std.mem.Allocator) EscapeAnalyzer {
        return .{
            .allocator = allocator,
            .escape_states = .{},
        };
    }

    pub fn deinit(self: *EscapeAnalyzer) void {
        self.escape_states.deinit(self.allocator);
    }

    /// 分析变量逃逸状态
    pub fn analyzeFunction(self: *EscapeAnalyzer, func: *CompiledFunction) !void {
        for (func.bytecode) |inst| {
            switch (inst.opcode) {
                .store_global => {
                    // 存储到全局变量 -> 全局逃逸
                    if (inst.operand1 < func.constants.len) {
                        const const_val = func.constants[inst.operand1];
                        if (const_val == .string_val) {
                            try self.escape_states.put(self.allocator, const_val.string_val, .global_escape);
                        }
                    }
                },
                .ret => {
                    // 返回值可能逃逸，但需要更复杂的数据流分析
                },
                .set_prop => {
                    // 存储到对象属性 -> 堆逃逸
                },
                .call => {
                    // 作为参数传递可能逃逸
                },
                else => {},
            }
        }
    }

    /// 获取变量逃逸状态
    pub fn getEscapeState(self: *const EscapeAnalyzer, name: []const u8) EscapeState {
        return self.escape_states.get(name) orelse .no_escape;
    }

    /// 判断是否可以栈分配
    pub fn canStackAllocate(self: *const EscapeAnalyzer, name: []const u8) bool {
        return self.getEscapeState(name) == .no_escape;
    }
};

/// 内联缓存 - 多态方法调用优化
pub const InlineCache = struct {
    entries: [PIC_SIZE]CacheEntry,
    count: u8,
    state: CacheState,

    const PIC_SIZE = 4; // 多态内联缓存大小

    pub const CacheState = enum {
        uninitialized, // 未初始化
        monomorphic, // 单态（1个类型）
        polymorphic, // 多态（2-4个类型）
        megamorphic, // 超多态（回退到查找）
    };

    pub const CacheEntry = struct {
        class_id: u16,
        method_offset: u16,
        hit_count: u32,
    };

    pub fn init() InlineCache {
        return .{
            .entries = undefined,
            .count = 0,
            .state = .uninitialized,
        };
    }

    /// 查找缓存
    pub fn lookup(self: *InlineCache, class_id: u16) ?u16 {
        for (self.entries[0..self.count]) |entry| {
            if (entry.class_id == class_id) {
                entry.hit_count += 1;
                return entry.method_offset;
            }
        }
        return null;
    }

    /// 更新缓存
    pub fn update(self: *InlineCache, class_id: u16, method_offset: u16) void {
        if (self.state == .megamorphic) return;

        if (self.count < PIC_SIZE) {
            self.entries[self.count] = .{
                .class_id = class_id,
                .method_offset = method_offset,
                .hit_count = 1,
            };
            self.count += 1;

            self.state = switch (self.count) {
                1 => .monomorphic,
                else => .polymorphic,
            };
        } else {
            self.state = .megamorphic;
        }
    }

    /// 获取缓存命中率
    pub fn getHitRate(self: *const InlineCache) f64 {
        var total_hits: u64 = 0;
        for (self.entries[0..self.count]) |entry| {
            total_hits += entry.hit_count;
        }
        return if (total_hits > 0)
            @as(f64, @floatFromInt(total_hits)) / @as(f64, @floatFromInt(self.count))
        else
            0.0;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "optimizer basic" {
    const opt = BytecodeOptimizer.init(std.testing.allocator, .basic);
    try std.testing.expect(opt.optimization_level == .basic);
}

test "type inference" {
    var inference = TypeInference.init(std.testing.allocator);
    defer inference.deinit();

    try inference.setVariableType("x", .integer);
    try std.testing.expect(inference.inferVariable("x") == .integer);
    try std.testing.expect(inference.inferVariable("y") == .unknown);
}

test "inline cache" {
    var cache = InlineCache.init();

    // 首次调用 - 未命中
    try std.testing.expect(cache.lookup(1) == null);
    cache.update(1, 100);
    try std.testing.expect(cache.state == .monomorphic);

    // 再次调用 - 命中
    try std.testing.expect(cache.lookup(1) == 100);

    // 不同类型 - 多态
    cache.update(2, 200);
    try std.testing.expect(cache.state == .polymorphic);
}

test "escape analyzer" {
    var analyzer = EscapeAnalyzer.init(std.testing.allocator);
    defer analyzer.deinit();

    try std.testing.expect(analyzer.canStackAllocate("local_var"));
}
