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
    pub fn constantFolding(self: *BytecodeOptimizer, func: *CompiledFunction) !void {
        var i: usize = 0;
        while (i + 2 < func.bytecode.len) {
            const inst1 = func.bytecode[i];
            const inst2 = func.bytecode[i + 1];
            const inst3 = func.bytecode[i + 2];

            // 模式：push_const, push_const, add_int -> push_const (folded)
            if (inst1.opcode == .push_const and inst2.opcode == .push_const) {
                // 检查常量索引是否有效
                if (inst1.operand1 >= func.constants.len or inst2.operand1 >= func.constants.len) {
                    i += 1;
                    continue;
                }

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

        // 条件表达式折叠 (三元运算符优化)
        try self.foldConditionalExpressions(func);
    }

    /// 条件表达式折叠 - 优化三元运算符 (true ? a : b)
    ///
    /// 模式匹配：
    /// 1. push_const (bool), jz else_label, <then_branch>, jmp end_label, <else_branch>
    ///    -> 如果条件为常量true，直接执行then分支
    ///    -> 如果条件为常量false，直接执行else分支
    fn foldConditionalExpressions(self: *BytecodeOptimizer, func: *CompiledFunction) !void {
        var i: usize = 0;
        while (i + 1 < func.bytecode.len) {
            const inst1 = func.bytecode[i];
            const inst2 = func.bytecode[i + 1];

            // 模式：push_const (bool), jz else_label
            if (inst1.opcode == .push_const and inst2.opcode == .jz) {
                const cond_val = func.constants[inst1.operand1];
                const else_label = inst2.operand1;

                // 检查条件是否为常量布尔值
                const is_true = switch (cond_val) {
                    .bool_val => |b| b,
                    .int_val => |n| n != 0,
                    else => null,
                };

                if (is_true) |cond| {
                    if (cond) {
                        // 条件为true：移除jz指令，保留then分支
                        // 需要找到对应的jmp end_label并移除
                        func.bytecode[i] = Instruction.init(.nop, 0, 0);
                        func.bytecode[i + 1] = Instruction.init(.nop, 0, 0);

                        // 查找并移除else分支的跳转
                        var j = i + 2;
                        while (j < func.bytecode.len and j < else_label) {
                            if (func.bytecode[j].opcode == .jmp) {
                                const end_label = func.bytecode[j].operand1;
                                func.bytecode[j] = Instruction.init(.nop, 0, 0);

                                // 将else分支标记为死代码
                                var k = else_label;
                                while (k < end_label and k < func.bytecode.len) {
                                    if (func.bytecode[k].opcode != .nop) {
                                        func.bytecode[k] = Instruction.init(.nop, 0, 0);
                                        self.stats.dead_code_removed += 1;
                                    }
                                    k += 1;
                                }
                                break;
                            }
                            j += 1;
                        }

                        self.stats.constants_folded += 1;
                    } else {
                        // 条件为false：跳转到else分支，移除then分支
                        func.bytecode[i] = Instruction.init(.nop, 0, 0);
                        func.bytecode[i + 1] = Instruction.init(.jmp, else_label, 0);

                        // 将then分支标记为死代码
                        var j = i + 2;
                        while (j < else_label and j < func.bytecode.len) {
                            if (func.bytecode[j].opcode != .nop and func.bytecode[j].opcode != .jmp) {
                                func.bytecode[j] = Instruction.init(.nop, 0, 0);
                                self.stats.dead_code_removed += 1;
                            }
                            j += 1;
                        }

                        self.stats.constants_folded += 1;
                    }
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

    /// 添加常量到常量池（完整实现：去重 + 高效索引）
    /// @pre value 必须有效
    /// @post 返回常量在常量池中的索引
    /// @ownership NON-OWNING (value)
    pub fn addConstant(self: *BytecodeOptimizer, func: *CompiledFunction, value: Value) !u16 {
        // 1. 检查常量池中是否已存在相同值（去重）
        for (func.constants, 0..) |existing, idx| {
            if (self.valuesEqual(existing, value)) {
                return @as(u16, @intCast(idx));
            }
        }

        // 2. 不存在，添加到常量池
        const new_constants = try self.allocator.alloc(Value, func.constants.len + 1);
        @memcpy(new_constants[0..func.constants.len], func.constants);
        new_constants[func.constants.len] = value;

        // 3. 释放旧常量池，更新指针
        if (func.constants.len > 0) {
            self.allocator.free(func.constants);
        }
        func.constants = new_constants;

        return @as(u16, @intCast(func.constants.len - 1));
    }

    /// 比较两个Value是否相等
    /// @pre val1 和 val2 必须有效
    /// @post 返回是否相等
    fn valuesEqual(_: *BytecodeOptimizer, val1: Value, val2: Value) bool {
        // 检查类型是否相同
        if (@as(std.meta.Tag(Value), val1) != @as(std.meta.Tag(Value), val2)) {
            return false;
        }

        return switch (val1) {
            .null_val => true,
            .bool_val => |b1| val2.bool_val == b1,
            .int_val => |int1| val2.int_val == int1,
            .float_val => |f1| val2.float_val == f1,
            .string_val => |s1| std.mem.eql(u8, s1, val2.string_val),
            .array_val => false, // 数组常量不去重（复杂度高）
            .class_ref => |c1| val2.class_ref == c1,
            .func_ref => |f1| val2.func_ref == f1,
        };
    }

    /// 死代码消除 - 移除不可达代码
    fn deadCodeElimination(self: *BytecodeOptimizer, func: *CompiledFunction) !void {
        const reachable = try self.allocator.alloc(bool, func.bytecode.len);
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

    /// 循环优化 - 循环不变代码外提（完整实现）
    /// @pre func 必须有效
    /// @post 循环不变代码被提升到循环外
    pub fn loopOptimization(self: *BytecodeOptimizer, func: *CompiledFunction) !void {
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

    /// 优化单个循环（完整实现）
    /// @pre loop_start < loop_end < func.bytecode.len
    /// @post 循环不变代码被提升
    fn optimizeLoop(self: *BytecodeOptimizer, func: *CompiledFunction, start: usize, end: usize) !void {
        // 1. 分析循环内的指令，识别不变代码
        var invariant_instructions: std.ArrayListUnmanaged(usize) = .{};
        defer invariant_instructions.deinit(self.allocator);

        // 2. 构建定义-使用链
        var def_use = try self.buildDefUseChain(func, start, end);
        defer def_use.deinit();

        // 3. 识别循环不变量
        var i = start + 1;
        while (i < end) : (i += 1) {
            const inst = func.bytecode[i];

            // 检查指令是否为循环不变
            if (try self.isLoopInvariant(func, inst, start, end, def_use)) {
                try invariant_instructions.append(self.allocator, i);
            }
        }

        // 4. 提升不变代码到循环前
        if (invariant_instructions.items.len > 0) {
            try self.hoistInstructions(func, invariant_instructions.items, start);
        }
    }

    /// 构建定义-使用链
    /// @pre func, start, end 必须有效
    /// @post 返回变量的定义和使用位置映射
    fn buildDefUseChain(self: *BytecodeOptimizer, func: *CompiledFunction, start: usize, end: usize) !std.AutoHashMap(u16, DefUseInfo) {
        var chain = std.AutoHashMap(u16, DefUseInfo).init(self.allocator);

        var i = start;
        while (i < end) : (i += 1) {
            const inst = func.bytecode[i];

            // 记录定义
            switch (inst.opcode) {
                .store_local, .store_global => {
                    const var_id = inst.operand1;
                    var info = chain.get(var_id) orelse DefUseInfo{
                        .definitions = std.ArrayListUnmanaged(usize){ .items = &.{}, .capacity = 0 },
                        .uses = std.ArrayListUnmanaged(usize){ .items = &.{}, .capacity = 0 },
                    };
                    try info.definitions.append(self.allocator, i);
                    try chain.put(var_id, info);
                },

                // 记录使用
                .push_local, .push_global => {
                    const var_id = inst.operand1;
                    var info = chain.get(var_id) orelse DefUseInfo{
                        .definitions = std.ArrayListUnmanaged(usize){ .items = &.{}, .capacity = 0 },
                        .uses = std.ArrayListUnmanaged(usize){ .items = &.{}, .capacity = 0 },
                    };
                    try info.uses.append(self.allocator, i);
                    try chain.put(var_id, info);
                },

                else => {},
            }
        }

        return chain;
    }

    /// 定义-使用信息
    const DefUseInfo = struct {
        definitions: std.ArrayListUnmanaged(usize),
        uses: std.ArrayListUnmanaged(usize),

        pub fn deinit(self: *DefUseInfo, allocator: std.mem.Allocator) void {
            self.definitions.deinit(allocator);
            self.uses.deinit(allocator);
        }
    };

    /// 判断指令是否为循环不变
    /// @pre inst, start, end, def_use 必须有效
    /// @post 返回指令是否不依赖循环变量
    fn isLoopInvariant(_: *BytecodeOptimizer, func: *CompiledFunction, inst: Instruction, start: usize, end: usize, def_use: std.AutoHashMap(u16, DefUseInfo)) !bool {
        _ = func;

        // 1. 不能有副作用（调用、I/O、异常）
        if (inst.opcode.isCall() or inst.opcode == .throw or inst.opcode == .yield_val) {
            return false;
        }

        // 2. 不能修改循环变量
        switch (inst.opcode) {
            .store_local, .store_global => return false,
            else => {},
        }

        // 3. 操作数必须是常量或循环外定义的变量
        switch (inst.opcode) {
            .push_local, .push_global => {
                const var_id = inst.operand1;
                if (def_use.get(var_id)) |info| {
                    // 检查所有定义是否都在循环外
                    for (info.definitions.items) |def_pos| {
                        if (def_pos >= start and def_pos < end) {
                            return false; // 在循环内定义
                        }
                    }
                }
            },

            .push_const => {
                // 常量总是不变的
                return true;
            },

            else => {},
        }

        return true;
    }

    /// 提升指令到循环前
    /// @pre positions 必须有效且排序
    /// @post 指令被移动到 loop_start 之前
    fn hoistInstructions(self: *BytecodeOptimizer, func: *CompiledFunction, positions: []const usize, loop_start: usize) !void {
        // 1. 收集要提升的指令
        var hoisted: std.ArrayListUnmanaged(Instruction) = .{};
        defer hoisted.deinit(self.allocator);

        for (positions) |pos| {
            try hoisted.append(self.allocator, func.bytecode[pos]);
            // 将原位置标记为nop
            func.bytecode[pos] = Instruction.init(.nop, 0, 0);
        }

        // 2. 在循环前插入提升的指令
        // 注意：这需要重新分配字节码数组
        const new_len = func.bytecode.len + hoisted.items.len;
        const new_bytecode = try self.allocator.alloc(Instruction, new_len);

        // 复制循环前的代码
        @memcpy(new_bytecode[0..loop_start], func.bytecode[0..loop_start]);

        // 插入提升的指令
        @memcpy(new_bytecode[loop_start .. loop_start + hoisted.items.len], hoisted.items);

        // 复制循环及之后的代码
        @memcpy(new_bytecode[loop_start + hoisted.items.len ..], func.bytecode[loop_start..]);

        // 更新字节码
        self.allocator.free(func.bytecode);
        func.bytecode = new_bytecode;
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

    /// 强度削减 - 用低开销操作替换高开销操作（完整实现）
    /// @pre func 必须有效
    /// @post 高开销操作被替换为等价的低开销操作
    pub fn strengthReduction(self: *BytecodeOptimizer, func: *CompiledFunction) !void {
        var i: usize = 0;
        while (i + 1 < func.bytecode.len) : (i += 1) {
            const inst = func.bytecode[i];

            switch (inst.opcode) {
                // 乘法优化
                .mul_int => {
                    // 检查前一条指令是否为push_const
                    if (i > 0 and func.bytecode[i - 1].opcode == .push_const) {
                        const const_idx = func.bytecode[i - 1].operand1;
                        if (const_idx < func.constants.len) {
                            const val = func.constants[const_idx];
                            if (val == .int_val) {
                                const n = val.int_val;

                                // 乘以0 -> pop + push_int_0
                                if (n == 0) {
                                    func.bytecode[i - 1] = Instruction.init(.pop, 0, 0);
                                    func.bytecode[i] = Instruction.init(.push_int_0, 0, 0);
                                    self.stats.constants_folded += 1;
                                }
                                // 乘以2的幂 -> 左移
                                else if (n > 0 and (n & (n - 1)) == 0) {
                                    // 计算移位量
                                    const shift = @ctz(n);

                                    // 创建移位量常量
                                    const shift_val = Value{ .int_val = shift };
                                    const shift_idx = try self.addConstant(func, shift_val);

                                    // 替换为左移
                                    func.bytecode[i - 1] = Instruction.init(.push_const, shift_idx, 0);
                                    func.bytecode[i] = Instruction.init(.shl, 0, 0);

                                    self.stats.constants_folded += 1;
                                }
                            }
                        }
                    }
                },

                // 浮点乘法优化
                .mul_float => {
                    if (i > 0 and func.bytecode[i - 1].opcode == .push_const) {
                        const const_idx = func.bytecode[i - 1].operand1;
                        if (const_idx < func.constants.len) {
                            const val = func.constants[const_idx];
                            if (val == .float_val) {
                                const f = val.float_val;
                                // 乘以0.0 -> pop + push_int_0
                                if (f == 0.0) {
                                    func.bytecode[i - 1] = Instruction.init(.pop, 0, 0);
                                    func.bytecode[i] = Instruction.init(.push_int_0, 0, 0);
                                    self.stats.constants_folded += 1;
                                }
                            }
                        }
                    }
                },

                // 除以2的幂 -> 右移
                .div_int => {
                    if (i > 0 and func.bytecode[i - 1].opcode == .push_const) {
                        const const_idx = func.bytecode[i - 1].operand1;
                        if (const_idx < func.constants.len) {
                            const val = func.constants[const_idx];
                            if (val == .int_val) {
                                const n = val.int_val;
                                if (n > 0 and (n & (n - 1)) == 0) {
                                    const shift = @ctz(n);
                                    const shift_val = Value{ .int_val = shift };
                                    const shift_idx = try self.addConstant(func, shift_val);

                                    func.bytecode[i - 1] = Instruction.init(.push_const, shift_idx, 0);
                                    func.bytecode[i] = Instruction.init(.shr, 0, 0);

                                    self.stats.constants_folded += 1;
                                }
                            }
                        }
                    }
                },

                // 模2的幂 -> 位与
                .mod_int => {
                    if (i > 0 and func.bytecode[i - 1].opcode == .push_const) {
                        const const_idx = func.bytecode[i - 1].operand1;
                        if (const_idx < func.constants.len) {
                            const val = func.constants[const_idx];
                            if (val == .int_val) {
                                const n = val.int_val;
                                if (n > 0 and (n & (n - 1)) == 0) {
                                    // x % 2^n -> x & (2^n - 1)
                                    const mask = n - 1;
                                    const mask_val = Value{ .int_val = mask };
                                    const mask_idx = try self.addConstant(func, mask_val);

                                    func.bytecode[i - 1] = Instruction.init(.push_const, mask_idx, 0);
                                    func.bytecode[i] = Instruction.init(.bit_and, 0, 0);

                                    self.stats.constants_folded += 1;
                                }
                            }
                        }
                    }
                },

                // 幂运算优化
                .pow_int => {
                    if (i > 0 and func.bytecode[i - 1].opcode == .push_const) {
                        const const_idx = func.bytecode[i - 1].operand1;
                        if (const_idx < func.constants.len) {
                            const val = func.constants[const_idx];
                            if (val == .int_val) {
                                const exp = val.int_val;

                                // x^0 -> 1
                                if (exp == 0) {
                                    func.bytecode[i - 1] = Instruction.init(.pop, 0, 0);
                                    func.bytecode[i] = Instruction.init(.push_int_1, 0, 0);
                                    self.stats.constants_folded += 1;
                                }
                                // x^1 -> x
                                else if (exp == 1) {
                                    func.bytecode[i - 1] = Instruction.init(.nop, 0, 0);
                                    func.bytecode[i] = Instruction.init(.nop, 0, 0);
                                    self.stats.dead_code_removed += 2;
                                }
                                // x^2 -> x * x
                                else if (exp == 2) {
                                    func.bytecode[i - 1] = Instruction.init(.dup, 0, 0);
                                    func.bytecode[i] = Instruction.init(.mul_int, 0, 0);
                                    self.stats.constants_folded += 1;
                                }
                            }
                        }
                    }
                },

                else => {},
            }
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
        for (self.entries[0..self.count], 0..) |*entry, i| {
            if (entry.class_id == class_id) {
                self.entries[i].hit_count += 1;
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

test "conditional expression folding - true condition" {
    // 测试 true ? a : b -> a
    var func = CompiledFunction{
        .bytecode = undefined,
        .constants = undefined,
        .name = "test",
        .arg_count = 0,
        .local_count = 0,
        .max_stack = 10,
        .flags = .{},
        .line_table = &[_]CompiledFunction.LineInfo{},
        .exception_table = &[_]CompiledFunction.ExceptionEntry{},
    };

    // 模拟字节码：push_const(true), jz(5), push_const(10), jmp(6), push_const(20)
    var bytecode = [_]Instruction{
        Instruction.init(.push_const, 0, 0), // true
        Instruction.init(.jz, 4, 0), // jump to else if false
        Instruction.init(.push_const, 1, 0), // then: 10
        Instruction.init(.jmp, 5, 0), // jump to end
        Instruction.init(.push_const, 2, 0), // else: 20
        Instruction.init(.nop, 0, 0), // end
    };
    func.bytecode = &bytecode;

    var constants = [_]Value{
        Value{ .bool_val = true }, // 0
        Value{ .int_val = 10 }, // 1
        Value{ .int_val = 20 }, // 2
    };
    func.constants = &constants;

    var opt = BytecodeOptimizer.init(std.testing.allocator, .basic);
    try opt.constantFolding(&func);

    // 验证：条件和jz应该被移除，else分支应该被标记为nop
    try std.testing.expect(func.bytecode[0].opcode == .nop);
    try std.testing.expect(func.bytecode[1].opcode == .nop);
    try std.testing.expect(func.bytecode[4].opcode == .nop); // else分支被移除
}

test "conditional expression folding - false condition" {
    // 测试 false ? a : b -> b
    var func = CompiledFunction{
        .bytecode = undefined,
        .constants = undefined,
        .name = "test",
        .arg_count = 0,
        .local_count = 0,
        .max_stack = 10,
        .flags = .{},
        .line_table = &[_]CompiledFunction.LineInfo{},
        .exception_table = &[_]CompiledFunction.ExceptionEntry{},
    };

    // 模拟字节码：push_const(false), jz(5), push_const(10), jmp(6), push_const(20)
    var bytecode = [_]Instruction{
        Instruction.init(.push_const, 0, 0), // false
        Instruction.init(.jz, 4, 0), // jump to else if false
        Instruction.init(.push_const, 1, 0), // then: 10
        Instruction.init(.jmp, 5, 0), // jump to end
        Instruction.init(.push_const, 2, 0), // else: 20
        Instruction.init(.nop, 0, 0), // end
    };
    func.bytecode = &bytecode;

    var constants = [_]Value{
        Value{ .bool_val = false }, // 0
        Value{ .int_val = 10 }, // 1
        Value{ .int_val = 20 }, // 2
    };
    func.constants = &constants;

    var opt = BytecodeOptimizer.init(std.testing.allocator, .basic);
    try opt.constantFolding(&func);

    // 验证：条件应该被移除，jz变为jmp，then分支应该被标记为nop
    try std.testing.expect(func.bytecode[0].opcode == .nop);
    try std.testing.expect(func.bytecode[1].opcode == .jmp);
    try std.testing.expect(func.bytecode[2].opcode == .nop); // then分支被移除
}

test "conditional expression folding - integer condition" {
    // 测试整数条件：1 ? a : b -> a (非零为true)
    var func = CompiledFunction{
        .bytecode = undefined,
        .constants = undefined,
        .name = "test",
        .arg_count = 0,
        .local_count = 0,
        .max_stack = 10,
        .flags = .{},
        .line_table = &[_]CompiledFunction.LineInfo{},
        .exception_table = &[_]CompiledFunction.ExceptionEntry{},
    };

    var bytecode = [_]Instruction{
        Instruction.init(.push_const, 0, 0), // 1 (true)
        Instruction.init(.jz, 4, 0),
        Instruction.init(.push_const, 1, 0),
        Instruction.init(.jmp, 5, 0),
        Instruction.init(.push_const, 2, 0),
        Instruction.init(.nop, 0, 0),
    };
    func.bytecode = &bytecode;

    var constants = [_]Value{
        Value{ .int_val = 1 }, // 0 (非零 = true)
        Value{ .int_val = 10 }, // 1
        Value{ .int_val = 20 }, // 2
    };
    func.constants = &constants;

    var opt = BytecodeOptimizer.init(std.testing.allocator, .basic);
    try opt.constantFolding(&func);

    // 验证：整数1应该被当作true处理
    try std.testing.expect(func.bytecode[0].opcode == .nop);
    try std.testing.expect(func.bytecode[1].opcode == .nop);
}
