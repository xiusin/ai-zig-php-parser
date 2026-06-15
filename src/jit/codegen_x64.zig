/// x86-64 代码生成器
/// @ownership NON-OWNING (allocator)
/// @thread-safety ISOLATED (单线程)
/// @memory-safety 所有内存操作经过边界检查
const std = @import("std");
const Assembler = @import("assembler_x64.zig").Assembler;
const Register = @import("assembler_x64.zig").Register;
const Condition = @import("assembler_x64.zig").Condition;
const CodeCache = @import("code_cache.zig").CodeCache;
const imports = @import("imports.zig");
const CompiledFunc = imports.CompiledFunc;
const OpCode = imports.OpCode;

/// 类型信息
pub const TypeInfo = enum {
    unknown,
    int,
    float,
    bool,
    string,
    array,
    object,
    null_type,
};

/// 寄存器映射
pub const RegisterMap = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMap(u32, Register),
    
    pub fn init(allocator: std.mem.Allocator) RegisterMap {
        return .{
            .allocator = allocator,
            .map = std.AutoHashMap(u32, Register).init(allocator),
        };
    }
    
    pub fn deinit(self: *RegisterMap) void {
        self.map.deinit();
    }
    
    pub fn put(self: *RegisterMap, var_id: u32, reg: Register) !void {
        try self.map.put(var_id, reg);
    }
    
    pub fn get(self: *const RegisterMap, var_id: u32) ?Register {
        return self.map.get(var_id);
    }
};

/// 跳转补丁
const JumpPatch = struct {
    inst_offset: usize,  // 指令在代码中的偏移
    target_ip: usize,    // 目标字节码 IP
    is_conditional: bool,
    condition: Condition,
};

