//! 极速字节码虚拟机
//! 目标：达到原生 PHP 执行速度
//!
//! 核心技术：
//! 1. 直接线程化 - 计算跳转表
//! 2. 超级指令 - 合并常见序列
//! 3. 寄存器窗口 - 减少栈操作
//! 4. 内联缓存 - 加速属性/方法访问
//! 5. 类型反馈 - 运行时特化

const std = @import("std");
const fast_value = @import("fast_value.zig");
const fast_pool = @import("fast_pool.zig");
const fast_string = @import("fast_string.zig");
const func_mod = @import("func.zig");
const jit = @import("../jit/root.zig");
const opcode_mod = @import("opcode.zig");

const FastValue = fast_value.FastValue;
const FastOps = fast_value.FastOps;
const ValueStack = fast_value.ValueStack;
pub const CompiledFunc = func_mod.CompiledFunc;
pub const OpCode = opcode_mod.OpCode;

// ============================================================================
// 字节码指令
// ============================================================================

// pub const OpCode = enum(u8) {
//     // 栈操作 (0x00-0x0F)
//     nop = 0x00,
//     push_nil = 0x01,
//     push_true = 0x02,
//     push_false = 0x03,
//     push_int = 0x04, // 后跟 i32
//     push_float = 0x05, // 后跟 f64
//     push_const = 0x06, // 后跟常量索引
//     push_local = 0x07, // 后跟局部变量索引
//     store_local = 0x08,
//     pop = 0x09,
//     dup = 0x0A,
//     swap = 0x0B,
// 
//     // 整数算术 (0x10-0x1F) - 类型特化
//     add_i = 0x10,
//     sub_i = 0x11,
//     mul_i = 0x12,
//     div_i = 0x13,
//     mod_i = 0x14,
//     neg_i = 0x15,
//     inc_i = 0x16,
//     dec_i = 0x17,
// 
//     // 浮点算术 (0x20-0x2F)
//     add_f = 0x20,
//     sub_f = 0x21,
//     mul_f = 0x22,
//     div_f = 0x23,
//     neg_f = 0x25,
// 
//     // 通用算术 (0x30-0x3F) - 带类型检查
//     add = 0x30,
//     sub = 0x31,
//     mul = 0x32,
//     div = 0x33,
//     mod = 0x34,
//     neg = 0x35,
// 
//     // 比较 (0x40-0x4F)
//     eq = 0x40,
//     ne = 0x41,
//     lt = 0x42,
//     le = 0x43,
//     gt = 0x44,
//     ge = 0x45,
//     eq_i = 0x46,
//     lt_i = 0x47,
//     gt_i = 0x48,
// 
//     // 位操作 (0x50-0x5F)
//     band = 0x50,
//     bor = 0x51,
//     bxor = 0x52,
//     bnot = 0x53,
//     shl = 0x54,
//     shr = 0x55,
// 
//     // 逻辑 (0x60-0x6F)
//     land = 0x60,
//     lor = 0x61,
//     lnot = 0x62,
// 
//     // 控制流 (0x70-0x7F)
//     jmp = 0x70, // 无条件跳转
//     jz = 0x71, // 为假跳转
//     jnz = 0x72, // 为真跳转
//     call = 0x73, // 函数调用
//     ret = 0x74, // 返回
//     ret_nil = 0x75, // 返回 nil
//     halt = 0x7F,
// 
//     // 超级指令 (0x80-0x8F) - 合并常见序列
//     load_add_i = 0x80, // push_local + add_i
//     load_sub_i = 0x81,
//     load_inc_store = 0x82, // push_local + inc_i + store_local
//     load_dec_store = 0x83,
//     push_0 = 0x84, // push_int 0
//     push_1 = 0x85, // push_int 1
//     push_m1 = 0x86, // push_int -1
//     dup_add_i = 0x87, // dup + add_i
// 
//     // 数组/对象 (0x90-0x9F)
//     new_array = 0x90,
//     array_get = 0x91,
//     array_set = 0x92,
//     array_push = 0x93,
//     obj_get = 0x94,
//     obj_set = 0x95,
//     obj_call = 0x96,
// 
//     // 字符串 (0xA0-0xAF)
//     concat = 0xA0,
//     strlen = 0xA1,
// 
//     // 内置函数 (0xB0-0xBF)
//     echo = 0xB0,
//     print = 0xB1,
// 
//     // 调试 (0xF0-0xFF)
//     debug = 0xF0,
//     line = 0xF1, // 行号信息
// };

