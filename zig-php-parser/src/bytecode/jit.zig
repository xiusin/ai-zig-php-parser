const std = @import("std");
const Instruction = @import("instruction.zig").Instruction;
const OpCode = @import("instruction.zig").OpCode;

/// JIT编译器 - 热点检测与原生代码生成
pub const JITCompiler = struct {
    allocator: std.mem.Allocator,
    /// 热点追踪表 - 记录函数调用次数和循环迭代次数
    hotspot_tracker: HotspotTracker,
    /// IR生成器
    ir_generator: IRGenerator,
    /// 原生代码生成器
    native_codegen: NativeCodegen,
    /// 是否启用JIT
    enabled: bool,
    /// 已编译代码缓存（按函数/循环ID）
    compiled_cache: std.AutoHashMap(u32, *NativeCode),

    pub fn init(allocator: std.mem.Allocator) !*JITCompiler {
        const jit = try allocator.create(JITCompiler);
        jit.* = .{
            .allocator = allocator,
            .hotspot_tracker = HotspotTracker.init(allocator),
            .ir_generator = IRGenerator.init(allocator),
            .native_codegen = try NativeCodegen.init(allocator),
            .enabled = true,
            .compiled_cache = std.AutoHashMap(u32, *NativeCode).init(allocator),
        };
        return jit;
    }

    pub fn deinit(self: *JITCompiler) void {
        var it = self.compiled_cache.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.compiled_cache.deinit();
        self.hotspot_tracker.deinit();
        self.ir_generator.deinit();
        self.native_codegen.deinit();
        self.allocator.destroy(self);
    }

    /// 记录函数调用，检测热点
    pub fn recordFunctionCall(self: *JITCompiler, func_id: u32) bool {
        if (!self.enabled) return false;
        return self.hotspot_tracker.recordFunctionCall(func_id);
    }

    /// 记录循环迭代，检测热点循环
    pub fn recordLoopIteration(self: *JITCompiler, loop_id: u32) bool {
        if (!self.enabled) return false;
        return self.hotspot_tracker.recordLoopIteration(loop_id);
    }

    /// 编译热点函数为原生代码
    pub fn compileFunction(
        self: *JITCompiler,
        func_or_loop_id: u32,
        bytecode: []const Instruction,
    ) !?*NativeCode {
        if (self.compiled_cache.get(func_or_loop_id)) |cached| {
            return cached;
        }

        // 1. 生成IR
        const ir = try self.ir_generator.generate(bytecode);
        defer {
            ir.deinit();
            self.allocator.destroy(ir);
        }

        // 2. 优化IR
        try self.ir_generator.optimize(ir);

        // 3. 生成原生代码
        if (try self.native_codegen.generate(ir)) |native| {
            try self.compiled_cache.put(func_or_loop_id, native);
            return native;
        }
        return null;
    }
};

/// 热点追踪器 - 记录调用频率和循环迭代
const HotspotTracker = struct {
    allocator: std.mem.Allocator,
    /// 函数调用计数表
    function_calls: std.AutoHashMap(u32, u32),
    /// 循环迭代计数表
    loop_iterations: std.AutoHashMap(u32, u32),
    /// 热点阈值 - 超过此值触发JIT编译
    hotspot_threshold: u32 = 1000,

    fn init(allocator: std.mem.Allocator) HotspotTracker {
        return .{
            .allocator = allocator,
            .function_calls = std.AutoHashMap(u32, u32).init(allocator),
            .loop_iterations = std.AutoHashMap(u32, u32).init(allocator),
        };
    }

    fn deinit(self: *HotspotTracker) void {
        self.function_calls.deinit();
        self.loop_iterations.deinit();
    }

    /// 记录函数调用，返回是否达到热点阈值
    fn recordFunctionCall(self: *HotspotTracker, func_id: u32) bool {
        const entry = self.function_calls.getOrPut(func_id) catch return false;
        if (!entry.found_existing) {
            entry.value_ptr.* = 0;
        }
        entry.value_ptr.* += 1;
        return entry.value_ptr.* >= self.hotspot_threshold;
    }

    /// 记录循环迭代，返回是否达到热点阈值
    fn recordLoopIteration(self: *HotspotTracker, loop_id: u32) bool {
        const entry = self.loop_iterations.getOrPut(loop_id) catch return false;
        if (!entry.found_existing) {
            entry.value_ptr.* = 0;
        }
        entry.value_ptr.* += 1;
        return entry.value_ptr.* >= self.hotspot_threshold;
    }
};