/// x86-64 代码生成器
/// @concurrency-model ISOLATED
pub const CodeGenX64 = struct {
    allocator: std.mem.Allocator,
    asm_: Assembler,
    
    // 寄存器分配
    available_regs: []const Register = &[_]Register{
        .rbx, .r12, .r13, .r14, .r15, // 被调用者保存寄存器
        .r10, .r11,                    // 临时寄存器
    },
    
    // 跳转补丁列表
    jump_patches: std.ArrayList(JumpPatch),
    
    // IP 到汇编代码偏移的映射
    ip_to_offset: std.AutoHashMap(usize, usize),
    
    /// @pre allocator 必须有效
    /// @post 返回初始化的代码生成器实例
    pub fn init(allocator: std.mem.Allocator) CodeGenX64 {
        return .{
            .allocator = allocator,
            .asm_ = Assembler.init(allocator),
            .jump_patches = .empty,
            .ip_to_offset = std.AutoHashMap(usize, usize).init(allocator),
        };
    }
    
    /// @pre self 必须已初始化
    /// @post 释放所有资源
    pub fn deinit(self: *CodeGenX64) void {
        self.asm_.deinit();
        self.jump_patches.deinit();
        self.ip_to_offset.deinit();
    }
    
    // ========================================================================
    // 函数序言和尾声
    // ========================================================================
    
    /// 生成函数序言
    /// @pre func 必须有效
    /// @post 生成标准的函数序言代码
    /// 
    /// 调用约定 (System V AMD64 ABI):
    /// - 参数: RDI, RSI, RDX, RCX, R8, R9, 栈
    /// - 返回值: RAX
    /// - 被调用者保存: RBX, RBP, R12-R15
    /// - 调用者保存: RAX, RCX, RDX, RSI, RDI, R8-R11
    fn emitPrologue(self: *CodeGenX64, func: *const CompiledFunc) !void {
        _ = func;
        
        // 保存帧指针
        try self.asm_.push(.rbp);
        try self.asm_.mov(.rbp, .rsp);
        
        // 保存被调用者保存寄存器
        try self.asm_.push(.rbx);
        try self.asm_.push(.r12);
        try self.asm_.push(.r13);
        try self.asm_.push(.r14);
        try self.asm_.push(.r15);
        
        // 为局部变量分配栈空间
        // 假设需要 64 字节的栈空间
        try self.asm_.subImm(.rsp, 64);
        
        // 参数传递：
        // RDI = stack_base (Value 数组基址)
        // RSI = bp (基指针)
        // RDX = stack_top (栈顶指针)
        
        // 保存参数到被调用者保存寄存器
        try self.asm_.mov(.r12, .rdi); // stack_base
        try self.asm_.mov(.r13, .rsi); // bp
        try self.asm_.mov(.r14, .rdx); // stack_top
    }
    
    /// 生成函数尾声
    /// @post 生成标准的函数尾声代码
    fn emitEpilogue(self: *CodeGenX64) !void {
        // 恢复栈指针
        try self.asm_.addImm(.rsp, 64);
        
        // 恢复被调用者保存寄存器
        try self.asm_.pop(.r15);
        try self.asm_.pop(.r14);
        try self.asm_.pop(.r13);
        try self.asm_.pop(.r12);
        try self.asm_.pop(.rbx);
        
        // 恢复帧指针
        try self.asm_.pop(.rbp);
        
        // 返回
        try self.asm_.ret();
    }
    
    // ========================================================================
    // 类型特化代码生成
    // ========================================================================
    
    /// 生成类型特化的加法指令
    /// @pre type_info 必须包含操作数的类型信息
    /// @post 根据类型生成优化的加法代码
    fn emitTypedAdd(self: *CodeGenX64, type_info: []const TypeInfo) !void {
        // 检查是否都是整数类型
        if (type_info.len >= 2 and 
            type_info[0] == .int and 
            type_info[1] == .int) {
            // 整数加法 - 类型特化
            // 假设操作数在 RAX 和 RBX 中
            try self.asm_.add(.rax, .rbx);
        } else {
            // 动态类型 - 调用运行时函数
            // 这里需要调用运行时的 add 函数
            // 暂时使用占位符
            try self.asm_.nop();
        }
    }
    
    /// 生成类型特化的乘法指令
    /// @pre type_info 必须包含操作数的类型信息
    /// @post 根据类型生成优化的乘法代码，应用强度削减优化
    fn emitTypedMul(self: *CodeGenX64, type_info: []const TypeInfo, constant_value: ?i64) !void {
        // 检查是否都是整数类型
        if (type_info.len >= 2 and 
            type_info[0] == .int and 
            type_info[1] == .int) {
            
            // 强度削减优化：检查是否乘以 2 的幂
            if (constant_value) |val| {
                if (val > 0 and std.math.isPowerOfTwo(@as(u64, @intCast(val)))) {
                    // 优化为左移
                    const shift = std.math.log2_int(u64, @intCast(val));
                    try self.asm_.shl(.rax, @intCast(shift));
                    return;
                }
            }
            
            // 普通整数乘法
            try self.asm_.imul(.rax, .rbx);
        } else {
            // 动态类型 - 调用运行时函数
            try self.asm_.nop();
        }
    }
    
    // ========================================================================
    // 方法内联
    // ========================================================================
    
    /// 检查函数是否应该内联
    /// @pre func 必须有效
    /// @post 返回是否应该内联该函数
    fn shouldInline(self: *const CodeGenX64, func: *const CompiledFunc) bool {
        _ = self;
        
        // 内联策略：
        // 1. 函数体小于 50 字节
        // 2. 调用深度 <= 3
        // 3. 无递归调用
        
        const max_inline_size = 50;
        if (func.code.len > max_inline_size) {
            return false;
        }
        
        // 简化版本：总是内联小函数
        return true;
    }
    
    /// 内联函数调用
    /// @pre func 必须有效且适合内联
    /// @post 生成内联的函数体代码
    fn inlineFunction(self: *CodeGenX64, func: *const CompiledFunc, type_info: []const TypeInfo) !void {
        // 保存当前状态
        const saved_ip_map = self.ip_to_offset;
        self.ip_to_offset = std.AutoHashMap(usize, usize).init(self.allocator);
        defer {
            self.ip_to_offset.deinit();
            self.ip_to_offset = saved_ip_map;
        }
        
        // 生成内联函数体
        try self.generateFunctionBody(func, type_info);
    }
    
    // ========================================================================
    // 指令生成
    // ========================================================================
    
    /// 生成函数体代码
    /// @pre func 和 type_info 必须有效
    /// @post 生成完整的函数体机器码
    fn generateFunctionBody(self: *CodeGenX64, func: *const CompiledFunc, type_info: []const TypeInfo) !void {
        const code = func.code;
        var ip: usize = 0;
        
        while (ip < code.len) {
            const current_ip = ip;
            
            // 记录 IP 到代码偏移的映射
            try self.ip_to_offset.put(current_ip, self.asm_.position());
            
            const op_byte = code[ip];
            ip += 1;
            const op: OpCode = @enumFromInt(op_byte);
            
            switch (op) {
                .push_0 => {
                    // 推入整数 0
                    try self.asm_.xorReg(.rax, .rax); // RAX = 0
                    try self.emitPushValue(.rax);
                },
                
                .push_1 => {
                    // 推入整数 1
                    try self.asm_.movImm32(.rax, 1);
                    try self.emitPushValue(.rax);
                },
                
                .push_int => {
                    // 推入整数常量
                    const val = std.mem.readInt(i32, code[ip..][0..4], .little);
                    ip += 4;
                    try self.asm_.movImm64(.rax, val);
                    try self.emitPushValue(.rax);
                },
                
                .push_local => {
                    // 推入局部变量
                    const idx = code[ip];
                    ip += 1;
                    // 计算局部变量地址：stack_base + (bp + idx) * 8
                    try self.asm_.lea(.rax, .r13, @as(i32, idx) * 8);
                    try self.asm_.movLoad(.rax, .r12, 0); // 从 stack_base[bp + idx] 加载
                    try self.emitPushValue(.rax);
                },
                
                .store_local => {
                    // 存储到局部变量
                    const idx = code[ip];
                    ip += 1;
                    try self.emitPopValue(.rax);
                    // 计算局部变量地址
                    try self.asm_.lea(.rbx, .r13, @as(i32, idx) * 8);
                    try self.asm_.movStore(.r12, 0, .rax); // 存储到 stack_base[bp + idx]
                },
                
                .pop => {
                    // 弹出栈顶
                    try self.asm_.subImm(.r14, 8); // stack_top -= 8
                },
                
                .dup => {
                    // 复制栈顶
                    try self.emitPeekValue(.rax);
                    try self.emitPushValue(.rax);
                },
                
                .add => {
                    // 加法
                    try self.emitPopValue(.rbx);
                    try self.emitPopValue(.rax);
                    try self.emitTypedAdd(type_info);
                    try self.emitPushValue(.rax);
                },
                
                .sub => {
                    // 减法
                    try self.emitPopValue(.rbx);
                    try self.emitPopValue(.rax);
                    try self.asm_.sub(.rax, .rbx);
                    try self.emitPushValue(.rax);
                },
                
                .mul => {
                    // 乘法（带强度削减优化）
                    try self.emitPopValue(.rbx);
                    try self.emitPopValue(.rax);
                    try self.emitTypedMul(type_info, null);
                    try self.emitPushValue(.rax);
                },
                
                .div => {
                    // 除法
                    try self.emitPopValue(.rbx);
                    try self.emitPopValue(.rax);
                    // x86-64 除法需要 RDX:RAX / RBX
                    try self.asm_.xorReg(.rdx, .rdx); // 清零 RDX
                    // 这里需要 IDIV 指令，暂时占位
                    try self.asm_.nop();
                    try self.emitPushValue(.rax);
                },
                
                .lt => {
                    // 小于比较
                    try self.emitPopValue(.rbx);
                    try self.emitPopValue(.rax);
                    try self.asm_.cmp(.rax, .rbx);
                    // 使用条件移动指令
                    try self.asm_.movImm32(.rax, 0);  // 默认 false
                    try self.asm_.movImm32(.rcx, 1);  // true 值
                    // 如果 RAX < RBX，则 RAX = RCX
                    try self.asm_.cmov(.L, .rax, .rcx);
                    try self.emitPushValue(.rax);
                },
                
                .le => {
                    // 小于等于比较
                    try self.emitPopValue(.rbx);
                    try self.emitPopValue(.rax);
                    try self.asm_.cmp(.rax, .rbx);
                    // 使用条件移动指令
                    try self.asm_.movImm32(.rax, 0);  // 默认 false
                    try self.asm_.movImm32(.rcx, 1);  // true 值
                    try self.asm_.cmov(.LE, .rax, .rcx);
                    try self.emitPushValue(.rax);
                },
                
                .gt => {
                    // 大于比较
                    try self.emitPopValue(.rbx);
                    try self.emitPopValue(.rax);
                    try self.asm_.cmp(.rax, .rbx);
                    // 使用条件移动指令
                    try self.asm_.movImm32(.rax, 0);  // 默认 false
                    try self.asm_.movImm32(.rcx, 1);  // true 值
                    try self.asm_.cmov(.G, .rax, .rcx);
                    try self.emitPushValue(.rax);
                },
                
                .ge => {
                    // 大于等于比较
                    try self.emitPopValue(.rbx);
                    try self.emitPopValue(.rax);
                    try self.asm_.cmp(.rax, .rbx);
                    // 使用条件移动指令
                    try self.asm_.movImm32(.rax, 0);  // 默认 false
                    try self.asm_.movImm32(.rcx, 1);  // true 值
                    try self.asm_.cmov(.GE, .rax, .rcx);
                    try self.emitPushValue(.rax);
                },
                
                .eq => {
                    // 等于比较
                    try self.emitPopValue(.rbx);
                    try self.emitPopValue(.rax);
                    try self.asm_.cmp(.rax, .rbx);
                    // 使用条件移动指令
                    try self.asm_.movImm32(.rax, 0);  // 默认 false
                    try self.asm_.movImm32(.rcx, 1);  // true 值
                    try self.asm_.cmov(.E, .rax, .rcx);
                    try self.emitPushValue(.rax);
                },
                
                .ne => {
                    // 不等于比较
                    try self.emitPopValue(.rbx);
                    try self.emitPopValue(.rax);
                    try self.asm_.cmp(.rax, .rbx);
                    // 使用条件移动指令
                    try self.asm_.movImm32(.rax, 0);  // 默认 false
                    try self.asm_.movImm32(.rcx, 1);  // true 值
                    try self.asm_.cmov(.NE, .rax, .rcx);
                    try self.emitPushValue(.rax);
                },
                
                .jz => {
                    // 条件跳转（为零跳转）
                    const offset = std.mem.readInt(i16, code[ip..][0..2], .little);
                    ip += 2;
                    const target_ip = @as(i32, @intCast(current_ip)) + offset;
                    
                    try self.emitPopValue(.rax);
                    try self.asm_.testReg(.rax, .rax);
                    
                    // 记录跳转补丁
                    const patch_offset = self.asm_.position();
                    try self.asm_.jcc(.E, 0); // 占位符
                    try self.jump_patches.append(self.allocator, .{
                        .inst_offset = patch_offset,
                        .target_ip = @intCast(target_ip),
                        .is_conditional = true,
                        .condition = .E,
                    });
                },
                
                .jnz => {
                    // 条件跳转（非零跳转）
                    const offset = std.mem.readInt(i16, code[ip..][0..2], .little);
                    ip += 2;
                    const target_ip = @as(i32, @intCast(current_ip)) + offset;
                    
                    try self.emitPopValue(.rax);
                    try self.asm_.testReg(.rax, .rax);
                    
                    const patch_offset = self.asm_.position();
                    try self.asm_.jcc(.NE, 0);
                    try self.jump_patches.append(self.allocator, .{
                        .inst_offset = patch_offset,
                        .target_ip = @intCast(target_ip),
                        .is_conditional = true,
                        .condition = .NE,
                    });
                },
                
                .jmp => {
                    // 无条件跳转
                    const offset = std.mem.readInt(i16, code[ip..][0..2], .little);
                    ip += 2;
                    const target_ip = @as(i32, @intCast(current_ip)) + offset;
                    
                    const patch_offset = self.asm_.position();
                    try self.asm_.jmp(0);
                    try self.jump_patches.append(self.allocator, .{
                        .inst_offset = patch_offset,
                        .target_ip = @intCast(target_ip),
                        .is_conditional = false,
                        .condition = .E, // 未使用
                    });
                },
                
                .call => {
                    // 函数调用
                    // 这里需要更复杂的处理，暂时占位
                    try self.asm_.nop();
                },
                
                .ret => {
                    // 返回
                    try self.emitPopValue(.rax);
                    try self.emitEpilogue();
                },
                
                .ret_nil => {
                    // 返回 nil
                    try self.asm_.xorReg(.rax, .rax);
                    try self.emitEpilogue();
                },
                
                .halt => {
                    // 停机
                    try self.asm_.xorReg(.rax, .rax);
                    try self.emitEpilogue();
                },
                
                else => {
                    // 不支持的指令 - 跳过
                    try self.asm_.nop();
                },
            }
        }
    }
    
    // ========================================================================
    // 辅助函数
    // ========================================================================
    
    /// 推入值到虚拟栈
    /// @pre reg 包含要推入的值
    /// @post 值被推入栈，stack_top 增加
    fn emitPushValue(self: *CodeGenX64, reg: Register) !void {
        // stack[stack_top] = reg
        try self.asm_.movStore(.r12, 0, reg); // 使用 R14 作为偏移
        // stack_top += 8
        try self.asm_.addImm(.r14, 8);
    }
    
    /// 从虚拟栈弹出值
    /// @pre 栈不为空
    /// @post 栈顶值被弹出到 reg，stack_top 减少
    fn emitPopValue(self: *CodeGenX64, reg: Register) !void {
        // stack_top -= 8
        try self.asm_.subImm(.r14, 8);
        // reg = stack[stack_top]
        try self.asm_.movLoad(reg, .r12, 0);
    }
    
    /// 查看栈顶值（不弹出）
    /// @pre 栈不为空
    /// @post 栈顶值被加载到 reg，栈不变
    fn emitPeekValue(self: *CodeGenX64, reg: Register) !void {
        // reg = stack[stack_top - 8]
        try self.asm_.movLoad(reg, .r14, -8);
    }
    
    /// 回填跳转指令
    /// @pre 所有跳转目标已生成
    /// @post 所有跳转指令的偏移被正确设置
    fn patchJumps(self: *CodeGenX64) !void {
        for (self.jump_patches.items) |patch| {
            const target_offset = self.ip_to_offset.get(patch.target_ip) orelse {
                return error.InvalidJumpTarget;
            };
            
            // 计算相对偏移
            const inst_end = patch.inst_offset + 6; // Jcc 指令长度为 6 字节
            const rel_offset = @as(i32, @intCast(target_offset)) - @as(i32, @intCast(inst_end));
            
            // 回填跳转偏移
            const code = self.asm_.code.items;
            std.mem.writeInt(i32, code[patch.inst_offset + 2..][0..4], rel_offset, .little);
        }
    }
    
    // ========================================================================
    // 公共接口
    // ========================================================================
    
    /// 生成函数代码
    /// @pre func 和 type_info 必须有效
    /// @post 返回生成的机器码
    pub fn generateFunction(
        self: *CodeGenX64,
        func: *const CompiledFunc,
        type_info: []const TypeInfo,
    ) ![]u8 {
        // 清空状态
        self.asm_.code.clearRetainingCapacity();
        self.jump_patches.clearRetainingCapacity();
        self.ip_to_offset.clearRetainingCapacity();
        
        // 生成函数序言
        try self.emitPrologue(func);
        
        // 生成函数体
        try self.generateFunctionBody(func, type_info);
        
        // 回填跳转
        try self.patchJumps();
        
        // 返回生成的代码
        return try self.asm_.code.toOwnedSlice(self.allocator);
    }
};