// ============================================================================
// 调用帧
// ============================================================================

pub const CallFrame = struct {
    func: *const CompiledFunc,
    ip: u32,
    bp: u32, // 基指针（局部变量起始）
    ret_addr: u32,
    hot_counter: u32 = 0,
};

// ============================================================================
// 内联缓存
// ============================================================================

pub const InlineCache = struct {
    const SIZE = 256;

    const Entry = struct {
        shape_id: u32,
        offset: u16,
        hits: u16,
    };

    entries: [SIZE]Entry,

    pub fn init() InlineCache {
        return .{ .entries = [_]Entry{.{ .shape_id = 0, .offset = 0, .hits = 0 }} ** SIZE };
    }

    pub fn lookup(self: *InlineCache, cache_id: u8, shape_id: u32) ?u16 {
        const e = &self.entries[cache_id];
        if (e.shape_id == shape_id and e.hits > 0) {
            e.hits +|= 1;
            return e.offset;
        }
        return null;
    }

    pub fn update(self: *InlineCache, cache_id: u8, shape_id: u32, offset: u16) void {
        self.entries[cache_id] = .{ .shape_id = shape_id, .offset = offset, .hits = 1 };
    }
};

// ============================================================================
// 类型反馈
// ============================================================================

pub const TypeFeedback = struct {
    const SIZE = 64;

    const Profile = packed struct {
        int_count: u8,
        float_count: u8,
        string_count: u8,
        other_count: u8,
    };

    profiles: [SIZE]Profile,

    pub fn init() TypeFeedback {
        return .{ .profiles = [_]Profile{.{ .int_count = 0, .float_count = 0, .string_count = 0, .other_count = 0 }} ** SIZE };
    }

    pub fn record(self: *TypeFeedback, site: u8, v: FastValue) void {
        const p = &self.profiles[site & (SIZE - 1)];
        if (v.isInt()) {
            p.int_count +|= 1;
        } else if (v.isFloat()) {
            p.float_count +|= 1;
        } else if (v.isString()) {
            p.string_count +|= 1;
        } else {
            p.other_count +|= 1;
        }
    }

    pub fn isMonomorphicInt(self: *const TypeFeedback, site: u8) bool {
        const p = self.profiles[site & (SIZE - 1)];
        return p.int_count > 10 and p.float_count == 0 and p.string_count == 0 and p.other_count == 0;
    }
};

// ============================================================================
// 快速虚拟机
// ============================================================================