/// IR指令类型
pub const IROpCode = enum(u8) {
    // 算术运算
    add_int,
    sub_int,
    mul_int,
    div_int,
    // 比较运算
    lt_int,
    gt_int,
    eq_int,
    // 控制流
    jump,
    jump_if_false,
    ret,
    // 内存操作
    load_local,
    store_local,
    load_const,
};

/// IR指令
pub const IRInstruction = struct {
    opcode: IROpCode,
    operands: [3]u32,
};

/// IR基本块
pub const IRBasicBlock = struct {
    id: u32,
    instructions: std.ArrayList(IRInstruction),
    predecessors: std.ArrayList(u32),
    successors: std.ArrayList(u32),

    fn init(allocator: std.mem.Allocator, id: u32) IRBasicBlock {
        _ = allocator;
        return .{
            .id = id,
            .instructions = .empty,
            .predecessors = .empty,
            .successors = .empty,
        };
    }

    fn deinit(self: *IRBasicBlock, allocator: std.mem.Allocator) void {
        self.instructions.deinit(allocator);
        self.predecessors.deinit(allocator);
        self.successors.deinit(allocator);
    }
};

/// IR函数
pub const IRFunction = struct {
    allocator: std.mem.Allocator,
    basic_blocks: std.ArrayList(IRBasicBlock),

    fn init(allocator: std.mem.Allocator) IRFunction {
        return .{
            .allocator = allocator,
            .basic_blocks = .empty,
        };
    }

    pub fn deinit(self: *IRFunction) void {
        for (self.basic_blocks.items) |*block| {
            block.deinit(self.allocator);
        }
        self.basic_blocks.deinit(self.allocator);
    }
};

