const std = @import("std");

/// OSR（On-Stack Replacement）管理器
/// 
/// 在运行时将解释执行切换到 JIT 编译代码
pub const OSRManager = struct {
    /// OSR 点
    pub const OSRPoint = struct {
        /// 字节码偏移
        bytecode_offset: u32,
        /// 编译后的机器码入口
        compiled_entry: *const fn (*InterpreterFrame) callconv(.c) void,
        /// 栈映射
        stack_map: StackMap,
    };
    
    /// 栈映射（解释器栈 -> 编译代码栈）
    pub const StackMap = struct {
        /// 局部变量映射
        locals: []LocalMapping,
        /// 操作数栈映射
        operand_stack: []OperandMapping,
        
        pub const LocalMapping = struct {
            interpreter_slot: u32,
            compiled_slot: u32,
            type_: ValueType,
        };
        
        pub const OperandMapping = struct {
            interpreter_offset: u32,
            compiled_offset: u32,
            type_: ValueType,
        };
        
        pub const ValueType = enum {
            int,
            float,
            object,
            bool,
        };
    };
    
    /// 解释器栈帧
    pub const InterpreterFrame = struct {
        /// 局部变量
        locals: []Value,
        /// 操作数栈
        operand_stack: []Value,
        /// 程序计数器
        pc: u32,
        /// 函数名
        function_name: []const u8,
    };
    
    /// 编译代码栈帧
    pub const CompiledFrame = struct {
        /// 局部变量（寄存器或栈槽）
        locals: []Value,
        /// 返回地址
        return_address: usize,
    };
    
    /// 值表示
    pub const Value = union(enum) {
        int: i64,
        float: f64,
        object: *anyopaque,
        bool: bool,
    };
    
    allocator: std.mem.Allocator,
    /// OSR 点注册表
    osr_points: std.AutoHashMap(u32, OSRPoint),
    
    pub fn init(allocator: std.mem.Allocator) OSRManager {
        return .{
            .allocator = allocator,
            .osr_points = std.AutoHashMap(u32, OSRPoint).init(allocator),
        };
    }
    
    pub fn deinit(self: *OSRManager) void {
        // 释放所有栈映射
        var it = self.osr_points.valueIterator();
        while (it.next()) |point| {
            self.allocator.free(point.stack_map.locals);
            self.allocator.free(point.stack_map.operand_stack);
        }
        self.osr_points.deinit();
    }
    
    /// 注册 OSR 点
    pub fn registerOSRPoint(
        self: *OSRManager,
        bytecode_offset: u32,
        compiled_entry: *const fn (*InterpreterFrame) callconv(.c) void,
        stack_map: StackMap,
    ) !void {
        try self.osr_points.put(bytecode_offset, .{
            .bytecode_offset = bytecode_offset,
            .compiled_entry = compiled_entry,
            .stack_map = stack_map,
        });
    }
    
    /// 执行 OSR
    /// @pre interpreter_frame 必须有效
    /// @post 切换到编译代码执行
    pub fn performOSR(
        self: *OSRManager,
        interpreter_frame: *InterpreterFrame,
    ) !void {
        // 1. 查找 OSR 点
        const osr_point = self.osr_points.get(interpreter_frame.pc) orelse
            return error.NoOSRPoint;
        
        // 2. 保存解释器状态
        const state = try self.captureInterpreterState(interpreter_frame);
        defer self.allocator.free(state.locals);
        defer self.allocator.free(state.operand_stack);
        
        // 3. 构建编译代码栈帧
        const compiled_frame = try self.buildCompiledFrame(state, osr_point.stack_map);
        defer self.allocator.free(compiled_frame.locals);
        
        // 4. 转换栈映射
        try self.transferState(state, compiled_frame, osr_point.stack_map);
        
        // 5. 跳转到编译代码
        osr_point.compiled_entry(interpreter_frame);
    }
    
    /// 捕获解释器状态
    fn captureInterpreterState(
        self: *OSRManager,
        frame: *InterpreterFrame,
    ) !InterpreterFrame {
        const locals = try self.allocator.alloc(Value, frame.locals.len);
        errdefer self.allocator.free(locals);
        
        const operand_stack = try self.allocator.alloc(Value, frame.operand_stack.len);
        errdefer self.allocator.free(operand_stack);
        
        @memcpy(locals, frame.locals);
        @memcpy(operand_stack, frame.operand_stack);
        
        return .{
            .locals = locals,
            .operand_stack = operand_stack,
            .pc = frame.pc,
            .function_name = frame.function_name,
        };
    }
    
    /// 构建编译代码栈帧
    fn buildCompiledFrame(
        self: *OSRManager,
        _: InterpreterFrame,
        stack_map: StackMap,
    ) !CompiledFrame {
        const locals = try self.allocator.alloc(Value, stack_map.locals.len);
        errdefer self.allocator.free(locals);
        
        return .{
            .locals = locals,
            .return_address = 0,
        };
    }
    
    /// 转换状态（解释器 -> 编译代码）
    fn transferState(
        _: *OSRManager,
        interpreter_state: InterpreterFrame,
        compiled_frame: CompiledFrame,
        stack_map: StackMap,
    ) !void {
        // 转换局部变量
        for (stack_map.locals) |mapping| {
            const value = interpreter_state.locals[mapping.interpreter_slot];
            compiled_frame.locals[mapping.compiled_slot] = value;
        }
        
        // 转换操作数栈（如果需要）
        for (stack_map.operand_stack) |_| {
            // 将操作数栈值存储到编译代码的临时位置
        }
    }
    
    /// 检查是否可以执行 OSR
    pub fn canPerformOSR(self: *OSRManager, bytecode_offset: u32) bool {
        return self.osr_points.contains(bytecode_offset);
    }
    
    /// 去优化（编译代码 -> 解释器）
    pub fn deoptimize(
        self: *OSRManager,
        compiled_frame: *CompiledFrame,
        bytecode_offset: u32,
    ) !InterpreterFrame {
        // 查找 OSR 点
        const osr_point = self.osr_points.get(bytecode_offset) orelse
            return error.NoOSRPoint;
        
        // 反向转换栈映射
        const locals = try self.allocator.alloc(Value, osr_point.stack_map.locals.len);
        errdefer self.allocator.free(locals);
        
        const operand_stack = try self.allocator.alloc(Value, osr_point.stack_map.operand_stack.len);
        errdefer self.allocator.free(operand_stack);
        
        // 反向映射局部变量
        for (osr_point.stack_map.locals) |mapping| {
            locals[mapping.interpreter_slot] = compiled_frame.locals[mapping.compiled_slot];
        }
        
        return .{
            .locals = locals,
            .operand_stack = operand_stack,
            .pc = bytecode_offset,
            .function_name = "",
        };
    }
};