pub const FastVM = struct {
    const MAX_FRAMES = 256;

    allocator: std.mem.Allocator,
    stack: ValueStack,
    frames: [MAX_FRAMES]CallFrame,
    frame_count: u32,
    globals: std.StringHashMapUnmanaged(FastValue),
    ic: InlineCache,
    tf: TypeFeedback,
    output: std.ArrayListUnmanaged(u8),
    code_cache: jit.CodeCache,
    jit_compiler: jit.Compiler,

    pub fn init(allocator: std.mem.Allocator) !FastVM {
        var code_cache = try jit.CodeCache.init(allocator, 1024 * 1024);
        errdefer code_cache.deinit();

        return .{
            .allocator = allocator,
            .stack = try ValueStack.init(allocator),
            .frames = undefined,
            .frame_count = 0,
            .globals = .{},
            .ic = InlineCache.init(),
            .tf = TypeFeedback.init(),
            .output = .{},
            .code_cache = code_cache,
            .jit_compiler = jit.Compiler.init(allocator),
        };
    }

    fn jitCompile(self: *FastVM, func: *const CompiledFunc, osr_ip: ?usize) void {
       const mutable_func = @constCast(func);
       if (mutable_func.jit_code != null) return;
       
       std.debug.print("Attempting JIT compile for {s} osr_ip={?}\n", .{func.name, osr_ip});
       
       if (self.jit_compiler.compile(&self.code_cache, func, &self.tf, osr_ip)) |res| {
            if (res) |r| {
                mutable_func.jit_code = r.code;
                mutable_func.osr_entry_offset = r.osr_entry_offset;
                std.debug.print("JIT compiled {s} osr_off={d}\n", .{func.name, r.osr_entry_offset});
            }
       } else |err| {
            std.debug.print("JIT compilation failed: {s}\n", .{@errorName(err)});
       }
    }

    pub fn deinit(self: *FastVM) void {
        self.stack.deinit(self.allocator);
        self.globals.deinit(self.allocator);
        self.output.deinit(self.allocator);
    }

    /// 执行函数
    pub fn execute(self: *FastVM, func: *const CompiledFunc) !FastValue {
        // std.debug.print("FastVM executing {s} (len={d})\n", .{func.name, func.code.len});
        
        // Force JIT for test
        // if (std.mem.eql(u8, func.name, "main") and func.jit_code == null) {
        //      self.jitCompile(func, null);
        // }

        // JIT Fast Path
        if (func.jit_code) |jit_ptr| {
             // Check signature for "sum" or "main"
             if (std.mem.eql(u8, func.name, "sum") or std.mem.eql(u8, func.name, "main")) {
                 // const stack_ptr = self.stack.data.ptr;
                 // const bp = self.stack.top; // Wait, bp should be 0 for main? No, execute sets bp to stack.top
                 // For main, frame is set up below.
                 // If we JIT, we need to setup frame or pass stack pointer correctly.
                 // For now, let's skip JIT Fast Path for main on entry, rely on OSR.
                 // return FastValue.initInt(42);
                 _ = jit_ptr;
             }
        }

        // 设置初始帧
        self.frames[0] = .{
            .func = func,
            .ip = 0,
            .bp = self.stack.top,
            .ret_addr = 0,
        };
        self.frame_count = 1;

        // 分配局部变量空间
        var i: u16 = 0;
        while (i < func.locals_count) : (i += 1) {
            self.stack.push(FastValue.nil);
        }

        return self.run();
    }

    /// 主执行循环 - 使用计算跳转表和指令预取
    fn run(self: *FastVM) !FastValue {
        var frame = &self.frames[self.frame_count - 1];
        const code = frame.func.code;

        while (true) {
            // 指令预取优化：预取下一条指令到 L1 缓存
            // 这可以隐藏内存延迟，提高指令吞吐量
            if (frame.ip + 16 < code.len) {
                @prefetch(code.ptr + frame.ip + 16, .{
                    .rw = .read,
                    .locality = 3, // 高局部性，保留在所有缓存级别
                    .cache = .data,
                });
            }

            if (frame.ip >= code.len) {
                return error.IPOutOfBounds;
            }

            const op_byte = code[frame.ip];
            const op: OpCode = @enumFromInt(op_byte);
            frame.ip += 1;
            // std.debug.print("Op: {s} stack: {d}\n", .{@tagName(op), self.stack.top});
            std.debug.print("Op: {s} stack: {d}\n", .{@tagName(op), self.stack.top});

            switch (op) {
                // --- 栈操作 ---
                .nop => {},
                .push_nil => self.stack.push(FastValue.nil),
                .push_true => self.stack.push(FastValue.true),
                .push_false => self.stack.push(FastValue.false),

                .push_int => {
                    const v = std.mem.readInt(i32, code[frame.ip..][0..4], .little);
                    frame.ip += 4;
                    self.stack.push(fast_value.small_int_cache.get(v));
                },

                .push_float => {
                    const bits = std.mem.readInt(u64, code[frame.ip..][0..8], .little);
                    frame.ip += 8;
                    self.stack.push(FastValue{ .bits = bits });
                },

                .push_const => {
                    const idx = std.mem.readInt(u16, code[frame.ip..][0..2], .little);
                    frame.ip += 2;
                    // 预取常量池数据
                    if (idx + 1 < frame.func.constants.len) {
                        @prefetch(&frame.func.constants[idx + 1], .{
                            .rw = .read,
                            .locality = 2,
                            .cache = .data,
                        });
                    }
                    self.stack.push(frame.func.constants[idx]);
                },

                .push_local => {
                    const idx = code[frame.ip];
                    frame.ip += 1;
                    self.stack.push(self.stack.data[frame.bp + idx]);
                },

                .store_local => {
                    const idx = code[frame.ip];
                    frame.ip += 1;
                    self.stack.data[frame.bp + idx] = self.stack.pop();
                },

                .pop => _ = self.stack.pop(),
                .dup => self.stack.dup(),
                .swap => self.stack.swap(),

                // --- 整数算术（类型特化，无检查） ---
                .add_i => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.addInt(a, b));
                },
                .sub_i => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.subInt(a, b));
                },
                .mul_i => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.mulInt(a, b));
                },
                .div_i => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.divInt(a, b));
                },
                .mod_i => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.modInt(a, b));
                },
                .neg_i => {
                    const a = self.stack.pop();
                    self.stack.push(FastOps.negInt(a));
                },
                .inc_i => {
                    const a = self.stack.pop();
                    self.stack.push(FastValue.initInt(a.asInt() + 1));
                },
                .dec_i => {
                    const a = self.stack.pop();
                    self.stack.push(FastValue.initInt(a.asInt() - 1));
                },

                // --- 浮点算术 ---
                .add_f => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.addFloat(a, b));
                },
                .sub_f => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.subFloat(a, b));
                },
                .mul_f => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.mulFloat(a, b));
                },
                .div_f => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.divFloat(a, b));
                },
                .neg_f => {
                    const a = self.stack.pop();
                    self.stack.push(FastOps.negFloat(a));
                },

                // --- 通用算术（带类型检查） ---
                .add => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    if (a.isInt() and b.isInt()) {
                        self.tf.record(@intCast(frame.ip - 1), a);
                    } else {
                        self.tf.record(@intCast(frame.ip - 1), FastValue.nil);
                    }
                    self.stack.push(FastOps.add(a, b));
                },
                .sub => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    if (a.isInt() and b.isInt()) {
                        self.tf.record(@intCast(frame.ip - 1), a);
                    } else {
                        self.tf.record(@intCast(frame.ip - 1), FastValue.nil);
                    }
                    self.stack.push(FastOps.sub(a, b));
                },
                .mul => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    if (a.isInt() and b.isInt()) {
                        self.tf.record(@intCast(frame.ip - 1), a);
                    } else {
                        self.tf.record(@intCast(frame.ip - 1), FastValue.nil);
                    }
                    self.stack.push(FastOps.mul(a, b));
                },
                .div => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.div(a, b));
                },
                .mod => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    if (a.isInt() and b.isInt()) {
                        self.stack.push(FastOps.modInt(a, b));
                    } else {
                        const af = a.toFloat();
                        const bf = b.toFloat();
                        self.stack.push(FastValue.initFloat(@mod(af, bf)));
                    }
                },
                .neg => {
                    const a = self.stack.pop();
                    if (a.isInt()) {
                        self.stack.push(FastOps.negInt(a));
                    } else {
                        self.stack.push(FastOps.negFloat(FastValue.initFloat(a.toFloat())));
                    }
                },

                // --- 比较 ---
                .eq => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.eq(a, b));
                },
                .ne => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(if (FastOps.eq(a, b).asBool()) FastValue.false else FastValue.true);
                },
                .lt => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    if (a.isInt() and b.isInt()) {
                        self.tf.record(@intCast(frame.ip - 1), a);
                    } else {
                        self.tf.record(@intCast(frame.ip - 1), FastValue.nil);
                    }
                    self.stack.push(FastOps.lt(a, b));
                },
                .le => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(if (FastOps.gt(a, b).asBool()) FastValue.false else FastValue.true);
                },
                .gt => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.gt(a, b));
                },
                .ge => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(if (FastOps.lt(a, b).asBool()) FastValue.false else FastValue.true);
                },
                .eq_i => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.eqInt(a, b));
                },
                .lt_i => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.ltInt(a, b));
                },
                .gt_i => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.gtInt(a, b));
                },

                // --- 位操作 ---
                .band => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.bitAnd(a, b));
                },
                .bor => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.bitOr(a, b));
                },
                .bxor => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.bitXor(a, b));
                },
                .bnot => {
                    const a = self.stack.pop();
                    self.stack.push(FastOps.bitNot(a));
                },
                .shl => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.shl(a, b));
                },
                .shr => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(FastOps.shr(a, b));
                },

                // --- 逻辑 ---
                .land => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(if (a.toBool() and b.toBool()) FastValue.true else FastValue.false);
                },
                .lor => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(if (a.toBool() or b.toBool()) FastValue.true else FastValue.false);
                },
                .lnot => {
                    const a = self.stack.pop();
                    self.stack.push(if (a.toBool()) FastValue.false else FastValue.true);
                },

                // --- 控制流 ---
                .jmp => {
                    const offset = std.mem.readInt(i16, code[frame.ip..][0..2], .little);
                    frame.ip += 2;
                    frame.ip = @intCast(@as(i32, @intCast(frame.ip)) + offset);
                    
                    std.debug.print("JMP offset: {d} counter: {d}\n", .{offset, frame.hot_counter});
                    if (offset < 0) {
                        // std.debug.print("Backward jump: {d}\n", .{offset});
                        frame.hot_counter +|= 1;
                        if (frame.hot_counter > 100) {
                             self.jitCompile(frame.func, frame.ip);
                             if (frame.func.jit_code) |jit_ptr| {
                                 if (frame.func.osr_entry_offset != 0) {
                                     const stack_ptr = self.stack.data.ptr;
                                     const bp = frame.bp;
                                     // Pass stack.top as 3rd argument (x2)
                                     const stack_top = self.stack.top;
                                     const code_ptr = @intFromPtr(jit_ptr);
                                     const f: *const fn([*]FastValue, usize, usize, usize) callconv(.c) i64 = @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(code_ptr))));
                                     std.debug.print("JIT Call: stack_ptr={*} bp={d} stack_top={d} osr_off={d}\n", .{stack_ptr, bp, stack_top, frame.func.osr_entry_offset});
                                     const ret = f(stack_ptr, bp, stack_top, frame.func.osr_entry_offset);
                                     std.debug.print("OSR execution result: {d}\n", .{ret});
                                     return FastValue.initInt(ret);
                                 }
                             }
                        }
                    }
                },
                .jz => {
                    const offset = std.mem.readInt(i16, code[frame.ip..][0..2], .little);
                    frame.ip += 2;
                    if (!self.stack.pop().toBool()) {
                        frame.ip = @intCast(@as(i32, @intCast(frame.ip)) + offset);
                        if (offset < 0) {
                            // std.debug.print("Backward jump (jz): {d}\n", .{offset});
                            frame.hot_counter +|= 1;
                            if (frame.hot_counter > 100) {
                                 self.jitCompile(frame.func, frame.ip);
                                 if (frame.func.jit_code) |jit_ptr| {
                                     if (frame.func.osr_entry_offset != 0) {
                                         const stack_ptr = self.stack.data.ptr;
                                         const bp = frame.bp;
                                         const stack_top = self.stack.top;
                                         const code_ptr = @intFromPtr(jit_ptr);
                                         const f: *const fn([*]FastValue, usize, usize, usize) callconv(.c) i64 = @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(code_ptr))));
                                         std.debug.print("JIT Call: stack_ptr={*} bp={d} stack_top={d} osr_off={d}\n", .{stack_ptr, bp, stack_top, frame.func.osr_entry_offset});
                                         const ret = f(stack_ptr, bp, stack_top, frame.func.osr_entry_offset);
                                         std.debug.print("OSR execution result: {d}\n", .{ret});
                                         // return FastValue.initInt(ret);
                                         // _ = ret;
                                     }
                                 }
                            }
                        }
                    }
                },
                .jnz => {
                    const offset = std.mem.readInt(i16, code[frame.ip..][0..2], .little);
                    frame.ip += 2;
                    if (self.stack.pop().toBool()) {
                        frame.ip = @intCast(@as(i32, @intCast(frame.ip)) + offset);
                        if (offset < 0) {
                            // std.debug.print("Backward jump (jnz): {d}\n", .{offset});
                            frame.hot_counter +|= 1;
                            if (frame.hot_counter > 100) {
                                 self.jitCompile(frame.func, frame.ip);
                                 if (frame.func.jit_code) |jit_ptr| {
                                     if (frame.func.osr_entry_offset != 0) {
                                         const stack_ptr = self.stack.data.ptr;
                                         const bp = frame.bp;
                                         const stack_top = self.stack.top;
                                         const code_ptr = @intFromPtr(jit_ptr) + frame.func.osr_entry_offset;
                                         const f: *const fn([*]FastValue, usize, usize) callconv(.c) i64 = @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(code_ptr))));
                                         const ret = f(stack_ptr, bp, stack_top);
                                         // return FastValue.initInt(ret);
                                         _ = ret;
                                     }
                                 }
                            }
                        }
                    }
                },

                .ret => {
                    const result = self.stack.pop();
                    if (self.frame_count == 1) return result;

                    // 恢复调用者帧
                    self.stack.top = frame.bp;
                    self.frame_count -= 1;
                    frame = &self.frames[self.frame_count - 1];
                    self.stack.push(result);
                },

                .ret_nil => {
                    if (self.frame_count == 1) return FastValue.nil;

                    self.stack.top = frame.bp;
                    self.frame_count -= 1;
                    frame = &self.frames[self.frame_count - 1];
                    self.stack.push(FastValue.nil);
                },

                .halt => return self.stack.pop(),

                // --- 超级指令 ---
                .push_0 => self.stack.push(fast_value.small_int_cache.get(0)),
                .push_1 => self.stack.push(fast_value.small_int_cache.get(1)),
                .push_m1 => self.stack.push(fast_value.small_int_cache.get(-1)),

                .load_add_i => {
                    const idx = code[frame.ip];
                    frame.ip += 1;
                    const local = self.stack.data[frame.bp + idx];
                    const top = self.stack.pop();
                    self.stack.push(FastOps.addInt(local, top));
                },

                .load_sub_i => {
                    const idx = code[frame.ip];
                    frame.ip += 1;
                    const local = self.stack.data[frame.bp + idx];
                    const top = self.stack.pop();
                    self.stack.push(FastOps.subInt(local, top));
                },

                .load_inc_store => {
                    const idx = code[frame.ip];
                    frame.ip += 1;
                    const v = self.stack.data[frame.bp + idx];
                    self.stack.data[frame.bp + idx] = FastValue.initInt(v.asInt() + 1);
                },

                .load_dec_store => {
                    const idx = code[frame.ip];
                    frame.ip += 1;
                    const v = self.stack.data[frame.bp + idx];
                    self.stack.data[frame.bp + idx] = FastValue.initInt(v.asInt() - 1);
                },

                .dup_add_i => {
                    const top = self.stack.peek(0);
                    const second = self.stack.peek(1);
                    self.stack.push(FastOps.addInt(top, second));
                },

                // --- 输出 ---
                .echo => {
                    const v = self.stack.pop();
                    try self.printValue(v);
                },

                .print => {
                    const v = self.stack.pop();
                    try self.printValue(v);
                    self.stack.push(FastValue.initInt(1));
                },

                else => {
                    // 未实现的指令
                    return error.UnknownOpcode;
                },
            }
        }
    }

    fn printValue(self: *FastVM, v: FastValue) !void {
        if (v.isNil()) {
            // nil 不输出
        } else if (v.isBool()) {
            if (v.asBool()) {
                try self.output.appendSlice(self.allocator, "1");
            }
        } else if (v.isInt()) {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{v.asInt()}) catch return;
            try self.output.appendSlice(self.allocator, s);
        } else if (v.isFloat()) {
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{v.asFloat()}) catch return;
            try self.output.appendSlice(self.allocator, s);
        }
    }

    pub fn getOutput(self: *const FastVM) []const u8 {
        return self.output.items;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "FastVM simple" {
    var vm = try FastVM.init(std.testing.allocator);
    defer vm.deinit();

    // 测试: 10 + 20 = 30
    const code = [_]u8{
        @intFromEnum(OpCode.push_int), 10, 0, 0, 0,
        @intFromEnum(OpCode.push_int), 20, 0, 0, 0,
        @intFromEnum(OpCode.add_i),
        @intFromEnum(OpCode.halt),
    };

    const func = CompiledFunc{
        .name = "test",
        .code = &code,
        .constants = &[_]FastValue{},
        .locals_count = 0,
        .params_count = 0,
        .max_stack = 8,
    };

    const result = try vm.execute(&func);
    try std.testing.expect(result.asInt() == 30);
}

test "FastVM loop" {
    var vm = try FastVM.init(std.testing.allocator);
    defer vm.deinit();

    // 测试: sum = 0; for i = 1 to 10: sum += i
    // 局部变量: 0=sum, 1=i
    const code = [_]u8{
        // sum = 0
        @intFromEnum(OpCode.push_0),
        @intFromEnum(OpCode.store_local),
        0,
        // i = 1
        @intFromEnum(OpCode.push_1),
        @intFromEnum(OpCode.store_local),
        1,
        // loop:
        // sum = sum + i
        @intFromEnum(OpCode.push_local),
        0,
        @intFromEnum(OpCode.push_local),
        1,
        @intFromEnum(OpCode.add_i),
        @intFromEnum(OpCode.store_local),
        0,
        // i++
        @intFromEnum(OpCode.load_inc_store),
        1,
        // if i <= 10 goto loop
        @intFromEnum(OpCode.push_local),
        1,
        @intFromEnum(OpCode.push_int),
        10,
        0,
        0,
        0,
        @intFromEnum(OpCode.le),
        @intFromEnum(OpCode.jnz),
        @as(u8, @bitCast(@as(i8, -18))),
        0xFF,
        // return sum
        @intFromEnum(OpCode.push_local),
        0,
        @intFromEnum(OpCode.halt),
    };

    const func = CompiledFunc{
        .name = "sum",
        .code = &code,
        .constants = &[_]FastValue{},
        .locals_count = 2,
        .params_count = 0,
        .max_stack = 8,
    };

    const result = try vm.execute(&func);
    try std.testing.expect(result.asInt() == 55); // 1+2+...+10 = 55
}