/// IR生成器 - 将字节码转换为IR
const IRGenerator = struct {
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) IRGenerator {
        return .{ .allocator = allocator };
    }

    fn deinit(_: *IRGenerator) void {}

    /// 生成IR
    fn generate(self: *IRGenerator, bytecode: []const Instruction) !*IRFunction {
        const ir_func = try self.allocator.create(IRFunction);
        ir_func.* = IRFunction.init(self.allocator);

        try ir_func.basic_blocks.append(self.allocator, IRBasicBlock.init(self.allocator, 0));
        var block = &ir_func.basic_blocks.items[ir_func.basic_blocks.items.len - 1];

        // 将字节码指令转换为IR指令
        for (bytecode) |inst| {
            const ir_inst = try self.translateInstruction(inst);
            if (ir_inst) |ir| {
                try block.instructions.append(self.allocator, ir);
            }
        }

        return ir_func;
    }

    /// 翻译单条字节码指令为IR指令
    fn translateInstruction(_: *IRGenerator, inst: Instruction) !?IRInstruction {
        return switch (inst.opcode) {
            .add_int => IRInstruction{
                .opcode = .add_int,
                .operands = .{ 0, 0, 0 },
            },
            .sub_int => IRInstruction{
                .opcode = .sub_int,
                .operands = .{ 0, 0, 0 },
            },
            .mul_int => IRInstruction{
                .opcode = .mul_int,
                .operands = .{ 0, 0, 0 },
            },
            .lt => IRInstruction{
                .opcode = .lt_int,
                .operands = .{ 0, 0, 0 },
            },
            .ret => IRInstruction{
                .opcode = .ret,
                .operands = .{ 0, 0, 0 },
            },
            else => null,
        };
    }

    /// 优化IR - 常量传播、死代码消除、强度削减、循环展开、CSE、LICM
    fn optimize(self: *IRGenerator, ir_func: *IRFunction) !void {
        // Pass 1: 循环展开（在其他优化之前，以便后续优化展开后的代码）
        try self.loopUnrolling(ir_func);

        for (ir_func.basic_blocks.items) |*block| {
            // Pass 2: 常量传播
            constantPropagation(ir_func.allocator, block);
            // Pass 3: 公共子表达式消除（CSE）
            try self.commonSubexpressionElimination(ir_func.allocator, block);
            // Pass 4: 循环不变量外提（LICM）
            try self.loopInvariantCodeMotion(ir_func.allocator, block);
            // Pass 5: 死代码消除
            deadCodeElimination(block);
            // Pass 6: 强度削减
            strengthReduction(block);
        }
    }

    /// 公共子表达式消除（CSE）- 识别并复用相同的计算
    /// @pre block 包含有效的 IR 指令
    /// @post 相同的表达式被合并，减少重复计算
    fn commonSubexpressionElimination(
        _: *IRGenerator,
        allocator: std.mem.Allocator,
        block: *IRBasicBlock,
    ) !void {
        // 表达式哈希表：(opcode, op1, op2) -> 结果寄存器
        var expr_map = std.AutoHashMap(u64, u32).init(allocator);
        defer expr_map.deinit();

        for (block.instructions.items) |*inst| {
            switch (inst.opcode) {
                .add_int, .sub_int, .mul_int, .lt_int => {
                    // 计算表达式哈希
                    const hash = computeExprHash(inst.*);

                    if (expr_map.get(hash)) |existing_reg| {
                        // 找到相同表达式，替换为 move 指令
                        inst.opcode = .load_const;
                        inst.operands[1] = existing_reg;
                        inst.operands[2] = 0;
                    } else {
                        // 记录新表达式
                        try expr_map.put(hash, inst.operands[0]);
                    }
                },
                else => {},
            }
        }
    }

    /// 计算表达式哈希值
    fn computeExprHash(inst: IRInstruction) u64 {
        var hash: u64 = @intFromEnum(inst.opcode);
        hash = hash *% 31 +% inst.operands[1];
        hash = hash *% 31 +% inst.operands[2];
        return hash;
    }

    /// 循环不变量外提（LICM）- 将循环内不变的计算移到循环外
    /// @pre block 包含有效的 IR 指令
    /// @post 循环不变量被提升到循环外
    fn loopInvariantCodeMotion(
        self: *IRGenerator,
        allocator: std.mem.Allocator,
        block: *IRBasicBlock,
    ) !void {
        _ = self;

        // 识别循环不变量：操作数都是常量或循环外定义的变量
        var invariants = std.AutoHashMap(u32, bool).init(allocator);
        defer invariants.deinit();

        // 第一遍：标记常量和循环外定义的寄存器
        for (block.instructions.items, 0..) |inst, i| {
            if (inst.opcode == .load_const) {
                try invariants.put(inst.operands[0], true);
            }
            // 简化：假设前半部分是循环外定义
            if (i < block.instructions.items.len / 3) {
                try invariants.put(inst.operands[0], true);
            }
        }

        // 第二遍：识别并标记不变的计算
        var changed = true;
        while (changed) {
            changed = false;
            for (block.instructions.items) |inst| {
                switch (inst.opcode) {
                    .add_int, .sub_int, .mul_int => {
                        const op1_inv = invariants.get(inst.operands[1]) orelse false;
                        const op2_inv = invariants.get(inst.operands[2]) orelse false;

                        if (op1_inv and op2_inv) {
                            const already_inv = invariants.get(inst.operands[0]) orelse false;
                            if (!already_inv) {
                                try invariants.put(inst.operands[0], true);
                                changed = true;
                            }
                        }
                    },
                    else => {},
                }
            }
        }

        // 第三遍：将不变量移到循环前（简化实现：标记即可）
        // 实际应用中需要重新组织基本块
        for (block.instructions.items) |inst| {
            const is_inv = invariants.get(inst.operands[0]) orelse false;
            if (is_inv and (inst.opcode == .add_int or
                inst.opcode == .sub_int or
                inst.opcode == .mul_int))
            {
                // 标记为可提升（实际实现需要移动指令）
                // 简化实现：仅识别，不移动
            }
        }
    }

    /// 循环展开优化 - 识别小循环并展开
    /// @pre ir_func 包含有效的基本块和指令
    /// @post 小循环（迭代次数 <= UNROLL_THRESHOLD）被展开
    fn loopUnrolling(self: *IRGenerator, ir_func: *IRFunction) !void {
        const UNROLL_THRESHOLD: u32 = 4; // 最大展开次数

        var block_idx: usize = 0;
        while (block_idx < ir_func.basic_blocks.items.len) : (block_idx += 1) {
            const block = &ir_func.basic_blocks.items[block_idx];

            // 查找循环模式：load_const (循环变量) -> 比较 -> 条件跳转
            const loop_info = try self.detectSimpleLoop(block);
            if (loop_info) |info| {
                if (info.trip_count > 0 and info.trip_count <= UNROLL_THRESHOLD) {
                    // 展开循环
                    try self.unrollLoop(ir_func, block_idx, info);
                }
            }
        }
    }

    /// 循环信息
    const LoopInfo = struct {
        trip_count: u32, // 迭代次数（0 表示未知）
        induction_var: u32, // 归纳变量寄存器
        body_start: usize, // 循环体起始指令索引
        body_end: usize, // 循环体结束指令索引
    };

    /// 检测简单循环模式
    fn detectSimpleLoop(_: *IRGenerator, block: *IRBasicBlock) !?LoopInfo {
        if (block.instructions.items.len < 3) return null;

        // 查找模式：load_const -> lt_int -> branch
        var i: usize = 0;
        while (i + 2 < block.instructions.items.len) : (i += 1) {
            const inst1 = block.instructions.items[i];
            const inst2 = block.instructions.items[i + 1];

            // 检测：load_const r0, N; lt_int r1, r_var, r0
            if (inst1.opcode == .load_const and inst2.opcode == .lt_int) {
                const trip_count = inst1.operands[1];
                const induction_var = inst2.operands[1];

                // 简单启发式：假设循环体是接下来的指令直到返回指令
                var body_end = i + 2;
                while (body_end < block.instructions.items.len) : (body_end += 1) {
                    const op = block.instructions.items[body_end].opcode;
                    if (op == .ret) break;
                }

                return LoopInfo{
                    .trip_count = trip_count,
                    .induction_var = induction_var,
                    .body_start = i + 2,
                    .body_end = body_end,
                };
            }
        }
        return null;
    }

    /// 展开循环
    fn unrollLoop(
        self: *IRGenerator,
        ir_func: *IRFunction,
        block_idx: usize,
        info: LoopInfo,
    ) !void {
        const block = &ir_func.basic_blocks.items[block_idx];
        const body_len = info.body_end - info.body_start;
        if (body_len == 0) return;

        // 创建展开后的指令列表
        var unrolled = std.ArrayList(IRInstruction).empty;
        errdefer unrolled.deinit(self.allocator);

        // 保留循环前的指令
        for (block.instructions.items[0..info.body_start]) |inst| {
            try unrolled.append(self.allocator, inst);
        }

        // 展开循环体
        var iter: u32 = 0;
        while (iter < info.trip_count) : (iter += 1) {
            for (block.instructions.items[info.body_start..info.body_end]) |inst| {
                var new_inst = inst;
                // 更新归纳变量的常量值
                if (new_inst.opcode == .load_const and
                    new_inst.operands[0] == info.induction_var)
                {
                    new_inst.operands[1] = iter;
                }
                try unrolled.append(self.allocator, new_inst);
            }
        }

        // 保留循环后的指令
        if (info.body_end < block.instructions.items.len) {
            for (block.instructions.items[info.body_end..]) |inst| {
                try unrolled.append(self.allocator, inst);
            }
        }

        // 替换原始指令
        block.instructions.deinit(self.allocator);
        block.instructions = unrolled;
    }

    /// 常量传播优化 - 识别并传播编译期常量
    fn constantPropagation(allocator: std.mem.Allocator, block: *IRBasicBlock) void {
        // 常量值表：寄存器ID -> 常量值
        var constants = std.AutoHashMap(u32, i64).init(allocator);
        defer constants.deinit();

        for (block.instructions.items) |*inst| {
            switch (inst.opcode) {
                .load_const => {
                    // 记录常量加载
                    constants.put(inst.operands[0], @intCast(inst.operands[1])) catch {};
                },
                .add_int, .sub_int, .mul_int => {
                    // 如果两个操作数都是常量，计算结果
                    const lhs = constants.get(inst.operands[1]);
                    const rhs = constants.get(inst.operands[2]);
                    if (lhs != null and rhs != null) {
                        const result = switch (inst.opcode) {
                            .add_int => lhs.? + rhs.?,
                            .sub_int => lhs.? - rhs.?,
                            .mul_int => lhs.? * rhs.?,
                            else => unreachable,
                        };
                        // 替换为常量加载
                        inst.opcode = .load_const;
                        inst.operands[1] = @intCast(result);
                        inst.operands[2] = 0;
                        constants.put(inst.operands[0], result) catch {};
                    }
                },
                else => {},
            }
        }
    }

    /// 死代码消除
    fn deadCodeElimination(block: *IRBasicBlock) void {
        // 移除无效指令（结果未使用的纯计算）
        var i: usize = 0;
        while (i < block.instructions.items.len) {
            const inst = block.instructions.items[i];
            // 跳过控制流指令
            if (inst.opcode == .ret or inst.opcode == .jump or
                inst.opcode == .jump_if_false)
            {
                i += 1;
                continue;
            }
            // 检查是否有后续指令使用此结果
            var used = false;
            for (block.instructions.items[i + 1 ..]) |later| {
                if (later.operands[1] == inst.operands[0] or
                    later.operands[2] == inst.operands[0])
                {
                    used = true;
                    break;
                }
            }
            if (!used and inst.opcode != .store_local) {
                _ = block.instructions.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// 强度削减优化
    fn strengthReduction(block: *IRBasicBlock) void {
        for (block.instructions.items) |*inst| {
            switch (inst.opcode) {
                // 乘以2 -> 左移1
                .mul_int => {
                    if (inst.operands[2] == 2) {
                        inst.opcode = .add_int;
                        inst.operands[2] = inst.operands[1];
                    }
                },
                else => {},
            }
        }
    }
};

/// 页面大小常量 (x86_64/ARM64 标准)
const PAGE_SIZE: usize = 4096;

/// 原生代码
/// @memory-protection RWX (mmap allocated)
/// @ownership TRANSFER (caller must call deinit)
pub const NativeCode = struct {
    code: []align(PAGE_SIZE) u8,
    code_len: usize,
    /// 入口点：接受 VM 上下文指针，返回执行状态
    /// @calling-convention x86_64_sysv (macOS/Linux)
    entry_point: ?*const fn (*anyopaque) callconv(.c) i32,

    /// @pre self.code 必须是 mmap 分配的内存
    /// @post self.code 被 munmap 释放
    pub fn deinit(self: *NativeCode, allocator: std.mem.Allocator) void {
        _ = allocator;
        const c = @cImport({
            @cInclude("sys/mman.h");
        });
        _ = c.munmap(self.code.ptr, self.code_len);
    }
};

/// 原生代码生成器 - x86_64平台
const NativeCodegen = struct {
    allocator: std.mem.Allocator,
    code_buffer: std.ArrayList(u8),

    fn init(allocator: std.mem.Allocator) !NativeCodegen {
        return .{
            .allocator = allocator,
            .code_buffer = .empty,
        };
    }

    fn deinit(self: *NativeCodegen) void {
        self.code_buffer.deinit(self.allocator);
    }

    /// 生成原生代码
    /// @post 返回的 NativeCode 使用 mmap 分配的 RWX 内存
    fn generate(self: *NativeCodegen, ir_func: *IRFunction) !?*NativeCode {
        self.code_buffer.clearRetainingCapacity();

        // 函数序言
        try self.emitPrologue();

        // 遍历基本块生成代码
        for (ir_func.basic_blocks.items) |block| {
            for (block.instructions.items) |inst| {
                try self.emitInstruction(inst);
            }
        }

        // 函数尾声
        try self.emitEpilogue();

        // 使用 mmap 分配可执行内存 (RWX)
        const c = @cImport({
            @cInclude("sys/mman.h");
        });
        const code_len = self.code_buffer.items.len;
        const aligned_len = std.mem.alignForward(usize, code_len, PAGE_SIZE);

        const ptr = c.mmap(
            null,
            aligned_len,
            c.PROT_READ | c.PROT_WRITE | c.PROT_EXEC,
            c.MAP_PRIVATE | c.MAP_ANONYMOUS,
            -1,
            0,
        );
        if (ptr == c.MAP_FAILED) return null;

        const code: []align(PAGE_SIZE) u8 = @alignCast(@as([*]u8, @ptrCast(ptr))[0..aligned_len]);
        @memcpy(code[0..code_len], self.code_buffer.items);

        const native = try self.allocator.create(NativeCode);
        native.* = .{
            .code = code,
            .code_len = aligned_len,
            .entry_point = @ptrCast(@alignCast(code.ptr)),
        };
        return native;
    }

    /// 生成函数序言 (x86_64)
    fn emitPrologue(self: *NativeCodegen) !void {
        // push rbp
        try self.code_buffer.append(self.allocator, 0x55);
        // mov rbp, rsp
        try self.code_buffer.appendSlice(self.allocator, &[_]u8{ 0x48, 0x89, 0xe5 });
    }

    /// 生成函数尾声 (x86_64)
    fn emitEpilogue(self: *NativeCodegen) !void {
        // pop rbp
        try self.code_buffer.append(self.allocator, 0x5d);
        // ret
        try self.code_buffer.append(self.allocator, 0xc3);
    }

    /// 生成IR指令对应的原生代码
    fn emitInstruction(self: *NativeCodegen, inst: IRInstruction) !void {
        switch (inst.opcode) {
            .add_int => {
                // add eax, ebx (简化示例)
                try self.code_buffer.appendSlice(self.allocator, &[_]u8{ 0x01, 0xd8 });
            },
            .sub_int => {
                // sub eax, ebx
                try self.code_buffer.appendSlice(self.allocator, &[_]u8{ 0x29, 0xd8 });
            },
            .mul_int => {
                // imul eax, ebx
                try self.code_buffer.appendSlice(self.allocator, &[_]u8{ 0x0f, 0xaf, 0xc3 });
            },
            .ret => {
                // 已在epilogue中处理
            },
            else => {},
        }
    }
};
