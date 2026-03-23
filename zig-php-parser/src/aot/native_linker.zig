//! Native Linker - 实际的对象文件生成和可执行文件链接
//!
//! 本模块实现真正的 AOT 编译后端：
//! 1. 将 IR 转换为 Zig 代码
//! 2. 调用 Zig 编译器生成对象文件
//! 3. 链接生成可执行文件
//!
//! ## 设计策略
//!
//! 由于直接生成机器码或 LLVM IR 过于复杂，我们采用"转译"策略：
//! - IR → Zig 代码 → 对象文件 → 可执行文件
//!
//! 这种方法的优势：
//! - 利用 Zig 编译器的优化能力
//! - 自动处理平台差异
//! - 简化实现复杂度
//! - 保证内存安全
//!
//! @ownership NON-OWNING (allocator)
//! @thread-safety ISOLATED

const std = @import("std");
const Allocator = std.mem.Allocator;
const IR = @import("ir.zig");
const Diagnostics = @import("diagnostics.zig");
const DiagnosticEngine = Diagnostics.DiagnosticEngine;

/// 获取类名的最后一部分（用于变量名）
/// @param full_name 完整类名（如 "App\\Utils\\Helper"）
/// @return 最后一部分（如 "Helper"）
fn getLastPartOfClassName(full_name: []const u8) []const u8 {
    var i: usize = full_name.len;
    while (i > 0) {
        i -= 1;
        if (full_name[i] == '\\') {
            return full_name[i + 1 ..];
        }
    }
    return full_name;
}

/// 转义字符串中的反斜杠（用于Zig标识符）
fn escapeBackslashes(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    var count: usize = 0;
    for (str) |c| {
        if (c == '\\') count += 1;
    }
    if (count == 0) return try allocator.dupe(u8, str);

    var result = try allocator.alloc(u8, str.len + count);
    var i: usize = 0;
    for (str) |c| {
        if (c == '\\') {
            result[i] = '\\';
            result[i + 1] = '\\';
            i += 2;
        } else {
            result[i] = c;
            i += 1;
        }
    }
    return result;
}

/// 原生链接器配置
pub const NativeLinkerConfig = struct {
    /// 目标平台
    target: Target,
    /// 优化级别
    optimize_level: OptimizeLevel,
    /// 是否生成静态链接的可执行文件
    static_link: bool = true,
    /// 是否包含调试信息
    debug_info: bool = true,
    /// 是否剥离符号
    strip_symbols: bool = false,
    /// CPU model/features passed to Zig as -mcpu=<value> (e.g. \"native\")
    mcpu: ?[]const u8 = null,
    /// Extra flags appended to `zig build-exe` invocation
    extra_zig_flags: []const []const u8 = &.{},
    /// 详细输出
    verbose: bool = false,
    /// Dump generated Zig code
    dump_zig: bool = false,
    /// Path to dump Zig code (optional)
    dump_zig_path: ?[]const u8 = null,
    emit_asm_path: ?[]const u8 = null,
    emit_llvm_ir_path: ?[]const u8 = null,
    emit_llvm_bc_path: ?[]const u8 = null,
    lowering_policy: LoweringPolicy = LoweringPolicy.@"error",
};

pub const LoweringPolicy = enum {
    warn,
    @"error",
};

/// 目标平台
pub const Target = struct {
    arch: Arch,
    os: OS,
    abi: ABI,

    pub const Arch = enum {
        x86_64,
        aarch64,
        arm,
    };

    pub const OS = enum {
        linux,
        macos,
        windows,
    };

    pub const ABI = enum {
        gnu,
        musl,
        msvc,
        none,
    };
};

/// 优化级别
pub const OptimizeLevel = enum {
    debug,
    release_safe,
    release_fast,
    release_small,

    pub fn toZigOptimize(self: OptimizeLevel) []const u8 {
        return switch (self) {
            .debug => "Debug",
            .release_safe => "ReleaseSafe",
            .release_fast => "ReleaseFast",
            .release_small => "ReleaseSmall",
        };
    }
};

/// 原生链接器
pub const NativeLinker = struct {
    const Self = @This();

    const ComposedTraitMethod = struct {
        provider_trait: []const u8,
        function_trait: []const u8,
        exposed_name: []const u8,
        original_name: []const u8,
        visibility: IR.TypeDef.Visibility,
        is_static: bool,
        is_abstract: bool = false,
    };

    const ComposedTraitProperty = struct {
        prop: IR.TypeDef.Property,
    };

    const ComposedTraitConstant = struct {
        constant: IR.TypeDef.Constant,
    };

    allocator: Allocator,
    config: NativeLinkerConfig,
    diagnostics: *DiagnosticEngine,
    temp_dir: ?[]const u8,
    func_return_types: std.StringHashMap(bool), // 函数名 -> 是否有返回值
    current_reg_types: ?*const std.AutoHashMap(usize, IR.Type),
    current_reg_is_value: ?[]bool,
    current_reg_may_heap: ?[]bool,
    current_function_has_this: bool = false,
    current_exception_handler: ?u32 = null,
    current_cleanup_regs: ?[]const usize = null,
    current_alloca_regs: ?*const std.AutoHashMap(usize, void) = null,
    current_var_name_map: ?*const std.AutoHashMap(usize, []const u8) = null,
    current_byref_regs: ?*const std.AutoHashMap(usize, void) = null,
    current_switch_value_regs: ?*const std.AutoHashMap(usize, void) = null,
    current_global_get_names: ?*const std.AutoHashMap(usize, []const u8) = null,
    current_concat_operand_regs: ?*const std.AutoHashMap(usize, void) = null,
    current_coalesce_nowarn_regs: ?*const std.AutoHashMap(usize, void) = null,
    current_unset_regs: ?*std.AutoHashMap(usize, void) = null,
    ref_param_alloca_map: ?*std.AutoHashMap(usize, usize) = null,
    current_ref_capture_allocas: ?*const std.AutoHashMap(usize, usize) = null,
    current_make_ref_allocas: ?*const std.AutoHashMap(usize, void) = null,
    current_optimized_alloca_regs: ?*const std.AutoHashMap(usize, void) = null,
    current_function_for_resolve: ?*const IR.Function = null,
    current_register_types: ?*const std.AutoHashMap(usize, IR.Type) = null,
    current_inferred_types: ?*const std.AutoHashMap(usize, IR.Type) = null, // 类型推断结果
    hoisted_instructions: ?std.AutoHashMap(*const IR.Instruction, void) = null, // LICM 已提升指令
    ir_module: ?*const IR.Module = null, // 当前IR模块（用于查找函数）
    current_ref_ptr_regs: ?*const std.AutoHashMap(usize, void) = null, // 非alloca的指针寄存器（PHI/select合并引用参数）
    param_registers: ?*std.StringHashMap(usize) = null, // 参数名 -> 寄存器ID（用于引用写回）
    current_liveness: ?*const @import("liveness_analysis.zig").LivenessAnalysis = null, // 活跃性分析结果

    /// 查找make_ref指令的原始alloca
    fn findMakeRefSource(self: *Self, reg_id: usize) ?usize {
        const func = self.current_function_for_resolve orelse return null;
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.result) |result_reg| {
                    if (result_reg.id == reg_id) {
                        if (inst.op == .make_ref) {
                            return inst.op.make_ref.ptr.id;
                        }
                    }
                }
            }
        }
        return null;
    }

    /// 检查寄存器是否需要 release（排除优化的 alloca）
    fn shouldReleaseReg(self: *Self, reg_id: usize) bool {
        if (self.current_optimized_alloca_regs) |opt_regs| {
            if (opt_regs.contains(reg_id)) {
                return false;
            }
        }

        // alloca 指针寄存器：允许生成 reg_*.release（实际会用 .* 形式）
        if (self.current_alloca_regs) |alloca_regs| {
            if (alloca_regs.contains(reg_id)) {
                return true;
            }
        }

        // 标量类型禁止 release，避免生成 i64/f64/bool 上的 .release 调用
        if (self.current_reg_types) |rt| {
            const ty = rt.get(reg_id) orelse IR.Type.php_value;
            const tag = @as(std.meta.Tag(IR.Type), ty);
            switch (tag) {
                .php_value, .php_string, .php_array, .php_object, .php_resource, .php_callable => return true,
                else => return false,
            }
        }

        // 无法获知类型时，保守：允许（保持旧行为）
        return true;
    }

    /// 检查寄存器是否是指针类型（alloca 或 ref_ptr）
    fn isPointerReg(self: *Self, reg_id: usize) bool {
        // 检查是否是 alloca 寄存器
        if (self.current_alloca_regs) |alloca_regs| {
            if (alloca_regs.contains(reg_id)) {
                return true;
            }
        }
        
        // 检查是否是 ref_ptr 寄存器（PHI/select 合并引用参数）
        if (self.current_ref_ptr_regs) |ref_ptr_regs| {
            if (ref_ptr_regs.contains(reg_id)) {
                return true;
            }
        }
        
        return false;
    }

    /// 类型推断统计（用于诊断和质量门禁）
    var type_infer_hit_count: usize = 0;
    var type_infer_fallback_count: usize = 0;

    /// 获取寄存器的推断类型（优先使用推断结果）
    /// strict_mode = true 时，fallback 到 php_value 会触发诊断警告
    fn getInferredRegType(self: *Self, reg_id: usize, fallback: IR.Type) IR.Type {
        // 强制所有寄存器类型为 php_value，因为所有寄存器都是 runtime.Value
        _ = self;
        _ = reg_id;
        _ = fallback;
        return IR.Type{ .php_value = {} };
    }

    /// 严格模式类型推断：推断失败时报告诊断警告
    fn getInferredRegTypeStrict(self: *Self, reg_id: usize, fallback: IR.Type) IR.Type {
        // 强制所有寄存器类型为 php_value
        return self.getInferredRegType(reg_id, fallback);
    }

    /// 类型推断核心实现（已废弃，保留用于兼容）
    fn getInferredRegTypeEx(
        self: *Self,
        reg_id: usize,
        fallback: IR.Type,
        strict: bool,
    ) IR.Type {
        _ = self;
        _ = strict;
        _ = reg_id;
        _ = fallback;
        // 强制所有寄存器类型为 php_value
        return IR.Type{ .php_value = {} };
    }

    /// 重置类型推断统计
    fn resetTypeInferStats() void {
        type_infer_hit_count = 0;
        type_infer_fallback_count = 0;
    }

    /// 获取类型推断命中率
    fn getTypeInferHitRate() f64 {
        const total = type_infer_hit_count +
            type_infer_fallback_count;
        if (total == 0) return 1.0;
        return @as(f64, @floatFromInt(type_infer_hit_count)) /
            @as(f64, @floatFromInt(total));
    }

    fn handleUnsupportedOp(self: *Self, inst: *const IR.Instruction) !void {
        const tag = std.meta.activeTag(inst.op);
        const op_name = @tagName(tag);
        switch (self.config.lowering_policy) {
            .warn => self.diagnostics.reportWarning(inst.location, "AOT lowering 未实现 IR op: {s}（参考 docs/2026-02-05/aot_interpreter_feature_gap_matrix.md）", .{op_name}),
            .@"error" => {
                self.diagnostics.reportError(inst.location, "AOT lowering 未实现 IR op: {s}（参考 docs/2026-02-05/aot_interpreter_feature_gap_matrix.md）", .{op_name});
                return error.UnsupportedIrOp;
            },
        }
    }

    /// 寄存器使用信息（用于生命周期分析）
    const RegUseInfo = struct {
        block_idx: usize,
        inst_idx: usize,
    };

    /// 寄存器生命周期信息
    const RegLifetime = struct {
        def_block: usize, // 定义所在的块索引
        def_inst: usize, // 定义所在的指令索引
        last_use_block: usize, // 最后使用所在的块索引
        last_use_inst: usize, // 最后使用所在的指令索引
        use_count: usize, // 使用次数
        is_temp: bool, // 是否为临时寄存器（只使用一次）
        needs_release: bool, // 是否需要释放（字符串、数组等）
    };

    /// 初始化原生链接器
    pub fn init(
        allocator: Allocator,
        config: NativeLinkerConfig,
        diagnostics: *DiagnosticEngine,
    ) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .diagnostics = diagnostics,
            .temp_dir = null,
            .func_return_types = std.StringHashMap(bool).init(allocator),
            .current_reg_types = null,
            .current_reg_is_value = null,
            .current_reg_may_heap = null,
            .current_function_has_this = false,
            .current_exception_handler = null,
            .current_cleanup_regs = null,
            .current_alloca_regs = null,
            .current_concat_operand_regs = null,
        };
        return self;
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        if (self.temp_dir) |dir| {
            self.allocator.free(dir);
        }
        self.func_return_types.deinit();
        if (self.hoisted_instructions) |*map| {
            map.deinit();
        }
    }

    /// 创建临时目录
    fn createTempDir(self: *Self) ![]const u8 {
        if (self.temp_dir) |dir| {
            return dir;
        }

        // 使用固定的临时目录名
        const temp_name = ".zigphp_aot_build";

        // 不删除已存在的目录，让zig使用增量编译缓存
        // std.fs.cwd().deleteTree(temp_name) catch {};

        // 创建目录（如果不存在）
        std.fs.cwd().makeDir(temp_name) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // 返回绝对路径
        const abs_path = try std.fs.cwd().realpathAlloc(self.allocator, temp_name);
        self.temp_dir = abs_path;

        return abs_path;
    }

    /// 将 IR 模块转换为 Zig 代码
    pub fn generateZigCode(self: *Self, ir_module: *const IR.Module) ![]const u8 {
        // std.debug.print("=== generateZigCode: {d} functions ===\n", .{ir_module.functions.items.len});

        // 设置当前IR模块
        self.ir_module = ir_module;
        defer self.ir_module = null;

        var code = std.ArrayList(u8){};
        errdefer code.deinit(self.allocator);

        // 创建writer并确保它的生命周期覆盖整个函数
        var writer = code.writer(self.allocator);

        // 收集所有函数的返回类型信息
        self.func_return_types.clearRetainingCapacity();

        for (ir_module.functions.items) |func| {
            // 所有用户函数都返回 !runtime.Value（即使是 void 函数）
            // 因为它们可能抛出异常
            try self.func_return_types.put(func.name, true);
        }
        if (!self.func_return_types.contains("select")) {
            try self.func_return_types.put("select", true);
        }

        // 生成文件头
        try writer.writeAll(
            \\// Generated by zig-php AOT compiler
            \\// DO NOT EDIT
            \\
            \\const std = @import("std");
            \\const runtime = @import("runtime_lib.zig");
            \\
            \\
        );

        // 生成字符串表
        if (ir_module.string_table.items.len > 0) {
            try writer.writeAll("// String table\n");
            try writer.writeAll("const string_table = [_][]const u8{\n");
            for (ir_module.string_table.items) |str| {
                // 转义字符串中的特殊字符
                try writer.writeAll("    \"");
                for (str) |c| {
                    switch (c) {
                        '\n' => try writer.writeAll("\\n"),
                        '\r' => try writer.writeAll("\\r"),
                        '\t' => try writer.writeAll("\\t"),
                        '\\' => try writer.writeAll("\\\\"),
                        '"' => try writer.writeAll("\\\""),
                        else => try writer.writeByte(c),
                    }
                }
                try writer.writeAll("\",\n");
            }
            try writer.writeAll("};\n\n");

            // 静态字符串池：运行时初始化一次（懒加载）
            try writer.writeAll("// 静态字符串池（运行时初始化一次）\n");
            try writer.writeAll("var static_strings: [string_table.len]*runtime.PHPString = undefined;\n");
            try writer.writeAll("var static_strings_initialized = false;\n\n");
            try writer.writeAll("fn initStaticStrings() void {\n");
            try writer.writeAll("    if (static_strings_initialized) return;\n");
            try writer.writeAll("    for (string_table, 0..) |str, i| {\n");
            try writer.writeAll("        static_strings[i] = runtime.PHPString.initStatic(str);\n");
            try writer.writeAll("    }\n");
            try writer.writeAll("    static_strings_initialized = true;\n");
            try writer.writeAll("}\n\n");
        }

        // 生成全局变量
        for (ir_module.globals.items) |global| {
            try self.generateGlobalVariable(writer, global);
        }

        // 生成函数
        // std.debug.print("=== GENERATING FUNCTIONS: count={d} ===\n", .{ir_module.functions.items.len});
        var func_code = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        defer func_code.deinit(self.allocator);

        for (ir_module.functions.items, 0..) |func, i| {
            _ = i;
            const before_len = func_code.items.len;
            try self.generateFunction(&func_code, ir_module, func);

            // 输出生成的函数代码
            if (std.mem.eql(u8, func.name, "__main__")) {
                const func_text = func_code.items[before_len..];
                _ = func_text;
                // std.debug.print("=== GENERATED CODE FOR {s} ===\n{s}\n=== END ===\n", .{ func.name, func_text });
            }
        }

        // 将生成的函数代码写入主代码
        // std.debug.print("Writing function code to main\n", .{});
        try writer.writeAll(func_code.items);
        // std.debug.print("Function code written\n", .{});

        var has_select: bool = false;
        for (ir_module.functions.items) |func| {
            if (std.mem.eql(u8, func.name, "select")) {
                has_select = true;
                break;
            }
        }
        if (!has_select) {
            try writer.writeAll(
                \\
                \\pub fn @"select"(ctx: runtime.Value, args: []const runtime.Value, allocator: std.mem.Allocator) anyerror!runtime.Value {
                \\    return runtime.php_select_builtin(ctx, args, allocator);
                \\}
                \\
            );
        }

        var has_go: bool = false;
        var has_go_wait_all: bool = false;
        var has_go_join: bool = false;
        for (ir_module.functions.items) |func| {
            if (std.mem.eql(u8, func.name, "go")) has_go = true;
            if (std.mem.eql(u8, func.name, "go_wait_all")) has_go_wait_all = true;
            if (std.mem.eql(u8, func.name, "go_join")) has_go_join = true;
        }
        if (!has_go) {
            try writer.writeAll(
                \\
                \\pub fn @"go"(ctx: runtime.Value, args: []const runtime.Value, allocator: std.mem.Allocator) anyerror!runtime.Value {
                \\    return runtime.php_go(ctx, args, allocator);
                \\}
                \\
            );
        }
        if (!has_go_wait_all) {
            try writer.writeAll(
                \\
                \\pub fn @"go_wait_all"(ctx: runtime.Value, args: []const runtime.Value, allocator: std.mem.Allocator) anyerror!runtime.Value {
                \\    return runtime.php_go_wait_all(ctx, args, allocator);
                \\}
                \\
            );
        }
        if (!has_go_join) {
            try writer.writeAll(
                \\
                \\pub fn @"go_join"(ctx: runtime.Value, args: []const runtime.Value, allocator: std.mem.Allocator) anyerror!runtime.Value {
                \\    return runtime.php_go_join(ctx, args, allocator);
                \\}
                \\
            );
        }

        var has_get_class_methods: bool = false;
        var has_get_class_vars: bool = false;
        var has_get_object_vars: bool = false;
        var has_get_called_class: bool = false;
        var has_forward_static_call: bool = false;
        var has_forward_static_call_array: bool = false;
        for (ir_module.functions.items) |func| {
            if (std.mem.eql(u8, func.name, "get_class_methods")) has_get_class_methods = true;
            if (std.mem.eql(u8, func.name, "get_class_vars")) has_get_class_vars = true;
            if (std.mem.eql(u8, func.name, "get_object_vars")) has_get_object_vars = true;
            if (std.mem.eql(u8, func.name, "get_called_class")) has_get_called_class = true;
            if (std.mem.eql(u8, func.name, "forward_static_call")) has_forward_static_call = true;
            if (std.mem.eql(u8, func.name, "forward_static_call_array")) has_forward_static_call_array = true;
        }
        if (!has_get_class_methods) {
            try writer.writeAll(
                \\
                \\pub fn @"get_class_methods"(ctx: runtime.Value, args: []const runtime.Value, allocator: std.mem.Allocator) anyerror!runtime.Value {
                \\    return runtime.php_get_class_methods_builtin(ctx, args, allocator);
                \\}
                \\
            );
        }
        if (!has_get_class_vars) {
            try writer.writeAll(
                \\
                \\pub fn @"get_class_vars"(ctx: runtime.Value, args: []const runtime.Value, allocator: std.mem.Allocator) anyerror!runtime.Value {
                \\    return runtime.php_get_class_vars_builtin(ctx, args, allocator);
                \\}
                \\
            );
        }
        if (!has_get_object_vars) {
            try writer.writeAll(
                \\
                \\pub fn @"get_object_vars"(ctx: runtime.Value, args: []const runtime.Value, allocator: std.mem.Allocator) anyerror!runtime.Value {
                \\    return runtime.php_get_object_vars_builtin(ctx, args, allocator);
                \\}
                \\
            );
        }
        if (!has_get_called_class) {
            try writer.writeAll(
                \\
                \\pub fn @"get_called_class"(ctx: runtime.Value, args: []const runtime.Value, allocator: std.mem.Allocator) anyerror!runtime.Value {
                \\    return runtime.php_get_called_class_builtin(ctx, args, allocator);
                \\}
                \\
            );
        }
        if (!has_forward_static_call) {
            try writer.writeAll(
                \\
                \\pub fn @"forward_static_call"(ctx: runtime.Value, args: []const runtime.Value, allocator: std.mem.Allocator) anyerror!runtime.Value {
                \\    return runtime.php_forward_static_call_builtin(ctx, args, allocator);
                \\}
                \\
            );
        }
        if (!has_forward_static_call_array) {
            try writer.writeAll(
                \\
                \\pub fn @"forward_static_call_array"(ctx: runtime.Value, args: []const runtime.Value, allocator: std.mem.Allocator) anyerror!runtime.Value {
                \\    return runtime.php_forward_static_call_array_builtin(ctx, args, allocator);
                \\}
                \\
            );
        }

        // 生成类注册函数
        try self.generateClassRegistration(writer, ir_module);

        // 生成函数注册函数
        try self.generateFunctionRegistration(writer, ir_module);

        // 生成AOT function_exists（覆盖runtime版本）
        try writer.writeAll(
            \\
            \\// AOT已注册函数名列表（用于function_exists）
            \\const aot_registered_functions = std.StaticStringMap(void).initComptime(.{
            \\
        );
        // 遍历builtin_map生成函数名列表
        for (builtin_map.keys()) |key| {
            try writer.print("    .{{ \"{s}\", {{}} }},\n", .{key});
        }
        try writer.writeAll(
            \\});
            \\
            \\pub fn aot_function_exists(name: []const u8) runtime.Value {
            \\    if (aot_registered_functions.has(name)) return runtime.Value.initBool(true);
            \\    if (runtime.user_function_registry) |reg| {
            \\        if (reg.contains(name)) return runtime.Value.initBool(true);
            \\    }
            \\    return runtime.Value.initBool(false);
            \\}
            \\
            \\// AOT变量函数调用：覆盖runtime的invoke_callable，支持AOT注册函数
            \\pub fn aot_call_named_function(name: []const u8, args: []const runtime.Value, allocator: std.mem.Allocator) !runtime.Value {
            \\    _ = name;
            \\    _ = args;
            \\    _ = allocator;
            \\    return error.UnknownFunction;
            \\}
            \\
        );

        // 生成主入口
        const has_strings = ir_module.string_table.items.len > 0;

        try writer.writeAll(
            \\
            \\// 全局变量表
            \\var global_vars: std.StringHashMap(runtime.Value) = undefined;
            \\var global_vars_initialized: bool = false;
            \\
            \\// 全局变量引用绑定表: target -> source (e.g., $b = &$a means $b -> $a)
            \\var global_ref_bindings: std.StringHashMap([]const u8) = undefined;
            \\var global_ref_bindings_initialized: bool = false;
            \\
            \\// 创建全局变量引用绑定: $target = &$source
            \\pub fn bindGlobalRef(target: []const u8, source: []const u8) !void {
            \\    if (!global_ref_bindings_initialized) {
            \\        global_ref_bindings = std.StringHashMap([]const u8).init(runtime.runtime_allocator);
            \\        global_ref_bindings_initialized = true;
            \\    }
            \\    // 解析 source 的引用链，找到真正的源变量
            \\    const resolved_source = resolveRefSource(source);
            \\    // 复制 target 和 resolved_source 字符串
            \\    const target_copy = try runtime.runtime_allocator.dupe(u8, target);
            \\    const source_copy = try runtime.runtime_allocator.dupe(u8, resolved_source);
            \\    // 如果已存在旧绑定，释放旧的字符串
            \\    if (try global_ref_bindings.fetchPut(target_copy, source_copy)) |old| {
            \\        runtime.runtime_allocator.free(old.key);
            \\        runtime.runtime_allocator.free(old.value);
            \\    }
            \\    // 同步当前值: $target 应该和 resolved_source 指向相同的值
            \\    if (global_vars_initialized) {
            \\        if (global_vars.get(resolved_source)) |src_val| {
            \\            const gop = try global_vars.getOrPut(target);
            \\            if (!gop.found_existing) {
            \\                gop.key_ptr.* = try runtime.runtime_allocator.dupe(u8, target);
            \\            }
            \\            if (gop.found_existing) {
            \\                gop.value_ptr.release(runtime.runtime_allocator);
            \\            }
            \\            _ = src_val.retain();
            \\            gop.value_ptr.* = src_val;
            \\        }
            \\    }
            \\}
            \\
            \\// 获取变量的引用源（如果是引用则返回源变量名，否则返回自身）
            \\fn resolveRefSource(name: []const u8) []const u8 {
            \\    if (!global_ref_bindings_initialized) return name;
            \\    // 循环解析引用链
            \\    var current = name;
            \\    var depth: usize = 0;
            \\    while (depth < 10) : (depth += 1) {
            \\        if (global_ref_bindings.get(current)) |source| {
            \\            current = source;
            \\        } else {
            \\            break;
            \\        }
            \\    }
            \\    return current;
            \\}
            \\
            \\// 查找所有引用同一源的变量
            \\fn findAllRefsToSource(source: []const u8, out_buf: *[32][]const u8) usize {
            \\    if (!global_ref_bindings_initialized) return 0;
            \\    var count: usize = 0;
            \\    var it = global_ref_bindings.iterator();
            \\    while (it.next()) |entry| {
            \\        if (count >= 32) break;
            \\        const resolved = resolveRefSource(entry.key_ptr.*);
            \\        if (std.mem.eql(u8, resolved, source)) {
            \\            out_buf[count] = entry.key_ptr.*;
            \\            count += 1;
            \\        }
            \\    }
            \\    return count;
            \\}
            \\
            \\pub fn getGlobalVar(name: []const u8) runtime.Value {
            \\    // 超全局变量直接从global_vars读取
            \\    if (name.len > 1 and name[0] == '$' and name[1] == '_' and global_vars_initialized) {
            \\        if (global_vars.get(name)) |value| {
            \\            _ = value.retain();
            \\            return value;
            \\        }
            \\    }
            \\    if (std.mem.eql(u8, name, "$GLOBALS") and global_vars_initialized) {
            \\        if (global_vars.get(name)) |value| {
            \\            _ = value.retain();
            \\            return value;
            \\        }
            \\    }
            \\    // 先查找常量表
            \\    if (runtime.constants.get(name)) |const_val| {
            \\        _ = const_val.retain();
            \\        return const_val;
            \\    }
            \\    // 再查找全局变量表
            \\    if (!global_vars_initialized) {
            \\        var wbuf: [256]u8 = undefined;
            \\        const wmsg = std.fmt.bufPrint(&wbuf, "Undefined variable {s}", .{name}) catch "Undefined variable";
            \\        runtime.emitWarning(wmsg);
            \\        return runtime.Value.initNull();
            \\    }
            \\    if (global_vars.get(name)) |value| {
            \\        _ = value.retain();
            \\        return value;
            \\    }
            \\    var wbuf2: [256]u8 = undefined;
            \\    const wmsg2 = std.fmt.bufPrint(&wbuf2, "Undefined variable {s}", .{name}) catch "Undefined variable";
            \\    runtime.emitWarning(wmsg2);
            \\    return runtime.Value.initNull();
            \\}
            \\
            \\pub fn getGlobalVarNoWarn(name: []const u8) runtime.Value {
            \\    if (name.len > 1 and name[0] == '$' and name[1] == '_' and global_vars_initialized) {
            \\        if (global_vars.get(name)) |value| {
            \\            _ = value.retain();
            \\            return value;
            \\        }
            \\    }
            \\    if (std.mem.eql(u8, name, "$GLOBALS") and global_vars_initialized) {
            \\        if (global_vars.get(name)) |value| {
            \\            _ = value.retain();
            \\            return value;
            \\        }
            \\    }
            \\    if (runtime.constants.get(name)) |const_val| {
            \\        _ = const_val.retain();
            \\        return const_val;
            \\    }
            \\    if (!global_vars_initialized) return runtime.Value.initNull();
            \\    if (global_vars.get(name)) |value| {
            \\        _ = value.retain();
            \\        return value;
            \\    }
            \\    return runtime.Value.initNull();
            \\}
            \\
            \\pub fn globalVarIsDefined(name: []const u8) bool {
            \\    if (runtime.constants.get(name) != null) return true;
            \\    if (!global_vars_initialized) return false;
            \\    return global_vars.get(name) != null;
            \\}
            \\
            \\pub fn setGlobalVar(name: []const u8, value: runtime.Value) !void {
            \\    if (!global_vars_initialized) return;
            \\    
            \\    // 解析引用链：找到真正的源变量
            \\    const source = resolveRefSource(name);
            \\    
            \\    // 设置源变量的值
            \\    try setGlobalVarDirect(source, value);
            \\    
            \\    // 如果设置的是引用变量，也同步更新源变量
            \\    if (!std.mem.eql(u8, name, source)) {
            \\        try setGlobalVarDirect(name, value);
            \\    }
            \\    
            \\    // 查找所有引用同一源的其他变量并同步更新
            \\    var refs_buf: [32][]const u8 = undefined;
            \\    const ref_count = findAllRefsToSource(source, &refs_buf);
            \\    for (refs_buf[0..ref_count]) |ref_name| {
            \\        if (!std.mem.eql(u8, ref_name, name)) {
            \\            try setGlobalVarDirect(ref_name, value);
            \\        }
            \\    }
            \\}
            \\
            \\// 直接设置全局变量值，不处理引用传播
            \\fn setGlobalVarDirect(name: []const u8, value: runtime.Value) !void {
            \\    if (!global_vars_initialized) return;
            \\    const gop = try global_vars.getOrPut(name);
            \\    if (!gop.found_existing) {
            \\        const key_copy = try runtime.runtime_allocator.dupe(u8, name);
            \\        gop.key_ptr.* = key_copy;
            \\        _ = value.retain();
            \\        gop.value_ptr.* = value;
            \\    } else {
            \\        gop.value_ptr.release(runtime.runtime_allocator);
            \\        _ = value.retain();
            \\        gop.value_ptr.* = value;
            \\    }
            \\}
            \\
            \\pub fn unsetGlobalVar(name_val: runtime.Value) !void {
            \\    if (!global_vars_initialized) return;
            \\    if (!name_val.isString()) return;
            \\    const name = name_val.asString().data;
            \\    // 从全局变量表中删除并释放
            \\    if (global_vars.getPtr(name)) |val_ptr| {
            \\        // 通知弱引用系统：对象即将被 unset
            \\        runtime.php_weak_mark_dead(val_ptr.*);
            \\        // Release setGlobalVar的retain
            \\        val_ptr.release(runtime.runtime_allocator);
            \\        // 从表中删除
            \\        if (global_vars.fetchRemove(name)) |kv| {
            \\            runtime.runtime_allocator.free(kv.key);
            \\        }
            \\    }
            \\}
            \\
            \\pub fn getGlobalVarDynamic(name_val: runtime.Value) !runtime.Value {
            \\    const name_str = try name_val.toString(runtime.runtime_allocator);
            \\    defer name_str.release(runtime.runtime_allocator);
            \\    return getGlobalVar(name_str.data);
            \\}
            \\
            \\pub fn setGlobalVarDynamic(name_val: runtime.Value, value: runtime.Value) !void {
            \\    const name_str = try name_val.toString(runtime.runtime_allocator);
            \\    defer name_str.release(runtime.runtime_allocator);
            \\    // Add $ prefix if not present
            \\    if (name_str.data.len > 0 and name_str.data[0] == '$') {
            \\        try setGlobalVar(name_str.data, value);
            \\    } else {
            \\        const prefixed = try std.fmt.allocPrint(runtime.runtime_allocator, "${s}", .{name_str.data});
            \\        defer runtime.runtime_allocator.free(prefixed);
            \\        try setGlobalVar(prefixed, value);
            \\    }
            \\}
            \\
            \\pub fn main() !void {
            \\    const allocator = std.heap.page_allocator;
            \\
            \\    runtime.initRuntime(allocator);
            \\    defer runtime.deinitRuntime();
            \\
            \\    // 初始化全局变量表
            \\    global_vars = std.StringHashMap(runtime.Value).init(allocator);
            \\    global_vars_initialized = true;
            \\
            \\    // 初始化超全局变量
            \\    {
            \\        const superglobal_names = [_][]const u8{ "$_GET", "$_POST", "$_REQUEST", "$_COOKIE", "$_SESSION", "$_ENV", "$_FILES", "$GLOBALS" };
            \\        for (superglobal_names) |name| {
            \\            const key = try allocator.dupe(u8, name);
            \\            const arr = try runtime.PHPArray.init(allocator);
            \\            try global_vars.put(key, runtime.Value.initArray(arr));
            \\        }
            \\        // $_SERVER with basic info
            \\        const server_key = try allocator.dupe(u8, "$_SERVER");
            \\        const server_arr = try runtime.PHPArray.init(allocator);
            \\        const argv_arr = try runtime.PHPArray.init(allocator);
            \\        for (std.os.argv, 0..) |arg_ptr, i| {
            \\            const arg = std.mem.span(arg_ptr);
            \\            const arg_str = try runtime.PHPString.init(allocator, arg);
            \\            try argv_arr.push(allocator, runtime.Value.initString(arg_str));
            \\            if (i == 0) {
            \\                const script_str = try runtime.PHPString.init(allocator, "SCRIPT_FILENAME");
            \\                try server_arr.setByValue(allocator, runtime.Value.initString(script_str), runtime.Value.initString(arg_str));
            \\            }
            \\        }
            \\        const argc_str = try runtime.PHPString.init(allocator, "argc");
            \\        try server_arr.setByValue(allocator, runtime.Value.initString(argc_str), runtime.Value.initInt(@intCast(std.os.argv.len)));
            \\        const argv_str = try runtime.PHPString.init(allocator, "argv");
            \\        try server_arr.setByValue(allocator, runtime.Value.initString(argv_str), runtime.Value.initArray(argv_arr));
            \\        const sapi_str = try runtime.PHPString.init(allocator, "PHP_SAPI");
            \\        const sapi_val = try runtime.PHPString.init(allocator, "cli");
            \\        try server_arr.setByValue(allocator, runtime.Value.initString(sapi_str), runtime.Value.initString(sapi_val));
            \\        try global_vars.put(server_key, runtime.Value.initArray(server_arr));
            \\    }
            \\
            \\    // 注意：cleanupAllClasses 必须在 global_vars 清理之后执行
            \\    // 因为 global_vars 中的对象可能需要调用 __destruct，
            \\    // 而 __destruct 依赖 class_registry（由 cleanupAllClasses 清除）
            \\    // Zig defer 是 LIFO 顺序，所以先注册 cleanupAllClasses，
            \\    // 再注册 global_vars cleanup，这样 global_vars cleanup 先执行
            \\    defer runtime.cleanupAllClasses();
            \\    defer {
            \\        var it = global_vars.valueIterator();
            \\        while (it.next()) |val| {
            \\            val.release(runtime.runtime_allocator);
            \\        }
            \\        global_vars.deinit();
            \\    }
            \\
        );

        // 只在有字符串表时调用 initStaticStrings
        if (has_strings) {
            try writer.writeAll(
                \\    // 初始化静态字符串池（一次性开销）
                \\    initStaticStrings();
                \\
            );
        }

        // 初始化PHP预定义常量
        try writer.writeAll(
            \\    // 初始化PHP预定义常量
            \\    {
            \\        const key1 = try allocator.dupeZ(u8, "COUNT_RECURSIVE");
            \\        try runtime.constants.put(key1, runtime.Value.initInt(1));
            \\        const key2 = try allocator.dupeZ(u8, "COUNT_NORMAL");
            \\        try runtime.constants.put(key2, runtime.Value.initInt(0));
            \\    }
            \\
        );

        try writer.writeAll(
            \\    var alloc_stats_enabled: bool = false;
            \\    if (std.process.getEnvVarOwned(allocator, "ZIGPHP_ALLOC_STATS")) |v| {
            \\        alloc_stats_enabled = true;
            \\        allocator.free(v);
            \\    } else |_| {}
            \\
            \\    defer if (alloc_stats_enabled) {
            \\        const s = runtime.getAllocStats();
            \\        std.debug.print(
            \\            "ALLOC_STATS alloc_bytes={d} alloc_count={d} free_bytes={d} free_count={d} live_bytes={d} live_allocs={d} peak_live_bytes={d} peak_live_allocs={d} php_string_live_objects={d} php_string_live_bytes={d} php_array_live_objects={d} php_object_live_objects={d}\\n",
            \\            .{ s.alloc_bytes, s.alloc_count, s.free_bytes, s.free_count, s.live_bytes, s.live_allocs, s.peak_live_bytes, s.peak_live_allocs, s.php_string_live_objects, s.php_string_live_bytes, s.php_array_live_objects, s.php_object_live_objects },
            \\        );
            \\    };
            \\
            \\    var profiling_enabled: bool = false;
            \\    if (std.process.getEnvVarOwned(allocator, "ZIGPHP_PROFILE")) |v| {
            \\        profiling_enabled = true;
            \\        allocator.free(v);
            \\    } else |_| {}
            \\
            \\    var profiler: runtime.profiler.Profiler = undefined;
            \\    var generator: runtime.flamegraph.FlameGraphGenerator = undefined;
            \\
            \\    if (profiling_enabled) {
            \\        profiler = try runtime.profiler.Profiler.init(allocator, .custom);
            \\        profiler.enable();
            \\        runtime.profiler.setGlobalProfiler(&profiler);
            \\
            \\        generator = try runtime.flamegraph.FlameGraphGenerator.init(allocator, &profiler);
            \\        generator.setMinDisplayTime(0);
            \\        if (std.process.getEnvVarOwned(allocator, "ZIGPHP_PROFILE_INTERVAL_NS")) |s| {
            \\            defer allocator.free(s);
            \\            generator.setSamplingInterval(std.fmt.parseInt(u64, s, 10) catch generator.sampling_interval_ns);
            \\        } else |_| {}
            \\        try generator.startSampling();
            \\    }
            \\
            \\    defer if (profiling_enabled) {
            \\        generator.stopSampling();
            \\
            \\        const folded = generator.generateFoldedFormat(allocator) catch null;
            \\        if (folded) |data| {
            \\            defer allocator.free(data);
            \\            const out = std.fs.cwd().createFile("flamegraph.txt", .{}) catch null;
            \\            if (out) |file| {
            \\                defer file.close();
            \\                _ = file.writeAll(data) catch {};
            \\            }
            \\        }
            \\
            \\        const pb = std.fs.cwd().createFile("profile.pb", .{}) catch null;
            \\        if (pb) |file| {
            \\            defer file.close();
            \\            var buf: [16 * 1024]u8 = undefined;
            \\            var w = file.writer(&buf);
            \\            runtime.pprof.writeCpuProfileFromFlameGraph(allocator, &w.interface, generator.root, generator.sampling_interval_ns) catch {};
            \\            _ = w.end() catch {};
            \\        }
            \\
            \\        generator.deinit();
            \\        runtime.profiler.setGlobalProfiler(null);
            \\        profiler.deinit();
            \\    };
            \\
            \\    // 注册所有类
            \\    registerAllClasses(allocator) catch {};
            \\    // 注册所有函数
            \\    registerAllFunctions() catch {};
            \\
        );

        // 检查是否存在 __main__ 函数
        var has_main = false;
        for (ir_module.functions.items) |func| {
            if (std.mem.eql(u8, func.name, "__main__")) {
                has_main = true;
                break;
            }
        }

        if (has_main) {
            // std.debug.print("Writing main call\n", .{});
            try writer.writeAll(
                \\
                \\    _ = @"__main__"(runtime.Value.initNull(), &[_]runtime.Value{}, allocator) catch |err| {
                \\        if (runtime.hasException()) {
                \\            runtime.php_handle_uncaught_exception();
                \\            return;
                \\        }
                \\        return err;
                \\    };
                \\
            );
            // std.debug.print("After main call\n", .{});
        }

        // std.debug.print("Before final writeAll\n", .{});

        try writer.writeAll(
            \\    _ = runtime.php_go_wait_all(runtime.Value.initNull(), &[_]runtime.Value{}, allocator) catch {};
            \\}
            \\
        );

        // std.debug.print("After writeAll\n", .{});

        // std.debug.print("\n\n=== STARTING POST-PROCESSING ===\n\n", .{});

        // 后处理：修复所有错误的类型转换模式
        const generated_code = try code.toOwnedSlice(self.allocator);

        // std.debug.print("Post-processing: {d} bytes\n", .{generated_code.len});
        // std.debug.print("Skipping all post-processing (array_push fixed)\n", .{});

        // 禁用所有后处理：array_push 已经正确生成代码
        return generated_code;
    }

    /// 生成全局变量
    fn generateGlobalVariable(_: *Self, writer: anytype, global: *const IR.Global) !void {
        // 生成全局变量声明
        try writer.print("var @\"{s}\": runtime.Value = undefined;\n", .{global.name});
    }

    /// 生成函数注册代码
    fn generateFunctionRegistration(self: *Self, writer: anytype, ir_module: *const IR.Module) !void {
        _ = self;
        try writer.writeAll(
            \\
            \\fn registerAllFunctions() !void {
            \\
        );

        for (ir_module.functions.items) |func| {
            // 跳过类方法
            if (std.mem.indexOf(u8, func.name, "::") != null) continue;
            // 跳过内部函数
            if (std.mem.eql(u8, func.name, "__main__")) continue;
            if (!func.register_at_startup) continue;

            // 直接注册函数，因为函数签名已经统一
            try writer.print("    try runtime.registerUserFunctionWithLocation(\"{s}\", @\"{s}\", \"{s}\", {d});\n", .{ func.name, func.name, func.location.file, func.location.line });
            // 注册函数元数据（参数计数，用于反射 API）
            const param_count = func.params.items.len;
            var required_count: usize = 0;
            for (func.params.items) |p| {
                if (!p.has_default and !p.is_variadic) required_count += 1;
            }
            try writer.print("    runtime.registerFunctionMeta(\"{s}\", {d}, {d});\n", .{ func.name, param_count, required_count });
        }

        // 为闭包函数也注册元数据（闭包不走 register_at_startup 但需要反射元数据）
        for (ir_module.functions.items) |func| {
            if (std.mem.startsWith(u8, func.name, "__closure_") or std.mem.startsWith(u8, func.name, "__arrow_")) {
                const cpc = func.params.items.len;
                var crc: usize = 0;
                for (func.params.items) |p| {
                    if (!p.has_default and !p.is_variadic) crc += 1;
                }
                try writer.print("    runtime.registerFunctionMeta(\"{s}\", {d}, {d});\n", .{ func.name, cpc, crc });
            }
        }

        try writer.writeAll(
            \\    // 注册AOT callable hook
            \\    runtime.aot_callable_hook = &aot_dispatch_callable;
            \\}
            \\
            \\// AOT变量函数dispatch：支持所有AOT注册的builtin函数、用户函数和静态方法
            \\fn aot_dispatch_callable(name: []const u8, args: []const runtime.Value, allocator: std.mem.Allocator) anyerror!runtime.Value {
            \\    // 1. 检查是否是静态方法调用: "ClassName::methodName"
            \\    if (std.mem.indexOf(u8, name, "::")) |sep_pos| {
            \\        const class_name = name[0..sep_pos];
            \\        const method_name = name[sep_pos + 2..];
            \\        return aot_dispatch_static_method(class_name, method_name, args, allocator);
            \\    }
            \\
            \\    // 2. 检查是否是用户定义的函数
            \\    const user_func_result = aot_dispatch_user_function(name, args, allocator);
            \\    if (user_func_result) |result| {
            \\        return result;
            \\    } else |err| {
            \\        if (err != error.UnknownFunction) return err;
            \\    }
            \\
            \\    // 3. 检查是否是 builtin 函数
            \\
        );

        // 生成每个builtin函数的dispatch分支
        for (builtin_map.keys(), builtin_map.values()) |key, info| {
            // 只处理is_*类型检查函数（单参数，无allocator）
            if (!std.mem.startsWith(u8, key, "is_")) continue;
            if (info.needs_allocator) continue;
            
            // is_subclass_of 需要 2 个参数，特殊处理
            if (std.mem.eql(u8, key, "is_subclass_of")) {
                try writer.print("    if (std.mem.eql(u8, name, \"{s}\")) {{\n", .{key});
                try writer.print("        if (args.len >= 2) return try runtime.{s}(args[0], args[1]);\n", .{info.runtime_name});
                try writer.print("        return runtime.Value.initNull();\n    }}\n", .{});
                continue;
            }
            
            try writer.print("    if (std.mem.eql(u8, name, \"{s}\")) {{\n", .{key});
            try writer.print("        if (args.len > 0) return try runtime.{s}(args[0]);\n", .{info.runtime_name});
            try writer.print("        return runtime.Value.initNull();\n    }}\n", .{});
        }

        try writer.writeAll(
            \\
            \\    return error.UnknownFunction;
            \\}
            \\
            \\// 分发用户定义的函数调用
            \\fn aot_dispatch_user_function(name: []const u8, args: []const runtime.Value, allocator: std.mem.Allocator) !runtime.Value {
            \\
        );

        // 生成用户函数的dispatch分支
        var has_user_functions = false;
        for (ir_module.functions.items) |func| {
            if (func.is_method) continue; // 跳过方法，只处理全局函数
            
            has_user_functions = true;
            try writer.print("    if (std.mem.eql(u8, name, \"{s}\")) {{\n", .{func.name});
            try writer.print("        return @\"{s}\"(runtime.Value.initNull(), args, allocator);\n", .{func.name});
            try writer.writeAll("    }\n");
        }

        // Note: 如果没有用户函数，标记参数为故意未使用
        if (!has_user_functions) {
            try writer.writeAll("    _ = name;\n");
            try writer.writeAll("    _ = args;\n");
            try writer.writeAll("    _ = allocator;\n");
        }

        try writer.writeAll(
            \\    return error.UnknownFunction;
            \\}
            \\
            \\// 分发静态方法调用
            \\fn aot_dispatch_static_method(class_name: []const u8, method_name: []const u8, args: []const runtime.Value, allocator: std.mem.Allocator) !runtime.Value {
            \\
        );

        // 生成静态方法的dispatch分支
        var has_static_methods = false;
        for (ir_module.types.items) |type_def| {
            if (type_def.kind != .class) continue;
            
            // 先检查这个类是否有静态方法
            var class_has_static_methods = false;
            for (type_def.methods) |method| {
                if (method.is_static) {
                    class_has_static_methods = true;
                    break;
                }
            }
            
            // 只为有静态方法的类生成分支
            if (!class_has_static_methods) continue;
            
            has_static_methods = true;
            try writer.print("    if (std.mem.eql(u8, class_name, \"{s}\")) {{\n", .{type_def.name});
            
            for (type_def.methods) |method| {
                if (!method.is_static) continue;
                
                try writer.print("        if (std.mem.eql(u8, method_name, \"{s}\")) {{\n", .{method.name});
                // 静态方法的完整名称是 "ClassName::methodName"
                try writer.print("            return @\"{s}::{s}\"(runtime.Value.initNull(), args, allocator);\n", .{type_def.name, method.name});
                try writer.writeAll("        }\n");
            }
            
            try writer.writeAll("    }\n");
        }

        // 只有在完全没有任何静态方法时才标记参数未使用
        if (!has_static_methods) {
            try writer.writeAll("    _ = class_name;\n");
            try writer.writeAll("    _ = method_name;\n");
            try writer.writeAll("    _ = args;\n");
            try writer.writeAll("    _ = allocator;\n");
        }

        try writer.writeAll(
            \\    return error.UnknownFunction;
            \\}
            \\
        );
    }

    /// 查找函数定义
    fn findFunction(self: *Self, ir_module: *const IR.Module, name: []const u8) ?*const IR.Function {
        _ = self;
        for (ir_module.functions.items) |func| {
            if (std.mem.eql(u8, func.name, name)) {
                return func;
            }
        }
        return null;
    }

    fn findTypeDef(
        self: *Self,
        ir_module: *const IR.Module,
        name: []const u8,
        kind: IR.TypeDef.Kind,
    ) ?*const IR.TypeDef {
        _ = self;
        for (ir_module.types.items) |td_ptr| {
            const td = td_ptr.*;
            if (td.kind == kind and std.mem.eql(u8, td.name, name)) {
                return td_ptr;
            }
        }
        return null;
    }

    fn findTypeMethod(
        self: *Self,
        type_def: *const IR.TypeDef,
        name: []const u8,
    ) ?IR.TypeDef.Method {
        _ = self;
        for (type_def.methods) |method| {
            if (std.mem.eql(u8, method.name, name)) return method;
        }
        return null;
    }

    fn findTypeProperty(
        self: *Self,
        type_def: *const IR.TypeDef,
        name: []const u8,
    ) ?IR.TypeDef.Property {
        _ = self;
        for (type_def.properties) |prop| {
            if (std.mem.eql(u8, prop.name, name)) return prop;
        }
        return null;
    }

    fn findTypeConstant(
        self: *Self,
        type_def: *const IR.TypeDef,
        name: []const u8,
    ) ?IR.TypeDef.Constant {
        _ = self;
        for (type_def.constants) |constant| {
            if (std.mem.eql(u8, constant.name, name)) return constant;
        }
        return null;
    }

    fn constInstructionsEqual(
        self: *Self,
        lhs: ?*const IR.Instruction,
        rhs: ?*const IR.Instruction,
    ) bool {
        _ = self;
        if (lhs == null and rhs == null) return true;
        if (lhs == null or rhs == null) return false;

        const l = lhs.?;
        const r = rhs.?;
        return switch (l.op) {
            .const_int => |lv| switch (r.op) {
                .const_int => |rv| lv == rv,
                else => false,
            },
            .const_float => |lv| switch (r.op) {
                .const_float => |rv| lv == rv,
                else => false,
            },
            .const_bool => |lv| switch (r.op) {
                .const_bool => |rv| lv == rv,
                else => false,
            },
            .const_null => switch (r.op) {
                .const_null => true,
                else => false,
            },
            .const_string => |lv| switch (r.op) {
                .const_string => |rv| lv == rv,
                else => false,
            },
            .array_new => switch (r.op) {
                .array_new => true,
                else => false,
            },
            else => false,
        };
    }

    fn constantsEqual(
        self: *Self,
        lhs: IR.TypeDef.ConstantValue,
        rhs: IR.TypeDef.ConstantValue,
    ) bool {
        _ = self;
        return switch (lhs) {
            .int => |lv| switch (rhs) {
                .int => |rv| lv == rv,
                else => false,
            },
            .float => |lv| switch (rhs) {
                .float => |rv| lv == rv,
                else => false,
            },
            .string => |lv| switch (rhs) {
                .string => |rv| std.mem.eql(u8, lv, rv),
                else => false,
            },
            .bool => |lv| switch (rhs) {
                .bool => |rv| lv == rv,
                else => false,
            },
            .null => switch (rhs) {
                .null => true,
                else => false,
            },
        };
    }

    fn traitPropertiesCompatible(
        self: *Self,
        lhs: IR.TypeDef.Property,
        rhs: IR.TypeDef.Property,
    ) bool {
        return lhs.is_static == rhs.is_static and
            lhs.visibility == rhs.visibility and
            std.meta.eql(lhs.type_, rhs.type_) and
            self.constInstructionsEqual(lhs.default_value, rhs.default_value);
    }

    fn traitConstantsCompatible(
        self: *Self,
        lhs: IR.TypeDef.Constant,
        rhs: IR.TypeDef.Constant,
    ) bool {
        return lhs.visibility == rhs.visibility and
            self.constantsEqual(lhs.value, rhs.value);
    }

    fn traitMethodsEquivalent(
        self: *Self,
        lhs: ComposedTraitMethod,
        rhs: ComposedTraitMethod,
    ) bool {
        _ = self;
        return std.mem.eql(u8, lhs.exposed_name, rhs.exposed_name) and
            std.mem.eql(u8, lhs.function_trait, rhs.function_trait) and
            std.mem.eql(u8, lhs.original_name, rhs.original_name) and
            lhs.visibility == rhs.visibility and
            lhs.is_static == rhs.is_static;
    }

    fn isAbstractTraitMethod(self: *Self, method: ComposedTraitMethod) bool {
        _ = self;
        return method.is_abstract;
    }

    fn appendTraitProperty(
        self: *Self,
        list: *std.ArrayListUnmanaged(ComposedTraitProperty),
        prop: IR.TypeDef.Property,
    ) !void {
        for (list.items) |existing| {
            if (!std.mem.eql(u8, existing.prop.name, prop.name)) continue;
            if (!self.traitPropertiesCompatible(existing.prop, prop)) {
                return error.TraitPropertyConflict;
            }
            return;
        }
        try list.append(self.allocator, .{ .prop = prop });
    }

    fn appendTraitConstant(
        self: *Self,
        list: *std.ArrayListUnmanaged(ComposedTraitConstant),
        constant: IR.TypeDef.Constant,
    ) !void {
        for (list.items) |existing| {
            if (!std.mem.eql(u8, existing.constant.name, constant.name)) continue;
            if (!self.traitConstantsCompatible(existing.constant, constant)) {
                return error.TraitConstantConflict;
            }
            return;
        }
        try list.append(self.allocator, .{ .constant = constant });
    }

    fn appendUniqueTraitMethod(
        self: *Self,
        list: *std.ArrayListUnmanaged(ComposedTraitMethod),
        method: ComposedTraitMethod,
    ) !void {
        for (list.items, 0..) |existing, idx| {
            if (!std.mem.eql(u8, existing.exposed_name, method.exposed_name)) {
                continue;
            }
            
            // 如果方法完全等价，跳过
            if (self.traitMethodsEquivalent(existing, method)) return;
            
            // 检查是否是抽象方法与具体实现的组合
            const existing_is_abstract = self.isAbstractTraitMethod(existing);
            const method_is_abstract = self.isAbstractTraitMethod(method);
            
            if (existing_is_abstract and !method_is_abstract) {
                // 现有方法是抽象的，新方法是具体的 -> 用具体实现替换抽象方法
                list.items[idx] = method;
                return;
            } else if (!existing_is_abstract and method_is_abstract) {
                // 现有方法是具体的，新方法是抽象的 -> 保留具体实现，忽略抽象方法
                return;
            }
            
            // 两个都是具体实现，或两个都是抽象方法 -> 冲突
            return error.TraitMethodConflict;
        }
        try list.append(self.allocator, method);
    }

    fn resolveTraitMethodTarget(
        self: *Self,
        methods: []ComposedTraitMethod,
        method_ref: IR.TypeDef.TraitMethodRef,
    ) !usize {
        _ = self;
        var found_idx: ?usize = null;
        for (methods, 0..) |method, idx| {
            if (!std.mem.eql(u8, method.exposed_name, method_ref.method_name)) {
                continue;
            }
            if (method_ref.trait_name) |trait_name| {
                if (!std.mem.eql(u8, method.provider_trait, trait_name)) continue;
            }
            if (found_idx != null) return error.AmbiguousTraitMethodReference;
            found_idx = idx;
        }
        return found_idx orelse error.UnknownTraitMethodReference;
    }

    fn applyTraitAdaptations(
        self: *Self,
        type_def: *const IR.TypeDef,
        methods: *std.ArrayListUnmanaged(ComposedTraitMethod),
    ) !void {
        const base_methods = try self.allocator.dupe(
            ComposedTraitMethod,
            methods.items,
        );
        defer self.allocator.free(base_methods);

        for (type_def.trait_adaptations) |adaptation| {
            switch (adaptation) {
                .insteadof => |data| {
                    _ = try self.resolveTraitMethodTarget(
                        methods.items,
                        data.preferred,
                    );
                    var write_idx: usize = 0;
                    for (methods.items) |method| {
                        var excluded = false;
                        if (std.mem.eql(
                            u8,
                            method.exposed_name,
                            data.preferred.method_name,
                        )) {
                            for (data.excluded_traits) |excluded_trait| {
                                if (std.mem.eql(
                                    u8,
                                    method.provider_trait,
                                    excluded_trait,
                                )) {
                                    excluded = true;
                                    break;
                                }
                            }
                        }
                        if (!excluded) {
                            methods.items[write_idx] = method;
                            write_idx += 1;
                        }
                    }
                    methods.items.len = write_idx;
                },
                .alias => |data| {
                    if (data.alias) |alias_name| {
                        const target_idx = try self.resolveTraitMethodTarget(
                            base_methods,
                            data.original,
                        );
                        var alias_method = base_methods[target_idx];
                        alias_method.exposed_name = alias_name;
                        if (data.visibility) |visibility| {
                            alias_method.visibility = visibility;
                        }
                        try methods.append(self.allocator, alias_method);
                    } else if (data.visibility) |visibility| {
                        const target_idx = self.resolveTraitMethodTarget(
                            methods.items,
                            data.original,
                        ) catch continue;
                        methods.items[target_idx].visibility = visibility;
                    }
                },
            }
        }
    }

    fn resolveTraitExports(
        self: *Self,
        ir_module: *const IR.Module,
        trait_name: []const u8,
        out_methods: *std.ArrayListUnmanaged(ComposedTraitMethod),
        out_properties: *std.ArrayListUnmanaged(ComposedTraitProperty),
        out_constants: *std.ArrayListUnmanaged(ComposedTraitConstant),
    ) !void {
        const trait_td = self.findTypeDef(ir_module, trait_name, .trait) orelse {
            return error.TraitNotFound;
        };

        var imported_methods = std.ArrayListUnmanaged(ComposedTraitMethod){};
        var resolved_methods = std.ArrayListUnmanaged(ComposedTraitMethod){};
        var imported_properties = std.ArrayListUnmanaged(ComposedTraitProperty){};
        var resolved_properties = std.ArrayListUnmanaged(ComposedTraitProperty){};
        var imported_constants = std.ArrayListUnmanaged(ComposedTraitConstant){};
        var resolved_constants = std.ArrayListUnmanaged(ComposedTraitConstant){};

        for (trait_td.traits) |used_trait_name| {
            var nested_methods = std.ArrayListUnmanaged(ComposedTraitMethod){};
            var nested_properties = std.ArrayListUnmanaged(ComposedTraitProperty){};
            var nested_constants = std.ArrayListUnmanaged(ComposedTraitConstant){};
            try self.resolveTraitExports(
                ir_module,
                used_trait_name,
                &nested_methods,
                &nested_properties,
                &nested_constants,
            );

            for (nested_methods.items) |method| {
                var imported = method;
                imported.provider_trait = used_trait_name;
                try imported_methods.append(self.allocator, imported);
            }
            for (nested_properties.items) |prop| {
                try self.appendTraitProperty(&imported_properties, prop.prop);
            }
            for (nested_constants.items) |constant| {
                try self.appendTraitConstant(
                    &imported_constants,
                    constant.constant,
                );
            }
        }

        try self.applyTraitAdaptations(trait_td, &imported_methods);

        // 如果trait自己定义了某个方法，移除所有同名的导入方法
        // 这样trait自己的方法会覆盖导入的方法，避免冲突
        for (trait_td.methods) |own_method| {
            var i: usize = 0;
            while (i < imported_methods.items.len) {
                if (std.mem.eql(u8, imported_methods.items[i].exposed_name, own_method.name)) {
                    _ = imported_methods.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }

        for (imported_methods.items) |method| {
            try self.appendUniqueTraitMethod(&resolved_methods, method);
        }

        for (trait_td.methods) |method| {
            try self.appendUniqueTraitMethod(&resolved_methods, .{
                .provider_trait = trait_td.name,
                .function_trait = trait_td.name,
                .exposed_name = method.name,
                .original_name = method.name,
                .visibility = method.visibility,
                .is_static = method.is_static,
                .is_abstract = method.is_abstract,
            });
        }

        for (imported_properties.items) |prop| {
            if (self.findTypeProperty(trait_td, prop.prop.name)) |own_prop| {
                if (!self.traitPropertiesCompatible(own_prop, prop.prop)) {
                    return error.TraitPropertyConflict;
                }
                continue;
            }
            try self.appendTraitProperty(&resolved_properties, prop.prop);
        }
        for (trait_td.properties) |prop| {
            try self.appendTraitProperty(&resolved_properties, prop);
        }

        for (imported_constants.items) |constant| {
            if (self.findTypeConstant(trait_td, constant.constant.name)) |own_constant| {
                if (!self.traitConstantsCompatible(
                    own_constant,
                    constant.constant,
                )) {
                    return error.TraitConstantConflict;
                }
                continue;
            }
            try self.appendTraitConstant(&resolved_constants, constant.constant);
        }
        for (trait_td.constants) |constant| {
            try self.appendTraitConstant(&resolved_constants, constant);
        }

        for (resolved_methods.items) |method| {
            var exported = method;
            exported.provider_trait = trait_td.name;
            try out_methods.append(self.allocator, exported);
        }
        for (resolved_properties.items) |prop| {
            try self.appendTraitProperty(out_properties, prop.prop);
        }
        for (resolved_constants.items) |constant| {
            try self.appendTraitConstant(out_constants, constant.constant);
        }
    }

    fn resolveClassTraitMembers(
        self: *Self,
        ir_module: *const IR.Module,
        class_td: *const IR.TypeDef,
        out_methods: *std.ArrayListUnmanaged(ComposedTraitMethod),
        out_properties: *std.ArrayListUnmanaged(ComposedTraitProperty),
        out_constants: *std.ArrayListUnmanaged(ComposedTraitConstant),
    ) !void {
        var imported_methods = std.ArrayListUnmanaged(ComposedTraitMethod){};
        var imported_properties = std.ArrayListUnmanaged(ComposedTraitProperty){};
        var imported_constants = std.ArrayListUnmanaged(ComposedTraitConstant){};

        for (class_td.traits) |trait_name| {
            try self.resolveTraitExports(
                ir_module,
                trait_name,
                &imported_methods,
                &imported_properties,
                &imported_constants,
            );
        }

        try self.applyTraitAdaptations(class_td, &imported_methods);

        for (imported_methods.items) |method| {
            if (self.findTypeMethod(class_td, method.exposed_name) != null) {
                continue;
            }
            try self.appendUniqueTraitMethod(out_methods, method);
        }

        for (imported_properties.items) |prop| {
            if (self.findTypeProperty(class_td, prop.prop.name)) |own_prop| {
                if (!self.traitPropertiesCompatible(own_prop, prop.prop)) {
                    return error.TraitPropertyConflict;
                }
                continue;
            }
            try self.appendTraitProperty(out_properties, prop.prop);
        }

        for (imported_constants.items) |constant| {
            if (self.findTypeConstant(class_td, constant.constant.name)) |own_constant| {
                if (!self.traitConstantsCompatible(
                    own_constant,
                    constant.constant,
                )) {
                    return error.TraitConstantConflict;
                }
                continue;
            }
            try self.appendTraitConstant(out_constants, constant.constant);
        }
    }

    fn emitMethodRegistration(
        self: *Self,
        writer: anytype,
        meta_name: []const u8,
        exposed_name: []const u8,
        function_trait: []const u8,
        original_name: []const u8,
        visibility: IR.TypeDef.Visibility,
        is_static: bool,
    ) !void {
        const full_method_name = try std.fmt.allocPrint(
            self.allocator,
            "{s}::{s}",
            .{ function_trait, original_name },
        );
        defer self.allocator.free(full_method_name);
        const escaped_method_name = try escapeBackslashes(
            self.allocator,
            full_method_name,
        );
        defer self.allocator.free(escaped_method_name);
        // 从IR函数定义获取参数计数
        var pc: usize = 0;
        var rp: usize = 0;
        if (self.ir_module) |ir_mod| {
            if (self.findFunction(ir_mod, full_method_name)) |func| {
                pc = func.params.items.len;
                for (func.params.items) |p| {
                    if (!p.has_default and !p.is_variadic) rp += 1;
                }
            }
        }
        try writer.print(
            "    try {s}_meta.addMethod(.{{ .name = \"{s}\", .func = @\"{s}\", .is_static = {}, .is_public = {}, .is_protected = {}, .is_private = {}, .param_count = {d}, .required_params = {d} }});\n",
            .{
                meta_name,
                exposed_name,
                escaped_method_name,
                is_static,
                visibility == .public,
                visibility == .protected,
                visibility == .private,
                pc,
                rp,
            },
        );
    }

    /// 检查函数是否有返回值
    fn functionHasReturnValue(self: *Self, func: *const IR.Function) bool {
        _ = self;
        for (func.blocks.items) |block| {
            if (block.terminator) |term| {
                if (term == .ret and term.ret != null) {
                    return true;
                }
            }
        }
        return false;
    }

    /// 检查参数是否被使用
    fn isParamUsed(self: *Self, func: *const IR.Function, param_name: []const u8) bool {
        _ = self;
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.op == .param) {
                    if (std.mem.eql(u8, inst.op.param.name, param_name)) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    /// 生成类注册代码
    fn generateClassRegistration(self: *Self, writer: anytype, ir_module: *const IR.Module) !void {
        var class_count: usize = 0;
        var class_names: [64][]const u8 = undefined; // 完整类名（用于注册）
        var class_short_names: [64][]const u8 = undefined; // 短名（用于变量名）
        var type_def_idx: [64]?usize = [_]?usize{null} ** 64;

        for (ir_module.types.items, 0..) |td_ptr, idx| {
            const td = td_ptr.*;
            // 收集所有类型：class, interface, trait, enum
            if (td.kind != .class and td.kind != .@"enum" and td.kind != .interface and td.kind != .trait) continue;
            if (class_count >= 64) break;
            class_names[class_count] = td.name;
            class_short_names[class_count] = getLastPartOfClassName(td.name);
            type_def_idx[class_count] = idx;
            class_count += 1;
        }

        if (class_count == 0) {
            try writer.writeAll(
                \\
                \\fn registerAllClasses(allocator: std.mem.Allocator) !void {
                \\    try runtime.ClassMeta.registerExceptionClass(allocator);
                \\}
                \\
            );
            return;
        }

        try writer.writeAll(
            \\
            \\fn registerAllClasses(allocator: std.mem.Allocator) !void {
            \\    try runtime.ClassMeta.registerExceptionClass(allocator);
            \\
        );

        for (0..class_count) |ci| {
            const full_cname = class_names[ci]; // 完整类名
            const short_cname = class_short_names[ci]; // 短名（用于变量名）
            // ✅ 转义完整类名中的反斜杠
            const escaped_full_cname = try escapeBackslashes(self.allocator, full_cname);
            defer self.allocator.free(escaped_full_cname);
            // ✅ 使用短名作为变量名，但注册时使用完整类名
            try writer.print("    const {s}_meta = try runtime.ClassMeta.init(allocator, \"{s}\");\n", .{ short_cname, escaped_full_cname });

            if (type_def_idx[ci]) |tdi| {
                const td_ptr = ir_module.types.items[tdi];
                const td = td_ptr.*;
                // 设置 is_interface 和 is_trait 标志
                if (td.kind == .interface) {
                    try writer.print("    {s}_meta.is_interface = true;\n", .{short_cname});
                } else if (td.kind == .trait) {
                    try writer.print("    {s}_meta.is_trait = true;\n", .{short_cname});
                }
            }

            if (type_def_idx[ci]) |tdi| {
                const td_ptr = ir_module.types.items[tdi];
                const td = td_ptr.*;
                var trait_methods = std.ArrayListUnmanaged(ComposedTraitMethod){};
                var trait_properties = std.ArrayListUnmanaged(ComposedTraitProperty){};
                var trait_constants = std.ArrayListUnmanaged(ComposedTraitConstant){};
                try self.resolveClassTraitMembers(
                    ir_module,
                    td_ptr,
                    &trait_methods,
                    &trait_properties,
                    &trait_constants,
                );

                for (td.properties) |prop| {
                    const is_public = prop.visibility == .public;
                    try writer.print("    try {s}_meta.addProperty(.{{ .name = \"{s}\", .default_value = ", .{ short_cname, prop.name });
                    if (prop.default_value) |dv| {
                        switch (dv.op) {
                            .const_int => |v| try writer.print("runtime.Value.initInt({d})", .{v}),
                            .const_float => |v| try writer.print("runtime.Value.initFloat({d})", .{v}),
                            .const_bool => |v| try writer.writeAll(if (v) "runtime.Value.initBool(true)" else "runtime.Value.initBool(false)"),
                            .const_null => try writer.writeAll("runtime.Value.initNull()"),
                            .const_string => |sid| try writer.print(
                                "runtime.Value.initString(try runtime.PHPString.init(runtime.runtime_allocator, string_table[{d}]))",
                                .{sid},
                            ),
                            .array_new => try writer.writeAll("runtime.Value.initArray(try runtime.PHPArray.init(runtime.runtime_allocator))"),
                            else => try writer.writeAll("runtime.Value.initNull()"),
                        }
                    } else {
                        try writer.writeAll("runtime.Value.initNull()");
                    }
                    try writer.print(", .is_static = {}, .is_public = {}, .is_readonly = false }});\n", .{ prop.is_static, is_public });

                    if (prop.is_static) {
                        try writer.print("    try {s}_meta.setStaticProperty(\"{s}\", ", .{ short_cname, prop.name });
                        if (prop.default_value) |dv| {
                            switch (dv.op) {
                                .const_int => |v| try writer.print("runtime.Value.initInt({d})", .{v}),
                                .const_float => |v| try writer.print("runtime.Value.initFloat({d})", .{v}),
                                .const_bool => |v| try writer.writeAll(if (v) "runtime.Value.initBool(true)" else "runtime.Value.initBool(false)"),
                                .const_null => try writer.writeAll("runtime.Value.initNull()"),
                                .const_string => |sid| try writer.print(
                                    "runtime.Value.initString(try runtime.PHPString.init(runtime.runtime_allocator, string_table[{d}]))",
                                    .{sid},
                                ),
                                .array_new => try writer.writeAll("runtime.Value.initArray(try runtime.PHPArray.init(runtime.runtime_allocator))"),
                                else => try writer.writeAll("runtime.Value.initNull()"),
                            }
                        } else {
                            try writer.writeAll("runtime.Value.initNull()");
                        }
                        try writer.writeAll(");\n");
                    }
                }
                for (trait_properties.items) |trait_prop_info| {
                    const prop = trait_prop_info.prop;
                    const is_public = prop.visibility == .public;
                    try writer.print(
                        "    if ({s}_meta.properties.get(\"{s}\") == null) {{\n",
                        .{ short_cname, prop.name },
                    );
                    try writer.print(
                        "        try {s}_meta.addProperty(.{{ .name = \"{s}\", .default_value = ",
                        .{ short_cname, prop.name },
                    );
                    if (prop.default_value) |dv| {
                        switch (dv.op) {
                            .const_int => |v| try writer.print("runtime.Value.initInt({d})", .{v}),
                            .const_float => |v| try writer.print("runtime.Value.initFloat({d})", .{v}),
                            .const_bool => |v| try writer.writeAll(if (v) "runtime.Value.initBool(true)" else "runtime.Value.initBool(false)"),
                            .const_null => try writer.writeAll("runtime.Value.initNull()"),
                            .const_string => |sid| try writer.print(
                                "runtime.Value.initString(try runtime.PHPString.init(runtime.runtime_allocator, string_table[{d}]))",
                                .{sid},
                            ),
                            .array_new => try writer.writeAll("runtime.Value.initInt(-1)"),
                            else => try writer.writeAll("runtime.Value.initNull()"),
                        }
                    } else {
                        try writer.writeAll("runtime.Value.initNull()");
                    }
                    try writer.print(", .is_static = {}, .is_public = {}, .is_readonly = false }});\n", .{ prop.is_static, is_public });

                    if (prop.is_static) {
                        try writer.print("        try {s}_meta.setStaticProperty(\"{s}\", ", .{ short_cname, prop.name });
                        if (prop.default_value) |dv| {
                            switch (dv.op) {
                                .const_int => |v| try writer.print("runtime.Value.initInt({d})", .{v}),
                                .const_float => |v| try writer.print("runtime.Value.initFloat({d})", .{v}),
                                .const_bool => |v| try writer.writeAll(if (v) "runtime.Value.initBool(true)" else "runtime.Value.initBool(false)"),
                                .const_null => try writer.writeAll("runtime.Value.initNull()"),
                                .const_string => |sid| try writer.print(
                                    "runtime.Value.initString(try runtime.PHPString.init(runtime.runtime_allocator, string_table[{d}]))",
                                    .{sid},
                                ),
                                .array_new => try writer.writeAll("runtime.Value.initArray(try runtime.PHPArray.init(runtime.runtime_allocator))"),
                                else => try writer.writeAll("runtime.Value.initNull()"),
                            }
                        } else {
                            try writer.writeAll("runtime.Value.initNull()");
                        }
                        try writer.writeAll(");\n");
                    }
                    try writer.writeAll("    }\n");
                }

                for (td.methods) |method| {
                    try self.emitMethodRegistration(
                        writer,
                        short_cname,
                        method.name,
                        full_cname,
                        method.name,
                        method.visibility,
                        method.is_static,
                    );
                }
                for (trait_methods.items) |method| {
                    try writer.print(
                        "    if ({s}_meta.methods.get(\"{s}\") == null) ",
                        .{ short_cname, method.exposed_name },
                    );
                    try self.emitMethodRegistration(
                        writer,
                        short_cname,
                        method.exposed_name,
                        method.function_trait,
                        method.original_name,
                        method.visibility,
                        method.is_static,
                    );
                }
            }

            // 注册类上的 PHP attributes (#[...])
            if (type_def_idx[ci]) |tdi3| {
                const td3 = ir_module.types.items[tdi3].*;
                if (td3.attributes.len > 0) {
                    try writer.print("    {{\n", .{});
                    try writer.print("        const attr_arr = try runtime.PHPArray.init(allocator);\n", .{});
                    for (td3.attributes) |attr| {
                        const escaped_attr = try self.escapeString(attr.name);
                        defer self.allocator.free(escaped_attr);
                        try writer.print("        {{\n", .{});
                        try writer.print("            const attr_obj = try runtime.php_object_new(\"ReflectionAttribute\", allocator);\n", .{});
                        try writer.print("            const attr_o = runtime.Value_asObject(attr_obj);\n", .{});
                        try writer.print("            try attr_o.setProperty(\"__name\", runtime.Value.initString(try runtime.PHPString.init(allocator, \"{s}\")));\n", .{escaped_attr});
                        // 存储参数数组
                        try writer.print("            const args_arr = try runtime.PHPArray.init(allocator);\n", .{});
                        for (attr.args) |arg| {
                            const escaped_arg = try self.escapeString(arg);
                            defer self.allocator.free(escaped_arg);
                            try writer.print("            try args_arr.push(allocator, runtime.Value.initString(try runtime.PHPString.init(allocator, \"{s}\")));\n", .{escaped_arg});
                        }
                        try writer.print("            try attr_o.setProperty(\"__args\", runtime.Value.initArray(args_arr));\n", .{});
                        try writer.print("            try attr_arr.push(allocator, attr_obj);\n", .{});
                        try writer.print("        }}\n", .{});
                    }
                    try writer.print("        try {s}_meta.setStaticProperty(\"__attributes\", runtime.Value.initArray(attr_arr));\n", .{short_cname});
                    try writer.print("    }}\n", .{});
                }
            }

            // 设置魔术方法指针
            try writer.print("    if ({s}_meta.methods.get(\"__toString\")) |m| {s}_meta.magic_toString = m.func;\n", .{ short_cname, short_cname });

            // 先注册类，使 enum case 的 php_object_new 能找到 ClassMeta
            try writer.print("    try runtime.registerClass({s}_meta);\n", .{short_cname});

            // Register enum cases as static properties（必须在 registerClass 之后）
            if (type_def_idx[ci]) |tdi2| {
                const td2 = ir_module.types.items[tdi2].*;
                if (td2.kind == .@"enum") {
                    for (td2.enum_cases) |ec| {
                        const escaped_case = try self.escapeString(ec.name);
                        defer self.allocator.free(escaped_case);
                        const escaped_enum = try escapeBackslashes(self.allocator, td2.name);
                        defer self.allocator.free(escaped_enum);
                        try writer.writeAll("    {\n");
                        try writer.print("        const enum_val = try runtime.php_object_new(\"{s}\", allocator);\n", .{escaped_enum});
                        try writer.print("        const enum_obj = runtime.Value_asObject(enum_val);\n", .{});
                        try writer.print("        try enum_obj.setProperty(\"name\", runtime.Value.initString(try runtime.PHPString.init(allocator, \"{s}\")));\n", .{escaped_case});
                        if (ec.value) |cv| {
                            switch (cv) {
                                .int => |v| try writer.print("        try enum_obj.setProperty(\"value\", runtime.Value.initInt({d}));\n", .{v}),
                                .float => |v| try writer.print("        try enum_obj.setProperty(\"value\", runtime.Value.initFloat({d}));\n", .{v}),
                                .string => |s| {
                                    const escaped_val = try self.escapeString(s);
                                    defer self.allocator.free(escaped_val);
                                    try writer.print("        try enum_obj.setProperty(\"value\", runtime.Value.initString(try runtime.PHPString.init(allocator, \"{s}\")));\n", .{escaped_val});
                                },
                                .bool => |b| try writer.print("        try enum_obj.setProperty(\"value\", runtime.Value.initBool({s}));\n", .{if (b) "true" else "false"}),
                                .null => try writer.writeAll("        try enum_obj.setProperty(\"value\", runtime.Value.initNull());\n"),
                            }
                        }
                        try writer.print("        try {s}_meta.setStaticProperty(\"{s}\", enum_val);\n", .{ short_cname, escaped_case });
                        try writer.writeAll("    }\n");
                    }
                    // 存储有序的 case 名称列表
                    try writer.writeAll("    {\n");
                    try writer.print("        const case_arr = try runtime.PHPArray.init(allocator);\n", .{});
                    for (td2.enum_cases) |ec| {
                        const escaped_cn = try self.escapeString(ec.name);
                        defer self.allocator.free(escaped_cn);
                        try writer.print("        try case_arr.push(allocator, runtime.Value.initString(try runtime.PHPString.init(allocator, \"{s}\")));\n", .{escaped_cn});
                    }
                    try writer.print("        try {s}_meta.setStaticProperty(\"__enum_cases\", runtime.Value.initArray(case_arr));\n", .{short_cname});
                    try writer.writeAll("    }\n");
                }
            }
        }

        // 注册含静态属性的 trait（使 self::$prop 在 trait 方法中可用）
        for (ir_module.types.items) |td_ptr| {
            const td = td_ptr.*;
            if (td.kind != .trait) continue;

            var has_static = false;
            for (td.properties) |prop| {
                if (prop.is_static) {
                    has_static = true;
                    break;
                }
            }
            if (!has_static) continue;

            const tname = td.name;
            try writer.print("    const {s}_meta = try runtime.ClassMeta.init(allocator, \"{s}\");\n", .{ tname, tname });

            for (td.properties) |prop| {
                if (!prop.is_static) continue;
                const is_public = prop.visibility == .public;
                try writer.print("    try {s}_meta.addProperty(.{{ .name = \"{s}\", .default_value = ", .{ tname, prop.name });
                if (prop.default_value) |dv| {
                    switch (dv.op) {
                        .const_int => |v| try writer.print("runtime.Value.initInt({d})", .{v}),
                        .const_float => |v| try writer.print("runtime.Value.initFloat({d})", .{v}),
                        .const_bool => |v| try writer.writeAll(if (v) "runtime.Value.initBool(true)" else "runtime.Value.initBool(false)"),
                        .const_null => try writer.writeAll("runtime.Value.initNull()"),
                        .const_string => |sid| try writer.print(
                            "runtime.Value.initString(try runtime.PHPString.init(runtime.runtime_allocator, string_table[{d}]))",
                            .{sid},
                        ),
                        .array_new => try writer.writeAll("runtime.Value.initArray(try runtime.PHPArray.init(runtime.runtime_allocator))"),
                        else => try writer.writeAll("runtime.Value.initNull()"),
                    }
                } else {
                    try writer.writeAll("runtime.Value.initNull()");
                }
                try writer.print(", .is_static = true, .is_public = {}, .is_readonly = false }});\n", .{is_public});

                try writer.print("    try {s}_meta.setStaticProperty(\"{s}\", ", .{ tname, prop.name });
                if (prop.default_value) |dv| {
                    switch (dv.op) {
                        .const_int => |v| try writer.print("runtime.Value.initInt({d})", .{v}),
                        .const_float => |v| try writer.print("runtime.Value.initFloat({d})", .{v}),
                        .const_bool => |v| try writer.writeAll(if (v) "runtime.Value.initBool(true)" else "runtime.Value.initBool(false)"),
                        .const_null => try writer.writeAll("runtime.Value.initNull()"),
                        .const_string => |sid| try writer.print(
                            "runtime.Value.initString(try runtime.PHPString.init(runtime.runtime_allocator, string_table[{d}]))",
                            .{sid},
                        ),
                        .array_new => try writer.writeAll("runtime.Value.initArray(try runtime.PHPArray.init(runtime.runtime_allocator))"),
                        else => try writer.writeAll("runtime.Value.initNull()"),
                    }
                } else {
                    try writer.writeAll("runtime.Value.initNull()");
                }
                try writer.writeAll(");\n");
            }

            try writer.print("    try runtime.registerClass({s}_meta);\n", .{tname});
        }

        // 初始化类常量
        for (0..class_count) |ci| {
            if (type_def_idx[ci]) |tdi| {
                const td_ptr = ir_module.types.items[tdi];
                const td = td_ptr.*;
                const full_cname = class_names[ci];
                const short_cname = class_short_names[ci];
                _ = short_cname; // 这个循环中只需要full_cname
                var trait_methods = std.ArrayListUnmanaged(ComposedTraitMethod){};
                var trait_properties = std.ArrayListUnmanaged(ComposedTraitProperty){};
                var trait_constants = std.ArrayListUnmanaged(ComposedTraitConstant){};
                try self.resolveClassTraitMembers(
                    ir_module,
                    td_ptr,
                    &trait_methods,
                    &trait_properties,
                    &trait_constants,
                );

                // ✅ 转义完整类名
                const escaped_full_cname = try escapeBackslashes(self.allocator, full_cname);
                defer self.allocator.free(escaped_full_cname);

                for (td.constants) |const_info| {
                    const value_code = switch (const_info.value) {
                        .int => |v| try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt({d})", .{v}),
                        .float => |v| try std.fmt.allocPrint(self.allocator, "runtime.Value.initFloat({d})", .{v}),
                        .string => |s| blk: {
                            const escaped = try self.escapeString(s);
                            defer self.allocator.free(escaped);
                            break :blk try std.fmt.allocPrint(self.allocator, "runtime.Value.initString(try runtime.PHPString.init(runtime.runtime_allocator, \"{s}\"))", .{escaped});
                        },
                        .bool => |b| try std.fmt.allocPrint(self.allocator, "runtime.Value.initBool({s})", .{if (b) "true" else "false"}),
                        .null => try std.fmt.allocPrint(self.allocator, "runtime.Value.initNull()", .{}),
                    };
                    defer self.allocator.free(value_code);

                    const escaped_name = try self.escapeString(const_info.name);
                    defer self.allocator.free(escaped_name);

                    // ✅ 使用完整类名设置静态属性
                    try writer.print("    _ = try runtime.php_set_static_property(\"{s}\", \"{s}\", {s});\n", .{ escaped_full_cname, escaped_name, value_code });
                }

                for (trait_constants.items) |trait_const_info| {
                    const const_info = trait_const_info.constant;
                    const value_code = switch (const_info.value) {
                        .int => |v| try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt({d})", .{v}),
                        .float => |v| try std.fmt.allocPrint(self.allocator, "runtime.Value.initFloat({d})", .{v}),
                        .string => |s| blk: {
                            const escaped = try self.escapeString(s);
                            defer self.allocator.free(escaped);
                            break :blk try std.fmt.allocPrint(self.allocator, "runtime.Value.initString(try runtime.PHPString.init(runtime.runtime_allocator, \"{s}\"))", .{escaped});
                        },
                        .bool => |b| try std.fmt.allocPrint(self.allocator, "runtime.Value.initBool({s})", .{if (b) "true" else "false"}),
                        .null => try std.fmt.allocPrint(self.allocator, "runtime.Value.initNull()", .{}),
                    };
                    defer self.allocator.free(value_code);

                    const escaped_name = try self.escapeString(const_info.name);
                    defer self.allocator.free(escaped_name);

                    try writer.print("    _ = try runtime.php_set_static_property(\"{s}\", \"{s}\", {s});\n", .{ escaped_full_cname, escaped_name, value_code });
                }
            }
        }

        for (0..class_count) |ci| {
            if (type_def_idx[ci]) |tdi| {
                const td = ir_module.types.items[tdi].*;
                const short_cname = class_short_names[ci];
                if (td.parent) |parent_name| {
                    const escaped_parent = try self.escapeString(parent_name);
                    defer self.allocator.free(escaped_parent);
                    try writer.print(
                        "    {s}_meta.parent = if (runtime.findClass(\"{s}\")) |p| p else null;\n",
                        .{ short_cname, escaped_parent },
                    );
                }

                // 设置接口列表
                if (td.interfaces.len > 0) {
                    try writer.print("    {s}_meta.interfaces = &[_][]const u8{{", .{short_cname});
                    for (td.interfaces, 0..) |iface, idx| {
                        if (idx > 0) try writer.writeAll(", ");
                        const escaped_iface = try self.escapeString(iface);
                        defer self.allocator.free(escaped_iface);
                        try writer.print("\"{s}\"", .{escaped_iface});
                    }
                    try writer.writeAll("};\n");
                }
            }
        }

        for (0..class_count) |ci| {
            const full_cname = class_names[ci];
            const short_cname = class_short_names[ci];
            try writer.print("    if ({s}_meta.findMethod(\"__construct\")) |m| {{ {s}_meta.magic_construct = m.func; }}\n", .{ short_cname, short_cname });
            try writer.print("    if ({s}_meta.findMethod(\"__destruct\")) |m| {{ {s}_meta.magic_destruct = m.func; }}\n", .{ short_cname, short_cname });
            try writer.print("    if ({s}_meta.findMethod(\"__get\")) |m| {{ {s}_meta.magic_get = m.func; }}\n", .{ short_cname, short_cname });
            try writer.print("    if ({s}_meta.findMethod(\"__set\")) |m| {{ {s}_meta.magic_set = m.func; }}\n", .{ short_cname, short_cname });
            try writer.print("    if ({s}_meta.findMethod(\"__call\")) |m| {{ {s}_meta.magic_call = m.func; }}\n", .{ short_cname, short_cname });
            try writer.print("    if ({s}_meta.findMethod(\"__callStatic\")) |m| {{ {s}_meta.magic_callStatic = m.func; }}\n", .{ short_cname, short_cname });
            try writer.print("    if ({s}_meta.findMethod(\"__sleep\")) |m| {{ {s}_meta.magic_sleep = m.func; }}\n", .{ short_cname, short_cname });
            try writer.print("    if ({s}_meta.findMethod(\"__wakeup\")) |m| {{ {s}_meta.magic_wakeup = m.func; }}\n", .{ short_cname, short_cname });
            try writer.print("    if ({s}_meta.findMethod(\"__serialize\")) |m| {{ {s}_meta.magic_serialize = m.func; }}\n", .{ short_cname, short_cname });
            try writer.print("    if ({s}_meta.findMethod(\"__unserialize\")) |m| {{ {s}_meta.magic_unserialize = m.func; }}\n", .{ short_cname, short_cname });
            _ = full_cname; // 避免未使用警告
        }

        try writer.writeAll("}\n");
    }

    /// IR类型转Zig类型字符串
    fn irTypeToZigTypeString(self: *const Self, ir_type: IR.Type) []const u8 {
        _ = self;
        return switch (ir_type) {
            .void => "void",
            .i64 => "i64",
            .f64 => "f64",
            .bool => "bool",
            .php_value => "runtime.Value",
            .php_string => "runtime.Value",
            .php_array => "runtime.Value",
            .ptr => "runtime.Value",
            else => "runtime.Value",
        };
    }

    /// 检查函数是否需要 allocator 参数
    fn functionNeedsAllocator(self: *const Self, func_name: []const u8) bool {
        _ = self;
        // 先尝试直接查找
        if (builtinInfo(func_name)) |info| return info.needs_allocator;

        // 如果是 php_ 前缀，去掉前缀再查找
        if (std.mem.startsWith(u8, func_name, "php_")) {
            const lookup_name = func_name[4..];
            if (builtinInfo(lookup_name)) |info| return info.needs_allocator;
        }
        return false;
    }

    fn functionMayRaise(self: *const Self, func_name: []const u8) bool {
        _ = self;
        if (std.mem.startsWith(u8, func_name, "__declare_function__::")) return false;
        if (builtinInfo(func_name)) |info| return info.may_raise;
        return true;
    }

    /// 检查是否是内置函数
    fn isBuiltinFunction(self: *const Self, func_name: []const u8) bool {
        _ = self;

        // 已经是php_前缀的是内置函数
        if (std.mem.startsWith(u8, func_name, "php_")) return true;
        return builtinInfo(func_name) != null;
    }

    /// 检查用户定义函数是否存在于 IR module 中
    fn isUserDefinedFunction(self: *const Self, func_name: []const u8) bool {
        if (self.ir_module) |module| {
            return module.findFunction(func_name) != null;
        }
        return false;
    }

    /// 检查函数是否是"语句函数"（返回值通常被忽略）
    fn isStatementFunction(self: *const Self, func_name: []const u8) bool {
        _ = self;
        const statement_funcs = [_][]const u8{
            "echo",       "var_dump",  "print_r",     "unset",
            "array_push", "array_pop", "array_shift", "array_unshift",
            "sort",       "rsort",     "asort",       "arsort",
            "ksort",      "krsort",    "shuffle",     "usort",
            "uasort",     "uksort",
        };
        for (statement_funcs) |sf| {
            if (std.mem.eql(u8, func_name, sf)) return true;
        }
        return false;
    }

    /// 映射PHP函数名到运行时函数名
    fn mapToRuntimeFunction(self: *const Self, func_name: []const u8) []const u8 {
        _ = self;

        // 已经是php_前缀的直接返回
        if (std.mem.startsWith(u8, func_name, "php_")) {
            return func_name;
        }
        if (builtinInfo(func_name)) |info| return info.runtime_name;
        return func_name;
    }

    const BuiltinInfo = struct {
        runtime_name: []const u8,
        needs_allocator: bool,
        may_raise: bool = true,
        ref_params: []const u8 = &[_]u8{}, // indices of reference parameters (1-based for optional params)
    };

    fn builtinInfo(func_name: []const u8) ?BuiltinInfo {
        return builtin_map.get(func_name);
    }

    /// Get reference parameter indices for a builtin function (public for IR Generator)
    pub fn getBuiltinRefParams(func_name: []const u8) []const u8 {
        if (builtinInfo(func_name)) |info| return info.ref_params;
        return &[_]u8{};
    }

    const builtin_map = std.StaticStringMap(BuiltinInfo).initComptime(@as([]const struct { []const u8, BuiltinInfo }, &.{
        .{ "echo", bi(.{ .runtime_name = "php_echo", .needs_allocator = false }) },
        .{ "print", bi(.{ .runtime_name = "php_print", .needs_allocator = false }) },
        .{ "var_dump", bi(.{ .runtime_name = "php_var_dump", .needs_allocator = false }) },
        .{ "print_r", bi(.{ .runtime_name = "print_r", .needs_allocator = false }) },
        .{ "var_export", bi(.{ .runtime_name = "var_export", .needs_allocator = false }) },

        // 引用操作函数
        .{ "php_deref", bi(.{ .runtime_name = "php_deref", .needs_allocator = false }) },
        .{ "php_ref_assign", bi(.{ .runtime_name = "php_ref_assign", .needs_allocator = false, .may_raise = false }) },
        .{ "php_ref_assign_ptr", bi(.{ .runtime_name = "php_ref_assign_ptr", .needs_allocator = false, .may_raise = false }) },

        .{ "define", bi(.{ .runtime_name = "php_define", .needs_allocator = true }) },
        .{ "defined", bi(.{ .runtime_name = "php_defined", .needs_allocator = false }) },

        .{ "class_exists", bi(.{ .runtime_name = "php_class_exists", .needs_allocator = true }) },
        .{ "interface_exists", bi(.{ .runtime_name = "php_interface_exists", .needs_allocator = true }) },
        .{ "trait_exists", bi(.{ .runtime_name = "php_trait_exists", .needs_allocator = true }) },
        .{ "method_exists", bi(.{ .runtime_name = "php_method_exists", .needs_allocator = false }) },
        .{ "property_exists", bi(.{ .runtime_name = "php_property_exists", .needs_allocator = false }) },
        .{ "is_subclass_of", bi(.{ .runtime_name = "php_is_subclass_of", .needs_allocator = false }) },
        .{ "get_class", bi(.{ .runtime_name = "php_get_class", .needs_allocator = true }) },
        .{ "get_parent_class", .{ .runtime_name = "php_get_parent_class", .needs_allocator = true } },
        .{ "serialize", bi(.{ .runtime_name = "php_serialize", .needs_allocator = true }) },
        .{ "unserialize", bi(.{ .runtime_name = "php_unserialize", .needs_allocator = true }) },
        .{ "json_encode", bi(.{ .runtime_name = "php_json_encode", .needs_allocator = true }) },
        .{ "json_decode", bi(.{ .runtime_name = "php_json_decode", .needs_allocator = true }) },
        .{ "json_last_error", bi(.{ .runtime_name = "php_json_last_error", .needs_allocator = false, .may_raise = false }) },
        .{ "json_last_error_msg", bi(.{ .runtime_name = "php_json_last_error_msg", .needs_allocator = true, .may_raise = false }) },
        .{ "func_get_args", bi(.{ .runtime_name = "php_func_get_args", .needs_allocator = true }) },
        .{ "func_get_arg", bi(.{ .runtime_name = "php_func_get_arg", .needs_allocator = false }) },
        .{ "func_num_args", bi(.{ .runtime_name = "php_func_num_args", .needs_allocator = false, .may_raise = false }) },
        .{ "memory_get_usage", bi(.{ .runtime_name = "php_memory_get_usage", .needs_allocator = true, .may_raise = false }) },
        .{ "memory_get_peak_usage", bi(.{ .runtime_name = "php_memory_get_peak_usage", .needs_allocator = true, .may_raise = false }) },
        .{ "shell_exec", bi(.{ .runtime_name = "php_shell_exec", .needs_allocator = true, .may_raise = false }) },
        .{ "exec", bi(.{ .runtime_name = "php_exec", .needs_allocator = true, .may_raise = false, .ref_params = &[_]u8{ 1, 2 } }) },
        .{ "system", bi(.{ .runtime_name = "php_system", .needs_allocator = true, .may_raise = false, .ref_params = &[_]u8{1} }) },
        .{ "escapeshellarg", bi(.{ .runtime_name = "php_escapeshellarg", .needs_allocator = true, .may_raise = false }) },
        .{ "escapeshellcmd", bi(.{ .runtime_name = "php_escapeshellcmd", .needs_allocator = true, .may_raise = false }) },
        .{ "substr_replace", bi(.{ .runtime_name = "php_substr_replace", .needs_allocator = true, .may_raise = false }) },
        .{ "file_put_contents", .{ .runtime_name = "php_file_put_contents", .needs_allocator = true } },
        .{ "file_get_contents", .{ .runtime_name = "php_file_get_contents", .needs_allocator = true } },
        .{ "fopen", .{ .runtime_name = "php_fopen", .needs_allocator = true } },
        .{ "fwrite", .{ .runtime_name = "php_fwrite", .needs_allocator = true } },
        .{ "fread", .{ .runtime_name = "php_fread", .needs_allocator = true } },
        .{ "fclose", .{ .runtime_name = "php_fclose", .needs_allocator = false } },
        .{ "is_resource", .{ .runtime_name = "php_is_resource", .needs_allocator = false } },
        .{ "getcwd", .{ .runtime_name = "php_getcwd", .needs_allocator = true } },
        .{ "php_sapi_name", .{ .runtime_name = "php_sapi_name", .needs_allocator = true } },
        .{ "php_uname", .{ .runtime_name = "php_uname", .needs_allocator = true } },
        .{ "unlink", .{ .runtime_name = "php_unlink", .needs_allocator = false } },
        .{ "filesize", .{ .runtime_name = "php_filesize", .needs_allocator = false } },
        .{ "is_file", .{ .runtime_name = "php_is_file", .needs_allocator = false } },
        .{ "is_dir", .{ .runtime_name = "php_is_dir", .needs_allocator = false } },
        .{ "is_readable", .{ .runtime_name = "php_is_readable", .needs_allocator = false } },
        .{ "is_writable", .{ .runtime_name = "php_is_writable", .needs_allocator = false } },
        .{ "sys_get_temp_dir", .{ .runtime_name = "php_sys_get_temp_dir", .needs_allocator = true } },
        .{ "file", .{ .runtime_name = "php_file", .needs_allocator = true } },
        .{ "file_exists", .{ .runtime_name = "php_file_exists", .needs_allocator = false } },
        .{ "fgets", .{ .runtime_name = "php_fgets", .needs_allocator = false } },
        .{ "fseek", .{ .runtime_name = "php_fseek", .needs_allocator = false } },
        .{ "scandir", .{ .runtime_name = "php_scandir", .needs_allocator = true } },
        .{ "function_exists", bi(.{ .runtime_name = "aot_function_exists", .needs_allocator = false, .may_raise = false }) },
        .{ "gc_enable", bi(.{ .runtime_name = "php_gc_enable", .needs_allocator = true, .may_raise = false }) },
        .{ "gc_collect_cycles", bi(.{ .runtime_name = "php_gc_collect_cycles", .needs_allocator = true, .may_raise = false }) },
        .{ "ini_get", bi(.{ .runtime_name = "php_ini_get", .needs_allocator = true, .may_raise = false }) },
        .{ "getrusage", bi(.{ .runtime_name = "php_getrusage", .needs_allocator = true, .may_raise = false }) },

        .{ "strlen", bi(.{ .runtime_name = "php_strlen", .needs_allocator = false }) },
        .{ "substr", bi(.{ .runtime_name = "php_substr", .needs_allocator = true }) },
        .{ "strpos", bi(.{ .runtime_name = "php_strpos", .needs_allocator = false }) },
        .{ "strtoupper", bi(.{ .runtime_name = "php_strtoupper", .needs_allocator = true }) },
        .{ "strtolower", bi(.{ .runtime_name = "php_strtolower", .needs_allocator = true }) },
        .{ "trim", bi(.{ .runtime_name = "php_trim", .needs_allocator = true }) },
        .{ "ltrim", bi(.{ .runtime_name = "php_ltrim", .needs_allocator = true }) },
        .{ "rtrim", bi(.{ .runtime_name = "php_rtrim", .needs_allocator = true }) },
        .{ "str_replace", bi(.{ .runtime_name = "php_str_replace", .needs_allocator = true }) },
        .{ "str_ireplace", bi(.{ .runtime_name = "php_str_ireplace", .needs_allocator = true }) },
        .{ "str_repeat", bi(.{ .runtime_name = "php_str_repeat", .needs_allocator = true }) },
        .{ "str_pad", bi(.{ .runtime_name = "php_str_pad", .needs_allocator = true }) },
        .{ "strstr", bi(.{ .runtime_name = "php_strstr", .needs_allocator = true }) },
        .{ "strchr", bi(.{ .runtime_name = "php_strstr", .needs_allocator = true }) }, // strchr是strstr的别名
        .{ "strrev", bi(.{ .runtime_name = "php_strrev", .needs_allocator = true }) },
        .{ "str_contains", bi(.{ .runtime_name = "php_str_contains", .needs_allocator = false }) },
        .{ "preg_match", bi(.{ .runtime_name = "preg_match", .needs_allocator = true }) },
        .{ "preg_match_with_matches", bi(.{ .runtime_name = "preg_match_with_matches", .needs_allocator = true }) },
        .{ "preg_match_all", bi(.{ .runtime_name = "preg_match_all", .needs_allocator = true }) },
        .{ "preg_replace", bi(.{ .runtime_name = "preg_replace", .needs_allocator = true }) },
        .{ "preg_filter", bi(.{ .runtime_name = "preg_filter", .needs_allocator = true }) },
        .{ "preg_replace_callback", bi(.{ .runtime_name = "php_preg_replace_callback", .needs_allocator = true }) },
        .{ "preg_split", bi(.{ .runtime_name = "preg_split", .needs_allocator = true }) },
        .{ "preg_grep", bi(.{ .runtime_name = "preg_grep", .needs_allocator = true }) },
        .{ "preg_quote", bi(.{ .runtime_name = "preg_quote", .needs_allocator = true }) },
        .{ "preg_last_error", bi(.{ .runtime_name = "preg_last_error", .needs_allocator = false, .may_raise = false }) },
        .{ "str_starts_with", bi(.{ .runtime_name = "php_str_starts_with", .needs_allocator = false }) },
        .{ "str_word_count", bi(.{ .runtime_name = "php_str_word_count", .needs_allocator = false }) },
        .{ "str_ends_with", bi(.{ .runtime_name = "php_str_ends_with", .needs_allocator = false }) },
        .{ "ucfirst", bi(.{ .runtime_name = "php_ucfirst", .needs_allocator = true }) },
        .{ "lcfirst", bi(.{ .runtime_name = "php_lcfirst", .needs_allocator = true }) },
        .{ "ucwords", bi(.{ .runtime_name = "php_ucwords", .needs_allocator = true }) },
        .{ "explode", bi(.{ .runtime_name = "php_explode", .needs_allocator = true }) },
        .{ "implode", bi(.{ .runtime_name = "php_implode", .needs_allocator = true }) },
        .{ "join", bi(.{ .runtime_name = "php_implode", .needs_allocator = true }) },
        .{ "str_getcsv", bi(.{ .runtime_name = "php_str_getcsv", .needs_allocator = true }) },
        .{ "str_split", bi(.{ .runtime_name = "php_str_split", .needs_allocator = true }) },
        .{ "strcmp", bi(.{ .runtime_name = "php_strcmp", .needs_allocator = false }) },
        .{ "strcasecmp", bi(.{ .runtime_name = "php_strcasecmp", .needs_allocator = true }) },
        .{ "stripos", bi(.{ .runtime_name = "php_stripos", .needs_allocator = false }) },
        .{ "strrpos", bi(.{ .runtime_name = "php_strrpos", .needs_allocator = false }) },
        .{ "strripos", bi(.{ .runtime_name = "php_strripos", .needs_allocator = false }) },
        .{ "sprintf", bi(.{ .runtime_name = "php_sprintf", .needs_allocator = true }) },
        .{ "sscanf", .{ .runtime_name = "php_sscanf", .needs_allocator = true } },
        .{ "preg_match", .{ .runtime_name = "php_preg_match", .needs_allocator = true } },
        .{ "preg_match_all", .{ .runtime_name = "php_preg_match_all", .needs_allocator = true } },
        .{ "preg_replace", .{ .runtime_name = "php_preg_replace", .needs_allocator = true } },
        .{ "preg_replace_callback", .{ .runtime_name = "php_preg_replace_callback", .needs_allocator = true } },
        .{ "preg_split", .{ .runtime_name = "php_preg_split", .needs_allocator = true } },
        .{ "filter_var", bi(.{ .runtime_name = "php_filter_var", .needs_allocator = true }) },
        .{ "printf", bi(.{ .runtime_name = "php_printf", .needs_allocator = true }) },
        .{ "chunk_split", bi(.{ .runtime_name = "php_chunk_split", .needs_allocator = true }) },
        .{ "wordwrap", bi(.{ .runtime_name = "php_wordwrap", .needs_allocator = true }) },
        .{ "nl2br", bi(.{ .runtime_name = "php_nl2br", .needs_allocator = true }) },
        .{ "strip_tags", bi(.{ .runtime_name = "php_strip_tags", .needs_allocator = true }) },
        .{ "htmlspecialchars", bi(.{ .runtime_name = "php_htmlspecialchars", .needs_allocator = true }) },
        .{ "htmlentities", bi(.{ .runtime_name = "php_htmlentities", .needs_allocator = true }) },
        .{ "htmlspecialchars_decode", bi(.{ .runtime_name = "php_htmlspecialchars_decode", .needs_allocator = true }) },
        .{ "number_format", bi(.{ .runtime_name = "php_number_format", .needs_allocator = true }) },
        .{ "bin2hex", bi(.{ .runtime_name = "php_bin2hex", .needs_allocator = true }) },
        .{ "decbin", bi(.{ .runtime_name = "php_decbin", .needs_allocator = true }) },
        .{ "hex2bin", bi(.{ .runtime_name = "php_hex2bin", .needs_allocator = true }) },
        .{ "base64_encode", bi(.{ .runtime_name = "php_base64_encode", .needs_allocator = true }) },
        .{ "base64_decode", bi(.{ .runtime_name = "php_base64_decode", .needs_allocator = true }) },
        .{ "md5", bi(.{ .runtime_name = "php_md5", .needs_allocator = true }) },
        .{ "sha1", bi(.{ .runtime_name = "php_sha1", .needs_allocator = true }) },
        .{ "uniqid", bi(.{ .runtime_name = "php_uniqid", .needs_allocator = true }) },
        .{ "ord", bi(.{ .runtime_name = "php_ord", .needs_allocator = false }) },
        .{ "chr", bi(.{ .runtime_name = "php_chr", .needs_allocator = true }) },
        .{ "urlencode", bi(.{ .runtime_name = "php_urlencode", .needs_allocator = true }) },
        .{ "urldecode", bi(.{ .runtime_name = "php_urldecode", .needs_allocator = true }) },
        .{ "rawurlencode", bi(.{ .runtime_name = "php_rawurlencode", .needs_allocator = true }) },
        .{ "rawurldecode", bi(.{ .runtime_name = "php_rawurldecode", .needs_allocator = true }) },

        .{ "count", bi(.{ .runtime_name = "php_count", .needs_allocator = false }) },
        .{ "in_array", bi(.{ .runtime_name = "php_in_array", .needs_allocator = false }) },
        .{ "array_key_exists", bi(.{ .runtime_name = "php_array_key_exists", .needs_allocator = false }) },
        .{ "array_keys", bi(.{ .runtime_name = "php_array_keys", .needs_allocator = true }) },
        .{ "array_is_list", bi(.{ .runtime_name = "php_array_is_list", .needs_allocator = false, .may_raise = false }) },
        .{ "array_values", bi(.{ .runtime_name = "php_array_values", .needs_allocator = true }) },
        .{ "array_push", bi(.{ .runtime_name = "php_array_push", .needs_allocator = true }) },
        .{ "array_pop", bi(.{ .runtime_name = "php_array_pop", .needs_allocator = true }) },
        .{ "array_shift", bi(.{ .runtime_name = "php_array_shift", .needs_allocator = true }) },
        .{ "array_unshift", bi(.{ .runtime_name = "php_array_unshift", .needs_allocator = true }) },
        .{ "array_slice", bi(.{ .runtime_name = "php_array_slice", .needs_allocator = true }) },
        .{ "array_splice", bi(.{ .runtime_name = "php_array_splice", .needs_allocator = true }) },
        .{ "array_merge", bi(.{ .runtime_name = "php_array_merge", .needs_allocator = true }) },
        .{ "array_map", bi(.{ .runtime_name = "php_array_map", .needs_allocator = true }) },
        .{ "array_filter", bi(.{ .runtime_name = "php_array_filter", .needs_allocator = true }) },
        .{ "array_reduce", bi(.{ .runtime_name = "php_array_reduce", .needs_allocator = true }) },
        .{ "array_chunk", bi(.{ .runtime_name = "php_array_chunk", .needs_allocator = true }) },
        .{ "array_column", bi(.{ .runtime_name = "php_array_column", .needs_allocator = true }) },
        .{ "array_sum", bi(.{ .runtime_name = "php_array_sum", .needs_allocator = false }) },
        .{ "array_product", bi(.{ .runtime_name = "php_array_product", .needs_allocator = false }) },
        .{ "array_search", bi(.{ .runtime_name = "php_array_search", .needs_allocator = false }) },
        .{ "array_reverse", bi(.{ .runtime_name = "php_array_reverse", .needs_allocator = true }) },
        .{ "array_unique", bi(.{ .runtime_name = "php_array_unique", .needs_allocator = true }) },
        .{ "array_flip", bi(.{ .runtime_name = "php_array_flip", .needs_allocator = true }) },
        .{ "array_combine", bi(.{ .runtime_name = "php_array_combine", .needs_allocator = true }) },
        .{ "array_pad", bi(.{ .runtime_name = "php_array_pad", .needs_allocator = true }) },
        .{ "array_fill", bi(.{ .runtime_name = "php_array_fill", .needs_allocator = true }) },
        .{ "array_fill_keys", bi(.{ .runtime_name = "php_array_fill_keys", .needs_allocator = true }) },
        .{ "array_intersect", bi(.{ .runtime_name = "php_array_intersect", .needs_allocator = true }) },
        .{ "array_diff", bi(.{ .runtime_name = "php_array_diff", .needs_allocator = true }) },
        .{ "array_diff_key", bi(.{ .runtime_name = "php_array_diff_key", .needs_allocator = true }) },
        .{ "array_walk", bi(.{ .runtime_name = "php_array_walk", .needs_allocator = true }) },
        .{ "array_walk_recursive", bi(.{ .runtime_name = "php_array_walk_recursive", .needs_allocator = true }) },
        .{ "array_count_values", bi(.{ .runtime_name = "php_array_count_values", .needs_allocator = true }) },
        .{ "array_rand", bi(.{ .runtime_name = "php_array_rand", .needs_allocator = true }) },
        .{ "array_key_first", bi(.{ .runtime_name = "php_array_key_first", .needs_allocator = false }) },
        .{ "array_key_last", bi(.{ .runtime_name = "php_array_key_last", .needs_allocator = false }) },
        .{ "array_multisort", bi(.{ .runtime_name = "php_array_multisort", .needs_allocator = true }) },
        .{ "array_flip", bi(.{ .runtime_name = "php_array_flip", .needs_allocator = true }) },
        .{ "array_key_first", bi(.{ .runtime_name = "php_array_key_first", .needs_allocator = false }) },
        .{ "array_count_values", bi(.{ .runtime_name = "php_array_count_values", .needs_allocator = true }) },
        .{ "array_rand", bi(.{ .runtime_name = "php_array_rand", .needs_allocator = true }) },
        .{ "shuffle", bi(.{ .runtime_name = "php_shuffle", .needs_allocator = true }) },
        .{ "compact", bi(.{ .runtime_name = "php_compact", .needs_allocator = true }) },
        .{ "extract", bi(.{ .runtime_name = "php_extract", .needs_allocator = true }) },
        .{ "array_fill_keys", bi(.{ .runtime_name = "php_array_fill_keys", .needs_allocator = true }) },
        .{ "natsort", bi(.{ .runtime_name = "php_natsort", .needs_allocator = true }) },
        .{ "array_key_last", bi(.{ .runtime_name = "php_array_key_last", .needs_allocator = false }) },
        .{ "array_fill", bi(.{ .runtime_name = "php_array_fill", .needs_allocator = true }) },
        .{ "array_column", bi(.{ .runtime_name = "php_array_column", .needs_allocator = true }) },
        .{ "array_walk", bi(.{ .runtime_name = "php_array_walk", .needs_allocator = true }) },
        .{ "array_walk_recursive", bi(.{ .runtime_name = "php_array_walk_recursive", .needs_allocator = true }) },
        .{ "array_splice", bi(.{ .runtime_name = "php_array_splice", .needs_allocator = true }) },
        .{ "array_intersect", bi(.{ .runtime_name = "php_array_intersect", .needs_allocator = true }) },
        .{ "array_diff", bi(.{ .runtime_name = "php_array_diff", .needs_allocator = true }) },
        .{ "array_combine", bi(.{ .runtime_name = "php_array_combine", .needs_allocator = true }) },
        .{ "array_pad", bi(.{ .runtime_name = "php_array_pad", .needs_allocator = true }) },
        .{ "php_array_merge_into", bi(.{ .runtime_name = "php_array_merge_into", .needs_allocator = true }) },
        .{ "sizeof", bi(.{ .runtime_name = "php_sizeof", .needs_allocator = false }) },
        .{ "sort", bi(.{ .runtime_name = "php_sort", .needs_allocator = true }) },
        .{ "rsort", bi(.{ .runtime_name = "php_rsort", .needs_allocator = true }) },
        .{ "asort", bi(.{ .runtime_name = "php_asort", .needs_allocator = true }) },
        .{ "arsort", bi(.{ .runtime_name = "php_arsort", .needs_allocator = true }) },
        .{ "ksort", bi(.{ .runtime_name = "php_ksort", .needs_allocator = true }) },
        .{ "krsort", bi(.{ .runtime_name = "php_krsort", .needs_allocator = true }) },
        .{ "usort", bi(.{ .runtime_name = "php_usort", .needs_allocator = true }) },
        .{ "uasort", bi(.{ .runtime_name = "php_uasort", .needs_allocator = true }) },
        .{ "uksort", bi(.{ .runtime_name = "php_uksort", .needs_allocator = true }) },
        .{ "array_multisort", bi(.{ .runtime_name = "php_array_multisort", .needs_allocator = true }) },
        .{ "range", bi(.{ .runtime_name = "php_range", .needs_allocator = true }) },
        .{ "current", bi(.{ .runtime_name = "php_current", .needs_allocator = true }) },
        .{ "next", bi(.{ .runtime_name = "php_next", .needs_allocator = true }) },
        .{ "prev", bi(.{ .runtime_name = "php_prev", .needs_allocator = true }) },
        .{ "reset", bi(.{ .runtime_name = "php_reset", .needs_allocator = true }) },
        .{ "end", bi(.{ .runtime_name = "php_end", .needs_allocator = true }) },
        .{ "key", bi(.{ .runtime_name = "php_key", .needs_allocator = true }) },
        .{ "each", bi(.{ .runtime_name = "php_each", .needs_allocator = true }) },

        // Object functions
        .{ "php_object_new", bi(.{ .runtime_name = "php_object_new", .needs_allocator = true }) },
        .{ "php_object_new_with_constructor", bi(.{ .runtime_name = "php_object_new_with_constructor", .needs_allocator = true }) },

        .{ "abs", bi(.{ .runtime_name = "php_abs", .needs_allocator = false }) },
        .{ "sqrt", .{ .runtime_name = "php_sqrt", .needs_allocator = false } },
        .{ "round", .{ .runtime_name = "php_round", .needs_allocator = false } },
        .{ "floor", .{ .runtime_name = "php_floor", .needs_allocator = false } },
        .{ "ceil", .{ .runtime_name = "php_ceil", .needs_allocator = false } },
        .{ "min", .{ .runtime_name = "php_min", .needs_allocator = false } },
        .{ "max", .{ .runtime_name = "php_max", .needs_allocator = false } },
        .{ "pow", .{ .runtime_name = "php_pow_func", .needs_allocator = false } },
        .{ "sin", .{ .runtime_name = "php_sin", .needs_allocator = false } },
        .{ "cos", .{ .runtime_name = "php_cos", .needs_allocator = false } },
        .{ "tan", .{ .runtime_name = "php_tan", .needs_allocator = false } },
        .{ "asin", .{ .runtime_name = "php_asin", .needs_allocator = false } },
        .{ "acos", .{ .runtime_name = "php_acos", .needs_allocator = false } },
        .{ "atan", .{ .runtime_name = "php_atan", .needs_allocator = false } },
        .{ "atan2", .{ .runtime_name = "php_atan2", .needs_allocator = false } },
        .{ "log", .{ .runtime_name = "php_log", .needs_allocator = false } },
        .{ "log10", .{ .runtime_name = "php_log10", .needs_allocator = false } },
        .{ "exp", .{ .runtime_name = "php_exp", .needs_allocator = false } },
        .{ "fmod", .{ .runtime_name = "php_fmod", .needs_allocator = false } },
        .{ "hypot", .{ .runtime_name = "php_hypot", .needs_allocator = false } },
        .{ "deg2rad", .{ .runtime_name = "php_deg2rad", .needs_allocator = false } },
        .{ "rad2deg", .{ .runtime_name = "php_rad2deg", .needs_allocator = false } },
        .{ "pi", .{ .runtime_name = "php_pi", .needs_allocator = false } },
        .{ "rand", .{ .runtime_name = "php_rand", .needs_allocator = false } },
        .{ "mt_rand", .{ .runtime_name = "php_mt_rand", .needs_allocator = false } },

        .{ "time", bi(.{ .runtime_name = "php_time", .needs_allocator = false, .may_raise = false }) },
        .{ "mktime", .{ .runtime_name = "php_mktime", .needs_allocator = false } },
        .{ "microtime", bi(.{ .runtime_name = "php_microtime", .needs_allocator = true }) },
        .{ "date", bi(.{ .runtime_name = "php_date", .needs_allocator = true }) },
        .{ "strtotime", bi(.{ .runtime_name = "php_strtotime", .needs_allocator = true }) },
        .{ "sleep", bi(.{ .runtime_name = "php_sleep", .needs_allocator = false }) },
        .{ "usleep", bi(.{ .runtime_name = "php_usleep", .needs_allocator = false }) },

        .{ "srand", .{ .runtime_name = "php_srand", .needs_allocator = false } },
        .{ "mt_srand", .{ .runtime_name = "php_mt_srand", .needs_allocator = false } },
        .{ "random_int", .{ .runtime_name = "php_random_int", .needs_allocator = false } },
        .{ "random_bytes", .{ .runtime_name = "php_random_bytes", .needs_allocator = true } },

        // Static variable functions
        .{ "getStaticVar", bi(.{ .runtime_name = "getStaticVar", .needs_allocator = false }) },
        .{ "setStaticVar", bi(.{ .runtime_name = "setStaticVar", .needs_allocator = false }) },

        .{ "is_null", .{ .runtime_name = "php_is_null", .needs_allocator = false } },
        .{ "is_bool", .{ .runtime_name = "php_is_bool", .needs_allocator = false } },
        .{ "is_int", .{ .runtime_name = "php_is_int", .needs_allocator = false } },
        .{ "is_float", .{ .runtime_name = "php_is_float", .needs_allocator = false } },
        .{ "is_string", .{ .runtime_name = "php_is_string", .needs_allocator = false } },
        .{ "is_array", .{ .runtime_name = "php_is_array", .needs_allocator = false } },
        .{ "is_object", .{ .runtime_name = "php_is_object", .needs_allocator = false } },
        .{ "is_numeric", .{ .runtime_name = "php_is_numeric", .needs_allocator = false } },
        .{ "is_callable", .{ .runtime_name = "php_is_callable", .needs_allocator = false } },
        .{ "is_resource", .{ .runtime_name = "php_is_resource", .needs_allocator = false } },
        .{ "is_scalar", .{ .runtime_name = "php_is_scalar", .needs_allocator = false } },
        .{ "is_infinite", .{ .runtime_name = "php_is_infinite", .needs_allocator = false } },
        .{ "is_nan", .{ .runtime_name = "php_is_nan", .needs_allocator = false } },
        .{ "is_finite", .{ .runtime_name = "php_is_finite", .needs_allocator = false } },
        .{ "is_countable", .{ .runtime_name = "php_is_countable", .needs_allocator = false } },
        .{ "is_iterable", .{ .runtime_name = "php_is_iterable", .needs_allocator = false } },
        .{ "isset", .{ .runtime_name = "php_isset", .needs_allocator = false } },
        .{ "empty", .{ .runtime_name = "php_empty", .needs_allocator = false } },
        .{ "unset", .{ .runtime_name = "php_unset", .needs_allocator = true, .may_raise = false } },

        .{ "intval", .{ .runtime_name = "php_intval", .needs_allocator = false } },
        .{ "floatval", .{ .runtime_name = "php_floatval", .needs_allocator = false } },
        .{ "strval", .{ .runtime_name = "php_strval", .needs_allocator = true } },
        .{ "boolval", .{ .runtime_name = "php_boolval", .needs_allocator = false } },
        .{ "gettype", .{ .runtime_name = "php_gettype", .needs_allocator = true } },
        .{ "settype", bi(.{ .runtime_name = "php_settype", .needs_allocator = true, .may_raise = false, .ref_params = &[_]u8{0} }) },
        .{ "exit", .{ .runtime_name = "php_exit", .needs_allocator = false } },
        .{ "die", .{ .runtime_name = "php_exit", .needs_allocator = false } },

        .{ "file_get_contents", .{ .runtime_name = "php_file_get_contents", .needs_allocator = true } },
        .{ "file_put_contents", .{ .runtime_name = "php_file_put_contents", .needs_allocator = true } },
        .{ "file_exists", .{ .runtime_name = "php_file_exists", .needs_allocator = false } },
        .{ "is_file", .{ .runtime_name = "php_is_file", .needs_allocator = false } },
        .{ "is_dir", .{ .runtime_name = "php_is_dir", .needs_allocator = false } },
        .{ "filesize", .{ .runtime_name = "php_filesize", .needs_allocator = false } },
        .{ "unlink", .{ .runtime_name = "php_unlink", .needs_allocator = false } },
        .{ "rename", .{ .runtime_name = "php_rename", .needs_allocator = false } },
        .{ "copy", .{ .runtime_name = "php_copy", .needs_allocator = false } },
        .{ "mkdir", .{ .runtime_name = "php_mkdir", .needs_allocator = false } },
        .{ "rmdir", .{ .runtime_name = "php_rmdir", .needs_allocator = false } },
        .{ "basename", .{ .runtime_name = "php_basename", .needs_allocator = true } },
        .{ "dirname", .{ .runtime_name = "php_dirname", .needs_allocator = true } },

        .{ "go", bi(.{ .runtime_name = "php_go_builtin", .needs_allocator = true }) },

        .{ "php_concat", bi(.{ .runtime_name = "php_concat", .needs_allocator = true }) },
        .{ "php_array_iter_init", bi(.{ .runtime_name = "php_array_iter_init", .needs_allocator = true }) },
        .{ "php_array_iter_init_ref", bi(.{ .runtime_name = "php_array_iter_init_ref", .needs_allocator = true }) },
        .{ "php_array_iter_key", bi(.{ .runtime_name = "php_array_iter_key", .needs_allocator = true }) },
        .{ "php_array_iter_value_ref_reuse", bi(.{ .runtime_name = "php_array_iter_value_ref_reuse", .needs_allocator = false, .may_raise = true }) },
        .{ "php_array_iter_valid_ref", bi(.{ .runtime_name = "php_array_iter_valid_ref", .needs_allocator = false, .may_raise = true }) },
        .{ "php_array_iter_next_ref", bi(.{ .runtime_name = "php_array_iter_next_ref", .needs_allocator = false, .may_raise = true }) },
        .{ "php_array_iter_free", bi(.{ .runtime_name = "php_array_iter_free", .needs_allocator = true }) },
        .{ "php_array_iter_free_ref", bi(.{ .runtime_name = "php_array_iter_free_ref", .needs_allocator = true }) },
        .{ "php_create_closure", bi(.{ .runtime_name = "php_create_closure", .needs_allocator = true }) },
        .{ "php_object_unset", bi(.{ .runtime_name = "php_object_unset", .needs_allocator = true }) },
        .{ "php_args_append_spread", bi(.{ .runtime_name = "php_args_append_spread", .needs_allocator = true }) },
        .{ "php_invoke_callable_args_array", bi(.{ .runtime_name = "php_invoke_callable_args_array", .needs_allocator = true }) },
        .{ "php_object_call_safe_args_array", bi(.{ .runtime_name = "php_object_call_safe_args_array", .needs_allocator = true }) },
        .{ "php_object_call_args_array", bi(.{ .runtime_name = "php_object_call_args_array", .needs_allocator = true }) },
        .{ "php_constant_get", bi(.{ .runtime_name = "php_constant_get", .needs_allocator = true }) },
        .{ "php_go_builtin", bi(.{ .runtime_name = "php_go_builtin", .needs_allocator = true }) },
        .{ "php_json_encode", bi(.{ .runtime_name = "php_json_encode", .needs_allocator = true }) },

        // PCNTL 函数
        .{ "pcntl_fork", bi(.{ .runtime_name = "php_pcntl_fork", .needs_allocator = false }) },
        .{ "pcntl_waitpid", bi(.{ .runtime_name = "php_pcntl_waitpid", .needs_allocator = true }) },
        .{ "pcntl_wait", bi(.{ .runtime_name = "php_pcntl_wait", .needs_allocator = true }) },
        .{ "pcntl_wexitstatus", bi(.{ .runtime_name = "php_pcntl_wexitstatus", .needs_allocator = false }) },
        .{ "pcntl_signal", bi(.{ .runtime_name = "php_pcntl_signal", .needs_allocator = true }) },
        .{ "pcntl_signal_dispatch", bi(.{ .runtime_name = "php_pcntl_signal_dispatch", .needs_allocator = true }) },
        .{ "pcntl_alarm", bi(.{ .runtime_name = "php_pcntl_alarm", .needs_allocator = false }) },
        .{ "pcntl_sigprocmask", bi(.{ .runtime_name = "php_pcntl_sigprocmask", .needs_allocator = true }) },
        // POSIX 函数
        .{ "posix_getpid", bi(.{ .runtime_name = "php_posix_getpid", .needs_allocator = false }) },
        .{ "posix_kill", bi(.{ .runtime_name = "php_posix_kill", .needs_allocator = false }) },
        .{ "posix_mkfifo", bi(.{ .runtime_name = "php_posix_mkfifo", .needs_allocator = true }) },
        // IPC 函数
        .{ "ftok", bi(.{ .runtime_name = "php_ftok", .needs_allocator = true }) },
        .{ "msg_get_queue", bi(.{ .runtime_name = "php_msg_get_queue", .needs_allocator = true }) },
        .{ "msg_remove_queue", bi(.{ .runtime_name = "php_msg_remove_queue", .needs_allocator = false }) },
        .{ "sem_get", bi(.{ .runtime_name = "php_sem_get", .needs_allocator = true }) },
        .{ "sem_remove", bi(.{ .runtime_name = "php_sem_remove", .needs_allocator = false }) },
        .{ "shmop_open", bi(.{ .runtime_name = "php_shmop_open", .needs_allocator = true }) },
        .{ "shmop_close", bi(.{ .runtime_name = "php_shmop_close", .needs_allocator = false }) },
        // Socket 函数
        .{ "socket_create_pair", bi(.{ .runtime_name = "php_socket_create_pair", .needs_allocator = true }) },
        .{ "socket_close", bi(.{ .runtime_name = "php_socket_close", .needs_allocator = false }) },
        
        // 异常处理函数
        .{ "throwThrowable", bi(.{ .runtime_name = "throwThrowable", .needs_allocator = true }) },
    }));

    fn bi(info: BuiltinInfo) BuiltinInfo {
        return info;
    }

    /// 生成函数
    fn generateFunction(self: *Self, code: *std.ArrayList(u8), _: *const IR.Module, func: *const IR.Function) !void {
        const has_this = func.params.items.len > 0 and std.mem.eql(u8, func.params.items[0].name, "this");
        self.current_function_has_this = has_this;
        self.current_function_for_resolve = func;
        defer self.current_function_for_resolve = null;

        // 初始化参数寄存器映射
        var param_regs = std.StringHashMap(usize).init(self.allocator);
        defer param_regs.deinit();
        self.param_registers = &param_regs;
        defer self.param_registers = null;

        // 验证函数名
        if (func.name.len == 0 or !std.unicode.utf8ValidateSlice(func.name)) {
            return error.InvalidFunctionName;
        }

        // 活跃性分析
        const LivenessAnalysis = @import("liveness_analysis.zig").LivenessAnalysis;
        var liveness = LivenessAnalysis.init(self.allocator);
        defer liveness.deinit();
        try liveness.analyze(func);

        // 保存活跃性信息供后续使用
        self.current_liveness = &liveness;
        defer self.current_liveness = null;

        // 所有权追踪（暂时禁用）
        // const OwnershipTracker = @import("ownership_tracker.zig").OwnershipTracker;
        // var ownership = OwnershipTracker.init(self.allocator);
        // defer ownership.deinit();
        // try ownership.analyze(func);

        // 在代码生成时重新进行类型推断
        const TypeInferencePass = @import("type_inference_pass.zig").TypeInferencePass;
        var type_inference = TypeInferencePass.init(self.allocator);
        defer type_inference.deinit();

        try type_inference.inferTypes(func);

        // 推断返回类型：检查函数体中是否有返回值
        var has_return_value = false;
        for (func.blocks.items) |block| {
            if (block.terminator) |term| {
                if (term == .ret and term.ret != null) {
                    has_return_value = true;
                    break;
                }
            }
        }

        // 将函数返回类型信息存储到模块级别的HashMap中
        // 注意：这需要在generateZigCode中初始化
        // 这里我们假设已经在generateZigCode中处理了

        // 生成函数签名
        // 所有函数都是public的，以便相互调用
        const escaped_name = try escapeBackslashes(self.allocator, func.name);
        defer self.allocator.free(escaped_name);

        if (func.is_generator) {
            // Generator body function: private, same signature
            try code.appendSlice(self.allocator, "\n// MARKER: generator body function\nfn @\"__gen_body_");
            try code.appendSlice(self.allocator, escaped_name);
            try code.appendSlice(self.allocator, "\"(");
        } else {
            try code.appendSlice(self.allocator, "\n// MARKER: generateFunction called\npub fn @\"");
            try code.appendSlice(self.allocator, escaped_name);
            try code.appendSlice(self.allocator, "\"(");
        }

        // 统一函数签名：(ctx: runtime.Value, args: []const runtime.Value, allocator: std.mem.Allocator) !runtime.Value
        // Note: allocator 参数在大多数情况下未使用，但保留参数名以便需要时使用
        try code.appendSlice(self.allocator, "ctx: runtime.Value, args: []const runtime.Value, allocator: std.mem.Allocator) !runtime.Value {\n");
        try code.appendSlice(self.allocator, "    _ = &ctx;\n");
        try code.appendSlice(self.allocator, "    _ = allocator; // 标记为故意未使用\n");
        try code.appendSlice(self.allocator, "    const __prev_call_args = runtime.setCurrentCallArgs(args);\n");
        try code.appendSlice(self.allocator, "    defer runtime.restoreCurrentCallArgs(__prev_call_args);\n");

        // 如果是类方法，设置 ClassContext
        if (std.mem.indexOf(u8, func.name, "::")) |_| {
            const class_name = blk: {
                var it = std.mem.splitScalar(u8, func.name, ':');
                break :blk it.first();
            };
            const escaped_class = try self.escapeString(class_name);
            defer self.allocator.free(escaped_class);
            // LSB: 只设置 scope class（定义方法的类），不覆盖 called class
            // 调用方（php_call_static / ClassContext.init）已正确设置 called class
            // 如果 called class 未设置（直接调用），则同时设置为定义类
            try code.appendSlice(self.allocator, "    if (runtime.findClass(\"");
            try code.appendSlice(self.allocator, escaped_class);
            try code.appendSlice(self.allocator, "\")) |__class_meta| {\n");
            try code.appendSlice(self.allocator, "        const __prev_scope = runtime.getCurrentScopeClass();\n");
            try code.appendSlice(self.allocator, "        runtime.setCurrentScopeClass(__class_meta);\n");
            try code.appendSlice(self.allocator, "        defer runtime.setCurrentScopeClass(__prev_scope);\n");
            try code.appendSlice(self.allocator, "        if (runtime.getCurrentCalledClass() == null) {\n");
            try code.appendSlice(self.allocator, "            runtime.setCurrentCalledClass(__class_meta);\n");
            try code.appendSlice(self.allocator, "        }\n");
            try code.appendSlice(self.allocator, "    }\n");
        }

        const escaped_prof_name = try self.escapeString(func.name);
        defer self.allocator.free(escaped_prof_name);
        try code.appendSlice(self.allocator, "    runtime.profiler.enterGlobal(\"");
        try code.appendSlice(self.allocator, escaped_prof_name);
        try code.appendSlice(self.allocator, "\");\n");
        try code.appendSlice(self.allocator, "    defer runtime.profiler.exitGlobal(\"");
        try code.appendSlice(self.allocator, escaped_prof_name);
        try code.appendSlice(self.allocator, "\");\n");

        // Generator: extract context from thread-local
        if (func.is_generator) {
            try code.appendSlice(self.allocator, "    const __gen_ctx = runtime.php_generator_get_context();\n");
        }

        // 变量声明

        // 收集寄存器信息
        var all_registers = std.AutoHashMap(usize, IR.Type).init(self.allocator);
        defer all_registers.deinit();

        // 保存类型推断结果到 HashMap
        var inferred_types = std.AutoHashMap(usize, IR.Type).init(self.allocator);
        defer inferred_types.deinit();

        var inferred_reg_iter = type_inference.solver.reg_to_var.iterator();
        while (inferred_reg_iter.next()) |entry| {
            const reg_id = entry.key_ptr.*;
            if (type_inference.getInferredType(reg_id)) |inferred_type| {
                try inferred_types.put(reg_id, inferred_type);
            }
        }

        self.current_inferred_types = &inferred_types;
        defer self.current_inferred_types = null;

        var alloca_registers = std.AutoHashMap(usize, void).init(self.allocator);
        defer alloca_registers.deinit();

        // PHP 变量名映射：reg_id → var_name（从 func.var_names 获取，跨优化持久）
        var var_name_map = std.AutoHashMap(usize, []const u8).init(self.allocator);
        defer var_name_map.deinit();
        {
            var vn_it = func.var_names.iterator();
            while (vn_it.next()) |entry| {
                try var_name_map.put(@intCast(entry.key_ptr.*), entry.value_ptr.*);
            }
        }

        // 跟踪已unset的寄存器（避免cleanup时访问已释放内存）
        var unset_registers = std.AutoHashMap(usize, void).init(self.allocator);
        defer unset_registers.deinit();

        // 收集需要释放的寄存器（字符串、数组等）
        // 使用HashSet避免重复
        var cleanup_registers_set = std.AutoHashMap(usize, void).init(self.allocator);
        defer cleanup_registers_set.deinit();
        var cleanup_registers: std.ArrayList(usize) = .empty;
        defer cleanup_registers.deinit(self.allocator);

        // 收集寄存器定义
        // std.debug.print("Collecting registers from {d} blocks\n", .{func.blocks.items.len});
        for (func.blocks.items, 0..) |block, block_idx| {
            _ = block_idx;
            for (block.instructions.items) |inst| {
                // 检查是否是被 mem2reg 提升的 alloca（nop 指令 + ptr 类型）
                if (inst.op == .nop and inst.result != null) {
                    const reg = inst.result.?;
                    const reg_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    if (reg_tag == .ptr) {
                        // mem2reg 提升的 alloca：类型从 ptr 变为指向的类型
                        const inner_type = switch (reg.type_) {
                            .ptr => |inner| inner.*,
                            else => .php_value,
                        };
                        try all_registers.put(reg.id, inner_type);
                        // mem2reg提升的alloca也需要在函数结束时清理
                        try cleanup_registers_set.put(reg.id, {});
                        // std.debug.print("mem2reg promoted reg_{d}, type=ptr -> {s}\n", .{
                        //     reg.id,
                        //     @tagName(@as(std.meta.Tag(IR.Type), inner_type))
                        // });
                    }
                }

                // 跳过 nop 指令（被优化掉的指令）
                if (inst.op == .nop) continue;

                // 收集 result 寄存器
                if (inst.result) |reg| {
                    // 修正类型：如果指令使用运行时函数，结果应该是 Value
                    var corrected_type = reg.type_;
                    switch (inst.op) {
                        .add, .sub, .mul, .div, .mod, .pow, .concat, .eq, .ne, .lt, .le, .gt, .ge => |bin| {
                            // 如果操作数不是同类型的基本类型，结果应该是 Value
                            const lhs_tag = @as(std.meta.Tag(IR.Type), bin.lhs.type_);
                            const rhs_tag = @as(std.meta.Tag(IR.Type), bin.rhs.type_);
                            const res_tag = @as(std.meta.Tag(IR.Type), reg.type_);

                            const both_i64 = lhs_tag == .i64 and rhs_tag == .i64;
                            const both_f64 = lhs_tag == .f64 and rhs_tag == .f64;

                            if (!both_i64 and !both_f64) {
                                // 需要运行时函数，结果应该是 Value
                                corrected_type = .php_value;
                                if (self.config.verbose) {
                                    // std.debug.print("  Type correction: reg_{d} {s} -> php_value (mixed operands)\n", .{reg.id, @tagName(res_tag)});
                                }
                            } else if (both_i64 and res_tag != .i64) {
                                corrected_type = .php_value;
                                if (self.config.verbose) {
                                    // std.debug.print("  Type correction: reg_{d} {s} -> php_value (i64 mismatch)\n", .{reg.id, @tagName(res_tag)});
                                }
                            } else if (both_f64 and res_tag != .f64) {
                                corrected_type = .php_value;
                                if (self.config.verbose) {
                                    // std.debug.print("  Type correction: reg_{d} {s} -> php_value (f64 mismatch)\n", .{reg.id, @tagName(res_tag)});
                                }
                            }
                        },
                        .call => {
                            // 所有函数调用都返回 runtime.Value
                            const res_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                            if (res_tag != .php_value) {
                                corrected_type = .php_value;
                                if (self.config.verbose) {
                                    // std.debug.print("  Type correction: reg_{d} {s} -> php_value (call result)\n", .{reg.id, @tagName(res_tag)});
                                }
                            }
                        },
                        .call_indirect => {
                            // 间接调用也返回 runtime.Value
                            const res_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                            if (res_tag != .php_value) {
                                corrected_type = .php_value;
                                if (self.config.verbose) {
                                    // std.debug.print("  Type correction: reg_{d} {s} -> php_value (call_indirect result)\n", .{reg.id, @tagName(res_tag)});
                                }
                            }
                        },
                        .array_get, .property_get => {
                            // 数组/对象访问都返回 runtime.Value
                            const res_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                            if (res_tag != .php_value) {
                                corrected_type = .php_value;
                            }
                        },
                        else => {},
                    }

                    // alloca指令的类型不应该被修正
                    if (inst.op == .alloca) {
                        corrected_type = reg.type_;
                    }

                    try all_registers.put(reg.id, corrected_type);
                    if (inst.op == .alloca) {
                        try alloca_registers.put(reg.id, {});
                    }
                    // 注意：nop 指令（被优化掉的 alloca）不应该被添加到 alloca_registers

                    // 检查是否需要释放（字符串、数组等需要分配内存的类型）
                    if (inst.op != .alloca) {
                        // 只cleanup创建新值的指令
                        switch (inst.op) {
                            .new_object => {
                                // 对象创建：无论类型是php_object还是php_value都需要清理
                                try cleanup_registers_set.put(reg.id, {});
                            },
                            .const_string, .concat, .array_new, .call => {
                                if (corrected_type == .php_value) {
                                    try cleanup_registers_set.put(reg.id, {});
                                }
                            },
                            else => {},
                        }
                    } else {
                        // alloca 指令（局部变量）也需要在函数结束时释放
                        try cleanup_registers_set.put(reg.id, {});
                    }
                }

                // 收集操作数寄存器（所有 BinaryOp 和 UnaryOp）
                // 注意：只添加不存在的寄存器，不覆盖已修正的类型
                switch (inst.op) {
                    .phi => |phi| {
                        for (phi.incoming) |inc| {
                            if (!all_registers.contains(inc.value.id)) {
                                try all_registers.put(inc.value.id, inc.value.type_);
                            }
                        }
                    },
                    .add, .sub, .mul, .div, .mod, .pow, .bit_and, .bit_or, .bit_xor, .shl, .shr, .eq, .ne, .lt, .le, .gt, .ge, .identical, .not_identical, .spaceship, .and_, .or_, .concat => |bin| {
                        if (!all_registers.contains(bin.lhs.id)) {
                            try all_registers.put(bin.lhs.id, bin.lhs.type_);
                        }
                        if (!all_registers.contains(bin.rhs.id)) {
                            try all_registers.put(bin.rhs.id, bin.rhs.type_);
                        }
                    },
                    .neg, .bit_not, .not, .get_type => |un| {
                        if (!all_registers.contains(un.operand.id)) {
                            try all_registers.put(un.operand.id, un.operand.type_);
                        }
                    },
                    .store => |store| {
                        if (!all_registers.contains(store.value.id)) {
                            try all_registers.put(store.value.id, store.value.type_);
                        }
                        if (!all_registers.contains(store.ptr.id)) {
                            try all_registers.put(store.ptr.id, store.ptr.type_);
                        }
                    },
                    .load => |load| {
                        if (!all_registers.contains(load.ptr.id)) {
                            try all_registers.put(load.ptr.id, load.ptr.type_);
                        }
                    },
                    .call => |call| {
                        for (call.args) |arg| {
                            if (!all_registers.contains(arg.id)) {
                                try all_registers.put(arg.id, arg.type_);
                            }
                        }
                    },
                    .cast => |cast| {
                        if (!all_registers.contains(cast.value.id)) {
                            try all_registers.put(cast.value.id, cast.value.type_);
                        }
                    },
                    .box => |box_op| {
                        if (!all_registers.contains(box_op.value.id)) {
                            try all_registers.put(box_op.value.id, box_op.from_type);
                        }
                    },
                    .unbox => |unbox_op| {
                        if (!all_registers.contains(unbox_op.value.id)) {
                            try all_registers.put(unbox_op.value.id, .php_value);
                        }
                    },
                    else => {},
                }
            }

            // 收集 terminator 中的寄存器
            if (block.terminator) |term| {
                switch (term) {
                    .ret => |ret_reg| {
                        if (ret_reg) |reg| {
                            if (!all_registers.contains(reg.id)) {
                                try all_registers.put(reg.id, reg.type_);
                            }
                        }
                    },
                    .cond_br => |cbr| {
                        if (!all_registers.contains(cbr.cond.id)) {
                            try all_registers.put(cbr.cond.id, cbr.cond.type_);
                        }
                    },
                    .switch_ => |sw| {
                        if (!all_registers.contains(sw.value.id)) {
                            try all_registers.put(sw.value.id, sw.value.type_);
                        }
                    },
                    .throw => |thr| {
                        if (!all_registers.contains(thr.id)) {
                            try all_registers.put(thr.id, thr.type_);
                        }
                    },
                    else => {},
                }
            }
        }

        // 用 all_registers 中的类型覆盖 inferred_types（修正后的类型优先）
        var all_reg_iter = all_registers.iterator();
        while (all_reg_iter.next()) |entry| {
            const reg_id = entry.key_ptr.*;
            const corrected_type = entry.value_ptr.*;
            try inferred_types.put(reg_id, corrected_type);
        }
        // std.debug.print("Applied {d} corrected types to inferred_types\n", .{all_registers.count()});

        // ============================================================================
        // 反向类型传播（Backward Type Propagation）
        // ============================================================================
        // 目的：根据操作的使用场景，修正寄存器的类型
        //
        // 算法：
        // 1. 标记类型确定的寄存器（const_string, call 等）
        // 2. 遍历所有指令，根据操作需求传播类型约束
        //    - concat: 参数需要 php_value 或 php_string
        //    - call/call_indirect: 参数需要 php_value
        // 3. 只修改类型不确定的寄存器（如 const_int 可以转换为 Value）
        //
        // 示例：
        //   reg_1 = const_int 42        // 类型不确定，可以是 i64 或 php_value
        //   reg_2 = call @foo(reg_1)    // call 需要 php_value 参数
        //   => 传播后：reg_1 的类型修正为 php_value
        // ============================================================================
        const enable_debug = false; // 可选的调试输出

        // 首先标记哪些寄存器的类型是确定的（由定义决定）
        var definite_types = std.AutoHashMap(usize, void).init(self.allocator);
        defer definite_types.deinit();

        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.result) |reg| {
                    switch (inst.op) {
                        // 这些指令的结果类型是确定的，不应该被反向传播修改
                        .const_string,
                        .const_null,
                        .array_new,
                        .new_object,
                        .call,
                        .call_indirect,
                        .array_get,
                        .property_get,
                        .alloca, // alloca类型不应该被修改
                        => {
                            try definite_types.put(reg.id, {});
                        },
                        else => {},
                    }
                }
            }
        }

        // 然后进行反向传播，但跳过类型确定的寄存器
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                switch (inst.op) {
                    // concat 需要 php_value 参数
                    .concat => |op| {
                        if (!definite_types.contains(op.lhs.id)) {
                            if (all_registers.getPtr(op.lhs.id)) |lhs_type| {
                                const lhs_tag = @as(std.meta.Tag(IR.Type), lhs_type.*);
                                if (lhs_tag != .php_value and lhs_tag != .php_string) {
                                    if (enable_debug) std.debug.print("  Propagate: reg_{d} {s} -> php_value (concat lhs)\n", .{ op.lhs.id, @tagName(lhs_tag) });
                                    lhs_type.* = .php_value;
                                }
                            }
                        }
                        if (!definite_types.contains(op.rhs.id)) {
                            if (all_registers.getPtr(op.rhs.id)) |rhs_type| {
                                const rhs_tag = @as(std.meta.Tag(IR.Type), rhs_type.*);
                                if (rhs_tag != .php_value and rhs_tag != .php_string) {
                                    if (enable_debug) std.debug.print("  Propagate: reg_{d} {s} -> php_value (concat rhs)\n", .{ op.rhs.id, @tagName(rhs_tag) });
                                    rhs_type.* = .php_value;
                                }
                            }
                        }
                    },
                    // call 需要 php_value 参数
                    .call => |op| {
                        for (op.args) |arg| {
                            if (!definite_types.contains(arg.id)) {
                                if (all_registers.getPtr(arg.id)) |arg_type| {
                                    const arg_tag = @as(std.meta.Tag(IR.Type), arg_type.*);
                                    if (arg_tag != .php_value) {
                                        if (enable_debug) std.debug.print("  Propagate: reg_{d} {s} -> php_value (call arg)\n", .{ arg.id, @tagName(arg_tag) });
                                        arg_type.* = .php_value;
                                    }
                                }
                            }
                        }
                    },
                    // call_indirect 需要 php_value 参数
                    .call_indirect => |op| {
                        for (op.args) |arg| {
                            if (!definite_types.contains(arg.id)) {
                                if (all_registers.getPtr(arg.id)) |arg_type| {
                                    const arg_tag = @as(std.meta.Tag(IR.Type), arg_type.*);
                                    if (arg_tag != .php_value) {
                                        if (enable_debug) std.debug.print("  Propagate: reg_{d} {s} -> php_value (call_indirect arg)\n", .{ arg.id, @tagName(arg_tag) });
                                        arg_type.* = .php_value;
                                    }
                                }
                            }
                        }
                    },
                    else => {},
                }
            }
        }

        // 用 all_registers 中的类型覆盖 inferred_types（反向传播后）
        all_reg_iter = all_registers.iterator();
        while (all_reg_iter.next()) |entry| {
            const reg_id = entry.key_ptr.*;
            const corrected_type = entry.value_ptr.*;
            try inferred_types.put(reg_id, corrected_type);
        }
        // std.debug.print("Applied {d} corrected types after backward propagation\n", .{all_registers.count()});

        // 用代码生成时的类型推断结果覆盖寄存器类型
        // TODO: 暂时禁用，因为需要配合代码生成时的类型特化
        // std.debug.print("Applying inferred types: {d} entries\n",
        //     .{type_inference.solver.var_to_type.count()});

        // var inferred_reg_iter = type_inference.solver.reg_to_var.iterator();
        // while (inferred_reg_iter.next()) |entry| {
        //     const reg_id = entry.key_ptr.*;
        //     if (type_inference.getInferredType(reg_id)) |inferred_type| {
        //         const inferred_tag = @as(std.meta.Tag(IR.Type), inferred_type);
        //
        //         // 只在推断类型更具体时覆盖
        //         if (inferred_tag != .php_value) {
        //             if (all_registers.getPtr(reg_id)) |current_type| {
        //                 const current_tag = @as(std.meta.Tag(IR.Type), current_type.*);
        //                 if (current_tag == .php_value) {
        //                     current_type.* = inferred_type;
        //                     std.debug.print("  Override reg_{d}: php_value → {s}\n",
        //                         .{reg_id, @tagName(inferred_tag)});
        //                 }
        //             }
        //         }
        //     }
        // }

        // 保存到 self，供代码生成时使用
        self.current_register_types = &all_registers;

        // 记录被优化的 alloca 寄存器（直接变量而不是指针）
        var optimized_alloca_regs = std.AutoHashMap(usize, void).init(self.allocator);
        defer optimized_alloca_regs.deinit();

        // 记录引用参数的alloca -> param映射
        var ref_param_alloca_map = std.AutoHashMap(usize, usize).init(self.allocator);
        defer ref_param_alloca_map.deinit();

        // 查找引用参数的alloca和param对应关系
        if (func.ref_params.items.len > 0) {
            for (func.blocks.items) |block_scan| {
                var prev_param_reg: ?usize = null;
                var prev_param_is_ref = false;

                for (block_scan.instructions.items) |inst_scan| {
                    switch (inst_scan.op) {
                        .param => |param_op| {
                            if (inst_scan.result) |reg| {
                                // 检查是否是引用参数
                                for (func.ref_params.items) |ref_idx| {
                                    if (ref_idx == param_op.index) {
                                        prev_param_reg = reg.id;
                                        prev_param_is_ref = true;
                                        break;
                                    }
                                }
                            }
                        },
                        .store => |store_op| {
                            // 如果前一个是引用param，这个store的目标就是对应的alloca
                            if (prev_param_is_ref) {
                                if (prev_param_reg) |param_reg| {
                                    if (store_op.value.id == param_reg) {
                                        try ref_param_alloca_map.put(store_op.ptr.id, param_reg);
                                        prev_param_reg = null;
                                        prev_param_is_ref = false;
                                    }
                                }
                            }
                        },
                        else => {
                            if (prev_param_is_ref) {
                                prev_param_reg = null;
                                prev_param_is_ref = false;
                            }
                        },
                    }
                }
            }
        }

        // std.debug.print("ref_param_alloca_map.count() = {d}\n", .{ref_param_alloca_map.count()});
        var ref_it = ref_param_alloca_map.iterator();
        while (ref_it.next()) |_| {
            // std.debug.print("  alloca reg_{d} -> param reg_{d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        // 检测 by-ref 闭包捕获的 alloca（capture_get.by_ref + store 模式）
        // 映射 alloca_reg_id → capture_get_result_reg_id，用于区分初始 store 和后续 store
        var ref_capture_allocas = std.AutoHashMap(usize, usize).init(self.allocator);
        defer ref_capture_allocas.deinit();
        for (func.blocks.items) |blk_scan| {
            var prev_capture_reg: ?usize = null;
            for (blk_scan.instructions.items) |inst_scan| {
                switch (inst_scan.op) {
                    .capture_get => |cap_op| {
                        if (cap_op.by_ref) {
                            if (inst_scan.result) |reg| {
                                prev_capture_reg = reg.id;
                            }
                        }
                    },
                    .store => |store_op| {
                        if (prev_capture_reg) |cap_reg| {
                            if (store_op.value.id == cap_reg) {
                                try ref_capture_allocas.put(store_op.ptr.id, cap_reg);
                            }
                        }
                        prev_capture_reg = null;
                    },
                    else => {
                        prev_capture_reg = null;
                    },
                }
            }
        }

        // 检测被 make_ref 的 alloca（父作用域引用捕获），
        // 后续 store 到这些 alloca 需要通过 val_deref 写穿引用槽
        var make_ref_allocas = std.AutoHashMap(usize, void).init(self.allocator);
        defer make_ref_allocas.deinit();
        for (func.blocks.items) |blk_scan| {
            for (blk_scan.instructions.items) |inst_scan| {
                if (inst_scan.op == .make_ref) {
                    const ptr_id = inst_scan.op.make_ref.ptr.id;
                    if (alloca_registers.contains(ptr_id)) {
                        try make_ref_allocas.put(ptr_id, {});
                    }
                }
            }
        }

        // 记录被优化的 alloca 寄存器（直接变量而不是指针）
        self.current_optimized_alloca_regs = &optimized_alloca_regs;

        // 收集PHI/select指令产生的指针寄存器（合并引用参数产生的指针类型）
        var ref_ptr_regs = std.AutoHashMap(usize, void).init(self.allocator);
        defer ref_ptr_regs.deinit();
        for (func.blocks.items) |blk_scan| {
            for (blk_scan.instructions.items) |inst_scan| {
                if (inst_scan.result) |res| {
                    const rtag = @as(std.meta.Tag(IR.Type), res.type_);
                    if (rtag == .ptr and !alloca_registers.contains(res.id)) {
                        switch (inst_scan.op) {
                            .phi, .select => {
                                try ref_ptr_regs.put(res.id, {});
                            },
                            else => {},
                        }
                    }
                }
            }
        }
        self.current_ref_ptr_regs = &ref_ptr_regs;
        defer self.current_ref_ptr_regs = null;

        // 生成寄存器声明 - 使用简单的方式
        // std.debug.print("About to generate register declarations: count={d}\n", .{all_registers.count()});
        if (all_registers.count() > 0) {
            try code.appendSlice(self.allocator, "    // Register declarations\n");

            if (self.config.verbose) {
                // std.debug.print("  Generating {d} register declarations\n", .{all_registers.count()});
            }

            var reg_iter = all_registers.iterator();
            while (reg_iter.next()) |entry| {
                const reg_id = entry.key_ptr.*;
                _ = entry.value_ptr.*;

                // if (self.config.verbose and reg_id == 16) {
                //     std.debug.print("  reg_16 type: {s}\n", .{@tagName(@as(std.meta.Tag(IR.Type), reg_type))});
                // }

                const is_alloca = alloca_registers.contains(reg_id);

                // std.debug.print("reg_{d}: type={s}, is_alloca={}\n", .{ reg_id, @tagName(@as(std.meta.Tag(IR.Type), reg_type)), is_alloca });

                if (is_alloca) {
                    // 检查是否是引用参数的alloca
                    if (ref_param_alloca_map.get(reg_id)) |_| {
                        // 引用参数的alloca：声明为undefined，稍后在param后初始化
                        try code.appendSlice(self.allocator, "    var reg_");
                        try code.writer(self.allocator).print("{d}", .{reg_id});
                        try code.appendSlice(self.allocator, ": *runtime.Value = undefined;\n");
                        try code.appendSlice(self.allocator, "    _ = &reg_");
                        try code.writer(self.allocator).print("{d}", .{reg_id});
                        try code.appendSlice(self.allocator, ";\n");
                    } else {
                        // 普通alloca：创建storage
                        try code.appendSlice(self.allocator, "    var reg_");
                        try code.writer(self.allocator).print("{d}", .{reg_id});
                        try code.appendSlice(self.allocator, "_storage: runtime.Value = runtime.Value.initNull();\n");
                        try code.appendSlice(self.allocator, "    var reg_");
                        try code.writer(self.allocator).print("{d}", .{reg_id});
                        try code.appendSlice(self.allocator, ": *runtime.Value = &reg_");
                        try code.writer(self.allocator).print("{d}", .{reg_id});
                        try code.appendSlice(self.allocator, "_storage;\n");
                        try code.appendSlice(self.allocator, "    _ = &reg_");
                        try code.writer(self.allocator).print("{d}", .{reg_id});
                        try code.appendSlice(self.allocator, ";\n");
                        // PHP 变量：生成 defined 标记用于 Undefined variable Warning
                        if (var_name_map.get(reg_id)) |_| {
                            try code.writer(self.allocator).print("    var __def_{d}: bool = false;\n    _ = &__def_{d};\n", .{ reg_id, reg_id });
                        }
                    }
                } else {
                    // 检查是否是引用参数寄存器
                    const is_ref_param_reg = blk: {
                        if (self.current_function_for_resolve) |func_check| {
                            // 遍历指令找到param
                            for (func_check.blocks.items) |block_check| {
                                for (block_check.instructions.items) |inst_check| {
                                    if (inst_check.op == .param) {
                                        if (inst_check.result) |result_reg| {
                                            if (result_reg.id == reg_id) {
                                                // 检查是否是引用参数
                                                const param_op = inst_check.op.param;
                                                for (func_check.ref_params.items) |ref_idx| {
                                                    if (ref_idx == param_op.index) {
                                                        break :blk true;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        break :blk false;
                    };

                    if (is_ref_param_reg or ref_ptr_regs.contains(reg_id)) {
                        // 引用参数寄存器或PHI/select合并的指针寄存器：声明为指针类型
                        try code.appendSlice(self.allocator, "    var reg_");
                        try code.writer(self.allocator).print("{d}", .{reg_id});
                        try code.appendSlice(self.allocator, ": *runtime.Value = undefined;\n");
                        try code.appendSlice(self.allocator, "    _ = &reg_");
                        try code.writer(self.allocator).print("{d}", .{reg_id});
                        try code.appendSlice(self.allocator, ";\n");
                    } else {
                        // 普通寄存器：总是使用 runtime.Value 以避免类型不匹配
                        try code.appendSlice(self.allocator, "    var reg_");
                        try code.writer(self.allocator).print("{d}", .{reg_id});
                        try code.appendSlice(self.allocator, ": runtime.Value = runtime.Value.initNull();\n");
                        // 标记为可能未使用（避免Zig编译器警告）
                        try code.appendSlice(self.allocator, "    _ = &reg_");
                        try code.writer(self.allocator).print("{d}", .{reg_id});
                        try code.appendSlice(self.allocator, ";\n");
                        // mem2reg 提升的 PHP 变量：生成 defined 标记
                        if (var_name_map.get(reg_id)) |_| {
                            try code.writer(self.allocator).print("    var __def_{d}: bool = false;\n    _ = &__def_{d};\n", .{ reg_id, reg_id });
                        }
                    }
                }
            }
            try code.appendSlice(self.allocator, "\n");
        }

        // 参数初始化现在由IR中的param和store指令处理

        // 为引用参数提供fallback null值（函数作用域）
        try code.appendSlice(self.allocator, "    var null_val = runtime.Value.initNull();\n");
        try code.appendSlice(self.allocator, "    _ = &null_val;\n\n");

        self.current_reg_types = &all_registers;
        defer self.current_reg_types = null;
        defer self.current_optimized_alloca_regs = null;

        var max_reg_id: usize = 0;
        var max_iter = all_registers.iterator();
        while (max_iter.next()) |entry| {
            if (entry.key_ptr.* > max_reg_id) max_reg_id = entry.key_ptr.*;
        }

        const reg_is_value = try self.allocator.alloc(bool, max_reg_id + 1);
        defer self.allocator.free(reg_is_value);
        @memset(reg_is_value, false);

        var type_iter = all_registers.iterator();
        while (type_iter.next()) |entry| {
            const reg_id = entry.key_ptr.*;
            const reg_type = entry.value_ptr.*;
            const type_tag = @as(std.meta.Tag(IR.Type), reg_type);
            reg_is_value[reg_id] = !(type_tag == .i64 or type_tag == .f64 or type_tag == .bool);
        }

        self.current_reg_is_value = reg_is_value;
        defer self.current_reg_is_value = null;

        self.current_register_types = &all_registers;
        defer self.current_register_types = null;

        const reg_may_heap = try self.allocator.alloc(bool, max_reg_id + 1);
        defer self.allocator.free(reg_may_heap);
        @memset(reg_may_heap, false);

        var phi_and_select: std.ArrayListUnmanaged(*const IR.Instruction) = .{};
        defer phi_and_select.deinit(self.allocator);

        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                const reg = inst.result orelse continue;
                if (reg.id >= reg_may_heap.len) continue;
                if (!reg_is_value[reg.id]) continue;

                switch (inst.op) {
                    .const_int, .const_float, .const_bool, .const_null, .const_missing, .box => {
                        reg_may_heap[reg.id] = false;
                    },
                    .phi, .select => {
                        try phi_and_select.append(self.allocator, inst);
                    },
                    .const_string, .concat, .interpolate, .array_new, .new_object, .closure_new, .make_ref, .call, .call_indirect, .load, .array_get, .array_count, .array_key_exists, .property_get, .method_call, .static_method_call, .clone, .parent_call, .cast, .type_check, .get_type, .go_spawn, .channel_new, .channel_recv, .await_ => {
                        reg_may_heap[reg.id] = true;
                    },
                    else => {
                        reg_may_heap[reg.id] = true;
                    },
                }
            }
        }

        var changed = true;
        while (changed) {
            changed = false;
            for (phi_and_select.items) |inst| {
                const dest = inst.result orelse continue;
                if (!reg_is_value[dest.id]) continue;

                const new_val = switch (inst.op) {
                    .phi => |phi| blk: {
                        var v: bool = false;
                        for (phi.incoming) |incoming| {
                            const src = incoming.value;
                            const src_real_type = all_registers.get(src.id) orelse src.type_;
                            const src_tag = @as(std.meta.Tag(IR.Type), src_real_type);
                            if (src_tag == .i64 or src_tag == .f64 or src_tag == .bool) continue;
                            if (src.id < reg_may_heap.len) v = v or reg_may_heap[src.id];
                            if (v) break;
                        }
                        break :blk v;
                    },
                    .select => |sel| blk: {
                        var v: bool = false;
                        const then_real = all_registers.get(sel.then_value.id) orelse sel.then_value.type_;
                        const then_tag = @as(std.meta.Tag(IR.Type), then_real);
                        if (!(then_tag == .i64 or then_tag == .f64 or then_tag == .bool)) {
                            if (sel.then_value.id < reg_may_heap.len) v = v or reg_may_heap[sel.then_value.id];
                        }
                        const else_real = all_registers.get(sel.else_value.id) orelse sel.else_value.type_;
                        const else_tag = @as(std.meta.Tag(IR.Type), else_real);
                        if (!(else_tag == .i64 or else_tag == .f64 or else_tag == .bool)) {
                            if (sel.else_value.id < reg_may_heap.len) v = v or reg_may_heap[sel.else_value.id];
                        }
                        break :blk v;
                    },
                    else => reg_may_heap[dest.id],
                };

                if (reg_may_heap[dest.id] != new_val) {
                    reg_may_heap[dest.id] = new_val;
                    changed = true;
                }
            }
        }

        self.current_reg_may_heap = reg_may_heap;
        defer self.current_reg_may_heap = null;

        self.current_alloca_regs = &alloca_registers;
        defer self.current_alloca_regs = null;

        self.current_var_name_map = &var_name_map;
        defer self.current_var_name_map = null;

        // 预扫描：找出被传给 by-ref 内建函数第一个参数的寄存器
        var byref_regs = std.AutoHashMap(usize, void).init(self.allocator);
        defer byref_regs.deinit();
        {
            const byref_funcs = [_][]const u8{
                "array_push", "array_pop", "array_shift",  "array_unshift",
                "sort",       "rsort",     "usort",        "uksort",
                "uasort",     "shuffle",   "array_splice", "array_walk",
            };
            for (func.blocks.items) |blk_scan| {
                for (blk_scan.instructions.items) |inst_scan| {
                    if (inst_scan.op == .call) {
                        const call_op = inst_scan.op.call;
                        if (call_op.args.len > 0) {
                            for (byref_funcs) |bf| {
                                if (std.mem.eql(u8, call_op.func_name, bf)) {
                                    try byref_regs.put(call_op.args[0].id, {});
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }
        self.current_byref_regs = &byref_regs;
        defer self.current_byref_regs = null;

        // 预扫描：找出 switch 终止器使用的 value 寄存器
        var switch_value_regs = std.AutoHashMap(usize, void).init(self.allocator);
        defer switch_value_regs.deinit();
        for (func.blocks.items) |blk_scan| {
            if (blk_scan.terminator) |term| {
                if (term == .switch_) {
                    try switch_value_regs.put(term.switch_.value.id, {});
                }
            }
        }
        self.current_switch_value_regs = &switch_value_regs;
        defer self.current_switch_value_regs = null;

        // 预扫描：记录 global_get 指令的结果寄存器 → 变量名映射
        var global_get_names = std.AutoHashMap(usize, []const u8).init(self.allocator);
        var concat_operand_regs = std.AutoHashMap(usize, void).init(self.allocator);
        var coalesce_nowarn_regs = std.AutoHashMap(usize, void).init(self.allocator);
        defer global_get_names.deinit();
        defer concat_operand_regs.deinit();
        defer coalesce_nowarn_regs.deinit();
        // 第一遍：收集 global_get 和 const_null 寄存器
        var global_get_reg_set = std.AutoHashMap(usize, void).init(self.allocator);
        defer global_get_reg_set.deinit();
        var null_const_regs = std.AutoHashMap(usize, void).init(self.allocator);
        defer null_const_regs.deinit();
        for (func.blocks.items) |blk_scan| {
            for (blk_scan.instructions.items) |inst_scan| {
                if (inst_scan.op == .global_get) {
                    if (inst_scan.result) |reg| {
                        try global_get_names.put(reg.id, inst_scan.op.global_get.name);
                        try global_get_reg_set.put(reg.id, {});
                    }
                } else if (inst_scan.op == .concat) {
                    try concat_operand_regs.put(inst_scan.op.concat.lhs.id, {});
                    try concat_operand_regs.put(inst_scan.op.concat.rhs.id, {});
                } else if (inst_scan.op == .const_null) {
                    if (inst_scan.result) |reg| {
                        try null_const_regs.put(reg.id, {});
                    }
                }
            }
        }
        // 收集 array_get 的 result → base_reg 映射（用于回溯）
        var array_get_base = std.AutoHashMap(usize, usize).init(self.allocator);
        defer array_get_base.deinit();
        for (func.blocks.items) |blk_scan2| {
            for (blk_scan2.instructions.items) |inst_scan| {
                if (inst_scan.op == .array_get) {
                    if (inst_scan.result) |reg| {
                        try array_get_base.put(reg.id, inst_scan.op.array_get.array.id);
                    }
                }
            }
        }
        // 第二遍：找 coalesce 模式
        for (func.blocks.items) |blk_scan| {
            // 方法1：identical(reg, null_const) 模式检测
            for (blk_scan.instructions.items) |inst_scan| {
                if (inst_scan.op == .identical) {
                    const id_op = inst_scan.op.identical;
                    // 找出哪个操作数是 null const
                    const coalesce_reg_id: ?usize = if (null_const_regs.contains(id_op.rhs.id))
                        id_op.lhs.id
                    else if (null_const_regs.contains(id_op.lhs.id))
                        id_op.rhs.id
                    else
                        null;
                    if (coalesce_reg_id) |cid| {
                        // 直接是 global_get 结果
                        if (global_get_reg_set.contains(cid)) {
                            try coalesce_nowarn_regs.put(cid, {});
                        }
                        // 通过 array_get 间接连接的 global_get
                        var trace_id = cid;
                        var depth: usize = 0;
                        while (depth < 5) : (depth += 1) {
                            if (array_get_base.get(trace_id)) |base_id| {
                                try coalesce_nowarn_regs.put(trace_id, {});
                                if (global_get_reg_set.contains(base_id)) {
                                    try coalesce_nowarn_regs.put(base_id, {});
                                    break;
                                }
                                trace_id = base_id;
                            } else break;
                        }
                    }
                }
            }
            // 方法2：coalesce_rhs 块中的 global_get 和 array_get 也需要 NoWarn
            if (std.mem.startsWith(u8, blk_scan.label, "coalesce_rhs")) {
                for (blk_scan.instructions.items) |inst_scan| {
                    if (inst_scan.op == .global_get or inst_scan.op == .array_get) {
                        if (inst_scan.result) |reg| {
                            try coalesce_nowarn_regs.put(reg.id, {});
                        }
                    }
                }
            }
        }
        self.current_global_get_names = &global_get_names;
        defer self.current_global_get_names = null;
        self.current_concat_operand_regs = &concat_operand_regs;
        defer self.current_concat_operand_regs = null;
        self.current_coalesce_nowarn_regs = &coalesce_nowarn_regs;
        defer self.current_coalesce_nowarn_regs = null;

        self.current_unset_regs = &unset_registers;
        defer self.current_unset_regs = null;

        self.ref_param_alloca_map = &ref_param_alloca_map;
        defer self.ref_param_alloca_map = null;

        self.current_ref_capture_allocas = &ref_capture_allocas;
        defer self.current_ref_capture_allocas = null;

        self.current_make_ref_allocas = &make_ref_allocas;
        defer self.current_make_ref_allocas = null;

        // std.debug.print("alloca_registers.count() = {d}\n", .{alloca_registers.count()});
        var alloca_it = alloca_registers.keyIterator();
        while (alloca_it.next()) |_| {
            // std.debug.print("  alloca: reg_{d}\n", .{key.*});
        }

        // 将cleanup_registers_set转换为list（去重后）
        var cleanup_set_it = cleanup_registers_set.keyIterator();
        while (cleanup_set_it.next()) |key| {
            try cleanup_registers.append(self.allocator, key.*);
        }

        self.current_cleanup_regs = cleanup_registers.items;
        defer self.current_cleanup_regs = null;

        // 找出被store到alloca的寄存器，它们不应该被cleanup
        // 因为alloca会负责cleanup
        var stored_to_alloca = std.AutoHashMap(usize, void).init(self.allocator);
        defer stored_to_alloca.deinit();

        // 找出被store过的alloca指针（它们的值被retain过）
        var alloca_with_store = std.AutoHashMap(usize, void).init(self.allocator);
        defer alloca_with_store.deinit();

        // 遍历所有block查找store指令
        for (func.blocks.items) |block_scan| {
            for (block_scan.instructions.items) |inst| {
                if (inst.op == .store) {
                    const store_op = inst.op.store;
                    // 如果store的目标是alloca，记录源寄存器和alloca指针
                    if (alloca_registers.contains(store_op.ptr.id)) {
                        try stored_to_alloca.put(store_op.value.id, {});
                        try alloca_with_store.put(store_op.ptr.id, {});
                        // std.debug.print("stored_to_alloca: reg_{d} -> reg_{d}\n", .{store_op.value.id, store_op.ptr.id});
                    }
                }
            }
        }

        // 生成代码体
        if (func.blocks.items.len == 1) {
            // 单基本块：直接生成线性代码
            try code.appendSlice(self.allocator, "    // Instructions\n");
            const block = func.blocks.items[0];

            // 禁用异常跳转（单块函数没有状态机）
            const prev_handler = self.current_exception_handler;
            self.current_exception_handler = null;

            for (block.instructions.items) |inst| {
                try self.generateInstructionSimple(code, inst);
            }

            // 恢复异常处理器
            self.current_exception_handler = prev_handler;

            // 生成terminator（return指令）
            if (block.terminator) |term| {
                switch (term) {
                    .ret => |ret_val| {
                        // 引用参数写回：已通过load/store重定向实现，不需要显式写回

                        // 在return之前执行cleanup，但跳过即将返回的寄存器
                        if (cleanup_registers.items.len > 0) {
                            try code.appendSlice(self.allocator, "\n    // Cleanup: release allocated values (except return value)\n");
                            for (cleanup_registers.items) |reg_id| {
                                // 跳过已经被store到alloca的寄存器
                                if (stored_to_alloca.contains(reg_id)) continue;

                                const is_return_reg = if (ret_val) |reg| reg.id == reg_id else false;
                                if (!is_return_reg and self.shouldReleaseReg(reg_id)) {
                                    // 跳过引用参数的alloca（它们是undefined）
                                    if (ref_param_alloca_map.get(reg_id)) |_| continue;

                                    // 跳过指针寄存器（PHI/select合并引用参数，不拥有值）
                                    if (ref_ptr_regs.contains(reg_id)) continue;

                                    // 检查是否是alloca寄存器
                                    const is_ptr = alloca_registers.contains(reg_id);

                                    // 跳过已unset的寄存器（避免访问已释放内存）
                                    if (unset_registers.contains(reg_id)) continue;

                                    if (is_ptr) {
                                        // alloca指针：只需release一次
                                        // store指令会retain，函数结束时release一次即可平衡
                                        try code.writer(self.allocator).print("    reg_{d}.*.release(runtime.runtime_allocator);\n", .{reg_id});
                                    } else {
                                        try code.writer(self.allocator).print("    if (!reg_{d}.isNull()) reg_{d}.release(runtime.runtime_allocator);\n", .{ reg_id, reg_id });
                                    }
                                }
                            }
                        }

                        if (ret_val) |reg| {
                            // 始终返回原始 Value，不做类型转换
                            // 类型推断可能不准确（如 && 结果推断为 i64 但实际是 bool）
                            const is_alloca = alloca_registers.contains(reg.id);
                            if (is_alloca) {
                                try code.writer(self.allocator).print("    return reg_{d}.*;\n", .{reg.id});
                            } else {
                                try code.writer(self.allocator).print("    return reg_{d};\n", .{reg.id});
                            }
                        } else {
                            try code.appendSlice(self.allocator, "    return runtime.Value.initNull();\n");
                        }
                    },
                    .throw => |ex_reg| {
                        // 设置异常
                        try code.writer(self.allocator).print("    runtime.setException(reg_{d});\n", .{ex_reg.id});

                        // 清理资源（除了异常对象）
                        if (cleanup_registers.items.len > 0) {
                            try code.appendSlice(self.allocator, "    // Cleanup before throw\n");
                            for (cleanup_registers.items) |reg_id| {
                                if (reg_id == ex_reg.id) continue;
                                if (alloca_registers.contains(reg_id)) continue;
                                if (!self.shouldReleaseReg(reg_id)) continue;

                                try code.writer(self.allocator).print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                            }
                        }

                        // 返回 null 而非 error，让调用方的 hasException() 检查路由到 catch 块
                        try code.appendSlice(self.allocator, "    return runtime.Value.initNull();\n");
                    },
                    else => {
                        // 其他terminator不应该出现在单基本块中
                        // 没有返回值，可以释放所有寄存器
                        if (cleanup_registers.items.len > 0) {
                            try code.appendSlice(self.allocator, "\n    // Cleanup: release allocated values (except return value)\n");
                            for (cleanup_registers.items) |reg_id| {
                                // 跳过已经被store到alloca的寄存器
                                if (stored_to_alloca.contains(reg_id)) continue;

                                if (!self.shouldReleaseReg(reg_id)) continue;

                                // 跳过引用参数的alloca（它们是undefined）
                                if (ref_param_alloca_map.get(reg_id)) |_| continue;

                                // 跳过指针寄存器（PHI/select合并引用参数，不拥有值）
                                if (ref_ptr_regs.contains(reg_id)) continue;

                                // 检查是否是alloca寄存器
                                const is_ptr = alloca_registers.contains(reg_id);

                                // 跳过已unset的寄存器（避免访问已释放内存）
                                if (unset_registers.contains(reg_id)) continue;

                                if (is_ptr) {
                                    // alloca指针：只需release一次
                                    // store指令会retain，函数结束时release一次即可平衡
                                    try code.writer(self.allocator).print("    reg_{d}.*.release(runtime.runtime_allocator);\n", .{reg_id});
                                } else {
                                    try code.writer(self.allocator).print("    if (!reg_{d}.isNull()) reg_{d}.release(runtime.runtime_allocator);\n", .{ reg_id, reg_id });
                                }
                            }
                        }

                        try code.appendSlice(self.allocator, "    return runtime.Value.initNull();\n");
                    },
                }
            } else {
                // 没有terminator，添加默认返回
                // 没有返回值，可以释放所有寄存器
                if (cleanup_registers.items.len > 0) {
                    try code.appendSlice(self.allocator, "\n    // Cleanup: release allocated values\n");
                    for (cleanup_registers.items) |reg_id| {
                        // 跳过已经被store到alloca的寄存器
                        if (stored_to_alloca.contains(reg_id)) continue;

                        if (!self.shouldReleaseReg(reg_id)) continue;

                        // 跳过引用参数的alloca（它们是undefined）
                        if (ref_param_alloca_map.get(reg_id)) |_| continue;

                        // 跳过指针寄存器（PHI/select合并引用参数，不拥有值）
                        if (ref_ptr_regs.contains(reg_id)) continue;

                        // 跳过已unset的寄存器（避免访问已释放内存）
                        if (unset_registers.contains(reg_id)) continue;

                        const is_alloca = alloca_registers.contains(reg_id);
                        if (is_alloca) {
                            // alloca指针：只需release一次
                            // store指令会retain，函数结束时release一次即可平衡
                            try code.writer(self.allocator).print("    reg_{d}.*.release(runtime.runtime_allocator);\n", .{reg_id});
                        } else {
                            try code.writer(self.allocator).print("    if (!reg_{d}.isNull()) reg_{d}.release(runtime.runtime_allocator);\n", .{ reg_id, reg_id });
                        }
                    }
                }

                try code.appendSlice(self.allocator, "    return runtime.Value.initNull();\n");
            }
        } else {
            try self.generateControlFlowStateMachine(code, func, cleanup_registers.items, &alloca_registers);
        }

        try code.appendSlice(self.allocator, "}\n");

        // Generator: generate wrapper function with original name
        if (func.is_generator) {
            try code.appendSlice(self.allocator, "\n// MARKER: generator wrapper\npub fn @\"");
            try code.appendSlice(self.allocator, escaped_name);
            try code.appendSlice(self.allocator, "\"(ctx: runtime.Value, args: []const runtime.Value, allocator: std.mem.Allocator) !runtime.Value {\n");
            try code.appendSlice(self.allocator, "    return runtime.php_create_generator(&@\"__gen_body_");
            try code.appendSlice(self.allocator, escaped_name);
            try code.appendSlice(self.allocator, "\", ctx, args, allocator);\n}\n");
        }

        // 清空临时指针
        self.current_register_types = null;
    }

    /// 尝试生成简单的if/else模式
    /// 模式：entry块 -> cond_br -> then块 / else块（可选）-> merge块（可选）
    fn tryGenerateSimpleIfElsePattern(self: *Self, code: *std.ArrayList(u8), func: *const IR.Function, cleanup_regs: []const usize, alloca_regs: *const std.AutoHashMap(usize, void)) !bool {
        if (func.blocks.items.len < 2) return false;

        const entry_block = func.blocks.items[0];
        const entry_term = entry_block.terminator orelse return false;

        // 检查是否是cond_br
        if (entry_term != .cond_br) return false;

        const cond_br = entry_term.cond_br;

        // 找到then块和else块
        var then_idx: ?usize = null;
        var else_idx: ?usize = null;

        for (func.blocks.items, 0..) |block, idx| {
            if (block == cond_br.then_block) then_idx = idx;
            if (block == cond_br.else_block) else_idx = idx;
        }

        if (then_idx == null) return false;

        // 生成entry块的指令
        try code.appendSlice(self.allocator, "    // Instructions\n");
        for (entry_block.instructions.items) |inst| {
            try self.generateInstructionSimple(code, inst);
        }

        // 生成if语句
        try code.appendSlice(self.allocator, "\n    // If statement\n");
        try code.appendSlice(self.allocator, "    if (");

        // 检查条件寄存器类型
        const cond_reg = cond_br.cond;
        const cond_type_tag = @as(std.meta.Tag(IR.Type), cond_reg.type_);

        if (cond_type_tag == .bool) {
            // 原生bool类型，直接使用
            try code.appendSlice(self.allocator, "reg_");
            try code.writer(self.allocator).print("{d}", .{cond_reg.id});
        } else {
            // runtime.Value类型，需要转换为bool
            try code.appendSlice(self.allocator, "reg_");
            try code.writer(self.allocator).print("{d}", .{cond_reg.id});
            try code.appendSlice(self.allocator, ".toBool()");
        }

        try code.appendSlice(self.allocator, ") {\n");

        // 生成then块
        const then_block = func.blocks.items[then_idx.?];
        for (then_block.instructions.items) |inst| {
            try code.appendSlice(self.allocator, "    ");
            try self.generateInstructionSimple(code, inst);
        }

        // 检查then块的terminator
        if (then_block.terminator) |then_term| {
            switch (then_term) {
                .ret => |ret_val| {
                    // 生成return语句
                    if (ret_val) |reg| {
                        // 检查函数返回类型
                        const func_has_return_value = self.func_return_types.get(func.name) orelse false;

                        // Cleanup before return
                        if (cleanup_regs.len > 0) {
                            try code.appendSlice(self.allocator, "        // Cleanup\n");
                            for (cleanup_regs) |reg_id| {
                                const is_return_reg = reg.id == reg_id;
                                if (!is_return_reg and self.shouldReleaseReg(reg_id)) {
                                    const suffix = if (alloca_regs.contains(reg_id)) ".*" else "";
                                    try code.appendSlice(self.allocator, "        reg_");
                                    try code.writer(self.allocator).print("{d}", .{reg_id});
                                    try code.appendSlice(self.allocator, suffix);
                                    try code.appendSlice(self.allocator, ".release(runtime.runtime_allocator);\n");
                                }
                            }
                        }

                        if (func_has_return_value) {
                            // 函数返回runtime.Value，需要检查寄存器类型
                            // Use cached type from all_registers to ensure consistency

                            // Cleanup before return
                            if (cleanup_regs.len > 0) {
                                try code.appendSlice(self.allocator, "        // Cleanup\n");
                                for (cleanup_regs) |reg_id| {
                                    const is_return_reg = reg.id == reg_id;
                                    if (!is_return_reg and self.shouldReleaseReg(reg_id)) {
                                        const suffix = if (alloca_regs.contains(reg_id)) ".*" else "";
                                        try code.appendSlice(self.allocator, "        reg_");
                                        try code.writer(self.allocator).print("{d}", .{reg_id});
                                        try code.appendSlice(self.allocator, suffix);
                                        try code.appendSlice(self.allocator, ".release(runtime.runtime_allocator);\n");
                                    }
                                }
                            }

                            const real_type = self.current_reg_types.?.get(reg.id) orelse reg.type_;
                            const reg_type_tag = @as(std.meta.Tag(IR.Type), real_type);
                            if (reg_type_tag == .i64) {
                                try code.appendSlice(self.allocator, "        return runtime.Value.initInt(reg_");
                                try code.writer(self.allocator).print("{d}", .{reg.id});
                                try code.appendSlice(self.allocator, ".asInt());\n");
                            } else if (reg_type_tag == .f64) {
                                try code.appendSlice(self.allocator, "        return runtime.Value.initFloat(reg_");
                                try code.writer(self.allocator).print("{d}", .{reg.id});
                                try code.appendSlice(self.allocator, ".asFloat());\n");
                            } else if (reg_type_tag == .bool) {
                                try code.appendSlice(self.allocator, "        return runtime.Value.initBool(reg_");
                                try code.writer(self.allocator).print("{d}", .{reg.id});
                                try code.appendSlice(self.allocator, ".asBool());\n");
                            } else {
                                // 已经是runtime.Value类型
                                try code.appendSlice(self.allocator, "        return reg_");
                                try code.writer(self.allocator).print("{d}", .{reg.id});
                                try code.appendSlice(self.allocator, ";\n");
                            }
                        } else {
                            // 函数返回void或其他类型，直接返回
                            // Cleanup before return
                            if (cleanup_regs.len > 0) {
                                try code.appendSlice(self.allocator, "        // Cleanup\n");
                                for (cleanup_regs) |reg_id| {
                                    const is_return_reg = reg.id == reg_id;
                                    if (!is_return_reg and self.shouldReleaseReg(reg_id)) {
                                        const suffix = if (alloca_regs.contains(reg_id)) ".*" else "";
                                        try code.appendSlice(self.allocator, "        reg_");
                                        try code.writer(self.allocator).print("{d}", .{reg_id});
                                        try code.appendSlice(self.allocator, suffix);
                                        try code.appendSlice(self.allocator, ".release(runtime.runtime_allocator);\n");
                                    }
                                }
                            }
                            try code.appendSlice(self.allocator, "        return reg_");
                            try code.writer(self.allocator).print("{d}", .{reg.id});
                            try code.appendSlice(self.allocator, ";\n");
                        }
                    } else {
                        // Cleanup before return
                        if (cleanup_regs.len > 0) {
                            try code.appendSlice(self.allocator, "        // Cleanup\n");
                            for (cleanup_regs) |reg_id| {
                                const suffix = if (alloca_regs.contains(reg_id)) ".*" else "";
                                if (!self.shouldReleaseReg(reg_id)) continue;
                                try code.appendSlice(self.allocator, "        reg_");
                                try code.writer(self.allocator).print("{d}", .{reg_id});
                                try code.appendSlice(self.allocator, suffix);
                                try code.appendSlice(self.allocator, ".release(runtime.runtime_allocator);\n");
                            }
                        }
                        try code.appendSlice(self.allocator, "        return;\n");
                    }
                },
                .cond_br => |nested_cond_br| {
                    // 找到嵌套的then和else块
                    var nested_then_idx: ?usize = null;
                    var nested_else_idx: ?usize = null;

                    for (func.blocks.items, 0..) |block, idx| {
                        if (block == nested_cond_br.then_block) nested_then_idx = idx;
                        if (block == nested_cond_br.else_block) nested_else_idx = idx;
                    }

                    // 生成嵌套的if语句
                    try code.appendSlice(self.allocator, "        if (reg_");
                    try code.writer(self.allocator).print("{d}", .{nested_cond_br.cond.id});
                    try code.appendSlice(self.allocator, ") {\n");

                    // 生成嵌套的then块
                    if (nested_then_idx) |idx| {
                        const nested_then_block = func.blocks.items[idx];
                        for (nested_then_block.instructions.items) |inst| {
                            try code.appendSlice(self.allocator, "        ");
                            try self.generateInstructionSimple(code, inst);
                        }
                    }

                    try code.appendSlice(self.allocator, "        }");

                    // 生成嵌套的else块
                    if (nested_else_idx) |idx| {
                        if (nested_then_idx == null or idx != nested_then_idx.?) {
                            try code.appendSlice(self.allocator, " else {\n");
                            const nested_else_block = func.blocks.items[idx];
                            for (nested_else_block.instructions.items) |inst| {
                                try code.appendSlice(self.allocator, "        ");
                                try self.generateInstructionSimple(code, inst);
                            }
                            try code.appendSlice(self.allocator, "        }");
                        }
                    }

                    try code.appendSlice(self.allocator, "\n");
                },
                else => {},
            }
        }

        try code.appendSlice(self.allocator, "    }");

        // 生成else块（如果存在且不同于then块）
        if (else_idx != null and else_idx.? != then_idx.?) {
            try code.appendSlice(self.allocator, " else {\n");
            const else_block = func.blocks.items[else_idx.?];
            for (else_block.instructions.items) |inst| {
                try code.appendSlice(self.allocator, "    ");
                try self.generateInstructionSimple(code, inst);
            }

            // 检查else块的terminator
            if (else_block.terminator) |else_term| {
                switch (else_term) {
                    .ret => |ret_val| {
                        // 生成return语句
                        if (ret_val) |reg| {
                            // 检查函数返回类型
                            const func_has_return_value = self.func_return_types.get(func.name) orelse false;

                            // Cleanup before return
                            if (cleanup_regs.len > 0) {
                                try code.appendSlice(self.allocator, "        // Cleanup\n");
                                for (cleanup_regs) |reg_id| {
                                    const is_return_reg = reg.id == reg_id;
                                    if (!is_return_reg and self.shouldReleaseReg(reg_id)) {
                                        const suffix = if (alloca_regs.contains(reg_id)) ".*" else "";
                                        try code.appendSlice(self.allocator, "        reg_");
                                        try code.writer(self.allocator).print("{d}", .{reg_id});
                                        try code.appendSlice(self.allocator, suffix);
                                        try code.appendSlice(self.allocator, ".release(runtime.runtime_allocator);\n");
                                    }
                                }
                            }

                            if (func_has_return_value) {
                                // 函数返回runtime.Value，需要检查寄存器类型
                                const real_type = self.current_reg_types.?.get(reg.id) orelse reg.type_;
                                const reg_type_tag = @as(std.meta.Tag(IR.Type), real_type);
                                if (reg_type_tag == .i64) {
                                    try code.appendSlice(self.allocator, "        return runtime.Value.initInt(reg_");
                                    try code.writer(self.allocator).print("{d}", .{reg.id});
                                    try code.appendSlice(self.allocator, ".asInt());\n");
                                } else if (reg_type_tag == .f64) {
                                    try code.appendSlice(self.allocator, "        return runtime.Value.initFloat(reg_");
                                    try code.writer(self.allocator).print("{d}", .{reg.id});
                                    try code.appendSlice(self.allocator, ".asFloat());\n");
                                } else if (reg_type_tag == .bool) {
                                    try code.appendSlice(self.allocator, "        return runtime.Value.initBool(reg_");
                                    try code.writer(self.allocator).print("{d}", .{reg.id});
                                    try code.appendSlice(self.allocator, ".toBool());\n");
                                } else {
                                    // 已经是runtime.Value类型
                                    try code.appendSlice(self.allocator, "        return reg_");
                                    try code.writer(self.allocator).print("{d}", .{reg.id});
                                    try code.appendSlice(self.allocator, ";\n");
                                }
                            } else {
                                // 函数返回void或其他类型，直接返回
                                try code.appendSlice(self.allocator, "        return reg_");
                                try code.writer(self.allocator).print("{d}", .{reg.id});
                                try code.appendSlice(self.allocator, ";\n");
                            }
                        } else {
                            // Cleanup before return
                            if (cleanup_regs.len > 0) {
                                try code.appendSlice(self.allocator, "        // Cleanup\n");
                                for (cleanup_regs) |reg_id| {
                                    if (!self.shouldReleaseReg(reg_id)) continue;
                                    const suffix = if (alloca_regs.contains(reg_id)) ".*" else "";
                                    try code.appendSlice(self.allocator, "        reg_");
                                    try code.writer(self.allocator).print("{d}", .{reg_id});
                                    try code.appendSlice(self.allocator, suffix);
                                    try code.appendSlice(self.allocator, ".release(runtime.runtime_allocator);\n");
                                }
                            }
                            try code.appendSlice(self.allocator, "        return;\n");
                        }
                    },
                    .cond_br => |nested_cond_br| {
                        // 找到嵌套的then和else块
                        var nested_then_idx: ?usize = null;
                        var nested_else_idx: ?usize = null;

                        for (func.blocks.items, 0..) |block, idx| {
                            if (block == nested_cond_br.then_block) nested_then_idx = idx;
                            if (block == nested_cond_br.else_block) nested_else_idx = idx;
                        }

                        // 生成嵌套的if语句
                        try code.appendSlice(self.allocator, "        if (reg_");
                        try code.writer(self.allocator).print("{d}", .{nested_cond_br.cond.id});
                        try code.appendSlice(self.allocator, ") {\n");

                        // 生成嵌套的then块
                        if (nested_then_idx) |idx| {
                            const nested_then_block = func.blocks.items[idx];
                            for (nested_then_block.instructions.items) |inst| {
                                try code.appendSlice(self.allocator, "        ");
                                try self.generateInstructionSimple(code, inst);
                            }
                        }

                        try code.appendSlice(self.allocator, "        }");

                        // 生成嵌套的else块
                        if (nested_else_idx) |idx| {
                            if (nested_then_idx == null or idx != nested_then_idx.?) {
                                try code.appendSlice(self.allocator, " else {\n");
                                const nested_else_block = func.blocks.items[idx];
                                for (nested_else_block.instructions.items) |inst| {
                                    try code.appendSlice(self.allocator, "        ");
                                    try self.generateInstructionSimple(code, inst);
                                }
                                try code.appendSlice(self.allocator, "        }");
                            }
                        }

                        try code.appendSlice(self.allocator, "\n");
                    },
                    else => {},
                }
            }

            try code.appendSlice(self.allocator, "    }");
        }

        try code.appendSlice(self.allocator, "\n");

        return true;
    }

    /// 生成控制流状态机（用于复杂控制流）
    fn generateControlFlowStateMachine(self: *Self, code: *std.ArrayList(u8), func: *const IR.Function, cleanup_regs: []const usize, alloca_regs: *const std.AutoHashMap(usize, void)) !void {
        // std.debug.print("generateControlFlowStateMachine: current_reg_types={}\n", .{self.current_reg_types != null});

        // 尝试生成结构化控制流
        const prev_cleanup_regs = self.current_cleanup_regs;
        const prev_alloca_regs = self.current_alloca_regs;
        self.current_cleanup_regs = cleanup_regs;
        self.current_alloca_regs = alloca_regs;
        defer {
            self.current_cleanup_regs = prev_cleanup_regs;
            self.current_alloca_regs = prev_alloca_regs;
        }

        var writer = code.writer(self.allocator);

        // 检查是否有特殊控制流（通过块名或指令判断）
        var has_do_while = false;
        var has_switch = false;
        var has_match = false;
        var has_recursive_call = false;
        var has_foreach = false;

        for (func.blocks.items) |block| {
            if (std.mem.indexOf(u8, block.label, "do_while") != null) has_do_while = true;
            if (std.mem.indexOf(u8, block.label, "switch") != null) has_switch = true;
            if (std.mem.indexOf(u8, block.label, "match") != null) has_match = true;
            if (std.mem.indexOf(u8, block.label, "foreach") != null) has_foreach = true;

            // 检查是否有递归调用
            for (block.instructions.items) |inst| {
                if (inst.op == .call) {
                    const call_data = inst.op.call;
                    if (std.mem.eql(u8, call_data.func_name, func.name)) {
                        has_recursive_call = true;
                        break;
                    }
                }
            }

            if (has_do_while and has_switch and has_match and has_recursive_call and has_foreach) break;
        }

        // 临时禁用结构化控制流生成（AOT-CODEGEN-002）
        // 问题：结构化生成器在循环中错误地将顺序 if 语句识别为嵌套结构
        // 导致在第二个 if 的 then 分支中插入 continue，跳过后续代码
        // 解决方案：使用状态机模式，虽然代码冗长但正确
        if (false) {
            // 如果有特殊控制流，直接跳过结构化尝试
            // foreach 嵌套在其他循环中时也使用状态机（结构化生成器无法正确处理）
            const has_nested_foreach = has_foreach and func.blocks.items.len > 10; // 简单启发式
            if (!func.has_multi_level_break and !has_do_while and !has_switch and !has_match and !has_recursive_call and !has_nested_foreach) {
                const structured_result = try self.tryGenerateStructuredControlFlowNew(&writer, func, cleanup_regs, alloca_regs);
                if (structured_result) {
                    return;
                }
            }
        }

        // 生成状态机
        try code.appendSlice(self.allocator, "    // State machine for complex control flow\n");
        // 回退到状态机
        try code.appendSlice(self.allocator, "    // Control flow state machine\n");
        try code.appendSlice(self.allocator, "    var current_block: u32 = 0;\n");
        try code.appendSlice(self.allocator, "    var prev_block: u32 = 0;\n");
        try code.appendSlice(self.allocator, "    _ = &current_block;\n");
        try code.appendSlice(self.allocator, "    _ = &prev_block;\n");
        try code.appendSlice(self.allocator, "    while (true) {\n");
        try code.appendSlice(self.allocator, "        switch (current_block) {\n");

        // 检查函数是否有返回值
        const func_has_return_value = self.func_return_types.get(func.name) orelse false;

        for (func.blocks.items, 0..) |block, block_idx| {
            // 设置当前异常处理器
            if (block.exception_handler) |handler| {
                self.current_exception_handler = handler.index;
            } else {
                self.current_exception_handler = null;
            }

            if (block.exception_handler) |handler| {
                try writer.print("            {d} => {{ // {s} (handler: {d})\n", .{ block_idx, block.label, handler.index });
            } else {
                try writer.print("            {d} => {{ // {s}\n", .{ block_idx, block.label });
            }

            // 收集所有 phi 节点
            var phi_instructions = std.ArrayList(*const IR.Instruction).initCapacity(self.allocator, 0) catch unreachable;
            defer phi_instructions.deinit(self.allocator);

            var first_non_phi_idx: usize = 0;
            for (block.instructions.items, 0..) |inst, idx| {
                if (inst.op == .phi) {
                    try phi_instructions.append(self.allocator, inst);
                } else {
                    first_non_phi_idx = idx;
                    break;
                }
            }

            // 如果有 phi 节点，生成并行赋值
            if (phi_instructions.items.len > 0) {
                try self.generatePhiInstructionsParallel(code, phi_instructions.items, func);
            }

            // 生成非 phi 指令
            for (block.instructions.items[first_non_phi_idx..], first_non_phi_idx..) |inst, inst_idx| {
                try code.appendSlice(self.allocator, "    ");
                try self.generateInstructionSimple(code, inst);

                // 在指令后，release死亡的操作数（暂时禁用）
                _ = inst_idx;
                // if (self.current_liveness) |liveness| {
                //     try self.releaseDeadOperands(code, block_idx, inst_idx, inst.*, liveness, alloca_regs);
                // }
            }

            // 生成终止指令
            if (block.terminator) |term| {
                try self.generateTerminatorSimple(code, term, cleanup_regs, alloca_regs, func, block_idx, func_has_return_value);
            } else {
                if (block_idx + 1 < func.blocks.items.len) {
                    try writer.print("                prev_block = current_block;\n                current_block = {d};\n", .{block_idx + 1});
                } else {
                    if (cleanup_regs.len > 0) {
                        try code.appendSlice(self.allocator, "                // Cleanup\n");
                        for (cleanup_regs) |reg_id| {
                            const suffix = if (alloca_regs.contains(reg_id)) ".*" else "";
                            if (!self.shouldReleaseReg(reg_id)) continue;
                            try writer.print("                reg_{d}{s}.release(runtime.runtime_allocator);\n", .{ reg_id, suffix });
                        }
                    }
                    try code.appendSlice(self.allocator, "                return runtime.Value.initNull();\n");
                }
            }

            try code.appendSlice(self.allocator, "            },\n");
        }

        try code.appendSlice(self.allocator, "            else => unreachable,\n");
        try code.appendSlice(self.allocator, "        }\n");
        try code.appendSlice(self.allocator, "    }\n");
    }

    /// 生成多个 phi 指令的并行赋值（状态机版本）
    fn generatePhiInstructionsParallel(
        self: *Self,
        code: *std.ArrayList(u8),
        phi_instructions: []*const IR.Instruction,
        func: *const IR.Function,
    ) !void {
        var writer = code.writer(self.allocator);

        // 收集所有 phi 节点的信息
        const PhiInfo = struct {
            result_reg: IR.Register,
            incoming: []const IR.Instruction.PhiIncoming,
        };

        var phi_infos = std.ArrayList(PhiInfo).initCapacity(self.allocator, phi_instructions.len) catch unreachable;
        defer phi_infos.deinit(self.allocator);

        for (phi_instructions) |inst| {
            const result_reg = inst.result orelse continue;
            try phi_infos.append(self.allocator, .{
                .result_reg = result_reg,
                .incoming = inst.op.phi.incoming,
            });
        }

        if (phi_infos.items.len == 0) return;

        // 检查是否所有 phi 节点都只有一个 incoming
        var all_single_incoming = true;
        for (phi_infos.items) |info| {
            if (info.incoming.len != 1) {
                all_single_incoming = false;
                break;
            }
        }

        // 如果都是单个 incoming，直接赋值（不需要 switch）
        if (all_single_incoming) {
            for (phi_infos.items) |info| {
                if (info.incoming.len > 0) {
                    const result_is_ptr = self.isPointerReg(info.result_reg.id);
                    const value_is_ptr = self.isPointerReg(info.incoming[0].value.id);
                    
                    if (result_is_ptr and value_is_ptr) {
                        try writer.print("    reg_{d}.* = reg_{d}.*;\n", .{
                            info.result_reg.id,
                            info.incoming[0].value.id,
                        });
                    } else if (result_is_ptr) {
                        try writer.print("    reg_{d}.* = reg_{d};\n", .{
                            info.result_reg.id,
                            info.incoming[0].value.id,
                        });
                    } else if (value_is_ptr) {
                        try writer.print("    reg_{d} = reg_{d}.*;\n", .{
                            info.result_reg.id,
                            info.incoming[0].value.id,
                        });
                    } else {
                        try writer.print("    reg_{d} = reg_{d};\n", .{
                            info.result_reg.id,
                            info.incoming[0].value.id,
                        });
                    }
                }
            }
            return;
        }

        // 收集所有可能的前驱块
        var pred_blocks = std.AutoHashMap(u32, void).init(self.allocator);
        defer pred_blocks.deinit();

        for (phi_infos.items) |info| {
            for (info.incoming) |incoming| {
                for (func.blocks.items, 0..) |block, idx| {
                    if (block == incoming.block) {
                        try pred_blocks.put(@intCast(idx), {});
                        break;
                    }
                }
            }
        }

        // 如果没有前驱块，跳过switch生成
        if (pred_blocks.count() == 0) return;

        // 为每个前驱块生成并行赋值
        try writer.writeAll("    switch (prev_block) {\n");

        var pred_iter = pred_blocks.keyIterator();
        while (pred_iter.next()) |pred_idx_ptr| {
            const pred_idx = pred_idx_ptr.*;
            try writer.print("        {d} => {{\n", .{pred_idx});

            // 收集这个前驱块的所有赋值
            var assignments = std.ArrayList(PhiAssignment).initCapacity(self.allocator, 0) catch unreachable;
            defer assignments.deinit(self.allocator);

            for (phi_infos.items) |info| {
                for (info.incoming) |incoming| {
                    var incoming_idx: ?u32 = null;
                    for (func.blocks.items, 0..) |block, idx| {
                        if (block == incoming.block) {
                            incoming_idx = @intCast(idx);
                            break;
                        }
                    }
                    if (incoming_idx) |idx| {
                        if (idx == pred_idx) {
                            try assignments.append(self.allocator, .{
                                .result = info.result_reg,
                                .value = incoming.value,
                            });
                            break;
                        }
                    }
                }
            }

            // 使用并行赋值
            try self.generatePhiAssignmentsParallel(writer, assignments.items, "            ");

            try writer.writeAll("        },\n");
        }

        // 默认情况：如果prev_block不在预期范围内，使用第一个incoming的值
        // 这可能发生在控制流优化或未初始化的prev_block场景
        try writer.writeAll("        else => {\n");
        try writer.writeAll("            // Fallback: use first incoming value\n");
        for (phi_infos.items) |info| {
            if (info.incoming.len > 0) {
                const result_is_ptr = self.isPointerReg(info.result_reg.id);
                const value_is_ptr = self.isPointerReg(info.incoming[0].value.id);
                
                if (result_is_ptr and value_is_ptr) {
                    try writer.print("            reg_{d}.* = reg_{d}.*;\n", .{
                        info.result_reg.id,
                        info.incoming[0].value.id,
                    });
                } else if (result_is_ptr) {
                    try writer.print("            reg_{d}.* = reg_{d};\n", .{
                        info.result_reg.id,
                        info.incoming[0].value.id,
                    });
                } else if (value_is_ptr) {
                    try writer.print("            reg_{d} = reg_{d}.*;\n", .{
                        info.result_reg.id,
                        info.incoming[0].value.id,
                    });
                } else {
                    try writer.print("            reg_{d} = reg_{d};\n", .{
                        info.result_reg.id,
                        info.incoming[0].value.id,
                    });
                }
            }
        }
        try writer.writeAll("        },\n");
        try writer.writeAll("    }\n");
    }

    fn generatePhiInstructionStateMachine(self: *Self, code: *std.ArrayList(u8), inst: *const IR.Instruction, func: *const IR.Function) !void {
        var writer = code.writer(self.allocator);
        const phi = inst.op.phi;

        const result_reg = inst.result orelse return;

        // 使用修正后的类型
        const dest_type = if (self.current_register_types) |types|
            types.get(result_reg.id) orelse result_reg.type_
        else
            result_reg.type_;
        const dest_tag = @as(std.meta.Tag(IR.Type), dest_type);
        const dest_is_value = !(dest_tag == .i64 or dest_tag == .f64 or dest_tag == .bool);

        // 收集有效的 incoming 块
        const IncomingItem = struct { idx: u32, src: IR.Register };
        var valid_incoming = try std.ArrayList(IncomingItem).initCapacity(self.allocator, phi.incoming.len);
        defer valid_incoming.deinit(self.allocator);

        for (phi.incoming) |incoming| {
            var pred_idx: ?u32 = null;
            for (func.blocks.items, 0..) |block, idx| {
                if (block == incoming.block) {
                    pred_idx = @intCast(idx);
                    break;
                }
            }
            if (pred_idx) |idx| {
                try valid_incoming.append(self.allocator, .{ .idx = idx, .src = incoming.value });
            }
        }

        // 如果没有有效的incoming，跳过
        if (valid_incoming.items.len == 0) {
            return;
        }

        // 如果只有一个 incoming 值，直接赋值
        if (valid_incoming.items.len == 1) {
            const src = valid_incoming.items[0].src;
            const src_real_type = self.current_reg_types.?.get(src.id) orelse src.type_;
            const src_tag = @as(std.meta.Tag(IR.Type), src_real_type);
            try writer.print("    reg_{d} = ", .{result_reg.id});
            try self.writePhiSourceExpr(writer, dest_is_value, dest_tag, src_tag, src.id);
            try writer.writeAll(";");
            // 注释掉phi的自动retain，因为它导致ref_count多1
            // mem2reg优化后，phi代替store，store本身不应该retain
            // if (dest_is_value and dest_may_heap) {
            //     const src_may_heap = switch (src_tag) {
            //         .i64, .f64, .bool => false,
            //         else => if (self.current_reg_may_heap) |mh| mh[src.id] else true,
            //     };
            //     if (src_may_heap) {
            //         try writer.print(" _ = reg_{d}.retain();", .{result_reg.id});
            //     }
            // }
            try writer.writeAll("\n");
            return;
        }

        // 多个 incoming 值，生成 switch
        try writer.writeAll("    switch (prev_block) {\n");
        for (valid_incoming.items) |item| {
            const src = item.src;
            const src_real_type = self.current_reg_types.?.get(src.id) orelse src.type_;
            const src_tag = @as(std.meta.Tag(IR.Type), src_real_type);
            try writer.print("        {d} => {{ reg_{d} = ", .{ item.idx, result_reg.id });
            try self.writePhiSourceExpr(writer, dest_is_value, dest_tag, src_tag, src.id);
            try writer.writeAll(";");
            // 注释掉phi的自动retain
            // if (dest_is_value and dest_may_heap) {
            //     const src_may_heap = switch (src_tag) {
            //         .i64, .f64, .bool => false,
            //         else => if (self.current_reg_may_heap) |mh| mh[src.id] else true,
            //     };
            //     if (src_may_heap) {
            //         try writer.print(" _ = reg_{d}.retain();", .{result_reg.id});
            //     }
            // }
            try writer.writeAll(" },\n");
        }
        // 默认情况：使用第一个incoming值作为fallback
        if (valid_incoming.items.len > 0) {
            const first_src = valid_incoming.items[0].src;
            const src_real_type = self.current_reg_types.?.get(first_src.id) orelse first_src.type_;
            const src_tag = @as(std.meta.Tag(IR.Type), src_real_type);
            try writer.writeAll("        else => { reg_");
            try writer.print("{d} = ", .{result_reg.id});
            try self.writePhiSourceExpr(writer, dest_is_value, dest_tag, src_tag, first_src.id);
            try writer.writeAll("; },\n");
        } else {
            try writer.writeAll("        else => {},\n");
        }
        try writer.writeAll("    }\n");
    }

    fn writePhiSourceExpr(
        self: *Self,
        writer: anytype,
        dest_is_value: bool,
        dest_tag: std.meta.Tag(IR.Type),
        src_tag: std.meta.Tag(IR.Type),
        src_id: usize,
    ) !void {
        _ = self;
        _ = dest_is_value;
        _ = dest_tag;
        _ = src_tag;
        // 所有寄存器都是 Value 类型，直接使用
        return writer.print("reg_{d}", .{src_id});
    }

    fn writeRegAssignment(
        self: *Self,
        writer: anytype,
        reg_id: usize,
        value_expr: []const u8,
    ) !void {
        const is_alloca = if (self.current_alloca_regs) |alloca_regs|
            alloca_regs.contains(reg_id)
        else
            false;

        if (is_alloca) {
            try writer.print("    reg_{d}.* = {s};\n", .{ reg_id, value_expr });
        } else {
            try self.writeRegAssignmentFmt(writer, reg_id, "{s};\n", .{value_expr});
        }
    }

    /// 写入赋值语句的开始部分（不包括分号和换行）
    /// 返回是否需要解引用
    /// 生成操作数引用（处理 alloca）
    /// 安全的缓冲区格式化：确保不会覆盖输入
    /// 使用独立的临时缓冲区避免 use-after-write
    fn safeBufPrint(buf: []u8, comptime fmt: []const u8, args: anytype) ![]const u8 {
        return try std.fmt.bufPrint(buf, fmt, args);
    }

    fn getOperandRef(self: *Self, buf: []u8, reg_id: usize) ![]const u8 {
        const is_alloca = if (self.current_alloca_regs) |alloca_regs|
            alloca_regs.contains(reg_id)
        else
            false;

        return if (is_alloca)
            try std.fmt.bufPrint(buf, "reg_{d}.*", .{reg_id})
        else
            try std.fmt.bufPrint(buf, "reg_{d}", .{reg_id});
    }

    /// 获取操作数引用，根据期望类型自动添加转换
    fn getOperandRefTyped(self: *Self, buf: []u8, reg_id: usize, expected_type: std.meta.Tag(IR.Type)) ![]const u8 {
        const is_alloca = if (self.current_alloca_regs) |alloca_regs|
            alloca_regs.contains(reg_id)
        else
            false;

        // 使用独立缓冲区避免覆盖
        var temp_buf: [32]u8 = undefined;
        const base_ref = if (is_alloca)
            try std.fmt.bufPrint(&temp_buf, "reg_{d}.*", .{reg_id})
        else
            try std.fmt.bufPrint(&temp_buf, "reg_{d}", .{reg_id});

        // 如果期望类型是基本类型，添加转换
        if (expected_type == .i64) {
            return try std.fmt.bufPrint(buf, "{s}.asInt()", .{base_ref});
        } else if (expected_type == .f64) {
            return try std.fmt.bufPrint(buf, "{s}.asFloat()", .{base_ref});
        } else if (expected_type == .bool) {
            return try std.fmt.bufPrint(buf, "{s}.asBool()", .{base_ref});
        }

        return try std.fmt.bufPrint(buf, "{s}", .{base_ref});
    }

    /// 生成类型包装表达式：将推断类型的寄存器包装为 Value
    /// 例如：i64 -> Value.initInt(reg.asInt())
    /// 生成操作数引用（带类型转换）
    /// 用于二元运算等需要 Value 参数的地方
    fn getOperandValueRef(self: *Self, buf: []u8, operand: IR.Register) ![]const u8 {
        const op_type = if (self.current_register_types) |types|
            types.get(operand.id) orelse operand.type_
        else
            operand.type_;

        const op_tag = @as(std.meta.Tag(IR.Type), op_type);
        return try self.getValueWrapper(buf, operand.id, op_tag);
    }

    fn getValueWrapper(self: *Self, buf: []u8, reg_id: usize, inferred_type: std.meta.Tag(IR.Type)) ![]const u8 {
        const is_alloca = if (self.current_alloca_regs) |alloca_regs|
            alloca_regs.contains(reg_id)
        else
            false;

        // 先生成 base_ref 到临时缓冲区
        var temp_buf: [32]u8 = undefined;
        const base_ref = if (is_alloca)
            try std.fmt.bufPrint(&temp_buf, "reg_{d}.*", .{reg_id})
        else
            try std.fmt.bufPrint(&temp_buf, "reg_{d}", .{reg_id});

        // 根据推断类型生成包装（现在 base_ref 不会被覆盖）
        if (inferred_type == .i64) {
            return try std.fmt.bufPrint(buf, "runtime.Value.initInt({s}.asInt())", .{base_ref});
        } else if (inferred_type == .f64) {
            return try std.fmt.bufPrint(buf, "runtime.Value.initFloat({s}.asFloat())", .{base_ref});
        } else if (inferred_type == .bool) {
            return try std.fmt.bufPrint(buf, "runtime.Value.initBool({s}.toBool())", .{base_ref});
        }

        // php_value 或其他类型，直接返回
        return try std.fmt.bufPrint(buf, "{s}", .{base_ref});
    }

    /// 格式化寄存器引用到 writer（用于替换所有 writer.print("reg_{d}", .{id})）
    fn writeRegRef(self: *Self, writer: anytype, reg_id: usize) !void {
        const is_alloca = if (self.current_alloca_regs) |alloca_regs|
            alloca_regs.contains(reg_id)
        else
            false;

        if (is_alloca) {
            try writer.print("reg_{d}.*", .{reg_id});
        } else {
            try writer.print("reg_{d}", .{reg_id});
        }
    }

    fn writeRegAssignmentPrefix(
        self: *Self,
        writer: anytype,
        reg_id: usize,
    ) !void {
        const is_alloca = if (self.current_alloca_regs) |alloca_regs|
            alloca_regs.contains(reg_id)
        else
            false;

        if (is_alloca) {
            try writer.print("    reg_{d}.* = ", .{reg_id});
        } else {
            try writer.print("    reg_{d} = ", .{reg_id});
        }
    }

    /// Phi 赋值结构
    const PhiAssignment = struct {
        result: IR.Register,
        value: IR.Register,
    };

    /// 生成 phi 节点的值赋值（统一函数）
    /// 使用原始类型，不是推断类型，确保类型一致
    ///
    /// 注意：这个函数只生成单个 phi 赋值
    /// 对于多个相互依赖的 phi 节点，调用者需要处理并行赋值语义
    fn generatePhiValueAssignment(
        self: *Self,
        writer: anytype,
        result_reg: IR.Register,
        value_reg: IR.Register,
        indent: []const u8,
    ) !void {
        // 使用原始类型，不是推断类型
        const result_tag = @as(std.meta.Tag(IR.Type), result_reg.type_);

        // 检查value_reg是否是alloca
        const value_is_alloca = if (self.current_alloca_regs) |regs|
            regs.contains(value_reg.id)
        else
            false;
        const result_is_alloca = if (self.current_alloca_regs) |regs|
            regs.contains(result_reg.id)
        else
            false;

        // 如果结果是 php_value，总是直接赋值（所有寄存器都是 Value）
        if (result_tag == .php_value) {
            if (result_is_alloca and value_is_alloca) {
                try writer.print("{s}reg_{d}.* = reg_{d}.*;\n", .{ indent, result_reg.id, value_reg.id });
            } else if (result_is_alloca) {
                try writer.print("{s}reg_{d}.* = reg_{d};\n", .{ indent, result_reg.id, value_reg.id });
            } else if (value_is_alloca) {
                try writer.print("{s}reg_{d} = reg_{d}.*;\n", .{ indent, result_reg.id, value_reg.id });
            } else {
                try writer.print("{s}reg_{d} = reg_{d};\n", .{ indent, result_reg.id, value_reg.id });
            }
        } else {
            // 结果是原生类型（不应该发生，因为所有寄存器都是 Value）
            // 但为了安全，还是处理一下
            if (result_is_alloca and value_is_alloca) {
                try writer.print("{s}reg_{d}.* = reg_{d}.*;\n", .{ indent, result_reg.id, value_reg.id });
            } else if (result_is_alloca) {
                try writer.print("{s}reg_{d}.* = reg_{d};\n", .{ indent, result_reg.id, value_reg.id });
            } else if (value_is_alloca) {
                try writer.print("{s}reg_{d} = reg_{d}.*;\n", .{ indent, result_reg.id, value_reg.id });
            } else {
                try writer.print("{s}reg_{d} = reg_{d};\n", .{ indent, result_reg.id, value_reg.id });
            }
        }
    }

    /// 生成多个 phi 节点的并行赋值
    /// 处理相互依赖的情况，使用临时变量
    fn generatePhiAssignmentsParallel(
        self: *Self,
        writer: anytype,
        assignments: []const PhiAssignment,
        indent: []const u8,
    ) !void {
        if (assignments.len == 0) return;

        // 检测每个赋值是否有依赖
        var needs_temp = try std.ArrayList(bool).initCapacity(self.allocator, assignments.len);
        defer needs_temp.deinit(self.allocator);

        for (assignments) |assign1| {
            var has_dep = false;
            for (assignments) |assign2| {
                // 如果 assign1 的结果是 assign2 的源，则 assign2 需要临时变量
                if (assign1.result.id == assign2.value.id and assign1.result.id != assign2.result.id) {
                    has_dep = true;
                    break;
                }
            }
            try needs_temp.append(self.allocator, has_dep);
        }

        // 检查是否有任何依赖
        var has_any_dependency = false;
        for (needs_temp.items) |need| {
            if (need) {
                has_any_dependency = true;
                break;
            }
        }

        if (!has_any_dependency) {
            // 无依赖，直接赋值（不需要retain，因为phi代替store）
            for (assignments) |assign| {
                const value_is_ptr = self.isPointerReg(assign.value.id);
                const result_is_ptr = self.isPointerReg(assign.result.id);

                if (result_is_ptr and value_is_ptr) {
                    try writer.print("{s}reg_{d}.* = reg_{d}.*;\n", .{ indent, assign.result.id, assign.value.id });
                } else if (result_is_ptr) {
                    try writer.print("{s}reg_{d}.* = reg_{d};\n", .{ indent, assign.result.id, assign.value.id });
                } else if (value_is_ptr) {
                    try writer.print("{s}reg_{d} = reg_{d}.*;\n", .{ indent, assign.result.id, assign.value.id });
                } else {
                    try writer.print("{s}reg_{d} = reg_{d};\n", .{ indent, assign.result.id, assign.value.id });
                }
                // 注释掉retain，避免ref_count多1
                // try writer.print("{s}_ = reg_{d}.retain();\n", .{ indent, assign.result.id });
            }
        } else {
            // 有依赖，只为需要的赋值使用临时变量
            // 第一步：保存需要临时变量的源值
            for (assignments, 0..) |assign, i| {
                if (needs_temp.items[i]) {
                    const value_is_ptr = self.isPointerReg(assign.value.id);
                    if (value_is_ptr) {
                        try writer.print("{s}const phi_temp_{d} = reg_{d}.*;\n", .{ indent, i, assign.value.id });
                    } else {
                        try writer.print("{s}const phi_temp_{d} = reg_{d};\n", .{ indent, i, assign.value.id });
                    }
                }
            }
            // 第二步：赋值（不需要retain）
            for (assignments, 0..) |assign, i| {
                const result_is_ptr = self.isPointerReg(assign.result.id);

                if (needs_temp.items[i]) {
                    if (result_is_ptr) {
                        try writer.print("{s}reg_{d}.* = phi_temp_{d};\n", .{ indent, assign.result.id, i });
                    } else {
                        try writer.print("{s}reg_{d} = phi_temp_{d};\n", .{ indent, assign.result.id, i });
                    }
                } else {
                    const value_is_ptr = self.isPointerReg(assign.value.id);
                    if (result_is_ptr and value_is_ptr) {
                        try writer.print("{s}reg_{d}.* = reg_{d}.*;\n", .{ indent, assign.result.id, assign.value.id });
                    } else if (result_is_ptr) {
                        try writer.print("{s}reg_{d}.* = reg_{d};\n", .{ indent, assign.result.id, assign.value.id });
                    } else if (value_is_ptr) {
                        try writer.print("{s}reg_{d} = reg_{d}.*;\n", .{ indent, assign.result.id, assign.value.id });
                    } else {
                        try writer.print("{s}reg_{d} = reg_{d};\n", .{ indent, assign.result.id, assign.value.id });
                    }
                }
                // 注释掉retain
                // try writer.print("{s}_ = reg_{d}.retain();\n", .{ indent, assign.result.id });
            }
        }
    }

    /// 生成完整的赋值语句（包括分号和换行）
    /// format_str 不应包含 "reg_{d} = " 前缀
    fn writeRegAssignmentFmt(
        self: *Self,
        writer: anytype,
        reg_id: usize,
        comptime format_str: []const u8,
        args: anytype,
    ) !void {
        // 检测错误模式
        if (std.mem.indexOf(u8, format_str, "initInt(reg_") != null and
            std.mem.indexOf(u8, format_str, "asInt") == null)
        {
            std.debug.print("ERROR: reg_{d} = {s}\n", .{ reg_id, format_str });
            @panic("Found initInt(reg_) without asInt()!");
        }
        try self.writeRegAssignmentPrefix(writer, reg_id);
        try writer.print(format_str, args);
    }

    /// 统一的二元运算结果赋值
    /// 自动处理alloca解引用和类型转换
    fn writeBinaryOpAssignment(
        self: *Self,
        writer: anytype,
        result_reg: usize,
        result_type: std.meta.Tag(IR.Type),
        op_name: []const u8,
        lhs_reg: usize,
        rhs_reg: usize,
    ) !void {
        try self.writeRegAssignmentPrefix(writer, result_reg);

        switch (result_type) {
            .php_value => {
                try writer.print("try runtime.{s}(", .{op_name});
                try self.writeRegAccess(writer, lhs_reg);
                try writer.writeAll(", ");
                try self.writeRegAccess(writer, rhs_reg);
                try writer.writeAll(");\n");
            },
            .i64 => {
                try writer.print("(try runtime.{s}(", .{op_name});
                try self.writeRegAccess(writer, lhs_reg);
                try writer.writeAll(", ");
                try self.writeRegAccess(writer, rhs_reg);
                try writer.writeAll(")).asInt();\n");
            },
            .f64 => {
                try writer.print("(try runtime.{s}(", .{op_name});
                try self.writeRegAccess(writer, lhs_reg);
                try writer.writeAll(", ");
                try self.writeRegAccess(writer, rhs_reg);
                try writer.writeAll(")).asFloat();\n");
            },
            .bool => {
                try writer.print("(try runtime.{s}(", .{op_name});
                try self.writeRegAccess(writer, lhs_reg);
                try writer.writeAll(", ");
                try self.writeRegAccess(writer, rhs_reg);
                try writer.writeAll(")).asBool();\n");
            },
            else => {
                try writer.print("try runtime.{s}(", .{op_name});
                try self.writeRegAccess(writer, lhs_reg);
                try writer.writeAll(", ");
                try self.writeRegAccess(writer, rhs_reg);
                try writer.writeAll(");\n");
            },
        }
    }

    /// 统一的寄存器访问（自动处理alloca解引用）
    fn writeRegAccess(self: *Self, writer: anytype, reg_id: usize) !void {
        const is_alloca = if (self.current_alloca_regs) |regs|
            regs.contains(reg_id)
        else
            false;

        if (is_alloca) {
            try writer.print("reg_{d}.*", .{reg_id});
        } else {
            try writer.print("reg_{d}", .{reg_id});
        }
    }

    /// 统一的条件表达式生成
    /// 根据寄存器的实际类型生成正确的条件判断代码
    fn writeConditionExpr(
        self: *Self,
        writer: anytype,
        reg_id: usize,
        ir_type: IR.Type,
    ) !void {
        _ = ir_type; // 忽略IR类型，因为所有寄存器实际上都是Value类型

        // 检查是否是 alloca
        const is_alloca = if (self.current_alloca_regs) |alloca_regs|
            alloca_regs.contains(reg_id)
        else
            false;

        // 所有寄存器都是runtime.Value类型，统一使用toBool()
        if (is_alloca) {
            try writer.print("reg_{d}.*.toBool()", .{reg_id});
        } else {
            try writer.print("reg_{d}.toBool()", .{reg_id});
        }
    }

    fn writePhpValueExpr(
        self: *Self,
        writer: anytype,
        type_tag: std.meta.Tag(IR.Type),
        reg_id: usize,
    ) !void {
        // 检查是否是 alloca 寄存器
        const is_alloca = if (self.current_alloca_regs) |alloca_regs|
            alloca_regs.contains(reg_id)
        else
            false;

        // alloca 寄存器总是 *runtime.Value，需要解引用
        if (is_alloca) {
            return writer.print("reg_{d}.*", .{reg_id});
        }

        // 优先使用推断类型（来自 TypeInferencePass）
        const inferred_tag: ?std.meta.Tag(IR.Type) = if (self.current_inferred_types) |itypes| blk: {
            if (itypes.get(reg_id)) |inferred| {
                break :blk @as(std.meta.Tag(IR.Type), inferred);
            }
            break :blk null;
        } else null;

        // 其次使用寄存器声明类型
        const register_tag: std.meta.Tag(IR.Type) = if (self.current_register_types) |types| blk: {
            if (types.get(reg_id)) |corrected_type| {
                break :blk @as(std.meta.Tag(IR.Type), corrected_type);
            }
            break :blk type_tag;
        } else type_tag;

        // 最终有效类型：寄存器纠正类型为 php_value 时优先级最高（防止推断把 Value 误当标量）。
        // 其他情况仍按：推断类型 > 寄存器类型 > 参数类型。
        const effective_tag: std.meta.Tag(IR.Type) = if (register_tag == .php_value)
            .php_value
        else
            (inferred_tag orelse register_tag);

        // 如果有效类型已经是 php_value，直接使用
        if (effective_tag == .php_value) {
            return writer.print("reg_{d}", .{reg_id});
        }

        // 所有寄存器都是 Value 类型，直接使用
        return writer.print("reg_{d}", .{reg_id});
    }

    fn writeBoolExpr(
        self: *Self,
        writer: anytype,
        type_tag: std.meta.Tag(IR.Type),
        reg_id: usize,
    ) !void {
        // 检查是否是 alloca 寄存器
        const is_alloca = if (self.current_alloca_regs) |alloca_regs|
            alloca_regs.contains(reg_id)
        else
            false;

        // alloca 寄存器总是 *runtime.Value，需要解引用
        if (is_alloca) {
            return writer.print("reg_{d}.*.toBool()", .{reg_id});
        }

        // 优先使用推断类型
        const inferred_tag: ?std.meta.Tag(IR.Type) = if (self.current_inferred_types) |itypes| blk: {
            if (itypes.get(reg_id)) |inferred| {
                break :blk @as(std.meta.Tag(IR.Type), inferred);
            }
            break :blk null;
        } else null;

        const register_tag: std.meta.Tag(IR.Type) = if (self.current_register_types) |types| blk: {
            if (types.get(reg_id)) |corrected_type| {
                break :blk @as(std.meta.Tag(IR.Type), corrected_type);
            }
            break :blk type_tag;
        } else type_tag;

        const effective_tag = inferred_tag orelse register_tag;

        if (effective_tag == .bool) return writer.print("reg_{d}.toBool()", .{reg_id});
        if (effective_tag == .i64) return writer.print("(reg_{d} != 0)", .{reg_id});
        if (effective_tag == .f64) return writer.print("(reg_{d} != 0.0)", .{reg_id});
        return writer.print("reg_{d}.toBool()", .{reg_id});
    }

    fn writeValueArgs(
        self: *Self,
        writer: anytype,
        args: []const IR.Register,
    ) !void {
        for (args, 0..) |arg, i| {
            if (i > 0) try writer.writeAll(", ");

            // 使用 writeRegRef 处理 alloca 解引用
            try self.writeRegRef(writer, arg.id);
        }
    }

    fn writeValueArgsArray(
        self: *Self,
        writer: anytype,
        args: []const IR.Register,
    ) !void {
        return self.writeValueArgsArrayWithRefs(writer, args, null, &[_]u32{});
    }

    fn writeStrGetcsvArgs(
        self: *Self,
        writer: anytype,
        args: []const IR.Register,
    ) !void {
        if (args.len > 0) {
            const arg0 = args[0];
            try self.writePhpValueExpr(writer, @as(std.meta.Tag(IR.Type), arg0.type_), arg0.id);
        } else {
            try writer.writeAll("runtime.Value.initNull()");
        }
        try writer.writeAll(", ");

        if (args.len > 1) {
            const arg1 = args[1];
            try self.writePhpValueExpr(writer, @as(std.meta.Tag(IR.Type), arg1.type_), arg1.id);
        } else {
            try writer.writeAll("runtime.Value.initString(runtime.PHPString.initStatic(\",\"))");
        }
        try writer.writeAll(", ");

        if (args.len > 2) {
            const arg2 = args[2];
            try self.writePhpValueExpr(writer, @as(std.meta.Tag(IR.Type), arg2.type_), arg2.id);
        } else {
            try writer.writeAll("runtime.Value.initString(runtime.PHPString.initStatic(\"\\\"\"))");
        }
        try writer.writeAll(", ");

        if (args.len > 3) {
            const arg3 = args[3];
            try self.writePhpValueExpr(writer, @as(std.meta.Tag(IR.Type), arg3.type_), arg3.id);
        } else {
            try writer.writeAll("runtime.Value.initString(runtime.PHPString.initStatic(\"\\\\\"))");
        }
    }

    fn writeValueArgsArrayWithRefs(
        self: *Self,
        writer: anytype,
        args: []const IR.Register,
        func_name: ?[]const u8,
        ref_params: []const u32,
    ) !void {
        _ = func_name;

        try writer.writeAll("&[_]runtime.Value{");
        if (args.len > 0) {
            for (args, 0..) |arg, i| {
                if (i > 0) try writer.writeAll(", ");

                // 检查是否是引用参数
                var is_ref = false;
                for (ref_params) |ref_idx| {
                    if (ref_idx == i) {
                        is_ref = true;
                        break;
                    }
                }

                if (is_ref) {
                    // 引用参数：生成initRef
                    const arg_type = @as(std.meta.Tag(IR.Type), arg.type_);
                    if (arg_type == .ptr) {
                        // 已经是指针，直接initRef
                        try writer.print("runtime.Value.initRef(&reg_{d}", .{arg.id});
                        if (self.current_alloca_regs) |alloca_regs| {
                            if (alloca_regs.contains(arg.id)) {
                                try writer.writeAll(".*");
                            }
                        }
                        try writer.writeAll(")");
                    } else {
                        // 不是指针，按普通参数处理
                        try self.writeRegRef(writer, arg.id);
                    }
                } else {
                    // 普通参数
                    try self.writeRegRef(writer, arg.id);
                }
            }
        }
        try writer.writeAll("}");
    }

    /// 生成终止指令（简化版，用于状态机）
    fn generateTerminatorSimple(self: *Self, code: *std.ArrayList(u8), term: IR.Terminator, cleanup_regs: []const usize, alloca_regs: *const std.AutoHashMap(usize, void), func: *const IR.Function, current_block_idx: usize, _: bool) !void {
        var writer = code.writer(self.allocator);
        switch (term) {
            .ret => |ret_val| {
                if (cleanup_regs.len > 0) {
                    try code.appendSlice(self.allocator, "                // Cleanup (except return value)\n");
                    for (cleanup_regs) |reg_id| {
                        // 检查是否是返回值寄存器
                        const is_return_reg = if (ret_val) |reg| reg.id == reg_id else false;
                        if (!is_return_reg and self.shouldReleaseReg(reg_id)) {
                            if (self.ref_param_alloca_map) |map| {
                                if (map.get(reg_id)) |_| continue;
                            }
                            if (self.current_ref_ptr_regs) |rpr| {
                                if (rpr.contains(reg_id)) continue;
                            }
                            // 只cleanup alloca寄存器（局部变量）
                            // 其他寄存器（临时值）可能被返回值引用，不安全释放
                            if (alloca_regs.contains(reg_id)) {
                                try writer.print("                reg_{d}.*.release(runtime.runtime_allocator);\n", .{reg_id});
                            }
                        }
                    }
                }
                if (ret_val) |reg| {
                    // 始终返回原始 Value，不做类型转换
                    const is_alloca = alloca_regs.contains(reg.id);
                    if (is_alloca) {
                        try writer.print("                return reg_{d}.*;\n", .{reg.id});
                    } else {
                        try writer.print("                return reg_{d};\n", .{reg.id});
                    }
                } else {
                    try code.appendSlice(self.allocator, "                return runtime.Value.initNull();\n");
                }
            },
            .br => |target| {
                // 找到目标块的索引
                var target_idx: usize = 0;
                for (func.blocks.items, 0..) |block, idx| {
                    if (block == target) {
                        target_idx = idx;
                        break;
                    }
                }

                // 收集所有 phi 赋值
                var assignments = std.ArrayList(PhiAssignment).initCapacity(self.allocator, 0) catch unreachable;
                defer assignments.deinit(self.allocator);

                const source_block = func.blocks.items[current_block_idx];
                for (target.instructions.items) |inst| {
                    if (inst.op == .phi) {
                        const phi_op = inst.op.phi;
                        const result_reg = inst.result orelse continue;
                        for (phi_op.incoming) |incoming| {
                            if (incoming.block == source_block) {
                                try assignments.append(self.allocator, .{ .result = result_reg, .value = incoming.value });
                                break;
                            }
                        }
                    }
                }

                // 使用并行赋值
                try self.generatePhiAssignmentsParallel(writer, assignments.items, "            ");

                try writer.print("                prev_block = current_block;\n                current_block = {d};\n", .{target_idx});
            },
            .cond_br => |br| {
                // 找到then和else块的索引
                var then_idx: usize = 0;
                var else_idx: usize = 0;
                for (func.blocks.items, 0..) |block, idx| {
                    if (block == br.then_block) then_idx = idx;
                    if (block == br.else_block) else_idx = idx;
                }

                try writer.writeAll("                if (");
                try self.writeConditionExpr(writer, br.cond.id, br.cond.type_);
                try writer.writeAll(") {\n");

                // 设置 then 分支的 phi 值
                try self.generatePhiAssignments(writer, func, br.then_block, current_block_idx);

                try writer.print("                    prev_block = current_block;\n                    current_block = {d};\n                }} else {{\n", .{then_idx});

                // 设置 else 分支的 phi 值
                try self.generatePhiAssignments(writer, func, br.else_block, current_block_idx);

                try writer.print("                    prev_block = current_block;\n                    current_block = {d};\n                }}\n", .{else_idx});
            },
            .switch_ => |sw| {
                try writer.writeAll("                prev_block = current_block;\n");

                // 查找 switch value 对应的 global_get 变量名
                const sw_var_name = if (self.current_global_get_names) |gn| gn.get(sw.value.id) else null;
                const src_file = blk_src: {
                    if (func.location.file.len > 0 and !std.mem.eql(u8, func.location.file, "<unknown>")) break :blk_src func.location.file;
                    // fallback: 从块内指令取源文件路径
                    for (func.blocks.items) |blk_s| {
                        for (blk_s.instructions.items) |inst_s| {
                            if (inst_s.location.line > 0 and inst_s.location.file.len > 0) break :blk_src inst_s.location.file;
                        }
                    }
                    break :blk_src "<unknown>";
                };

                if (sw_var_name != null and sw.cases.len > 0) {
                    // PHP 行为：每个 case 比较处发 Warning + 使用 case 行号
                    try writer.print("                {{\n", .{});
                    try writer.print("                    const __sw_v = reg_{d}.toInt();\n", .{sw.value.id});
                    try writer.print("                    var __sw_done: bool = false;\n", .{});
                    try writer.print("                    _ = &__sw_done;\n", .{});

                    for (sw.cases) |case| {
                        var case_idx: usize = 0;
                        for (func.blocks.items, 0..) |block, idx| {
                            if (block == case.block) {
                                case_idx = idx;
                                break;
                            }
                        }

                        try writer.print("                    if (!__sw_done) {{\n", .{});
                        if (case.source_line > 0) {
                            try writer.print("                        runtime.setSourceLocation(\"{s}\", {d});\n", .{ src_file, case.source_line });
                        }
                        try writer.print("                        if (__sw_undef_{d}) runtime.emitWarning(\"Undefined variable {s}\");\n", .{ sw.value.id, sw_var_name.? });
                        try writer.print("                        if (__sw_v == {d}) {{ current_block = {d}; __sw_done = true; }}\n", .{ case.value, case_idx });
                        try writer.print("                    }}\n", .{});
                    }

                    // default 分支
                    var default_idx: usize = 0;
                    for (func.blocks.items, 0..) |block, idx| {
                        if (block == sw.default) {
                            default_idx = idx;
                            break;
                        }
                    }
                    try writer.print("                    if (!__sw_done) {{ current_block = {d}; }}\n", .{default_idx});
                    try writer.print("                }}\n", .{});
                } else {
                    // 非 global_get 变量或无 case：保持原始 Zig switch
                    try writer.print("                switch (reg_{d}.toInt()) {{\n", .{sw.value.id});
                    for (sw.cases) |case| {
                        var case_idx: usize = 0;
                        for (func.blocks.items, 0..) |block, idx| {
                            if (block == case.block) {
                                case_idx = idx;
                                break;
                            }
                        }
                        try writer.print("                    {d} => current_block = {d},\n", .{ case.value, case_idx });
                    }
                    var default_idx: usize = 0;
                    for (func.blocks.items, 0..) |block, idx| {
                        if (block == sw.default) {
                            default_idx = idx;
                            break;
                        }
                    }
                    try writer.print("                    else => current_block = {d},\n", .{default_idx});
                    try writer.writeAll("                }\n");
                }
            },
            .throw => |ex_reg| {
                const is_alloca = if (self.current_alloca_regs) |regs| regs.contains(ex_reg.id) else false;
                if (is_alloca) {
                    try writer.print("                runtime.setException(reg_{d}.*);\n", .{ex_reg.id});
                } else {
                    try writer.print("                runtime.setException(reg_{d});\n", .{ex_reg.id});
                }

                // 清理资源
                if (cleanup_regs.len > 0) {
                    try code.appendSlice(self.allocator, "                // Cleanup before throw\n");
                    for (cleanup_regs) |reg_id| {
                        // 跳过异常对象本身
                        if (reg_id == ex_reg.id) continue;

                        // 跳过 alloca 寄存器（它们是局部变量，会在函数结束时自动清理）
                        if (alloca_regs.contains(reg_id)) continue;

                        if (!self.shouldReleaseReg(reg_id)) continue;
                        // 不要释放异常对象本身，因为它已经被 setException 接管（retain）了
                        try writer.print("                reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                        // 释放后必须置null，防止catch块或后续代码访问悬垂指针（use-after-free）
                        try writer.print("                reg_{d} = runtime.Value.initNull();\n", .{reg_id});
                    }
                }

                if (self.current_exception_handler) |handler_idx| {
                    try writer.print("                current_block = {d};\n", .{handler_idx});
                } else {
                    // 返回 null 而非 error，让调用方的 hasException() 检查路由到 catch 块
                    try code.appendSlice(self.allocator, "                return runtime.Value.initNull();\n");
                }
            },
            else => {
                try code.appendSlice(self.allocator, "                return runtime.Value.initNull();\n");
            },
        }
    }

    /// 尝试生成while循环（简化版，用于generateFunction）
    fn tryGenerateWhileLoopSimple(self: *Self, code: *std.ArrayList(u8), func: *const IR.Function) !bool {
        // 需要至少4个块：entry, cond, body, exit
        if (func.blocks.items.len < 4) {
            return false;
        }

        const entry_block = func.blocks.items[0];

        // entry块必须以br终止，跳转到条件块
        const entry_term = entry_block.terminator orelse return false;
        if (entry_term != .br) {
            return false;
        }

        const cond_block_ptr = entry_term.br;
        var cond_idx: usize = 0;
        for (func.blocks.items, 0..) |block, idx| {
            if (block == cond_block_ptr) {
                cond_idx = idx;
                break;
            }
        }

        // 条件块必须存在且不是entry块
        if (cond_idx == 0) {
            return false;
        }

        const cond_block = func.blocks.items[cond_idx];

        // 条件块必须以cond_br终止
        const cond_term = cond_block.terminator orelse return false;
        if (cond_term != .cond_br) {
            return false;
        }

        const cond_br = cond_term.cond_br;
        var body_idx: usize = 0;
        var exit_idx: usize = 0;
        for (func.blocks.items, 0..) |block, idx| {
            if (block == cond_br.then_block) body_idx = idx;
            if (block == cond_br.else_block) exit_idx = idx;
        }

        // body块和exit块必须不同
        if (body_idx == exit_idx) {
            return false;
        }

        const body_block = func.blocks.items[body_idx];

        // body块必须以br终止，跳转回条件块（回边）
        const body_term = body_block.terminator orelse return false;
        if (body_term != .br) {
            return false;
        }

        var body_target_idx: usize = 0;
        for (func.blocks.items, 0..) |block, idx| {
            if (block == body_term.br) {
                body_target_idx = idx;
                break;
            }
        }

        if (body_target_idx != cond_idx) {
            // body块不是跳转回条件块，不是简单while循环
            return false;
        }

        // 所有条件满足，生成while循环
        try code.appendSlice(self.allocator, "    // Simple while loop (optimized, no state machine)\n");

        // 生成entry块的指令（初始化代码）
        for (entry_block.instructions.items) |inst| {
            try self.generateInstructionSimple(code, inst);
        }

        // 生成while循环
        try code.appendSlice(self.allocator, "    while (true) {\n");

        // 生成条件块的指令
        for (cond_block.instructions.items) |inst| {
            try code.appendSlice(self.allocator, "    ");
            try self.generateInstructionSimple(code, inst);
        }

        // 生成条件判断
        var writer = code.writer(self.allocator);

        // 根据条件寄存器的类型生成不同的代码
        if (cond_br.cond.type_ == .bool) {
            try writer.writeAll("        if (!");
            try writer.print("reg_{d}", .{cond_br.cond.id});
            try writer.writeAll(") break;\n");
        } else {
            try writer.writeAll("        if (!");
            try writer.print("reg_{d}", .{cond_br.cond.id});
            try writer.writeAll(".toBool()) break;\n");
        }

        // 生成body块的指令
        try code.appendSlice(self.allocator, "        // Loop body\n");

        // 收集body块中需要释放的临时寄存器
        var body_temps: std.ArrayList(usize) = .empty;
        defer body_temps.deinit(self.allocator);

        for (body_block.instructions.items) |inst| {
            if (inst.result) |reg| {
                // 检查是否是创建临时对象的指令
                switch (inst.op) {
                    .const_string, .concat, .array_new, .cast => {
                        // 这些指令可能创建新的Value，需要在循环体结束时释放
                        // 但要排除存储到变量的情况
                        try body_temps.append(self.allocator, reg.id);
                    },
                    else => {},
                }
            }
        }

        for (body_block.instructions.items) |inst| {
            try code.appendSlice(self.allocator, "    ");
            try self.generateInstructionSimple(code, inst);
        }

        // 在循环体结束时释放临时对象
        if (body_temps.items.len > 0) {
            try code.appendSlice(self.allocator, "        // Release loop body temporaries\n");
            for (body_temps.items) |reg_id| {
                try code.appendSlice(self.allocator, "        reg_");
                try code.writer(self.allocator).print("{d}", .{reg_id});
                try code.appendSlice(self.allocator, ".release(runtime.runtime_allocator);\n");
            }
        }

        try code.appendSlice(self.allocator, "    }\n");

        // 生成exit块的代码
        const exit_block = func.blocks.items[exit_idx];
        try code.appendSlice(self.allocator, "    // After loop\n");
        for (exit_block.instructions.items) |inst| {
            try self.generateInstructionSimple(code, inst);
        }

        return true;
    }

    /// 尝试生成for循环（简化版，用于generateFunction）
    fn tryGenerateForLoopSimple(self: *Self, code: *std.ArrayList(u8), func: *const IR.Function) !bool {
        // 需要至少5个块：entry, cond, body, loop, exit
        if (func.blocks.items.len < 5) {
            return false;
        }

        const entry_block = func.blocks.items[0];

        // entry块必须以br终止，跳转到条件块
        const entry_term = entry_block.terminator orelse return false;
        if (entry_term != .br) {
            return false;
        }

        const cond_block_ptr = entry_term.br;
        var cond_idx: usize = 0;
        for (func.blocks.items, 0..) |block, idx| {
            if (block == cond_block_ptr) {
                cond_idx = idx;
                break;
            }
        }

        // 条件块必须存在且不是entry块
        if (cond_idx == 0) {
            return false;
        }

        const cond_block = func.blocks.items[cond_idx];

        // 条件块必须以cond_br终止
        const cond_term = cond_block.terminator orelse return false;
        if (cond_term != .cond_br) {
            return false;
        }

        const cond_br = cond_term.cond_br;
        var body_idx: usize = 0;
        var exit_idx: usize = 0;
        for (func.blocks.items, 0..) |block, idx| {
            if (block == cond_br.then_block) body_idx = idx;
            if (block == cond_br.else_block) exit_idx = idx;
        }

        // body块和exit块必须不同
        if (body_idx == exit_idx) {
            return false;
        }

        const body_block = func.blocks.items[body_idx];

        // body块必须以br终止，跳转到loop块
        const body_term = body_block.terminator orelse return false;
        if (body_term != .br) {
            return false;
        }

        var loop_idx: usize = 0;
        for (func.blocks.items, 0..) |block, idx| {
            if (block == body_term.br) {
                loop_idx = idx;
                break;
            }
        }

        // loop块不能是条件块（那是while循环）
        if (loop_idx == cond_idx) {
            return false;
        }

        const loop_block = func.blocks.items[loop_idx];

        // loop块必须以br终止，跳转回条件块（回边）
        const loop_term = loop_block.terminator orelse return false;
        if (loop_term != .br) {
            return false;
        }

        var loop_target_idx: usize = 0;
        for (func.blocks.items, 0..) |block, idx| {
            if (block == loop_term.br) {
                loop_target_idx = idx;
                break;
            }
        }

        if (loop_target_idx != cond_idx) {
            // loop块不是跳转回条件块，不是简单for循环
            return false;
        }

        // 检查exit块是否是最后一个块
        // 如果不是，说明有更复杂的控制流，应该使用状态机
        if (exit_idx != func.blocks.items.len - 1) {
            return false;
        }

        // 所有条件满足，生成for循环
        try code.appendSlice(self.allocator, "    // Simple for loop (optimized, no state machine)\n");

        // 生成entry块的指令（初始化代码）
        for (entry_block.instructions.items) |inst| {
            try self.generateInstructionSimple(code, inst);
        }

        // 生成while循环（Zig没有for循环，用while模拟）
        try code.appendSlice(self.allocator, "    while (true) {\n");

        // 生成条件块的指令
        for (cond_block.instructions.items) |inst| {
            try code.appendSlice(self.allocator, "    ");
            try self.generateInstructionSimple(code, inst);
        }

        // 生成条件判断
        var writer = code.writer(self.allocator);

        // 根据条件寄存器的类型生成不同的代码
        if (cond_br.cond.type_ == .bool) {
            try writer.writeAll("        if (!");
            try writer.print("reg_{d}", .{cond_br.cond.id});
            try writer.writeAll(") { @branchHint(.unlikely); break; }\n");
        } else {
            try writer.writeAll("        if (!");
            try writer.print("reg_{d}", .{cond_br.cond.id});
            try writer.writeAll(".toBool()) { @branchHint(.unlikely); break; }\n");
        }

        // 生成body块的指令
        try code.appendSlice(self.allocator, "        // Loop body\n");

        // 收集body块中需要释放的临时寄存器
        var body_temps: std.ArrayList(usize) = .empty;
        defer body_temps.deinit(self.allocator);

        for (body_block.instructions.items) |inst| {
            if (inst.result) |reg| {
                // 检查是否是创建临时对象的指令
                switch (inst.op) {
                    .const_string, .concat, .array_new, .cast => {
                        // 这些指令可能创建新的Value，需要在循环体结束时释放
                        try body_temps.append(self.allocator, reg.id);
                    },
                    else => {},
                }
            }
        }

        for (body_block.instructions.items) |inst| {
            try code.appendSlice(self.allocator, "    ");
            try self.generateInstructionSimple(code, inst);
        }

        // 生成loop块的指令（增量表达式）
        try code.appendSlice(self.allocator, "        // Loop increment\n");
        for (loop_block.instructions.items) |inst| {
            try code.appendSlice(self.allocator, "    ");
            try self.generateInstructionSimple(code, inst);
        }

        // 在循环体结束时释放临时对象
        if (body_temps.items.len > 0) {
            try code.appendSlice(self.allocator, "        // Release loop body temporaries\n");
            for (body_temps.items) |reg_id| {
                try code.appendSlice(self.allocator, "        reg_");
                try code.writer(self.allocator).print("{d}", .{reg_id});
                try code.appendSlice(self.allocator, ".release(runtime.runtime_allocator);\n");
            }
        }

        try code.appendSlice(self.allocator, "    }\n");

        // 生成exit块的代码
        const exit_block = func.blocks.items[exit_idx];
        try code.appendSlice(self.allocator, "    // After loop\n");
        for (exit_block.instructions.items) |inst| {
            try self.generateInstructionSimple(code, inst);
        }

        try code.appendSlice(self.allocator, "}\n");
    }

    fn regMayHeap(self: *const Self, reg_id: usize) bool {
        // 基于静态类型的快速门禁：标量寄存器绝不应调用 release。
        if (self.current_reg_types) |rt| {
            const ty = rt.get(reg_id) orelse IR.Type.php_value;
            const tag = @as(std.meta.Tag(IR.Type), ty);
            switch (tag) {
                .php_value, .php_string, .php_array, .php_object, .php_resource, .php_callable => {
                    // php_string/php_array/php_object总是需要release
                    return true;
                },
                else => return false,
            }
        }
        if (self.current_reg_may_heap) |mh| {
            return mh[reg_id];
        }
        return true;
    }

    /// 获取寄存器访问后缀（alloca 寄存器需要 .*）
    fn getRegSuffix(self: *const Self, reg_id: usize) []const u8 {
        if (self.current_alloca_regs) |regs| {
            if (regs.contains(reg_id)) return ".*";
        }
        return "";
    }

    /// Release死亡的操作数
    fn releaseDeadOperands(
        self: *Self,
        code: *std.ArrayList(u8),
        block_idx: usize,
        inst_idx: usize,
        inst: IR.Instruction,
        liveness: *const @import("liveness_analysis.zig").LivenessAnalysis,
        alloca_regs: *const std.AutoHashMap(usize, void),
    ) !void {
        var writer = code.writer(self.allocator);

        // 收集指令使用的寄存器
        var used_regs = try std.ArrayList(usize).initCapacity(self.allocator, 0);
        defer used_regs.deinit(self.allocator);

        switch (inst.op) {
            .add, .sub, .mul, .div, .mod, .pow, .concat, .eq, .ne, .lt, .le, .gt, .ge, .bit_and, .bit_or, .bit_xor, .shl, .shr => |bin| {
                try used_regs.append(self.allocator, bin.lhs.id);
                try used_regs.append(self.allocator, bin.rhs.id);
            },
            .neg, .not, .bit_not => |un| {
                try used_regs.append(self.allocator, un.operand.id);
            },
            .cast => |op| {
                try used_regs.append(self.allocator, op.value.id);
            },
            .call => |call| {
                for (call.args) |arg| {
                    try used_regs.append(self.allocator, arg.id);
                }
            },
            .call_indirect => |call| {
                try used_regs.append(self.allocator, call.func_ptr.id);
                for (call.args) |arg| {
                    try used_regs.append(self.allocator, arg.id);
                }
            },
            .load => |op| {
                try used_regs.append(self.allocator, op.ptr.id);
            },
            .store => |op| {
                try used_regs.append(self.allocator, op.ptr.id);
                try used_regs.append(self.allocator, op.value.id);
            },
            .array_get => |op| {
                try used_regs.append(self.allocator, op.array.id);
                try used_regs.append(self.allocator, op.key.id);
            },
            .array_set => |op| {
                try used_regs.append(self.allocator, op.array.id);
                try used_regs.append(self.allocator, op.key.id);
                try used_regs.append(self.allocator, op.value.id);
            },
            .property_get => |op| {
                try used_regs.append(self.allocator, op.object.id);
            },
            .property_set => |op| {
                try used_regs.append(self.allocator, op.object.id);
                try used_regs.append(self.allocator, op.value.id);
            },
            else => {},
        }

        // 去重
        var seen = std.AutoHashMap(usize, void).init(self.allocator);
        defer seen.deinit();

        // Release死亡的寄存器（这是它们的最后使用）
        for (used_regs.items) |reg_id| {
            // 去重
            if (seen.contains(reg_id)) continue;
            try seen.put(reg_id, {});

            // 跳过alloca
            if (alloca_regs.contains(reg_id)) continue;

            // 跳过result寄存器（正在被赋值）
            if (inst.result) |result_reg| {
                if (reg_id == result_reg.id) continue;
            }

            // 检查是否需要release
            if (!self.regMayHeap(reg_id)) continue;

            // 检查是否在指令后死亡（不在live_out中）
            if (!liveness.isLiveAfter(block_idx, inst_idx, reg_id)) {
                try writer.print("                reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
            }
        }
    }

    fn generateCleanupCode(self: *Self, writer: anytype) !void {
        try self.generateCleanupCodeExcept(writer, null);
    }

    fn generateCleanupCodeExcept(self: *Self, writer: anytype, except_reg: ?u32) !void {
        if (self.current_cleanup_regs) |regs| {
            if (regs.len > 0) {
                try writer.writeAll("        // Cleanup on exception\n");
                for (regs) |reg_id| {
                    // 跳过排除的寄存器（如异常对象）
                    if (except_reg) |ex_reg| {
                        if (reg_id == ex_reg) continue;
                    }

                    // 跳过 alloca 寄存器（它们是局部变量，会在函数结束时自动清理）
                    if (self.current_alloca_regs) |alloca_regs| {
                        if (alloca_regs.contains(reg_id)) continue;
                    }

                    if (self.regMayHeap(reg_id)) {
                        try writer.print("        reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                        // 重新初始化为null，避免悬垂指针
                        try writer.print("        reg_{d} = runtime.Value.initNull();\n", .{reg_id});
                    }
                }
            }
        }
    }

    /// 生成指令（简化版）
    fn generateInstructionSimple(self: *Self, code: *std.ArrayList(u8), inst: *const IR.Instruction) !void {
        @setEvalBranchQuota(10000); // 增加编译时求值限制
        // 🔥 LICM: 跳过已提升的指令
        if (self.isInstructionHoisted(inst)) {
            return;
        }

        var writer = code.writer(self.allocator);

        // Add source location comment and set runtime location
        if (inst.location.line > 0) {
            try writer.print("    // {s}:{d}\n", .{ inst.location.file, inst.location.line });
            try writer.print("    runtime.setSourceLocation(\"{s}\", {d});\n", .{ inst.location.file, inst.location.line });
        }

        switch (inst.op) {
            .const_int => |val| {
                if (inst.result) |reg| {
                    // 检查是否是 alloca 寄存器（指针）
                    const is_alloca = if (self.current_alloca_regs) |alloca_regs|
                        alloca_regs.contains(reg.id)
                    else
                        false;

                    // 所有寄存器都是 Value 类型，总是生成 Value.initInt
                    if (self.regMayHeap(reg.id)) {
                        if (is_alloca) {
                            try writer.print("    reg_{d}.*.release(runtime.runtime_allocator);\n", .{reg.id});
                        } else {
                            try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                        }
                    }
                    if (is_alloca) {
                        try writer.print("    reg_{d}.* = runtime.Value.initInt({d});\n", .{ reg.id, val });
                    } else {
                        try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initInt({d});\n", .{val});
                    }
                }
            },
            .const_float => |val| {
                if (inst.result) |reg| {
                    // 所有寄存器都是 Value 类型
                    if (self.regMayHeap(reg.id)) {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                    }
                    try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initFloat({d});\n", .{val});
                }
            },
            .const_bool => |val| {
                if (inst.result) |reg| {
                    // 所有寄存器都是 Value 类型
                    if (self.regMayHeap(reg.id)) {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                    }
                    try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool({});\n", .{val});
                }
            },
            .const_string => |string_id| {
                if (inst.result) |reg| {
                    const suffix = self.getRegSuffix(reg.id);
                    if (self.regMayHeap(reg.id)) {
                        try writer.print("    reg_{d}{s}.release(runtime.runtime_allocator);\n", .{ reg.id, suffix });
                    }
                    // 使用 comptime 预分配的静态字符串（零运行时开销）
                    try writer.print("    reg_{d}{s} = runtime.Value.initString(static_strings[{d}]);\n", .{ reg.id, suffix, string_id });
                }
            },
            .alloca => {
                // alloca不需要生成代码
            },
            .box => |op| {
                if (inst.result) |reg| {
                    // 所有寄存器都是runtime.Value类型，box操作只是类型标记
                    // 在代码生成时，直接赋值即可
                    const value_is_alloca = if (self.current_alloca_regs) |regs|
                        regs.contains(op.value.id)
                    else
                        false;
                    const result_is_alloca = if (self.current_alloca_regs) |regs|
                        regs.contains(reg.id)
                    else
                        false;

                    if (result_is_alloca and value_is_alloca) {
                        try writer.print("    reg_{d}.* = reg_{d}.*;\n", .{ reg.id, op.value.id });
                    } else if (result_is_alloca) {
                        try writer.print("    reg_{d}.* = reg_{d};\n", .{ reg.id, op.value.id });
                    } else if (value_is_alloca) {
                        try writer.print("    reg_{d} = reg_{d}.*;\n", .{ reg.id, op.value.id });
                    } else {
                        try writer.print("    reg_{d} = reg_{d};\n", .{ reg.id, op.value.id });
                    }
                }
            },
            .unbox => |op| {
                if (inst.result) |reg| {
                    const to_tag = @as(std.meta.Tag(IR.Type), op.to_type);

                    // 从php_value提取基本类型
                    if (to_tag == .i64) {
                        try self.writeRegAssignmentFmt(writer, reg.id, "reg_{d}.asInt();\n", .{op.value.id});
                    } else if (to_tag == .f64) {
                        try self.writeRegAssignmentFmt(writer, reg.id, "reg_{d}.asFloat();\n", .{op.value.id});
                    } else if (to_tag == .bool) {
                        try self.writeRegAssignmentFmt(writer, reg.id, "reg_{d}.asBool();\n", .{op.value.id});
                    } else {
                        try self.writeRegAssignmentFmt(writer, reg.id, "reg_{d};\n", .{op.value.id});
                    }
                }
            },
            .store => |op| {
                // 检查是否是引用参数的初始化store（跳过）
                var is_ref_param_init = false;
                if (self.current_function_for_resolve) |func_check| {
                    for (func_check.blocks.items) |block_check| {
                        for (block_check.instructions.items) |inst_check| {
                            if (inst_check.op == .param) {
                                if (inst_check.result) |param_result| {
                                    if (param_result.id == op.value.id) {
                                        const param_op = inst_check.op.param;
                                        for (func_check.ref_params.items) |ref_idx| {
                                            if (ref_idx == param_op.index) {
                                                is_ref_param_init = true;
                                                break;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if (is_ref_param_init) return;

                // 检查value是否是指针寄存器（PHI/select合并引用参数），target是alloca
                // 此时应重新指向而不是值赋值：reg_alloca = reg_ptr
                if (self.current_ref_ptr_regs) |rpr| {
                    if (rpr.contains(op.value.id)) {
                        const is_target_alloca = if (self.current_alloca_regs) |regs| regs.contains(op.ptr.id) else false;
                        if (is_target_alloca) {
                            // 指针重新绑定：让alloca指向PHI/select选择的位置
                            try writer.print("    reg_{d} = reg_{d};\n", .{ op.ptr.id, op.value.id });
                            return;
                        }
                    }
                }

                // 检查ptr是否是引用参数的alloca（使用映射表重定向到param）
                if (self.ref_param_alloca_map) |map| {
                    if (map.get(op.ptr.id)) |param_reg_id| {
                        // 重定向：写入param而不是alloca
                        try writer.print("    reg_{d}.* = reg_{d};\n", .{ param_reg_id, op.value.id });
                        return;
                    }
                }

                // by-ref 闭包捕获：后续 store 须经 php_ref_assign_ptr 写入堆单元
                if (self.current_ref_capture_allocas) |rca| {
                    if (rca.get(op.ptr.id)) |init_cap_reg| {
                        if (op.value.id != init_cap_reg) {
                            // 非初始 store → 写穿引用
                            const is_real = if (self.current_alloca_regs) |regs| regs.contains(op.ptr.id) else false;
                            const value_is_alloca = if (self.current_alloca_regs) |regs| regs.contains(op.value.id) else false;
                            const val_suffix = if (value_is_alloca) ".*" else "";
                            if (is_real) {
                                try writer.print("    _ = try runtime.php_ref_assign_ptr(reg_{d}, reg_{d}{s});\n", .{ op.ptr.id, op.value.id, val_suffix });
                            } else {
                                try writer.print("    _ = try runtime.php_ref_assign_ptr(&reg_{d}, reg_{d}{s});\n", .{ op.ptr.id, op.value.id, val_suffix });
                            }
                            if (self.current_var_name_map) |vnm| {
                                if (vnm.get(op.ptr.id)) |_| {
                                    try writer.print("    __def_{d} = true;\n", .{op.ptr.id});
                                }
                            }
                            return;
                        }
                    }
                }

                // make_ref'd alloca：使用 ref_aware_store 写穿引用槽
                if (self.current_make_ref_allocas) |mra| {
                    if (mra.contains(op.ptr.id)) {
                        const value_is_alloca = if (self.current_alloca_regs) |regs| regs.contains(op.value.id) else false;
                        const val_suffix = if (value_is_alloca) ".*" else "";
                        try writer.print("    runtime.ref_aware_store(reg_{d}, reg_{d}{s});\n", .{ op.ptr.id, op.value.id, val_suffix });
                        if (self.current_var_name_map) |vnm| {
                            if (vnm.get(op.ptr.id)) |_| {
                                try writer.print("    __def_{d} = true;\n", .{op.ptr.id});
                            }
                        }
                        return;
                    }
                }

                // 检查 ptr 的实际类型（可能被 mem2reg 提升）
                const ptr_type = if (self.current_register_types) |types|
                    types.get(op.ptr.id) orelse op.ptr.type_
                else
                    op.ptr.type_;
                const ptr_tag = @as(std.meta.Tag(IR.Type), ptr_type);

                // 如果 ptr 是指针类型，但不在 alloca_registers 中，说明被 mem2reg 提升了
                const is_real_alloca = if (self.current_alloca_regs) |regs| regs.contains(op.ptr.id) else false;
                const ptr_is_optimized = (ptr_tag == .ptr and !is_real_alloca) or ptr_tag != .ptr;

                if (ptr_is_optimized) {
                    // mem2reg 优化：直接赋值
                    // 检查是否需要引用计数管理
                    const value_type = if (self.current_register_types) |types|
                        types.get(op.value.id) orelse op.value.type_
                    else
                        op.value.type_;
                    const value_tag = @as(std.meta.Tag(IR.Type), value_type);
                    const needs_refcount = value_tag == .php_value or value_tag == .php_string or value_tag == .php_array or value_tag == .php_object;

                    var src_buf: [32]u8 = undefined;
                    const src_ref = try self.getOperandRef(&src_buf, op.value.id);

                    if (needs_refcount) {
                        // 先 retain 新值（防止新旧值相同时被释放）
                        try writer.print("    _ = ({s}).retain();\n", .{src_ref});
                        // 释放旧值
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{op.ptr.id});
                        // 赋值
                        try writer.print("    reg_{d} = {s};\n", .{ op.ptr.id, src_ref });
                    } else {
                        // 非引用计数类型，直接赋值
                        try writer.print("    reg_{d} = {s};\n", .{ op.ptr.id, src_ref });
                    }
                } else {
                    // 原有的 store 逻辑（指针操作）
                    // 检查是否是 alloca 寄存器（即指针类型）
                    const is_ptr = if (self.current_alloca_regs) |regs| regs.contains(op.ptr.id) else false;
                    const ptr_prefix = if (is_ptr) "" else "&";

                    // 1. 释放旧值
                    try writer.print("    reg_{d}.*.release(runtime.runtime_allocator);\n", .{op.ptr.id});

                    // 2. 增加新值引用计数并赋值
                    // 使用修正后的类型
                    const corrected_value_type = if (self.current_register_types) |types|
                        types.get(op.value.id) orelse op.value.type_
                    else
                        op.value.type_;
                    const corrected_value_tag = @as(std.meta.Tag(IR.Type), corrected_value_type);

                    // 检查 value 是否是 alloca 寄存器
                    const value_is_alloca = if (self.current_alloca_regs) |alloca_regs|
                        alloca_regs.contains(op.value.id)
                    else
                        false;

                    // 检查 value 是否是引用参数寄存器（指针类型）
                    const value_is_ref_param = blk: {
                        if (self.current_function_for_resolve) |func_check| {
                            for (func_check.blocks.items) |block_check| {
                                for (block_check.instructions.items) |inst_check| {
                                    if (inst_check.op == .param) {
                                        if (inst_check.result) |result_reg| {
                                            if (result_reg.id == op.value.id) {
                                                const param_op = inst_check.op.param;
                                                for (func_check.ref_params.items) |ref_idx| {
                                                    if (ref_idx == param_op.index) {
                                                        break :blk true;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        break :blk false;
                    };

                    if (corrected_value_tag == .php_value or corrected_value_tag == .php_string or corrected_value_tag == .php_array or corrected_value_tag == .php_object or corrected_value_tag == .php_callable) {
                        // 已经是Value类型，需要retain
                        if (self.regMayHeap(op.value.id)) {
                            if (value_is_ref_param) {
                                try writer.print("    _ = reg_{d}.*.retain();\n", .{op.value.id});
                            } else if (value_is_alloca) {
                                try writer.print("    _ = reg_{d}.*.retain();\n", .{op.value.id});
                            } else {
                                try writer.print("    _ = reg_{d}.retain();\n", .{op.value.id});
                            }
                        }
                        if (value_is_ref_param) {
                            try writer.print("    runtime.val_assign({s}reg_{d}, reg_{d}.*);\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                        } else if (value_is_alloca) {
                            try writer.print("    runtime.val_assign({s}reg_{d}, reg_{d}.*);\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                        } else {
                            try writer.print("    runtime.val_assign({s}reg_{d}, reg_{d});\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                        }
                    } else if (corrected_value_tag == .i64) {
                        if (value_is_alloca) {
                            try writer.print("    runtime.val_assign({s}reg_{d}, reg_{d}.*);\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                        } else {
                            // 普通寄存器都是Value类型，需要.toInt()转换
                            try writer.print("    runtime.val_assign({s}reg_{d}, runtime.Value.initInt(reg_{d}.toInt()));\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                        }
                    } else if (corrected_value_tag == .f64) {
                        if (value_is_alloca) {
                            try writer.print("    runtime.val_assign({s}reg_{d}, reg_{d}.*);\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                        } else {
                            // 普通寄存器都是Value类型，需要.toFloat()转换
                            try writer.print("    runtime.val_assign({s}reg_{d}, runtime.Value.initFloat(reg_{d}.toFloat()));\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                        }
                    } else if (corrected_value_tag == .bool) {
                        if (value_is_alloca) {
                            try writer.print("    runtime.val_assign({s}reg_{d}, reg_{d}.*);\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                        } else {
                            // 普通寄存器都是Value类型，需要.toBool()转换
                            try writer.print("    runtime.val_assign({s}reg_{d}, runtime.Value.initBool(reg_{d}.toBool()));\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                        }
                    } else {
                        // Fallback for other types
                        if (self.regMayHeap(op.value.id)) {
                            if (value_is_alloca) {
                                try writer.print("    _ = reg_{d}.*.retain();\n", .{op.value.id});
                            } else {
                                try writer.print("    _ = reg_{d}.retain();\n", .{op.value.id});
                            }
                        }
                        if (value_is_alloca) {
                            try writer.print("    runtime.val_assign({s}reg_{d}, reg_{d}.*);\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                        } else {
                            try writer.print("    runtime.val_assign({s}reg_{d}, reg_{d});\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                        }
                    }
                } // end of optimized_alloca else

                // PHP 变量：标记已定义
                if (self.current_var_name_map) |vnm| {
                    if (vnm.get(op.ptr.id)) |_| {
                        try writer.print("    __def_{d} = true;\n", .{op.ptr.id});
                    }
                }
            },
            .make_ref => |op| {
                if (inst.result) |reg| {
                    // 检查ptr是否是alloca（指针类型）
                    const is_alloca = if (self.current_alloca_regs) |regs|
                        regs.contains(op.ptr.id)
                    else
                        false;

                    if (is_alloca) {
                        // alloca已经是指针，直接使用
                        try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.make_ref(reg_{d}, runtime.runtime_allocator);\n", .{op.ptr.id});
                    } else {
                        // 普通变量，需要取地址
                        try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.make_ref(&reg_{d}, runtime.runtime_allocator);\n", .{op.ptr.id});
                    }
                }
            },
            .load => |op| {
                if (inst.result) |reg| {
                    // 检查是否是引用参数的alloca（使用映射表重定向到param）
                    if (self.ref_param_alloca_map) |map| {
                        if (map.get(op.ptr.id)) |param_reg_id| {
                            // 重定向：从param读取而不是alloca
                            try writer.print("    reg_{d} = reg_{d}.*;\n", .{ reg.id, param_reg_id });
                            return;
                        }
                    }

                    // PHP 变量 undefined 检查
                    if (self.current_var_name_map) |vnm| {
                        if (vnm.get(op.ptr.id)) |vname| {
                            try writer.print("    if (!__def_{d}) runtime.emitWarning(\"Undefined variable {s}\");\n", .{ op.ptr.id, vname });
                        }
                    }

                    // 检查 ptr 的实际类型（可能被 mem2reg 提升）
                    const ptr_type = if (self.current_register_types) |types|
                        types.get(op.ptr.id) orelse op.ptr.type_
                    else
                        op.ptr.type_;
                    const ptr_tag = @as(std.meta.Tag(IR.Type), ptr_type);

                    // 如果 ptr 是指针类型，但不在 alloca_registers 中，说明被 mem2reg 提升了
                    const is_real_alloca = if (self.current_alloca_regs) |regs| regs.contains(op.ptr.id) else false;
                    const ptr_is_optimized = (ptr_tag == .ptr and !is_real_alloca) or ptr_tag != .ptr;

                    if (ptr_is_optimized) {
                        // by-ref 闭包捕获：需要解引用读取堆单元值
                        if (self.current_ref_capture_allocas) |rca| {
                            if (rca.contains(op.ptr.id)) {
                                if (self.regMayHeap(reg.id)) {
                                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                                }
                                try writer.print("    reg_{d} = runtime.val_deref(&reg_{d}).*;\n", .{ reg.id, op.ptr.id });
                                if (self.regMayHeap(reg.id)) {
                                    try writer.print("    _ = reg_{d}.retain();\n", .{reg.id});
                                }
                                return;
                            }
                        }
                        // mem2reg 优化：直接读取
                        var src_buf: [32]u8 = undefined;
                        const src_ref = try self.getOperandRef(&src_buf, op.ptr.id);
                        try writer.print("    reg_{d} = {s};\n", .{ reg.id, src_ref });
                        return;
                    }

                    // 原有的 load 逻辑
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);

                    // 检查结果寄存器是否是 alloca
                    const result_is_alloca = if (self.current_alloca_regs) |regs| regs.contains(reg.id) else false;
                    const result_prefix = if (result_is_alloca) ".*" else "";

                    if (type_tag != .i64 and type_tag != .f64 and type_tag != .bool) {
                        if (self.regMayHeap(reg.id)) {
                            if (result_is_alloca) {
                                try writer.print("    reg_{d}.*.release(runtime.runtime_allocator);\n", .{reg.id});
                            } else {
                                try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                            }
                        }
                    }

                    // 检查是否是 alloca 寄存器（即指针类型）
                    const is_ptr = if (self.current_alloca_regs) |regs| regs.contains(op.ptr.id) else false;

                    // 检查是否是引用参数寄存器（指针类型）
                    const ptr_is_ref_param = blk: {
                        if (self.current_function_for_resolve) |func_check| {
                            for (func_check.blocks.items) |block_check| {
                                for (block_check.instructions.items) |inst_check| {
                                    if (inst_check.op == .param) {
                                        if (inst_check.result) |result_reg| {
                                            if (result_reg.id == op.ptr.id) {
                                                const param_op = inst_check.op.param;
                                                for (func_check.ref_params.items) |ref_idx| {
                                                    if (ref_idx == param_op.index) {
                                                        break :blk true;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        break :blk false;
                    };

                    const ptr_prefix = if (is_ptr or ptr_is_ref_param) "" else "&";

                    // 始终使用通用加载路径，保留实际运行时类型
                    // 类型推断可能不准确（如函数参数推断为i64但实际是bool），
                    // 用 asInt()/asFloat()/asBool() 转换会丢失实际类型信息
                    {
                        try writer.print("    reg_{d}{s} = runtime.val_deref({s}reg_{d}).*;\n", .{ reg.id, result_prefix, ptr_prefix, op.ptr.id });
                        if (self.regMayHeap(reg.id)) {
                            if (result_is_alloca) {
                                try writer.print("    _ = reg_{d}.*.retain();\n", .{reg.id});
                            } else {
                                try writer.print("    _ = reg_{d}.retain();\n", .{reg.id});
                            }
                        }
                    }
                }
            },
            .concat => |op| {
                if (inst.result) |reg| {
                    if (self.regMayHeap(reg.id)) {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                    }

                    const lhs_name = if (self.current_global_get_names) |gn| gn.get(op.lhs.id) else null;
                    const rhs_name = if (self.current_global_get_names) |gn| gn.get(op.rhs.id) else null;
                    const use_undef_helper = lhs_name != null or rhs_name != null;

                    // 使用 current_register_types 获取真实类型
                    const lhs_type_tag = if (self.current_register_types) |types| blk: {
                        if (types.get(op.lhs.id)) |corrected_type| {
                            break :blk @as(std.meta.Tag(IR.Type), corrected_type);
                        }
                        break :blk @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    } else @as(std.meta.Tag(IR.Type), op.lhs.type_);

                    const rhs_type_tag = if (self.current_register_types) |types| blk: {
                        if (types.get(op.rhs.id)) |corrected_type| {
                            break :blk @as(std.meta.Tag(IR.Type), corrected_type);
                        }
                        break :blk @as(std.meta.Tag(IR.Type), op.rhs.type_);
                    } else @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    try self.writeRegAssignmentPrefix(writer, reg.id);
                    if (use_undef_helper) {
                        try writer.writeAll("try runtime.php_concat_with_undef(");
                    } else {
                        try writer.writeAll("try runtime.php_concat(");
                    }

                    // 左操作数 - 所有寄存器都是 Value，需要类型转换
                    if (lhs_type_tag == .i64) {
                        const lhs_suffix = if (self.current_alloca_regs) |regs| if (regs.contains(op.lhs.id)) ".*" else "" else "";
                        try writer.print("runtime.Value.initInt(reg_{d}{s}.asInt())", .{ op.lhs.id, lhs_suffix });
                    } else if (lhs_type_tag == .f64) {
                        const lhs_suffix = if (self.current_alloca_regs) |regs| if (regs.contains(op.lhs.id)) ".*" else "" else "";
                        try writer.print("runtime.Value.initFloat(reg_{d}{s}.asFloat())", .{ op.lhs.id, lhs_suffix });
                    } else if (lhs_type_tag == .bool) {
                        const lhs_suffix = if (self.current_alloca_regs) |regs| if (regs.contains(op.lhs.id)) ".*" else "" else "";
                        try writer.print("runtime.Value.initBool(reg_{d}{s}.toBool())", .{ op.lhs.id, lhs_suffix });
                    } else {
                        const lhs_suffix = if (self.current_alloca_regs) |regs| if (regs.contains(op.lhs.id)) ".*" else "" else "";
                        try writer.print("reg_{d}{s}", .{ op.lhs.id, lhs_suffix });
                    }

                    try writer.writeAll(", ");

                    // 右操作数 - 所有寄存器都是 Value，需要类型转换
                    if (rhs_type_tag == .i64) {
                        const rhs_suffix = if (self.current_alloca_regs) |regs| if (regs.contains(op.rhs.id)) ".*" else "" else "";
                        try writer.print("runtime.Value.initInt(reg_{d}{s}.asInt())", .{ op.rhs.id, rhs_suffix });
                    } else if (rhs_type_tag == .f64) {
                        const rhs_suffix = if (self.current_alloca_regs) |regs| if (regs.contains(op.rhs.id)) ".*" else "" else "";
                        try writer.print("runtime.Value.initFloat(reg_{d}{s}.asFloat())", .{ op.rhs.id, rhs_suffix });
                    } else if (rhs_type_tag == .bool) {
                        const rhs_suffix = if (self.current_alloca_regs) |regs| if (regs.contains(op.rhs.id)) ".*" else "" else "";
                        try writer.print("runtime.Value.initBool(reg_{d}{s}.toBool())", .{ op.rhs.id, rhs_suffix });
                    } else {
                        const rhs_suffix = if (self.current_alloca_regs) |regs| if (regs.contains(op.rhs.id)) ".*" else "" else "";
                        try writer.print("reg_{d}{s}", .{ op.rhs.id, rhs_suffix });
                    }

                    if (use_undef_helper) {
                        if (lhs_name) |name| {
                            const escaped_name = try self.escapeString(name);
                            defer self.allocator.free(escaped_name);
                            try writer.print(", !globalVarIsDefined(\"{s}\"), \"{s}\"", .{ escaped_name, escaped_name });
                        } else {
                            try writer.writeAll(", false, \"\"");
                        }
                        if (rhs_name) |name| {
                            const escaped_name = try self.escapeString(name);
                            defer self.allocator.free(escaped_name);
                            try writer.print(", !globalVarIsDefined(\"{s}\"), \"{s}\"", .{ escaped_name, escaped_name });
                        } else {
                            try writer.writeAll(", false, \"\"");
                        }
                    }
                    try writer.writeAll(", runtime.runtime_allocator);\n");
                }
            },
            .add => |op| {
                if (inst.result) |reg| {
                    // 使用类型推断结果（优先）。但在混合运算场景里，类型约束的反向传播
                    // 可能把 runtime.Value 错推为 f64/i64，因此这里优先以“寄存器收集阶段”
                    // 的纠正类型作为 fallback，避免生成不合法的原生算术表达式。
                    const lhs_fallback = if (self.current_register_types) |types|
                        (types.get(op.lhs.id) orelse op.lhs.type_)
                    else
                        op.lhs.type_;
                    const rhs_fallback = if (self.current_register_types) |types|
                        (types.get(op.rhs.id) orelse op.rhs.type_)
                    else
                        op.rhs.type_;
                    const result_fallback = if (self.current_register_types) |types|
                        (types.get(reg.id) orelse reg.type_)
                    else
                        reg.type_;

                    var lhs_type = self.getInferredRegType(op.lhs.id, lhs_fallback);
                    var rhs_type = self.getInferredRegType(op.rhs.id, rhs_fallback);
                    var result_type = self.getInferredRegType(reg.id, result_fallback);

                    // 混合运算保护：如果寄存器收集阶段已纠正为 php_value，
                    // 则禁止被推断结果覆盖为基本类型，避免生成 f64/i64 与 runtime.Value 的原生运算。
                    if (@as(std.meta.Tag(IR.Type), lhs_fallback) == .php_value) lhs_type = lhs_fallback;
                    if (@as(std.meta.Tag(IR.Type), rhs_fallback) == .php_value) rhs_type = rhs_fallback;
                    if (@as(std.meta.Tag(IR.Type), result_fallback) == .php_value) result_type = result_fallback;

                    const lhs_tag = @as(std.meta.Tag(IR.Type), lhs_type);
                    const rhs_tag = @as(std.meta.Tag(IR.Type), rhs_type);
                    const result_tag = @as(std.meta.Tag(IR.Type), result_type);

                    const lhs_expr_tag: std.meta.Tag(IR.Type) = if (@as(std.meta.Tag(IR.Type), lhs_fallback) == .php_value) .php_value else lhs_tag;
                    const rhs_expr_tag: std.meta.Tag(IR.Type) = if (@as(std.meta.Tag(IR.Type), rhs_fallback) == .php_value) .php_value else rhs_tag;

                    // 如果所有操作数都是 i64，生成原生加法（但寄存器是 Value，需要转换）
                    if (lhs_tag == .i64 and rhs_tag == .i64 and result_tag == .i64) {
                        // i64 + i64 → i64（原生，但需要转换）
                        try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initInt(reg_{d}.asInt() + reg_{d}.asInt());\n", .{ op.lhs.id, op.rhs.id });
                    } else if (lhs_tag == .f64 and rhs_tag == .f64 and result_tag == .f64) {
                        // f64 + f64 → f64（原生，但需要转换）
                        try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initFloat(reg_{d}.asFloat() + reg_{d}.asFloat());\n", .{ op.lhs.id, op.rhs.id });
                    } else {
                        // 混合类型或 php_value，使用运行时函数
                        try self.writeRegAssignmentPrefix(writer, reg.id);
                        switch (result_tag) {
                            .php_value => {
                                try writer.writeAll("try runtime.php_add(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(");\n");
                            },
                            .i64 => {
                                // 所有寄存器都是 Value 类型，需要包装
                                try writer.writeAll("runtime.Value.initInt((try runtime.php_add(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(")).asInt());\n");
                            },
                            .f64 => {
                                // 所有寄存器都是 Value 类型，需要包装
                                try writer.writeAll("runtime.Value.initFloat((try runtime.php_add(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(")).asFloat());\n");
                            },
                            .bool => {
                                // 所有寄存器都是 Value 类型，需要包装
                                try writer.writeAll("runtime.Value.initBool((try runtime.php_add(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(")).asBool());\n");
                            },
                            else => {
                                try writer.writeAll("try runtime.php_add(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(");\n");
                            },
                        }
                    }
                }
            },
            .sub => |op| {
                if (inst.result) |reg| {
                    const lhs_fallback = if (self.current_register_types) |types|
                        (types.get(op.lhs.id) orelse op.lhs.type_)
                    else
                        op.lhs.type_;
                    const rhs_fallback = if (self.current_register_types) |types|
                        (types.get(op.rhs.id) orelse op.rhs.type_)
                    else
                        op.rhs.type_;
                    const result_fallback = if (self.current_register_types) |types|
                        (types.get(reg.id) orelse reg.type_)
                    else
                        reg.type_;

                    var lhs_type = self.getInferredRegType(op.lhs.id, lhs_fallback);
                    var rhs_type = self.getInferredRegType(op.rhs.id, rhs_fallback);
                    var result_type = self.getInferredRegType(reg.id, result_fallback);

                    if (@as(std.meta.Tag(IR.Type), lhs_fallback) == .php_value) lhs_type = lhs_fallback;
                    if (@as(std.meta.Tag(IR.Type), rhs_fallback) == .php_value) rhs_type = rhs_fallback;
                    if (@as(std.meta.Tag(IR.Type), result_fallback) == .php_value) result_type = result_fallback;

                    const lhs_tag = @as(std.meta.Tag(IR.Type), lhs_type);
                    const rhs_tag = @as(std.meta.Tag(IR.Type), rhs_type);
                    const result_tag = @as(std.meta.Tag(IR.Type), result_type);

                    const lhs_expr_tag: std.meta.Tag(IR.Type) = if (@as(std.meta.Tag(IR.Type), lhs_fallback) == .php_value) .php_value else lhs_tag;
                    const rhs_expr_tag: std.meta.Tag(IR.Type) = if (@as(std.meta.Tag(IR.Type), rhs_fallback) == .php_value) .php_value else rhs_tag;

                    if (lhs_tag == .i64 and rhs_tag == .i64 and result_tag == .i64) {
                        // 所有寄存器都是 Value 类型，必须使用 php_sub
                        try writer.print("    reg_{d} = runtime.Value.initInt((try runtime.php_sub(reg_{d}, reg_{d})).asInt());\n", .{ reg.id, op.lhs.id, op.rhs.id });
                    } else if (lhs_tag == .f64 and rhs_tag == .f64 and result_tag == .f64) {
                        // 所有寄存器都是 Value 类型，必须使用 php_sub
                        try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initFloat((try runtime.php_sub(reg_{d}, reg_{d})).asFloat());\n", .{ op.lhs.id, op.rhs.id });
                    } else {
                        try self.writeRegAssignmentPrefix(writer, reg.id);
                        switch (result_tag) {
                            .php_value => {
                                try writer.writeAll("try runtime.php_sub(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(");\n");
                            },
                            .i64 => {
                                try writer.writeAll("(try runtime.php_sub(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(")).asInt();\n");
                            },
                            .f64 => {
                                try writer.writeAll("(try runtime.php_sub(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(")).asFloat();\n");
                            },
                            .bool => {
                                try writer.writeAll("(try runtime.php_sub(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(")).asBool();\n");
                            },
                            else => {
                                try writer.writeAll("try runtime.php_sub(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(");\n");
                            },
                        }
                    }
                }
            },
            .mul => |op| {
                // std.debug.print("generateInstructionSimple: mul reg_{d} = reg_{d} * reg_{d}\n", .{ if (inst.result) |r| r.id else 999, op.lhs.id, op.rhs.id });
                if (inst.result) |reg| {
                    const lhs_fallback = if (self.current_register_types) |types|
                        (types.get(op.lhs.id) orelse op.lhs.type_)
                    else
                        op.lhs.type_;
                    const rhs_fallback = if (self.current_register_types) |types|
                        (types.get(op.rhs.id) orelse op.rhs.type_)
                    else
                        op.rhs.type_;
                    const result_fallback = if (self.current_register_types) |types|
                        (types.get(reg.id) orelse reg.type_)
                    else
                        reg.type_;

                    var lhs_type = self.getInferredRegType(op.lhs.id, lhs_fallback);
                    var rhs_type = self.getInferredRegType(op.rhs.id, rhs_fallback);
                    var result_type = self.getInferredRegType(reg.id, result_fallback);

                    if (@as(std.meta.Tag(IR.Type), lhs_fallback) == .php_value) lhs_type = lhs_fallback;
                    if (@as(std.meta.Tag(IR.Type), rhs_fallback) == .php_value) rhs_type = rhs_fallback;
                    if (@as(std.meta.Tag(IR.Type), result_fallback) == .php_value) result_type = result_fallback;

                    const lhs_tag = @as(std.meta.Tag(IR.Type), lhs_type);
                    const rhs_tag = @as(std.meta.Tag(IR.Type), rhs_type);
                    const result_tag = @as(std.meta.Tag(IR.Type), result_type);

                    const lhs_expr_tag: std.meta.Tag(IR.Type) = if (@as(std.meta.Tag(IR.Type), lhs_fallback) == .php_value) .php_value else lhs_tag;
                    const rhs_expr_tag: std.meta.Tag(IR.Type) = if (@as(std.meta.Tag(IR.Type), rhs_fallback) == .php_value) .php_value else rhs_tag;

                    if (lhs_tag == .i64 and rhs_tag == .i64 and result_tag == .i64) {
                        // 所有寄存器都是 Value 类型，必须使用 php_mul
                        try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initInt((try runtime.php_mul(reg_{d}, reg_{d})).asInt());\n", .{ op.lhs.id, op.rhs.id });
                    } else if (lhs_tag == .f64 and rhs_tag == .f64 and result_tag == .f64) {
                        // 所有寄存器都是 Value 类型，必须使用 php_mul
                        try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initFloat((try runtime.php_mul(reg_{d}, reg_{d})).asFloat());\n", .{ op.lhs.id, op.rhs.id });
                    } else {
                        try self.writeRegAssignmentPrefix(writer, reg.id);
                        switch (result_tag) {
                            .php_value => {
                                try writer.writeAll("try runtime.php_mul(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(");\n");
                            },
                            .i64 => {
                                try writer.writeAll("(try runtime.php_mul(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(")).asInt();\n");
                            },
                            .f64 => {
                                try writer.writeAll("(try runtime.php_mul(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(")).asFloat();\n");
                            },
                            .bool => {
                                try writer.writeAll("(try runtime.php_mul(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(")).asBool();\n");
                            },
                            else => {
                                try writer.writeAll("try runtime.php_mul(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(");\n");
                            },
                        }
                    }
                }
            },
            .div => |op| {
                if (inst.result) |reg| {
                    const lhs_fallback = if (self.current_register_types) |types|
                        (types.get(op.lhs.id) orelse op.lhs.type_)
                    else
                        op.lhs.type_;
                    const rhs_fallback = if (self.current_register_types) |types|
                        (types.get(op.rhs.id) orelse op.rhs.type_)
                    else
                        op.rhs.type_;
                    const result_fallback = if (self.current_register_types) |types|
                        (types.get(reg.id) orelse reg.type_)
                    else
                        reg.type_;

                    var lhs_type = self.getInferredRegType(op.lhs.id, lhs_fallback);
                    var rhs_type = self.getInferredRegType(op.rhs.id, rhs_fallback);
                    var result_type = self.getInferredRegType(reg.id, result_fallback);

                    if (@as(std.meta.Tag(IR.Type), lhs_fallback) == .php_value) lhs_type = lhs_fallback;
                    if (@as(std.meta.Tag(IR.Type), rhs_fallback) == .php_value) rhs_type = rhs_fallback;
                    if (@as(std.meta.Tag(IR.Type), result_fallback) == .php_value) result_type = result_fallback;

                    const lhs_tag = @as(std.meta.Tag(IR.Type), lhs_type);
                    const rhs_tag = @as(std.meta.Tag(IR.Type), rhs_type);
                    const result_tag = @as(std.meta.Tag(IR.Type), result_type);

                    const lhs_expr_tag: std.meta.Tag(IR.Type) = if (@as(std.meta.Tag(IR.Type), lhs_fallback) == .php_value) .php_value else lhs_tag;
                    const rhs_expr_tag: std.meta.Tag(IR.Type) = if (@as(std.meta.Tag(IR.Type), rhs_fallback) == .php_value) .php_value else rhs_tag;

                    if (lhs_tag == .i64 and rhs_tag == .i64 and result_tag == .i64) {
                        // 所有寄存器都是 Value 类型，必须使用 php_div
                        try writer.print("    reg_{d} = runtime.Value.initInt((try runtime.php_div(reg_{d}, reg_{d})).asInt());\n", .{ reg.id, op.lhs.id, op.rhs.id });
                    } else if (lhs_tag == .f64 and rhs_tag == .f64 and result_tag == .f64) {
                        // 所有寄存器都是 Value 类型，必须使用 php_div
                        try writer.print("    reg_{d} = runtime.Value.initFloat((try runtime.php_div(reg_{d}, reg_{d})).asFloat());\n", .{ reg.id, op.lhs.id, op.rhs.id });
                    } else {
                        switch (result_tag) {
                            .php_value => {
                                try self.writeRegAssignmentPrefix(writer, reg.id);
                                try writer.writeAll("try runtime.php_div(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(");\n");
                            },
                            .i64 => {
                                try self.writeRegAssignmentPrefix(writer, reg.id);
                                try writer.writeAll("(try runtime.php_div(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(")).asInt();\n");
                            },
                            .f64 => {
                                try self.writeRegAssignmentPrefix(writer, reg.id);
                                try writer.writeAll("(try runtime.php_div(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(")).asFloat();\n");
                            },
                            .bool => {
                                try self.writeRegAssignmentPrefix(writer, reg.id);
                                try writer.writeAll("(try runtime.php_div(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(")).asBool();\n");
                            },
                            else => {
                                try writer.print("    reg_{d} = try runtime.php_div(", .{reg.id});
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(");\n");
                            },
                        }
                    }
                }
                try writer.writeAll("    if (runtime.hasException()) {\n");
                try writer.writeAll("        @branchHint(.unlikely);\n");
                try self.generateCleanupCode(writer);
                if (self.current_exception_handler) |handler_idx| {
                    try writer.print("        current_block = {d};\n", .{handler_idx});
                    try writer.writeAll("        continue;\n");
                } else {
                    try writer.writeAll("        return error.RuntimeError;\n");
                }
                try writer.writeAll("    }\n");
            },
            .mod => |op| {
                // 设置源码位置，供 Deprecated 警告使用
                if (inst.location.line > 0) {
                    try writer.print("    runtime.setSourceLocation(\"{s}\", {d});\n", .{ inst.location.file, inst.location.line });
                }
                if (inst.result) |reg| {
                    const lhs_fallback = if (self.current_register_types) |types|
                        (types.get(op.lhs.id) orelse op.lhs.type_)
                    else
                        op.lhs.type_;
                    const rhs_fallback = if (self.current_register_types) |types|
                        (types.get(op.rhs.id) orelse op.rhs.type_)
                    else
                        op.rhs.type_;
                    const result_fallback = if (self.current_register_types) |types|
                        (types.get(reg.id) orelse reg.type_)
                    else
                        reg.type_;

                    var lhs_type = self.getInferredRegType(op.lhs.id, lhs_fallback);
                    var rhs_type = self.getInferredRegType(op.rhs.id, rhs_fallback);
                    var result_type = self.getInferredRegType(reg.id, result_fallback);

                    if (@as(std.meta.Tag(IR.Type), lhs_fallback) == .php_value) lhs_type = lhs_fallback;
                    if (@as(std.meta.Tag(IR.Type), rhs_fallback) == .php_value) rhs_type = rhs_fallback;
                    if (@as(std.meta.Tag(IR.Type), result_fallback) == .php_value) result_type = result_fallback;

                    const lhs_tag = @as(std.meta.Tag(IR.Type), lhs_type);
                    const rhs_tag = @as(std.meta.Tag(IR.Type), rhs_type);
                    const result_tag = @as(std.meta.Tag(IR.Type), result_type);

                    const lhs_expr_tag: std.meta.Tag(IR.Type) = if (@as(std.meta.Tag(IR.Type), lhs_fallback) == .php_value) .php_value else lhs_tag;
                    const rhs_expr_tag: std.meta.Tag(IR.Type) = if (@as(std.meta.Tag(IR.Type), rhs_fallback) == .php_value) .php_value else rhs_tag;

                    if (lhs_tag == .i64 and rhs_tag == .i64 and result_tag == .i64) {
                        // 所有寄存器都是 Value 类型，必须使用 php_mod
                        try writer.print("    reg_{d} = runtime.Value.initInt((try runtime.php_mod(reg_{d}, reg_{d})).asInt());\n", .{ reg.id, op.lhs.id, op.rhs.id });
                    } else if (lhs_tag == .f64 and rhs_tag == .f64 and result_tag == .f64) {
                        // 所有寄存器都是 Value 类型，必须使用 php_mod
                        try writer.print("    reg_{d} = runtime.Value.initFloat((try runtime.php_mod(reg_{d}, reg_{d})).asFloat());\n", .{ reg.id, op.lhs.id, op.rhs.id });
                    } else {
                        switch (result_tag) {
                            .php_value => {
                                try self.writeRegAssignmentPrefix(writer, reg.id);
                                try writer.writeAll("try runtime.php_mod(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(");\n");
                            },
                            .i64 => {
                                try self.writeRegAssignmentPrefix(writer, reg.id);
                                try writer.writeAll("(try runtime.php_mod(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(")).asInt();\n");
                            },
                            .f64 => {
                                try self.writeRegAssignmentPrefix(writer, reg.id);
                                try writer.writeAll("(try runtime.php_mod(");
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(")).asFloat();\n");
                            },
                            .bool => {
                                try writer.print("    reg_{d} = (try runtime.php_mod(", .{reg.id});
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(")).asBool();\n");
                            },
                            else => {
                                try writer.print("    reg_{d} = try runtime.php_mod(", .{reg.id});
                                try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                                try writer.writeAll(", ");
                                try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                                try writer.writeAll(");\n");
                            },
                        }
                    }
                }
                try writer.writeAll("    if (runtime.hasException()) {\n");
                try writer.writeAll("        @branchHint(.unlikely);\n");
                try self.generateCleanupCode(writer);
                if (self.current_exception_handler) |handler_idx| {
                    try writer.print("        current_block = {d};\n", .{handler_idx});
                    try writer.writeAll("        continue;\n");
                } else {
                    try writer.writeAll("        return error.RuntimeError;\n");
                }
                try writer.writeAll("    }\n");
            },
            .pow => |op| {
                if (inst.result) |reg| {
                    const lhs_fallback = if (self.current_register_types) |types|
                        (types.get(op.lhs.id) orelse op.lhs.type_)
                    else
                        op.lhs.type_;
                    const rhs_fallback = if (self.current_register_types) |types|
                        (types.get(op.rhs.id) orelse op.rhs.type_)
                    else
                        op.rhs.type_;
                    const result_fallback = if (self.current_register_types) |types|
                        (types.get(reg.id) orelse reg.type_)
                    else
                        reg.type_;

                    var lhs_type = self.getInferredRegType(op.lhs.id, lhs_fallback);
                    var rhs_type = self.getInferredRegType(op.rhs.id, rhs_fallback);
                    var result_type = self.getInferredRegType(reg.id, result_fallback);

                    if (@as(std.meta.Tag(IR.Type), lhs_fallback) == .php_value) lhs_type = lhs_fallback;
                    if (@as(std.meta.Tag(IR.Type), rhs_fallback) == .php_value) rhs_type = rhs_fallback;
                    if (@as(std.meta.Tag(IR.Type), result_fallback) == .php_value) result_type = result_fallback;

                    const lhs_tag = @as(std.meta.Tag(IR.Type), lhs_type);
                    const rhs_tag = @as(std.meta.Tag(IR.Type), rhs_type);
                    const result_tag = @as(std.meta.Tag(IR.Type), result_type);

                    const lhs_expr_tag: std.meta.Tag(IR.Type) = if (@as(std.meta.Tag(IR.Type), lhs_fallback) == .php_value) .php_value else lhs_tag;
                    const rhs_expr_tag: std.meta.Tag(IR.Type) = if (@as(std.meta.Tag(IR.Type), rhs_fallback) == .php_value) .php_value else rhs_tag;

                    switch (result_tag) {
                        .php_value => {
                            try writer.print("    reg_{d} = try runtime.php_pow(", .{reg.id});
                            try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                            try writer.writeAll(");\n");
                        },
                        .i64 => {
                            try writer.print("    reg_{d} = (try runtime.php_pow(", .{reg.id});
                            try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                            try writer.writeAll(")).asInt();\n");
                        },
                        .f64 => {
                            try writer.print("    reg_{d} = (try runtime.php_pow(", .{reg.id});
                            try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                            try writer.writeAll(")).asFloat();\n");
                        },
                        else => {
                            try writer.print("    reg_{d} = try runtime.php_pow(", .{reg.id});
                            try self.writePhpValueExpr(writer, lhs_expr_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_expr_tag, op.rhs.id);
                            try writer.writeAll(");\n");
                        },
                    }
                }
            },
            .shl => |op| {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d} = runtime.Value.initInt(@truncate(@as(i128, reg_{d}.toInt()) << @as(u7, @intCast(@min(63, @max(0, reg_{d}.toInt()))))));\n", .{ reg.id, op.lhs.id, op.rhs.id });
                }
            },
            .shr => |op| {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d} = runtime.Value.initInt(reg_{d}.toInt() >> @as(u6, @intCast(@min(63, @max(0, reg_{d}.toInt())))));\n", .{ reg.id, op.lhs.id, op.rhs.id });
                }
            },
            .bit_and => |op| {
                if (inst.result) |reg| {
                    const alloca_regs = self.current_alloca_regs orelse unreachable;
                    const lhs_deref = if (alloca_regs.contains(op.lhs.id)) ".*" else "";
                    const rhs_deref = if (alloca_regs.contains(op.rhs.id)) ".*" else "";
                    const result_deref = if (alloca_regs.contains(reg.id)) ".*" else "";
                    try writer.print("    reg_{d}{s} = runtime.Value.initInt(reg_{d}{s}.toInt() & reg_{d}{s}.toInt());\n", .{ reg.id, result_deref, op.lhs.id, lhs_deref, op.rhs.id, rhs_deref });
                }
            },
            .bit_or => |op| {
                if (inst.result) |reg| {
                    const alloca_regs = self.current_alloca_regs orelse unreachable;
                    const lhs_deref = if (alloca_regs.contains(op.lhs.id)) ".*" else "";
                    const rhs_deref = if (alloca_regs.contains(op.rhs.id)) ".*" else "";
                    const result_deref = if (alloca_regs.contains(reg.id)) ".*" else "";
                    try writer.print("    reg_{d}{s} = runtime.Value.initInt(reg_{d}{s}.toInt() | reg_{d}{s}.toInt());\n", .{ reg.id, result_deref, op.lhs.id, lhs_deref, op.rhs.id, rhs_deref });
                }
            },
            .bit_xor => |op| {
                if (inst.result) |reg| {
                    const alloca_regs = self.current_alloca_regs orelse unreachable;
                    const lhs_deref = if (alloca_regs.contains(op.lhs.id)) ".*" else "";
                    const rhs_deref = if (alloca_regs.contains(op.rhs.id)) ".*" else "";
                    const result_deref = if (alloca_regs.contains(reg.id)) ".*" else "";
                    try writer.print("    reg_{d}{s} = runtime.Value.initInt(reg_{d}{s}.toInt() ^ reg_{d}{s}.toInt());\n", .{ reg.id, result_deref, op.lhs.id, lhs_deref, op.rhs.id, rhs_deref });
                }
            },
            .nop => {},
            .yield_val => |op| {
                // yield $value or yield $key => $value
                // Calls runtime.php_generator_yield(gen_ctx, key, value)
                // Result register receives the "sent" value
                const value_str = if (op.value) |v|
                    try std.fmt.allocPrint(self.allocator, "reg_{d}", .{v.id})
                else
                    try self.allocator.dupe(u8, "runtime.Value.initNull()");
                defer self.allocator.free(value_str);

                const key_str = if (op.key) |k|
                    try std.fmt.allocPrint(self.allocator, "reg_{d}", .{k.id})
                else
                    try self.allocator.dupe(u8, "runtime.Value.initNull()");
                defer self.allocator.free(key_str);

                if (inst.result) |reg| {
                    try writer.print("    reg_{d} = try runtime.php_generator_yield(__gen_ctx, {s}, {s});\n", .{ reg.id, key_str, value_str });
                } else {
                    try writer.print("    _ = try runtime.php_generator_yield(__gen_ctx, {s}, {s});\n", .{ key_str, value_str });
                }
                try writer.writeAll("    if (runtime.hasException()) {\n");
                try writer.writeAll("        @branchHint(.unlikely);\n");
                if (self.current_exception_handler) |handler_idx| {
                    try writer.print("        current_block = {d};\n", .{handler_idx});
                    try writer.writeAll("        continue;\n");
                } else {
                    try writer.writeAll("        return error.RuntimeError;\n");
                }
                try writer.writeAll("    }\n");
            },
            .yield_from => |op| {
                // yield from $iterable
                if (inst.result) |reg| {
                    try writer.print("    reg_{d} = try runtime.php_generator_yield_from(__gen_ctx, reg_{d});\n", .{ reg.id, op.operand.id });
                } else {
                    try writer.print("    _ = try runtime.php_generator_yield_from(__gen_ctx, reg_{d});\n", .{op.operand.id});
                }
                try writer.writeAll("    if (runtime.hasException()) {\n");
                try writer.writeAll("        @branchHint(.unlikely);\n");
                if (self.current_exception_handler) |handler_idx| {
                    try writer.print("        current_block = {d};\n", .{handler_idx});
                    try writer.writeAll("        continue;\n");
                } else {
                    try writer.writeAll("        return error.RuntimeError;\n");
                }
                try writer.writeAll("    }\n");
            },
            .param => |op| {
                if (inst.result) |reg| {
                    if (std.mem.eql(u8, op.name, "this")) {
                        // 检查reg是否是alloca指针
                        const is_alloca = if (self.current_alloca_regs) |regs| regs.contains(reg.id) else false;
                        if (is_alloca) {
                            try writer.print("    reg_{d}.* = ctx;\n", .{reg.id});
                        } else {
                            try writer.print("    reg_{d} = ctx;\n", .{reg.id});
                        }
                    } else {
                        // 检查函数是否有this参数
                        const has_this = blk: {
                            if (self.current_function_for_resolve) |func| {
                                if (func.params.items.len > 0) {
                                    break :blk std.mem.eql(u8, func.params.items[0].name, "this");
                                }
                            }
                            break :blk false;
                        };

                        // IR中参数索引：
                        // 有this: 0=this, 1=第一个参数, 2=第二个参数...
                        // 无this: 0=第一个参数, 1=第二个参数...
                        // args数组索引：0=第一个参数, 1=第二个参数...
                        const args_index = if (has_this) (if (op.index > 0) op.index - 1 else 0) else op.index;

                        // 检查是否是引用参数
                        const is_ref_param = blk: {
                            if (self.current_function_for_resolve) |func| {
                                for (func.ref_params.items) |ref_idx| {
                                    if (ref_idx == op.index) break :blk true;
                                }
                            }
                            break :blk false;
                        };

                        if (is_ref_param) {
                            // 引用参数：返回args中的指针（不解引用）
                            try self.writeRegAssignmentFmt(writer, reg.id, "if (args.len > {d} and !args[{d}].isMissing() and args[{d}].isRef()) args[{d}].asRef() else &null_val;\n", .{ args_index, args_index, args_index, args_index });

                            // 初始化对应的alloca（如果存在）
                            if (self.current_function_for_resolve) |func_check| {
                                for (func_check.blocks.items) |block_check| {
                                    for (block_check.instructions.items) |inst_check| {
                                        if (inst_check.op == .store) {
                                            const store_op = inst_check.op.store;
                                            if (store_op.value.id == reg.id) {
                                                // 检查目标寄存器类型：指针类型直接赋值，值类型需要解引用
                                                if (self.isPointerReg(store_op.ptr.id)) {
                                                    try writer.print("    reg_{d} = reg_{d};\n", .{ store_op.ptr.id, reg.id });
                                                } else {
                                                    try writer.print("    reg_{d} = reg_{d}.*;\n", .{ store_op.ptr.id, reg.id });
                                                }
                                                break;
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            // 检查是否是可变参数
                            const is_variadic = blk: {
                                if (self.current_function_for_resolve) |func| {
                                    if (op.index < func.params.items.len) {
                                        const param = func.params.items[op.index];
                                        // DEBUG: param info
                                        break :blk param.is_variadic;
                                    }
                                }
                                break :blk false;
                            };

                            if (is_variadic) {
                                // 可变参数：收集从 args_index 开始的所有参数到数组
                                // 特殊处理：如果恰好一个参数且是关联数组（命名 variadic 参数），直接使用
                                const is_alloca = if (self.current_alloca_regs) |allocas| allocas.contains(reg.id) else false;
                                if (is_alloca) {
                                    try writer.print("    reg_{d}.* = runtime.Value.initNull();\n", .{reg.id});
                                } else {
                                    try writer.print("    reg_{d} = runtime.Value.initNull();\n", .{reg.id});
                                }
                                try writer.print("    {{\n", .{});
                                try writer.print("        const __va_start: usize = {d};\n", .{args_index});
                                try writer.print("        if (args.len == __va_start + 1 and args[__va_start].isArray() and args[__va_start].asArray().hasStringKeys()) {{\n", .{});
                                if (is_alloca) {
                                    try writer.print("            reg_{d}.* = args[__va_start];\n", .{reg.id});
                                } else {
                                    try writer.print("            reg_{d} = args[__va_start];\n", .{reg.id});
                                }
                                try writer.print("        }} else {{\n", .{});
                                try writer.print("            var variadic_array = try runtime.PHPArray.init(runtime.runtime_allocator);\n", .{});
                                try writer.print("            var i: usize = __va_start;\n", .{});
                                try writer.print("            while (i < args.len) : (i += 1) {{\n", .{});
                                try writer.print("                try variadic_array.push(runtime.runtime_allocator, args[i]);\n", .{});
                                try writer.print("            }}\n", .{});
                                if (is_alloca) {
                                    try writer.print("            reg_{d}.* = runtime.Value.initArray(variadic_array);\n", .{reg.id});
                                } else {
                                    try writer.print("            reg_{d} = runtime.Value.initArray(variadic_array);\n", .{reg.id});
                                }
                                try writer.print("        }}\n", .{});
                                try writer.print("    }}\n", .{});
                            } else {
                                // 普通参数 - 现在所有寄存器都是 Value 类型
                                // 根据原始类型推断决定如何转换
                                const orig_type_tag = @as(std.meta.Tag(IR.Type), reg.type_);

                                if (orig_type_tag == .i64) {
                                    try self.writeRegAssignmentFmt(writer, reg.id, "if (args.len > {d} and !args[{d}].isMissing()) runtime.Value.initInt(args[{d}].toInt()) else runtime.Value.initInt(0);\n", .{ args_index, args_index, args_index });
                                } else if (orig_type_tag == .f64) {
                                    try self.writeRegAssignmentFmt(writer, reg.id, "if (args.len > {d} and !args[{d}].isMissing()) runtime.Value.initFloat(args[{d}].toFloat()) else runtime.Value.initFloat(0.0);\n", .{ args_index, args_index, args_index });
                                } else if (orig_type_tag == .bool) {
                                    try self.writeRegAssignmentFmt(writer, reg.id, "if (args.len > {d} and !args[{d}].isMissing()) runtime.Value.initBool(args[{d}].toBool()) else runtime.Value.initBool(false);\n", .{ args_index, args_index, args_index });
                                } else {
                                    try self.writeRegAssignmentFmt(writer, reg.id, "if (args.len > {d} and !args[{d}].isMissing()) args[{d}] else runtime.Value.initNull();\n", .{ args_index, args_index, args_index });
                                }
                            }
                        }
                    }
                }
            },
            .capture_get => |op| {
                if (inst.result) |reg| {
                    // ctx is the closure object
                    try self.writeRegAssignmentFmt(writer, reg.id, "ctx.asFunction().captures[{d}];\n", .{op.index});
                }
            },
            .type_check => |op| {
                if (inst.result) |reg| {
                    // 所有寄存器都是 Value 类型，包装成 Value.initBool
                    try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool(reg_{d}.isNull());\n", .{op.value.id});
                }
            },
            .instanceof => |op| {
                if (inst.result) |reg| {
                    try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.php_instanceof(reg_{d}, reg_{d});\n", .{ op.object.id, op.class_name.id });
                }
            },
            .select => |op| {
                if (inst.result) |reg| {
                    // 检查结果是否是指针类型（引用参数合并）
                    const is_result_ptr = if (self.current_ref_ptr_regs) |rpr| rpr.contains(reg.id) else false;

                    if (is_result_ptr) {
                        // 指针类型select：需要检查源值是否也是指针
                        const then_is_ptr = self.isPointerReg(op.then_value.id);
                        const else_is_ptr = self.isPointerReg(op.else_value.id);
                        
                        try writer.writeAll("    if (");
                        try self.writeConditionExpr(writer, op.cond.id, op.cond.type_);
                        try writer.writeAll(") {\n");
                        
                        if (then_is_ptr) {
                            // then_value 是指针，直接赋值
                            try writer.print("        reg_{d} = reg_{d};\n", .{ reg.id, op.then_value.id });
                        } else {
                            // then_value 不是指针，需要取地址
                            try writer.print("        reg_{d} = &reg_{d};\n", .{ reg.id, op.then_value.id });
                        }
                        
                        try writer.writeAll("    } else {\n");
                        
                        if (else_is_ptr) {
                            // else_value 是指针，直接赋值
                            try writer.print("        reg_{d} = reg_{d};\n", .{ reg.id, op.else_value.id });
                        } else {
                            // else_value 不是指针，需要取地址
                            try writer.print("        reg_{d} = &reg_{d};\n", .{ reg.id, op.else_value.id });
                        }
                        
                        try writer.writeAll("    }\n");
                    } else {
                        // 普通select：值类型
                        const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                        if (type_tag != .php_value) {
                            try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                        }
                        try writer.writeAll("    if (");
                        try self.writeConditionExpr(writer, op.cond.id, op.cond.type_);
                        try writer.writeAll(") {\n");

                        var then_buf: [32]u8 = undefined;
                        const then_ref = try self.getOperandRef(&then_buf, op.then_value.id);
                        try writer.print("        reg_{d} = {s};\n", .{ reg.id, then_ref });
                        try writer.print("        _ = reg_{d}.retain();\n", .{reg.id});
                        try writer.writeAll("    } else {\n");

                        var else_buf: [32]u8 = undefined;
                        const else_ref = try self.getOperandRef(&else_buf, op.else_value.id);
                        try writer.print("        reg_{d} = {s};\n", .{ reg.id, else_ref });
                        try writer.print("        _ = reg_{d}.retain();\n", .{reg.id});
                        try writer.writeAll("    }\n");
                    }
                }
            },
            .const_null => {
                if (inst.result) |reg| {
                    try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initNull();\n", .{});
                }
            },
            .const_missing => {
                if (inst.result) |reg| {
                    try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initMissing();\n", .{});
                }
            },
            .arg_count => {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d} = @intCast(args.len);\n", .{reg.id});
                }
            },
            .has_arg => |op| {
                if (inst.result) |reg| {
                    const has_this = blk: {
                        if (self.current_function_for_resolve) |func| {
                            if (func.params.items.len > 0) {
                                break :blk std.mem.eql(u8, func.params.items[0].name, "this");
                            }
                        }
                        break :blk false;
                    };
                    const args_index = if (has_this) (if (op.index > 0) op.index - 1 else 0) else op.index;
                    try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool((args.len > {d}) and !args[{d}].isMissing());\n", .{ args_index, args_index });
                }
            },
            .eq => |op| {
                if (inst.result) |reg| {
                    const corrected_type = if (self.current_register_types) |types|
                        types.get(reg.id) orelse reg.type_
                    else
                        reg.type_;
                    const type_tag = @as(std.meta.Tag(IR.Type), corrected_type);

                    // 获取操作数的修正类型
                    const lhs_corrected = if (self.current_register_types) |types|
                        types.get(op.lhs.id) orelse op.lhs.type_
                    else
                        op.lhs.type_;
                    const rhs_corrected = if (self.current_register_types) |types|
                        types.get(op.rhs.id) orelse op.rhs.type_
                    else
                        op.rhs.type_;

                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), lhs_corrected);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), rhs_corrected);

                    if (lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "reg_{d}.asInt() == reg_{d}.asInt();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool(reg_{d}.asInt() == reg_{d}.asInt());\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else if (lhs_type_tag == .f64 and rhs_type_tag == .f64) {
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "reg_{d}.asFloat() == reg_{d}.asFloat();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool(reg_{d}.asFloat() == reg_{d}.asFloat());\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else if (lhs_type_tag == .php_value and rhs_type_tag == .php_value) {
                        // 两个Value类型，直接调用运行时函数
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "(try runtime.php_eq(reg_{d}, reg_{d})).toBool();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.php_eq(reg_{d}, reg_{d});\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else {
                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_eq(", .{reg.id});
                            try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                            try writer.writeAll(")).toBool();\n");
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_eq(", .{reg.id});
                            try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                            try writer.writeAll(");\n");
                        }
                    }
                }
            },
            .ne => |op| {
                if (inst.result) |reg| {
                    const corrected_type = if (self.current_register_types) |types|
                        types.get(reg.id) orelse reg.type_
                    else
                        reg.type_;
                    const type_tag = @as(std.meta.Tag(IR.Type), corrected_type);

                    // 获取操作数的修正类型
                    const lhs_corrected = if (self.current_register_types) |types|
                        types.get(op.lhs.id) orelse op.lhs.type_
                    else
                        op.lhs.type_;
                    const rhs_corrected = if (self.current_register_types) |types|
                        types.get(op.rhs.id) orelse op.rhs.type_
                    else
                        op.rhs.type_;

                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), lhs_corrected);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), rhs_corrected);

                    if (lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "reg_{d}.asInt() != reg_{d}.asInt();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool(reg_{d}.asInt() != reg_{d}.asInt());\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else if (lhs_type_tag == .f64 and rhs_type_tag == .f64) {
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "reg_{d}.asFloat() != reg_{d}.asFloat();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool(reg_{d}.asFloat() != reg_{d}.asFloat());\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else if (lhs_type_tag == .php_value and rhs_type_tag == .php_value) {
                        // 两个Value类型，直接调用运行时函数
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "(try runtime.php_ne(reg_{d}, reg_{d})).toBool();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.php_ne(reg_{d}, reg_{d});\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else {
                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_ne(", .{reg.id});
                            try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                            try writer.writeAll(")).toBool();\n");
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_ne(", .{reg.id});
                            try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                            try writer.writeAll(");\n");
                        }
                    }
                }
            },
            .identical => |op| {
                if (inst.result) |reg| {
                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    // 所有寄存器都声明为runtime.Value，所以总是生成返回Value的代码
                    // 不再根据type_tag判断，因为会导致类型不匹配
                    try writer.print("    reg_{d} = try runtime.php_identical(", .{reg.id});
                    try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                    try writer.writeAll(", ");
                    try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                    try writer.writeAll(");\n");
                }
            },
            .not_identical => |op| {
                if (inst.result) |reg| {
                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    // 所有寄存器都声明为runtime.Value，所以总是生成返回Value的代码
                    // 不再根据type_tag判断，因为会导致类型不匹配
                    try writer.print("    reg_{d} = try runtime.php_not_identical(", .{reg.id});
                    try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                    try writer.writeAll(", ");
                    try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                    try writer.writeAll(");\n");
                }
            },
            .lt => |op| {
                if (inst.result) |reg| {
                    // 使用修正后的类型
                    const corrected_type = if (self.current_register_types) |types|
                        types.get(reg.id) orelse reg.type_
                    else
                        reg.type_;
                    const type_tag = @as(std.meta.Tag(IR.Type), corrected_type);

                    // 获取操作数的修正类型
                    const lhs_corrected = if (self.current_register_types) |types|
                        types.get(op.lhs.id) orelse op.lhs.type_
                    else
                        op.lhs.type_;
                    const rhs_corrected = if (self.current_register_types) |types|
                        types.get(op.rhs.id) orelse op.rhs.type_
                    else
                        op.rhs.type_;

                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), lhs_corrected);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), rhs_corrected);

                    // 检查操作数类型是否一致且为基本类型
                    if (lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                        // 两个i64比较（寄存器是Value类型，需要转换）
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "reg_{d}.asInt() < reg_{d}.asInt();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            // 结果是 Value 类型，需要包装
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool(reg_{d}.asInt() < reg_{d}.asInt());\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else if (lhs_type_tag == .f64 and rhs_type_tag == .f64) {
                        // 两个f64比较（寄存器是Value类型，需要转换）
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "reg_{d}.asFloat() < reg_{d}.asFloat();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool(reg_{d}.asFloat() < reg_{d}.asFloat());\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else if (lhs_type_tag == .php_value and rhs_type_tag == .php_value) {
                        // 两个Value类型，直接调用运行时函数
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "(try runtime.php_lt(reg_{d}, reg_{d})).toBool();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.php_lt(reg_{d}, reg_{d});\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else {
                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_lt(", .{reg.id});
                            try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                            try writer.writeAll(")).toBool();\n");
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_lt(", .{reg.id});
                            try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                            try writer.writeAll(");\n");
                        }
                    }
                }
            },
            .le => |op| {
                if (inst.result) |reg| {
                    const corrected_type = if (self.current_register_types) |types|
                        types.get(reg.id) orelse reg.type_
                    else
                        reg.type_;
                    const type_tag = @as(std.meta.Tag(IR.Type), corrected_type);

                    // 获取操作数的修正类型
                    const lhs_corrected = if (self.current_register_types) |types|
                        types.get(op.lhs.id) orelse op.lhs.type_
                    else
                        op.lhs.type_;
                    const rhs_corrected = if (self.current_register_types) |types|
                        types.get(op.rhs.id) orelse op.rhs.type_
                    else
                        op.rhs.type_;

                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), lhs_corrected);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), rhs_corrected);

                    if (lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "reg_{d}.asInt() <= reg_{d}.asInt();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool(reg_{d}.asInt() <= reg_{d}.asInt());\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else if (lhs_type_tag == .f64 and rhs_type_tag == .f64) {
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "reg_{d}.asFloat() <= reg_{d}.asFloat();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool(reg_{d}.asFloat() <= reg_{d}.asFloat());\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else if (lhs_type_tag == .php_value and rhs_type_tag == .php_value) {
                        // 两个Value类型，直接调用运行时函数
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "(try runtime.php_le(reg_{d}, reg_{d})).toBool();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.php_le(reg_{d}, reg_{d});\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else {
                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_le(", .{reg.id});
                            try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                            try writer.writeAll(")).toBool();\n");
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_le(", .{reg.id});
                            try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                            try writer.writeAll(");\n");
                        }
                    }
                }
            },
            .gt => |op| {
                if (inst.result) |reg| {
                    const corrected_type = if (self.current_register_types) |types|
                        types.get(reg.id) orelse reg.type_
                    else
                        reg.type_;
                    const type_tag = @as(std.meta.Tag(IR.Type), corrected_type);

                    // 获取操作数的修正类型
                    const lhs_corrected = if (self.current_register_types) |types|
                        types.get(op.lhs.id) orelse op.lhs.type_
                    else
                        op.lhs.type_;
                    const rhs_corrected = if (self.current_register_types) |types|
                        types.get(op.rhs.id) orelse op.rhs.type_
                    else
                        op.rhs.type_;

                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), lhs_corrected);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), rhs_corrected);

                    if (lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "reg_{d}.asInt() > reg_{d}.asInt();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool(reg_{d}.asInt() > reg_{d}.asInt());\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else if (lhs_type_tag == .f64 and rhs_type_tag == .f64) {
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "reg_{d}.asFloat() > reg_{d}.asFloat();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool(reg_{d}.asFloat() > reg_{d}.asFloat());\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else if (lhs_type_tag == .php_value and rhs_type_tag == .php_value) {
                        // 两个Value类型，直接调用运行时函数
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "(try runtime.php_gt(reg_{d}, reg_{d})).toBool();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.php_gt(reg_{d}, reg_{d});\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else {
                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_gt(", .{reg.id});
                            try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                            try writer.writeAll(")).toBool();\n");
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_gt(", .{reg.id});
                            try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                            try writer.writeAll(");\n");
                        }
                    }
                }
            },
            .ge => |op| {
                if (inst.result) |reg| {
                    const corrected_type = if (self.current_register_types) |types|
                        types.get(reg.id) orelse reg.type_
                    else
                        reg.type_;
                    const type_tag = @as(std.meta.Tag(IR.Type), corrected_type);

                    // 获取操作数的修正类型
                    const lhs_corrected = if (self.current_register_types) |types|
                        types.get(op.lhs.id) orelse op.lhs.type_
                    else
                        op.lhs.type_;
                    const rhs_corrected = if (self.current_register_types) |types|
                        types.get(op.rhs.id) orelse op.rhs.type_
                    else
                        op.rhs.type_;

                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), lhs_corrected);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), rhs_corrected);

                    if (lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "reg_{d}.asInt() >= reg_{d}.asInt();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool(reg_{d}.asInt() >= reg_{d}.asInt());\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else if (lhs_type_tag == .f64 and rhs_type_tag == .f64) {
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "reg_{d}.asFloat() >= reg_{d}.asFloat();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool(reg_{d}.asFloat() >= reg_{d}.asFloat());\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else if (lhs_type_tag == .php_value and rhs_type_tag == .php_value) {
                        // 两个Value类型，直接调用运行时函数
                        if (type_tag == .bool) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "(try runtime.php_ge(reg_{d}, reg_{d})).toBool();\n", .{ op.lhs.id, op.rhs.id });
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.php_ge(reg_{d}, reg_{d});\n", .{ op.lhs.id, op.rhs.id });
                        }
                    } else {
                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_ge(", .{reg.id});
                            try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                            try writer.writeAll(")).toBool();\n");
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_ge(", .{reg.id});
                            try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                            try writer.writeAll(");\n");
                        }
                    }
                }
            },
            .spaceship => |op| {
                if (inst.result) |reg| {
                    const lhs_corrected = if (self.current_register_types) |types|
                        types.get(op.lhs.id) orelse op.lhs.type_
                    else
                        op.lhs.type_;
                    const rhs_corrected = if (self.current_register_types) |types|
                        types.get(op.rhs.id) orelse op.rhs.type_
                    else
                        op.rhs.type_;

                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), lhs_corrected);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), rhs_corrected);

                    if (lhs_type_tag == .php_value and rhs_type_tag == .php_value) {
                        try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.php_spaceship(reg_{d}, reg_{d});\n", .{ op.lhs.id, op.rhs.id });
                    } else {
                        try writer.print("    reg_{d} = try runtime.php_spaceship(", .{reg.id});
                        try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                        try writer.writeAll(", ");
                        try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                        try writer.writeAll(");\n");
                    }
                }
            },
            .and_ => |op| {
                if (inst.result) |reg| {
                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    // 所有寄存器都是 Value 类型，总是需要包装
                    try writer.print("    reg_{d} = runtime.Value.initBool(", .{reg.id});
                    try self.writeBoolExpr(writer, lhs_type_tag, op.lhs.id);
                    try writer.writeAll(" and ");
                    try self.writeBoolExpr(writer, rhs_type_tag, op.rhs.id);
                    try writer.writeAll(");\n");
                }
            },
            .or_ => |op| {
                if (inst.result) |reg| {
                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    // 所有寄存器都是 Value 类型，总是需要包装
                    try writer.print("    reg_{d} = runtime.Value.initBool(", .{reg.id});
                    try self.writeBoolExpr(writer, lhs_type_tag, op.lhs.id);
                    try writer.writeAll(" or ");
                    try self.writeBoolExpr(writer, rhs_type_tag, op.rhs.id);
                    try writer.writeAll(");\n");
                }
            },
            .xor_ => |op| {
                if (inst.result) |reg| {
                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    // XOR: (a and !b) or (!a and b)
                    try writer.print("    reg_{d} = runtime.Value.initBool((", .{reg.id});
                    try self.writeBoolExpr(writer, lhs_type_tag, op.lhs.id);
                    try writer.writeAll(" and !");
                    try self.writeBoolExpr(writer, rhs_type_tag, op.rhs.id);
                    try writer.writeAll(") or (!");
                    try self.writeBoolExpr(writer, lhs_type_tag, op.lhs.id);
                    try writer.writeAll(" and ");
                    try self.writeBoolExpr(writer, rhs_type_tag, op.rhs.id);
                    try writer.writeAll("));\n");
                }
            },
            .neg => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const operand_type_tag = @as(std.meta.Tag(IR.Type), op.operand.type_);

                    if (type_tag == .i64 and operand_type_tag == .i64) {
                        try self.writeRegAssignmentFmt(writer, reg.id, "-reg_{d};\n", .{op.operand.id});
                    } else if (operand_type_tag == .php_value) {
                        if (type_tag == .i64) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "(try runtime.php_neg(reg_{d})).toInt();\n", .{op.operand.id});
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.php_neg(reg_{d});\n", .{op.operand.id});
                        }
                    } else {
                        // Default to runtime call if not simple i64
                        // If operand is i64 but result is Value, wrap operand
                        if (operand_type_tag == .i64) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.php_neg(runtime.Value.initInt(reg_{d}));\n", .{op.operand.id});
                        } else {
                            try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.php_neg(reg_{d});\n", .{op.operand.id});
                        }
                    }
                }
            },
            .clone => |op| {
                if (inst.result) |reg| {
                    try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.php_clone(reg_{d}, runtime.runtime_allocator);\n", .{op.operand.id});
                }
            },
            .bit_not => |op| {
                if (inst.result) |reg| {
                    const operand_type_tag = @as(std.meta.Tag(IR.Type), op.operand.type_);

                    // 所有寄存器都声明为 Value，所以总是返回 Value
                    if (operand_type_tag == .php_value) {
                        try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initInt(~reg_{d}.toInt());\n", .{op.operand.id});
                    } else if (operand_type_tag == .i64) {
                        try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initInt(~reg_{d});\n", .{op.operand.id});
                    } else {
                        try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initInt(~reg_{d}.toInt());\n", .{op.operand.id});
                    }
                }
            },
            .not => |op| {
                if (inst.result) |reg| {
                    // std.debug.print("generateInstructionSimple: not reg_{d} = !reg_{d}, result_type={s}, operand_type={s}\n", .{
                    //     reg.id, op.operand.id, @tagName(reg.type_), @tagName(op.operand.type_)
                    // });

                    // 使用修正后的类型
                    const operand_corrected = if (self.current_register_types) |types|
                        types.get(op.operand.id) orelse op.operand.type_
                    else
                        op.operand.type_;

                    const operand_type_tag = @as(std.meta.Tag(IR.Type), operand_corrected);

                    // 所有寄存器都声明为 runtime.Value，所以总是生成返回 Value 的代码
                    if (operand_type_tag == .php_value) {
                        try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.php_not(reg_{d});\n", .{op.operand.id});
                    } else if (operand_type_tag == .bool) {
                        try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool(!reg_{d});\n", .{op.operand.id});
                    } else if (operand_type_tag == .i64) {
                        try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool(reg_{d} == 0);\n", .{op.operand.id});
                    } else {
                        try writer.print("    reg_{d} = try runtime.php_not(", .{reg.id});
                        try self.writePhpValueExpr(writer, operand_type_tag, op.operand.id);
                        try writer.writeAll(");\n");
                    }
                }
            },
            .call => |op| {
                // @ 错误抑制运算符：直接调用运行时函数
                if (std.mem.eql(u8, op.func_name, "php_error_suppress_push")) {
                    try writer.writeAll("    runtime.php_error_suppress_push();\n");
                } else if (std.mem.eql(u8, op.func_name, "php_error_suppress_pop")) {
                    try writer.writeAll("    runtime.php_error_suppress_pop();\n");
                } else {

                // 生成函数调用
                // 检查是否是内置函数
                const is_builtin = self.isBuiltinFunction(op.func_name);
                const is_runtime_declare = std.mem.startsWith(u8, op.func_name, "__declare_function__::");

                // 生成函数调用
                if (is_runtime_declare) {
                    const declared_name = op.func_name["__declare_function__::".len..];
                    if (self.ir_module) |module| {
                        if (module.findFunction(declared_name)) |func| {
                            const escaped_declared_name = try self.escapeString(declared_name);
                            defer self.allocator.free(escaped_declared_name);
                            try writer.print("    try runtime.registerUserFunctionWithLocation(\"{s}\", @\"{s}\", \"{s}\", {d});\n", .{ escaped_declared_name, escaped_declared_name, func.location.file, func.location.line });
                            // 注册函数元数据
                            const pc = func.params.items.len;
                            var rc: usize = 0;
                            for (func.params.items) |p| {
                                if (!p.has_default and !p.is_variadic) rc += 1;
                            }
                            try writer.print("    runtime.registerFunctionMeta(\"{s}\", {d}, {d});\n", .{ escaped_declared_name, pc, rc });
                        }
                    }
                    if (inst.result) |reg| {
                        try self.writeRegAssignmentPrefix(writer, reg.id);
                        try writer.writeAll("runtime.Value.initNull();\n");
                    }
                } else if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    if (type_tag != .i64 and type_tag != .f64 and type_tag != .bool) {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                    }

                    // 有返回值寄存器
                    if (is_builtin) {
                        const runtime_name = self.mapToRuntimeFunction(op.func_name);

                        // 特殊处理 throwThrowable：需要将Value参数转换为[]const u8
                        if (std.mem.eql(u8, runtime_name, "throwThrowable")) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                            if (op.args.len >= 2) {
                                // 第1个参数：class_name (Value -> []const u8)
                                const class_arg = op.args[0];
                                try writer.print("reg_{d}.asString().data, ", .{class_arg.id});
                                
                                // 第2个参数：message (Value -> []const u8)
                                const msg_arg = op.args[1];
                                try writer.print("reg_{d}.asString().data", .{msg_arg.id});
                            } else {
                                try writer.writeAll("\"UnhandledMatchError\", \"Unhandled match case\"");
                            }
                            try writer.writeAll(", runtime.runtime_allocator);\n");
                        } else if (std.mem.eql(u8, runtime_name, "preg_match") or std.mem.eql(u8, runtime_name, "php_preg_match")) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                            if (op.args.len >= 2) {
                                // 前2个参数正常传递
                                try self.writeValueArgs(writer, op.args[0..2]);
                                try writer.writeAll(", ");
                                
                                // 第3个参数matches（引用）
                                if (op.args.len >= 3) {
                                    const matches_arg = op.args[2];
                                    const matches_type = @as(std.meta.Tag(IR.Type), matches_arg.type_);
                                    const is_alloca = if (self.current_alloca_regs) |alloca_regs|
                                        alloca_regs.contains(matches_arg.id)
                                    else
                                        false;
                                    
                                    if (matches_type == .ptr or is_alloca) {
                                        // 指针类型，直接传递
                                        try writer.print("reg_{d}", .{matches_arg.id});
                                    } else {
                                        // 非指针类型：检查是否是常量（const.null等）
                                        // 对于常量，使用临时变量；对于寄存器，取地址
                                        const inst_for_arg = blk: {
                                            if (self.current_function_for_resolve) |func| {
                                                for (func.blocks.items) |block| {
                                                    for (block.instructions.items) |inst_item| {
                                                        if (inst_item.result) |res| {
                                                            if (res.id == matches_arg.id) {
                                                                break :blk inst_item;
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            break :blk null;
                                        };
                                        
                                        // 如果是常量指令（const_null, const_int等），使用临时变量
                                        const is_const = if (inst_for_arg) |inst_item|
                                            (inst_item.op == .const_null or inst_item.op == .const_int or inst_item.op == .const_float or inst_item.op == .const_bool or inst_item.op == .const_string)
                                        else
                                            false;
                                        
                                        if (is_const) {
                                            try writer.writeAll("blk: { var tmp = reg_");
                                            try writer.print("{d}; break :blk &tmp; }}", .{matches_arg.id});
                                        } else {
                                            try writer.print("&reg_{d}", .{matches_arg.id});
                                        }
                                    }
                                } else {
                                    // 使用一个临时变量
                                    try writer.writeAll("blk: { var tmp = runtime.Value.initNull(); break :blk &tmp; }");
                                }
                                try writer.writeAll(", ");
                                
                                // 第4个参数flags（可选，默认0）
                                if (op.args.len >= 4) {
                                    try self.writeRegRef(writer, op.args[3].id);
                                } else {
                                    try writer.writeAll("runtime.Value.initInt(0)");
                                }
                                try writer.writeAll(", ");
                                
                                // 第5个参数offset（可选，默认0）
                                if (op.args.len >= 5) {
                                    try self.writeRegRef(writer, op.args[4].id);
                                } else {
                                    try writer.writeAll("runtime.Value.initInt(0)");
                                }
                                
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                            } else {
                                // 参数不足，fallback
                                try writer.writeAll("runtime.Value.initNull(), runtime.Value.initNull(), blk: { var tmp = runtime.Value.initNull(); break :blk &tmp; }, runtime.Value.initInt(0), runtime.Value.initInt(0), runtime.runtime_allocator);\n");
                            }
                        } else if (std.mem.eql(u8, runtime_name, "preg_match_all") or std.mem.eql(u8, runtime_name, "php_preg_match_all")) {
                            // preg_match_all与preg_match相同处理
                            try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                            if (op.args.len >= 2) {
                                try self.writeValueArgs(writer, op.args[0..2]);
                                try writer.writeAll(", ");
                                
                                if (op.args.len >= 3) {
                                    const matches_arg = op.args[2];
                                    const is_alloca = if (self.current_alloca_regs) |alloca_regs|
                                        alloca_regs.contains(matches_arg.id)
                                    else
                                        false;
                                    
                                    if (is_alloca) {
                                        // 真正的alloca寄存器
                                        try writer.print("reg_{d}", .{matches_arg.id});
                                    } else {
                                        // 非alloca：使用临时变量（因为可能是未定义的ptr寄存器）
                                        try writer.writeAll("blk: { var tmp = reg_");
                                        try writer.print("{d}; break :blk &tmp; }}", .{matches_arg.id});
                                    }
                                } else {
                                    try writer.writeAll("blk: { var tmp = runtime.Value.initNull(); break :blk &tmp; }");
                                }
                                try writer.writeAll(", ");
                                
                                if (op.args.len >= 4) {
                                    try self.writeRegRef(writer, op.args[3].id);
                                } else {
                                    try writer.writeAll("runtime.Value.initInt(0)");
                                }
                                try writer.writeAll(", ");
                                
                                if (op.args.len >= 5) {
                                    try self.writeRegRef(writer, op.args[4].id);
                                } else {
                                    try writer.writeAll("runtime.Value.initInt(0)");
                                }
                                
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                            } else {
                                try writer.writeAll("runtime.Value.initNull(), runtime.Value.initNull(), blk: { var tmp = runtime.Value.initNull(); break :blk &tmp; }, runtime.Value.initInt(0), runtime.Value.initInt(0), runtime.runtime_allocator);\n");
                            }
                        } else if (std.mem.eql(u8, runtime_name, "preg_match_with_matches")) {
                            // 旧版本兼容：preg_match_with_matches
                            if (op.args.len >= 3) {
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.php_preg_match(", .{});
                                // 前2个参数正常传递
                                try self.writeValueArgs(writer, op.args[0..2]);
                                try writer.writeAll(", ");
                                // 第3个参数：引用参数
                                const matches_arg = op.args[2];
                                const is_alloca = if (self.current_alloca_regs) |alloca_regs|
                                    alloca_regs.contains(matches_arg.id)
                                else
                                    false;
                                
                                // 只有真正的alloca寄存器（*Value）才直接传递，其他都取地址
                                if (is_alloca) {
                                    try writer.print("reg_{d}", .{matches_arg.id});
                                } else {
                                    try writer.print("&reg_{d}", .{matches_arg.id});
                                }
                                try writer.writeAll(", runtime.Value.initInt(0), runtime.Value.initInt(0), runtime.runtime_allocator);\n");
                            } else {
                                // 参数不足，fallback
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.php_preg_match(", .{});
                                try self.writeValueArgs(writer, op.args);
                                try writer.writeAll(", blk: { var tmp = runtime.Value.initNull(); break :blk &tmp; }, runtime.Value.initInt(0), runtime.Value.initInt(0), runtime.runtime_allocator);\n");
                            }
                        } else if (std.mem.eql(u8, runtime_name, "php_max") or std.mem.eql(u8, runtime_name, "php_min")) {
                            try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                            try self.writeValueArgsArray(writer, op.args);
                            try writer.writeAll(");\n");
                        } else if (std.mem.eql(u8, runtime_name, "php_in_array")) {
                            // in_array(needle, haystack, strict = false)
                            try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                            try self.writeValueArgs(writer, op.args);
                            if (op.args.len < 3) {
                                try writer.writeAll(", runtime.Value.initBool(false)");
                            }
                            try writer.writeAll(");\n");
                        } else if (std.mem.eql(u8, runtime_name, "php_array_slice")) {
                            // array_slice 的 length 参数是可选的，缺失时补 null
                            try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                            try self.writeValueArgs(writer, op.args);
                            if (op.args.len < 3) {
                                try writer.writeAll(", runtime.Value.initNull()");
                            }
                            try writer.writeAll(", runtime.runtime_allocator);\n");
                        } else if (std.mem.eql(u8, runtime_name, "php_mt_rand") or std.mem.eql(u8, runtime_name, "php_rand")) {
                            // mt_rand(min = null, max = null) - 不需要allocator
                            try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                            if (op.args.len == 0) {
                                try writer.writeAll("runtime.Value.initNull(), runtime.Value.initNull()");
                            } else if (op.args.len == 1) {
                                try self.writeValueArgs(writer, op.args);
                                try writer.writeAll(", runtime.Value.initNull()");
                            } else {
                                try self.writeValueArgs(writer, op.args);
                            }
                            try writer.writeAll(");\n");
                        } else if (self.functionNeedsAllocator(op.func_name)) {
                            if (std.mem.eql(u8, runtime_name, "php_sprintf") or std.mem.eql(u8, runtime_name, "php_printf")) {
                                if (op.args.len == 0) {
                                    try writer.print("    reg_{d} = runtime.Value.initNull();\n", .{reg.id});
                                } else {
                                    const fmt_arg = op.args[0];
                                    const fmt_arg_type = @as(std.meta.Tag(IR.Type), fmt_arg.type_);
                                    try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                    try self.writePhpValueExpr(writer, fmt_arg_type, fmt_arg.id);
                                    try writer.writeAll(", ");
                                    try self.writeValueArgsArray(writer, op.args[1..]);
                                    try writer.writeAll(", runtime.runtime_allocator);\n");
                                }
                            } else if (std.mem.eql(u8, runtime_name, "php_str_getcsv")) {
                                if (op.args.len < 4) {
                                    try writer.writeAll("    runtime.emitDeprecatedStrGetcsvEscape();\n");
                                }
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                try self.writeStrGetcsvArgs(writer, op.args);
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_array_merge") or std.mem.eql(u8, runtime_name, "php_array_intersect") or std.mem.eql(u8, runtime_name, "php_array_diff") or std.mem.eql(u8, runtime_name, "php_array_diff_key") or std.mem.eql(u8, runtime_name, "php_array_multisort") or std.mem.eql(u8, runtime_name, "php_compact") or std.mem.eql(u8, runtime_name, "php_array_map") or std.mem.eql(u8, runtime_name, "php_json_decode") or std.mem.eql(u8, runtime_name, "php_func_get_args") or std.mem.eql(u8, runtime_name, "php_memory_get_usage") or std.mem.eql(u8, runtime_name, "php_memory_get_peak_usage") or std.mem.eql(u8, runtime_name, "php_shell_exec") or std.mem.eql(u8, runtime_name, "php_exec") or std.mem.eql(u8, runtime_name, "php_system") or std.mem.eql(u8, runtime_name, "php_substr_replace") or std.mem.eql(u8, runtime_name, "php_function_exists") or std.mem.eql(u8, runtime_name, "php_gc_enable") or std.mem.eql(u8, runtime_name, "php_gc_collect_cycles") or std.mem.eql(u8, runtime_name, "php_ini_get") or std.mem.eql(u8, runtime_name, "php_getrusage") or std.mem.eql(u8, runtime_name, "php_unset")) {
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                try self.writeValueArgsArray(writer, op.args);
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_array_push") or std.mem.eql(u8, runtime_name, "php_array_unshift")) {
                                if (op.args.len == 0) {
                                    try writer.print("    reg_{d} = runtime.Value.initNull();\n", .{reg.id});
                                } else {
                                    const first_arg = op.args[0];
                                    const first_type = @as(std.meta.Tag(IR.Type), first_arg.type_);
                                    try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                    try self.writePhpValueExpr(writer, first_type, first_arg.id);
                                    try writer.writeAll(", ");
                                    try self.writeValueArgsArray(writer, op.args[1..]);
                                    try writer.writeAll(", runtime.runtime_allocator);\n");
                                }
                            } else if (std.mem.eql(u8, runtime_name, "php_microtime")) {
                                // microtime(get_as_float = false)
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                if (op.args.len > 0) {
                                    try self.writeValueArgs(writer, op.args);
                                } else {
                                    try writer.writeAll("runtime.Value.initBool(false)");
                                }
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_date")) {
                                // date(format, timestamp = null)
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                if (op.args.len > 0) {
                                    try self.writeValueArgs(writer, op.args);
                                    if (op.args.len == 1) {
                                        try writer.writeAll(", runtime.Value.initNull()");
                                    }
                                } else {
                                    try writer.writeAll("runtime.Value.initNull(), runtime.Value.initNull()");
                                }
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_strtotime")) {
                                // strtotime(time_str, now = null)
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                if (op.args.len > 0) {
                                    try self.writeValueArgs(writer, op.args);
                                    if (op.args.len == 1) {
                                        try writer.writeAll(", runtime.Value.initNull()");
                                    }
                                } else {
                                    try writer.writeAll("runtime.Value.initNull(), runtime.Value.initNull()");
                                }
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_count")) {
                                // count(arr, mode = 0)
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                if (op.args.len > 0) {
                                    try self.writeValueArgs(writer, op.args);
                                    if (op.args.len == 1) {
                                        try writer.writeAll(", runtime.Value.initInt(0)");
                                    }
                                } else {
                                    try writer.writeAll("runtime.Value.initNull(), runtime.Value.initInt(0)");
                                }
                                try writer.writeAll(");\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_array_chunk")) {
                                // array_chunk(arr, size, preserve_keys = false)
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                if (op.args.len > 0) {
                                    try self.writeValueArgs(writer, op.args);
                                    if (op.args.len == 2) {
                                        try writer.writeAll(", runtime.Value.initBool(false)");
                                    } else if (op.args.len == 1) {
                                        try writer.writeAll(", runtime.Value.initInt(1), runtime.Value.initBool(false)");
                                    }
                                }
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_array_rand")) {
                                // array_rand(arr, num = 1)
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                if (op.args.len > 0) {
                                    try self.writeValueArgs(writer, op.args);
                                    if (op.args.len == 1) {
                                        try writer.writeAll(", runtime.Value.initInt(1)");
                                    }
                                }
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_json_encode")) {
                                // json_encode(value, flags = 0, depth = 512)
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                if (op.args.len > 0) {
                                    try self.writeValueArgs(writer, op.args);
                                    if (op.args.len == 1) {
                                        try writer.writeAll(", runtime.Value.initInt(0), runtime.Value.initInt(512)");
                                    } else if (op.args.len == 2) {
                                        try writer.writeAll(", runtime.Value.initInt(512)");
                                    }
                                } else {
                                    try writer.writeAll("runtime.Value.initNull(), runtime.Value.initInt(0), runtime.Value.initInt(512)");
                                }
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_array_column")) {
                                // array_column(arr, column_key, index_key = null)
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                if (op.args.len >= 2) {
                                    try self.writeValueArgs(writer, op.args);
                                    if (op.args.len == 2) {
                                        try writer.writeAll(", runtime.Value.initNull()");
                                    }
                                } else {
                                    try writer.writeAll("runtime.Value.initNull(), runtime.Value.initNull(), runtime.Value.initNull()");
                                }
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_extract")) {
                                // extract(arr, flags = EXTR_OVERWRITE, prefix = "")
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                if (op.args.len > 0) {
                                    try self.writeValueArgs(writer, op.args);
                                    if (op.args.len == 1) {
                                        try writer.writeAll(", runtime.Value.initInt(0), runtime.Value.initString(runtime.PHPString.initStatic(\"\"))");
                                    } else if (op.args.len == 2) {
                                        try writer.writeAll(", runtime.Value.initString(runtime.PHPString.initStatic(\"\"))");
                                    }
                                } else {
                                    try writer.writeAll("runtime.Value.initNull(), runtime.Value.initInt(0), runtime.Value.initString(runtime.PHPString.initStatic(\"\"))");
                                }
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_array_iter_init") or
                                std.mem.eql(u8, runtime_name, "php_array_iter_key") or
                                std.mem.eql(u8, runtime_name, "php_array_iter_free"))
                            {
                                // 这些函数的 allocator 在第二个参数位置
                                if (op.args.len > 0) {
                                    const first_arg = op.args[0];
                                    const first_type = @as(std.meta.Tag(IR.Type), first_arg.type_);
                                    try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                    try self.writePhpValueExpr(writer, first_type, first_arg.id);
                                    try writer.writeAll(", runtime.runtime_allocator");
                                    if (op.args.len > 1) {
                                        try writer.writeAll(", ");
                                        try self.writeValueArgs(writer, op.args[1..]);
                                    }
                                    try writer.writeAll(");\n");
                                } else {
                                    try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(runtime.Value.initNull(), runtime.runtime_allocator);\n", .{runtime_name});
                                }
                            } else if (op.args.len > 0) {
                                // 特殊处理：file_put_contents只接受2个参数+allocator
                                if (std.mem.eql(u8, runtime_name, "php_file_put_contents")) {
                                    const max_args = @min(op.args.len, 2);
                                    try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                    try self.writeValueArgs(writer, op.args[0..max_args]);
                                    try writer.writeAll(", runtime.runtime_allocator);\n");
                                } else {
                                    try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                    try self.writeValueArgs(writer, op.args);
                                    try writer.writeAll(", runtime.runtime_allocator);\n");
                                }
                            } else {
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(runtime.runtime_allocator);\n", .{runtime_name});
                            }
                        } else {
                            // 特殊处理可选参数函数
                            if (std.mem.eql(u8, runtime_name, "php_round")) {
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                if (op.args.len > 0) {
                                    try self.writeValueArgs(writer, op.args);
                                    if (op.args.len == 1) {
                                        try writer.writeAll(", runtime.Value.initNull()");
                                    }
                                } else {
                                    try writer.writeAll("runtime.Value.initNull(), runtime.Value.initNull()");
                                }
                                try writer.writeAll(");\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_count")) {
                                // count(arr, mode = 0)
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                if (op.args.len > 0) {
                                    try self.writeValueArgs(writer, op.args);
                                    if (op.args.len == 1) {
                                        try writer.writeAll(", runtime.Value.initInt(0)");
                                    }
                                } else {
                                    try writer.writeAll("runtime.Value.initNull(), runtime.Value.initInt(0)");
                                }
                                try writer.writeAll(");\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_isset")) {
                                // isset(...$vars) - 可变参数，传递数组切片
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(&[_]runtime.Value{{", .{runtime_name});
                                if (op.args.len > 0) {
                                    for (op.args, 0..) |arg, i| {
                                        if (i > 0) try writer.writeAll(", ");
                                        const arg_type = @as(std.meta.Tag(IR.Type), arg.type_);
                                        try self.writePhpValueExpr(writer, arg_type, arg.id);
                                    }
                                }
                                try writer.writeAll("});\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_unset")) {
                                // unset(...$vars) - 可变参数，传递数组切片
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(&[_]runtime.Value{{", .{runtime_name});
                                if (op.args.len > 0) {
                                    for (op.args, 0..) |arg, i| {
                                        if (i > 0) try writer.writeAll(", ");
                                        const arg_type = @as(std.meta.Tag(IR.Type), arg.type_);
                                        try self.writePhpValueExpr(writer, arg_type, arg.id);
                                    }
                                }
                                try writer.writeAll("}, runtime.runtime_allocator);\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_str_word_count")) {
                                // str_word_count(str, format = 0, charlist = null)
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                if (op.args.len > 0) {
                                    try self.writeValueArgs(writer, op.args);
                                    if (op.args.len == 1) {
                                        try writer.writeAll(", runtime.Value.initInt(0), runtime.Value.initNull()");
                                    } else if (op.args.len == 2) {
                                        try writer.writeAll(", runtime.Value.initNull()");
                                    }
                                } else {
                                    try writer.writeAll("runtime.Value.initNull(), runtime.Value.initInt(0), runtime.Value.initNull()");
                                }
                                try writer.writeAll(");\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_mkdir")) {
                                // mkdir(dirname, permissions = 0777, recursive = false)
                                try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                if (op.args.len > 0) {
                                    try self.writeValueArgs(writer, op.args);
                                    if (op.args.len == 1) {
                                        try writer.writeAll(", runtime.Value.initInt(0o777), runtime.Value.initBool(false)");
                                    } else if (op.args.len == 2) {
                                        try writer.writeAll(", runtime.Value.initBool(false)");
                                    }
                                } else {
                                    try writer.writeAll("runtime.Value.initNull(), runtime.Value.initInt(0o777), runtime.Value.initBool(false)");
                                }
                                try writer.writeAll(");\n");
                            } else if (std.mem.eql(u8, runtime_name, "aot_function_exists")) {
                                // 直接调用，不带runtime.前缀
                                try self.writeRegAssignmentFmt(writer, reg.id, "aot_function_exists(", .{});
                                if (op.args.len > 0) {
                                    const arg = op.args[0];
                                    try self.writePhpValueExpr(writer, @as(std.meta.Tag(IR.Type), arg.type_), arg.id);
                                    try writer.writeAll(".asString().data");
                                }
                                try writer.writeAll(");\n");
                            } else {
                                // 通用builtin函数调用
                                const builtin_info = builtinInfo(op.func_name);
                                const may_raise = if (builtin_info) |info| info.may_raise else true;
                                
                                if (may_raise) {
                                    try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.{s}(", .{runtime_name});
                                } else {
                                    try self.writeRegAssignmentFmt(writer, reg.id, "runtime.{s}(", .{runtime_name});
                                }
                                try self.writeValueArgs(writer, op.args);
                                try writer.writeAll(");\n");
                            }
                        }
                    } else {
                        // 用户定义函数 - 先检查是否存在
                        const escaped_func_name = try self.escapeString(op.func_name);
                        defer self.allocator.free(escaped_func_name);
                        if (!self.isUserDefinedFunction(op.func_name)) {
                            // 函数未定义：生成运行时 Fatal error
                            if (inst.location.line > 0) {
                                try writer.print("    runtime.setSourceLocation(\"{s}\", {d});\n", .{ inst.location.file, inst.location.line });
                            }
                            try writer.print("    runtime.php_call_undefined_function(\"{s}\");\n", .{escaped_func_name});
                        } else {
                            const func_has_return_value = self.func_return_types.get(op.func_name) orelse false;
                            const in_try_block = self.current_exception_handler != null;

                            // 查找函数的引用参数信息
                            const target_func = if (self.ir_module) |module| module.findFunction(op.func_name) else null;
                            const ref_params = if (target_func) |func| func.ref_params.items else &[_]u32{};

                            if (func_has_return_value) {
                                if (in_try_block) {
                                    try self.writeRegAssignmentPrefix(writer, reg.id);
                                    try writer.print("@\"{s}\"(runtime.Value.initNull(), ", .{escaped_func_name});
                                    try self.writeValueArgsArrayWithRefs(writer, op.args, op.func_name, ref_params);
                                    try writer.writeAll(", runtime.runtime_allocator) catch runtime.Value.initNull();\n");
                                } else {
                                    try self.writeRegAssignmentPrefix(writer, reg.id);
                                    try writer.print("try @\"{s}\"(runtime.Value.initNull(), ", .{escaped_func_name});
                                    try self.writeValueArgsArrayWithRefs(writer, op.args, op.func_name, ref_params);
                                    try writer.writeAll(", runtime.runtime_allocator);\n");
                                }
                            } else {
                                if (in_try_block) {
                                    try writer.print("    _ = @\"{s}\"(runtime.Value.initNull(), ", .{escaped_func_name});
                                    try self.writeValueArgsArrayWithRefs(writer, op.args, op.func_name, ref_params);
                                    try writer.writeAll(", runtime.runtime_allocator) catch {};\n");
                                } else {
                                    try writer.print("    _ = try @\"{s}\"(runtime.Value.initNull(), ", .{escaped_func_name});
                                    try self.writeValueArgsArrayWithRefs(writer, op.args, op.func_name, ref_params);
                                    try writer.writeAll(", runtime.runtime_allocator);\n");
                                }
                                try self.writeRegAssignmentPrefix(writer, reg.id);
                                try writer.writeAll("runtime.Value.initNull();\n");
                            }
                        }
                    }

                    if (self.functionMayRaise(op.func_name)) {
                        try writer.writeAll("    if (runtime.hasException()) {\n");
                        try writer.writeAll("        @branchHint(.unlikely);\n");
                        try self.generateCleanupCode(writer);
                        if (self.current_exception_handler) |handler_idx| {
                            try writer.print("        current_block = {d};\n", .{handler_idx});
                            try writer.print("        continue;\n", .{});
                        } else {
                            try writer.writeAll("        return error.RuntimeError;\n");
                        }
                        try writer.writeAll("    }\n");
                    }
                } else {
                    // 无返回值寄存器
                    if (is_runtime_declare) {
                        const declared_name = op.func_name["__declare_function__::".len..];
                        if (self.ir_module) |module| {
                            if (module.findFunction(declared_name)) |func| {
                                const escaped_declared_name = try self.escapeString(declared_name);
                                defer self.allocator.free(escaped_declared_name);
                                try writer.print("    try runtime.registerUserFunctionWithLocation(\"{s}\", @\"{s}\", \"{s}\", {d});\n", .{ escaped_declared_name, escaped_declared_name, func.location.file, func.location.line });
                                // 注册函数元数据
                                const pc = func.params.items.len;
                                var rc: usize = 0;
                                for (func.params.items) |p| {
                                    if (!p.has_default and !p.is_variadic) rc += 1;
                                }
                                try writer.print("    runtime.registerFunctionMeta(\"{s}\", {d}, {d});\n", .{ escaped_declared_name, pc, rc });
                            }
                        }
                    } else if (is_builtin) {
                        const runtime_name = self.mapToRuntimeFunction(op.func_name);
                        const needs_alloc = self.functionNeedsAllocator(op.func_name);

                        // 检查是否需要 allocator 参数
                        if (needs_alloc) {
                            if (std.mem.eql(u8, runtime_name, "php_sprintf") or std.mem.eql(u8, runtime_name, "php_printf")) {
                                if (op.args.len == 0) {
                                    try writer.writeAll("    _ = runtime.Value.initNull();\n");
                                } else {
                                    const fmt_arg = op.args[0];
                                    const fmt_arg_type = @as(std.meta.Tag(IR.Type), fmt_arg.type_);
                                    try writer.print("    _ = try runtime.{s}(", .{runtime_name});
                                    try self.writePhpValueExpr(writer, fmt_arg_type, fmt_arg.id);
                                    try writer.writeAll(", ");
                                    try self.writeValueArgsArray(writer, op.args[1..]);
                                    try writer.writeAll(", runtime.runtime_allocator);\n");
                                }
                            } else if (std.mem.eql(u8, runtime_name, "php_str_getcsv")) {
                                if (op.args.len < 4) {
                                    try writer.writeAll("    runtime.emitDeprecatedStrGetcsvEscape();\n");
                                }
                                try writer.print("    _ = try runtime.{s}(", .{runtime_name});
                                try self.writeStrGetcsvArgs(writer, op.args);
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_array_merge") or std.mem.eql(u8, runtime_name, "php_array_intersect") or std.mem.eql(u8, runtime_name, "php_array_diff") or std.mem.eql(u8, runtime_name, "php_array_diff_key") or std.mem.eql(u8, runtime_name, "php_array_multisort") or std.mem.eql(u8, runtime_name, "php_array_map") or std.mem.eql(u8, runtime_name, "php_json_decode") or std.mem.eql(u8, runtime_name, "php_memory_get_usage") or std.mem.eql(u8, runtime_name, "php_memory_get_peak_usage") or std.mem.eql(u8, runtime_name, "php_shell_exec") or std.mem.eql(u8, runtime_name, "php_exec") or std.mem.eql(u8, runtime_name, "php_system") or std.mem.eql(u8, runtime_name, "php_substr_replace") or std.mem.eql(u8, runtime_name, "php_function_exists") or std.mem.eql(u8, runtime_name, "php_gc_enable") or std.mem.eql(u8, runtime_name, "php_gc_collect_cycles") or std.mem.eql(u8, runtime_name, "php_ini_get") or std.mem.eql(u8, runtime_name, "php_getrusage") or std.mem.eql(u8, runtime_name, "php_unset")) {
                                try writer.print("    _ = try runtime.{s}(", .{runtime_name});
                                try self.writeValueArgsArray(writer, op.args);
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                            } else if (std.mem.eql(u8, runtime_name, "php_array_push") or std.mem.eql(u8, runtime_name, "php_array_unshift")) {
                                if (op.args.len > 0) {
                                    const first_arg = op.args[0];
                                    const first_type = @as(std.meta.Tag(IR.Type), first_arg.type_);
                                    try writer.print("    _ = try runtime.{s}(", .{runtime_name});
                                    try self.writePhpValueExpr(writer, first_type, first_arg.id);
                                    try writer.writeAll(", ");
                                    try self.writeValueArgsArray(writer, op.args[1..]);
                                    try writer.writeAll(", runtime.runtime_allocator);\n");
                                } else {
                                    try writer.writeAll("    _ = runtime.Value.initNull();\n");
                                }
                            } else if (op.args.len > 0) {
                                try writer.print("    _ = try runtime.{s}(", .{runtime_name});
                                try self.writeValueArgs(writer, op.args);
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                            } else {
                                try writer.print("    _ = try runtime.{s}(runtime.runtime_allocator);\n", .{runtime_name});
                            }
                        } else {
                            // 特殊处理php_ref_assign_ptr：第一个参数需要指针
                            if (std.mem.eql(u8, runtime_name, "php_ref_assign_ptr") and op.args.len >= 2) {
                                try writer.print("    _ = try runtime.{s}(", .{runtime_name});
                                // 第一个参数：检查是否已经是指针类型寄存器
                                const first_arg = op.args[0];
                                const is_ptr_reg = if (self.current_ref_ptr_regs) |rpr|
                                    rpr.contains(first_arg.id)
                                else
                                    false;
                                const is_alloca_reg = if (self.current_alloca_regs) |ar|
                                    ar.contains(first_arg.id)
                                else
                                    false;
                                
                                if (is_ptr_reg or is_alloca_reg) {
                                    // 已经是指针类型寄存器，直接使用
                                    try writer.print("reg_{d}", .{first_arg.id});
                                } else {
                                    // 普通值类型寄存器，需要取地址
                                    try writer.print("&reg_{d}", .{first_arg.id});
                                }
                                // 其余参数：正常处理
                                for (op.args[1..]) |arg| {
                                    try writer.writeAll(", ");
                                    try self.writeRegRef(writer, arg.id);
                                }
                                try writer.writeAll(");\n");
                            } else {
                                // 通用builtin函数调用（无返回值）
                                const builtin_info = builtinInfo(op.func_name);
                                const may_raise = if (builtin_info) |info| info.may_raise else true;
                                
                                if (may_raise) {
                                    try writer.print("    _ = try runtime.{s}(", .{runtime_name});
                                } else {
                                    try writer.print("    _ = runtime.{s}(", .{runtime_name});
                                }
                                try self.writeValueArgs(writer, op.args);
                                try writer.writeAll(");\n");
                            }
                        }
                    } else {
                        // 用户定义函数
                        try writer.print("    _ = try @\"{s}\"(runtime.Value.initNull(), ", .{op.func_name});
                        try self.writeValueArgsArray(writer, op.args);
                        try writer.writeAll(", runtime.runtime_allocator);\n");
                    }

                    if (self.functionMayRaise(op.func_name)) {
                        try writer.writeAll("    if (runtime.hasException()) {\n");
                        try writer.writeAll("        @branchHint(.unlikely);\n");
                        try self.generateCleanupCode(writer);
                        if (self.current_exception_handler) |handler_idx| {
                            try writer.print("        current_block = {d};\n", .{handler_idx});
                            try writer.print("        continue;\n", .{});
                        } else {
                            try writer.writeAll("        return error.RuntimeError;\n");
                        }
                        try writer.writeAll("    }\n");
                    }
                }
                } // end else (not error_suppress)
            },
            .call_indirect => |op| {
                // 检查func_ptr是否是alloca寄存器，需要解引用
                const func_ptr_is_alloca = if (self.current_alloca_regs) |alloca_regs|
                    alloca_regs.contains(op.func_ptr.id)
                else
                    false;

                const func_ptr_expr = if (func_ptr_is_alloca)
                    try std.fmt.allocPrint(self.allocator, "reg_{d}.*", .{op.func_ptr.id})
                else
                    try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.func_ptr.id});
                defer self.allocator.free(func_ptr_expr);

                const in_try_block = self.current_exception_handler != null;

                if (inst.result) |reg| {
                    if (in_try_block) {
                        try self.writeRegAssignmentFmt(writer, reg.id, "runtime.php_invoke_callable({s}, ", .{func_ptr_expr});
                    } else {
                        try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.php_invoke_callable({s}, ", .{func_ptr_expr});
                    }
                    try self.writeValueArgsArray(writer, op.args);
                    if (in_try_block) {
                        try writer.writeAll(", runtime.runtime_allocator) catch runtime.Value.initNull();\n");
                    } else {
                        try writer.writeAll(", runtime.runtime_allocator);\n");
                    }
                } else {
                    if (in_try_block) {
                        try writer.print("    _ = runtime.php_invoke_callable({s}, ", .{func_ptr_expr});
                    } else {
                        try writer.print("    _ = try runtime.php_invoke_callable({s}, ", .{func_ptr_expr});
                    }
                    try self.writeValueArgsArray(writer, op.args);
                    if (in_try_block) {
                        try writer.writeAll(", runtime.runtime_allocator) catch runtime.Value.initNull();\n");
                    } else {
                        try writer.writeAll(", runtime.runtime_allocator);\n");
                    }
                }

                try writer.writeAll("    if (runtime.hasException()) {\n");
                try writer.writeAll("        @branchHint(.unlikely);\n");
                try self.generateCleanupCode(writer);
                if (self.current_exception_handler) |handler_idx| {
                    try writer.print("        current_block = {d};\n", .{handler_idx});
                    try writer.writeAll("        continue;\n");
                } else {
                    try writer.writeAll("        return error.RuntimeError;\n");
                }
                try writer.writeAll("    }\n");
            },
            .array_new => |op| {
                _ = op;
                if (inst.result) |reg| {
                    // std.debug.print("ENTER array_new: reg_{d}\n", .{reg.id});
                    const is_alloca = if (self.current_alloca_regs) |alloca_regs| blk: {
                        const result = alloca_regs.contains(reg.id);
                        // std.debug.print("  alloca_regs.contains({d})={}, count={}\n", .{reg.id, result, alloca_regs.count()});
                        break :blk result;
                    } else blk: {
                        // std.debug.print("  current_alloca_regs=null\n", .{});
                        break :blk false;
                    };

                    if (is_alloca) {
                        try writer.print("    reg_{d}.*.release(runtime.runtime_allocator);\n", .{reg.id});
                        try writer.print("    reg_{d}.* = runtime.Value.initArray(try runtime.PHPArray.init(runtime.runtime_allocator));\n", .{reg.id});
                    } else {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                        try writer.print("    reg_{d} = runtime.Value.initArray(try runtime.PHPArray.init(runtime.runtime_allocator));\n", .{reg.id});
                    }
                }
            },
            .array_get => |op| {
                if (inst.result) |reg| {
                    if (self.shouldReleaseReg(reg.id)) {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                    }
                    // coalesce 上下文: 基值为 null 时直接返回 null，不触发警告
                    const is_coalesce_ag = if (self.current_coalesce_nowarn_regs) |cr| cr.contains(reg.id) else false;
                    
                    // 检查操作数是否是alloca
                    const array_is_alloca = if (self.current_alloca_regs) |allocas| allocas.contains(op.array.id) else false;
                    const key_is_alloca = if (self.current_alloca_regs) |allocas| allocas.contains(op.key.id) else false;
                    
                    if (is_coalesce_ag) {
                        if (array_is_alloca) {
                            try writer.print("    if (reg_{d}.*.isNull()) {{\n", .{op.array.id});
                        } else {
                            try writer.print("    if (reg_{d}.isNull()) {{\n", .{op.array.id});
                        }
                        try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initNull();\n", .{});
                        try writer.print("    }} else {{\n", .{});
                        try writer.writeAll("    ");
                        try self.writeRegAssignmentPrefix(writer, reg.id);
                        try writer.writeAll("try runtime.php_array_get(");
                        if (array_is_alloca) {
                            try writer.print("reg_{d}.*", .{op.array.id});
                        } else {
                            try writer.print("reg_{d}", .{op.array.id});
                        }
                        try writer.writeAll(", ");
                        if (key_is_alloca) {
                            try writer.print("reg_{d}.*", .{op.key.id});
                        } else {
                            try writer.print("reg_{d}", .{op.key.id});
                        }
                        try writer.writeAll(", runtime.runtime_allocator);\n");
                        try writer.print("    }}\n", .{});
                    } else {
                        try writer.writeAll("    ");
                        try self.writeRegAssignmentPrefix(writer, reg.id);
                        try writer.writeAll("try runtime.php_array_get(");
                        if (array_is_alloca) {
                            try writer.print("reg_{d}.*", .{op.array.id});
                        } else {
                            try writer.print("reg_{d}", .{op.array.id});
                        }
                        try writer.writeAll(", ");
                        if (key_is_alloca) {
                            try writer.print("reg_{d}.*", .{op.key.id});
                        } else {
                            try writer.print("reg_{d}", .{op.key.id});
                        }
                        try writer.writeAll(", runtime.runtime_allocator);\n");
                    }
                }
            },
            .array_set => |op| {
                try writer.writeAll("    if (runtime.Value_isObject(");
                try self.writeRegRef(writer, op.array.id);
                try writer.writeAll(")) {\n");
                try writer.writeAll("        _ = try runtime.php_object_call(");
                try self.writeRegRef(writer, op.array.id);
                try writer.writeAll(", \"offsetSet\", &[_]runtime.Value{");
                try self.writeRegRef(writer, op.key.id);
                try writer.writeAll(", ");
                try self.writeRegRef(writer, op.value.id);
                try writer.writeAll("});\n");
                try writer.writeAll("    } else {\n");
                try writer.writeAll("        try ");
                try self.writeRegRef(writer, op.array.id);
                try writer.writeAll(".asArray().setByValue(runtime.runtime_allocator, ");
                try self.writeRegRef(writer, op.key.id);
                try writer.writeAll(", ");
                try self.writeRegRef(writer, op.value.id);
                try writer.writeAll(");\n");
                try writer.writeAll("    }\n");
            },
            .array_set_nested => |op| {
                // 嵌套数组赋值，支持 auto-vivification
                // 注意：outer_array 本身可能是 null（来自 array_get）
                try writer.writeAll(
                    \\    {
                    \\        // 确保 outer_array 不是 null
                    \\        var outer_val = reg_
                );
                try writer.print("{d}", .{op.outer_array.id});
                try writer.writeAll(
                    \\;
                    \\        if (outer_val.isNull()) {
                    \\            // outer_array 是 null，无法设置（这是三维+数组的情况）
                    \\            // 跳过此操作，因为父级数组不存在
                    \\        } else {
                    \\            const outer_arr = outer_val.asArray();
                    \\            var inner = outer_arr.getByValue(reg_
                );
                try writer.print("{d}", .{op.outer_key.id});
                try writer.writeAll(
                    \\);
                    \\            if (inner == null or inner.?.isNull()) {
                    \\                const new_arr = try runtime.PHPArray.init(runtime.runtime_allocator);
                    \\                const new_val = runtime.Value.initArray(new_arr);
                    \\                try outer_arr.setByValue(runtime.runtime_allocator, reg_
                );
                try writer.print("{d}", .{op.outer_key.id});
                try writer.writeAll(
                    \\, new_val);
                    \\                inner = new_val;
                    \\            }
                    \\            try inner.?.asArray().setByValue(runtime.runtime_allocator, reg_
                );
                try writer.print("{d}", .{op.inner_key.id});
                try writer.writeAll(", reg_");
                try writer.print("{d}", .{op.value.id});
                try writer.writeAll(
                    \\);
                    \\        }
                    \\    }
                    \\
                );
            },
            .array_ensure => |op| {
                // 确保数组元素存在（auto-vivification），返回子数组
                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                    try writer.writeAll(
                        \\    {
                        \\        const arr = reg_
                    );
                    try writer.print("{d}", .{op.array.id});
                    try writer.writeAll(
                        \\.asArray();
                        \\        var elem = arr.getByValue(reg_
                    );
                    try writer.print("{d}", .{op.key.id});
                    try writer.writeAll(
                        \\);
                        \\        if (elem == null or elem.?.isNull()) {
                        \\            const new_arr = try runtime.PHPArray.init(runtime.runtime_allocator);
                        \\            const new_val = runtime.Value.initArray(new_arr);
                        \\            try arr.setByValue(runtime.runtime_allocator, reg_
                    );
                    try writer.print("{d}", .{op.key.id});
                    try writer.writeAll(
                        \\, new_val);
                        \\            elem = new_val;
                        \\        }
                        \\        reg_
                    );
                    try writer.print("{d}", .{reg.id});
                    try writer.writeAll(
                        \\ = elem.?;
                        \\    }
                        \\
                    );
                }
            },
            .array_push => |op| {
                // 检查value是否是alloca指针
                const val_is_alloca = if (self.current_alloca_regs) |regs| regs.contains(op.value.id) else false;
                if (val_is_alloca) {
                    try writer.print("    try reg_{d}.asArray().push(runtime.runtime_allocator, reg_{d}.*);\n", .{ op.array.id, op.value.id });
                } else {
                    try writer.print("    try reg_{d}.asArray().push(runtime.runtime_allocator, reg_{d});\n", .{ op.array.id, op.value.id });
                }
            },
            .array_count => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);

                    if (type_tag == .i64) {
                        // 直接返回i64类型（内部计算用）
                        try self.writeRegAssignmentFmt(writer, reg.id, "@intCast(reg_{d}.asArray().count());\n", .{op.operand.id});
                    } else {
                        // 返回Value类型（运行时边界）
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                        try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initInt(@intCast(reg_{d}.asArray().count()));\n", .{op.operand.id});
                    }
                }
            },
            .array_unset => |op| {
                // 简化：所有寄存器都是 Value 类型，使用 unsetByValue
                try writer.print(
                    "    _ = reg_{d}.asArray().unsetByValue(runtime.runtime_allocator, reg_{d});\n",
                    .{ op.array.id, op.key.id },
                );
            },
            .interpolate => |op| {
                // 字符串插值：将多个部分连接成一个字符串
                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});

                    if (op.parts.len == 0) {
                        // 空插值，返回空字符串
                        try writer.print("    reg_{d} = runtime.Value.initString(try runtime.PHPString.init(runtime.runtime_allocator, \"\"));\n", .{reg.id});
                    } else if (op.parts.len == 1) {
                        // 单个部分，直接转换为字符串
                        const part = op.parts[0];
                        const part_type_tag = @as(std.meta.Tag(IR.Type), part.type_);

                        if (part_type_tag == .php_value or part_type_tag == .php_string) {
                            // 已经是Value类型，调用toString
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initString(try reg_{d}.toString(runtime.runtime_allocator));\n", .{part.id});
                        } else if (part_type_tag == .i64) {
                            // i64类型，转换为字符串
                            try writer.print("    reg_{d} = runtime.Value.initString(try runtime.PHPString.init(runtime.runtime_allocator, try std.fmt.allocPrint(runtime.runtime_allocator, \"{{d}}\", .{{reg_{d}}})));\n", .{ reg.id, part.id });
                        } else if (part_type_tag == .f64) {
                            // f64类型，转换为字符串
                            try writer.print("    reg_{d} = runtime.Value.initString(try runtime.PHPString.init(runtime.runtime_allocator, try std.fmt.allocPrint(runtime.runtime_allocator, \"{{d}}\", .{{reg_{d}}})));\n", .{ reg.id, part.id });
                        } else if (part_type_tag == .bool) {
                            // bool类型，转换为字符串
                            try writer.print("    reg_{d} = runtime.Value.initString(try runtime.PHPString.init(runtime.runtime_allocator, if (reg_{d}) \"1\" else \"\"));\n", .{ reg.id, part.id });
                        } else {
                            // 其他类型，默认调用toString
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initString(try reg_{d}.toString(runtime.runtime_allocator));\n", .{part.id});
                        }
                    } else {
                        // 多个部分，需要连接
                        // 生成一个临时数组来存储所有部分
                        try writer.print("    {{\n", .{});
                        try writer.print("        var parts = try runtime.runtime_allocator.alloc(runtime.Value, {d});\n", .{op.parts.len});
                        try writer.print("        defer runtime.runtime_allocator.free(parts);\n", .{});

                        // 将每个部分转换为Value并存储到数组中
                        for (op.parts, 0..) |part, i| {
                            const part_type_tag = @as(std.meta.Tag(IR.Type), part.type_);

                            if (part_type_tag == .php_value or part_type_tag == .php_string) {
                                // 已经是Value类型，直接使用
                                try writer.print("        parts[{d}] = reg_{d};\n", .{ i, part.id });
                            } else if (part_type_tag == .i64) {
                                // i64类型，转换为Value
                                try writer.print("        parts[{d}] = runtime.Value.initInt(reg_{d});\n", .{ i, part.id });
                            } else if (part_type_tag == .f64) {
                                // f64类型，转换为Value
                                try writer.print("        parts[{d}] = runtime.Value.initFloat(reg_{d});\n", .{ i, part.id });
                            } else if (part_type_tag == .bool) {
                                // bool类型，转换为Value
                                try writer.print("        parts[{d}] = runtime.Value.initBool(reg_{d});\n", .{ i, part.id });
                            } else {
                                // 其他类型，默认直接使用
                                try writer.print("        parts[{d}] = reg_{d};\n", .{ i, part.id });
                            }
                        }

                        // 调用运行时函数进行插值
                        try writer.print("        reg_{d} = try runtime.php_interpolate(parts, runtime.runtime_allocator);\n", .{reg.id});
                        try writer.print("    }}\n", .{});
                    }
                }
            },
            // ============ PHP Object Operations ============
            .new_object => |op| {
                if (inst.result) |reg| {
                    const is_alloca = if (self.current_alloca_regs) |alloca_regs|
                        alloca_regs.contains(reg.id)
                    else
                        false;

                    // 创建对象
                    const escaped_class = try self.escapeString(op.class_name);
                    defer self.allocator.free(escaped_class);

                    const new_in_try = self.current_exception_handler != null;
                    if (is_alloca) {
                        try writer.print("    reg_{d}.*.release(runtime.runtime_allocator);\n", .{reg.id});
                        if (new_in_try) {
                            try writer.print("    reg_{d}.* = runtime.php_object_new_with_constructor(\"{s}\", ", .{ reg.id, escaped_class });
                        } else {
                            try writer.print("    reg_{d}.* = try runtime.php_object_new_with_constructor(\"{s}\", ", .{ reg.id, escaped_class });
                        }
                    } else {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                        if (new_in_try) {
                            try writer.print("    reg_{d} = runtime.php_object_new_with_constructor(\"{s}\", ", .{ reg.id, escaped_class });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_object_new_with_constructor(\"{s}\", ", .{ reg.id, escaped_class });
                        }
                    }

                    try self.writeValueArgsArray(writer, op.args);
                    if (new_in_try) {
                        try writer.writeAll(", runtime.runtime_allocator) catch runtime.Value.initNull();\n");
                    } else {
                        try writer.writeAll(", runtime.runtime_allocator);\n");
                    }

                    // 检查异常
                    try writer.writeAll("    if (runtime.hasException()) {\n");
                    try writer.writeAll("        @branchHint(.unlikely);\n");
                    try self.generateCleanupCodeExcept(writer, reg.id);
                    if (self.current_exception_handler) |handler_idx| {
                        try writer.print("        current_block = {d};\n", .{handler_idx});
                        try writer.print("        continue;\n", .{});
                    } else {
                        try writer.writeAll("        return error.RuntimeError;\n");
                    }
                    try writer.writeAll("    }\n");
                }
            },
            .property_get => |op| {
                if (inst.result) |reg| {
                    const escaped_prop = try self.escapeString(op.property_name);
                    defer self.allocator.free(escaped_prop);
                    const result_is_alloca = if (self.current_alloca_regs) |regs| regs.contains(reg.id) else false;
                    const object_is_alloca = if (self.current_alloca_regs) |regs| regs.contains(op.object.id) else false;
                    
                    if (result_is_alloca) {
                        try writer.print("    reg_{d}.*.release(runtime.runtime_allocator);\n", .{reg.id});
                        if (object_is_alloca) {
                            try writer.print("    reg_{d}.* = try runtime.php_object_get(reg_{d}.*, \"{s}\");\n", .{ reg.id, op.object.id, escaped_prop });
                        } else {
                            try writer.print("    reg_{d}.* = try runtime.php_object_get(reg_{d}, \"{s}\");\n", .{ reg.id, op.object.id, escaped_prop });
                        }
                    } else {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                        if (object_is_alloca) {
                            try writer.print("    reg_{d} = try runtime.php_object_get(reg_{d}.*, \"{s}\");\n", .{ reg.id, op.object.id, escaped_prop });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_object_get(reg_{d}, \"{s}\");\n", .{ reg.id, op.object.id, escaped_prop });
                        }
                    }
                }
            },
            .property_set => |op| {
                const value_type_tag = @as(std.meta.Tag(IR.Type), op.value.type_);

                const escaped_prop = try self.escapeString(op.property_name);
                defer self.allocator.free(escaped_prop);
                // Check for property set hook: __prop_set_<name>
                const hook_name = try std.fmt.allocPrint(self.allocator, "__prop_set_{s}", .{escaped_prop});
                defer self.allocator.free(hook_name);
                const has_hook = blk: {
                    // Skip hook interception if we're inside the hook method itself (prevent infinite recursion)
                    if (self.current_function_for_resolve) |cur_func| {
                        if (std.mem.endsWith(u8, cur_func.name, hook_name)) {
                            break :blk false;
                        }
                    }
                    // Check if any registered function matches the hook pattern
                    var fit = self.func_return_types.iterator();
                    while (fit.next()) |entry| {
                        if (std.mem.endsWith(u8, entry.key_ptr.*, hook_name)) {
                            break :blk true;
                        }
                    }
                    break :blk false;
                };
                if (has_hook) {
                    // Call hook method instead of direct set
                    try writer.print("    _ = try runtime.php_object_call(reg_{d}, \"{s}\", &[_]runtime.Value{{", .{ op.object.id, hook_name });
                    try self.writePhpValueExpr(writer, value_type_tag, op.value.id);
                    try writer.writeAll("});\n");
                } else {
                    try writer.print("    _ = try runtime.php_object_set(reg_{d}, \"{s}\", ", .{ op.object.id, escaped_prop });
                    try self.writePhpValueExpr(writer, value_type_tag, op.value.id);
                    try writer.writeAll(");\n");
                }
            },
            .method_call => |op| blk: {
                const obj_tag = @as(std.meta.Tag(IR.Type), op.object.type_);
                if (obj_tag == .php_object) {
                    const direct_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ op.object.type_.php_object, op.method_name });
                    defer self.allocator.free(direct_name);

                    if (self.func_return_types.contains(direct_name)) {
                        const escaped_direct = try self.escapeString(direct_name);
                        defer self.allocator.free(escaped_direct);
                        const has_return = self.func_return_types.get(direct_name) orelse false;

                        if (inst.result) |reg| {
                            const is_alloca_reg = if (self.current_alloca_regs) |alloca_regs|
                                alloca_regs.contains(reg.id)
                            else
                                false;
                            const deref = if (is_alloca_reg) ".*." else ".";
                            const star = if (is_alloca_reg) ".*" else "";
                            try writer.print("    reg_{d}{s}release(runtime.runtime_allocator);\n", .{reg.id, deref});
                            if (has_return) {
                                try writer.print("    reg_{d}{s} = try @\"{s}\"(", .{ reg.id, star, escaped_direct });
                                try self.writeRegRef(writer, op.object.id);
                                try writer.writeAll(", ");
                                try self.writeValueArgsArray(writer, op.args);
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                            } else {
                                try writer.print("    _ = try @\"{s}\"(", .{escaped_direct});
                                try self.writeRegRef(writer, op.object.id);
                                try writer.writeAll(", ");
                                try self.writeValueArgsArray(writer, op.args);
                                try writer.writeAll(", runtime.runtime_allocator);\n");
                                try writer.print("    reg_{d}{s} = runtime.Value.initNull();\n", .{reg.id, star});
                            }
                        } else {
                            try writer.print("    _ = try @\"{s}\"(", .{escaped_direct});
                            try self.writeRegRef(writer, op.object.id);
                            try writer.writeAll(", ");
                            try self.writeValueArgsArray(writer, op.args);
                            try writer.writeAll(", runtime.runtime_allocator);\n");
                        }

                        try writer.writeAll("    if (runtime.hasException()) {\n");
                        try writer.writeAll("        @branchHint(.unlikely);\n");
                        // 如果方法有返回值，排除result寄存器
                        const except_reg = if (inst.result) |r| r.id else null;
                        try self.generateCleanupCodeExcept(writer, except_reg);
                        if (self.current_exception_handler) |handler_idx| {
                            try writer.print("        current_block = {d};\n", .{handler_idx});
                            try writer.print("        continue;\n", .{});
                        } else {
                            try writer.writeAll("        return error.RuntimeError;\n");
                        }
                        try writer.writeAll("    }\n");
                        break :blk;
                    }
                }

                const escaped_method = try self.escapeString(op.method_name);
                defer self.allocator.free(escaped_method);

                const method_in_try = self.current_exception_handler != null;
                if (inst.result) |reg| {
                    const is_alloca_reg = if (self.current_alloca_regs) |alloca_regs|
                        alloca_regs.contains(reg.id)
                    else
                        false;
                    const deref = if (is_alloca_reg) ".*." else ".";
                    const star = if (is_alloca_reg) ".*" else "";
                    try writer.print("    reg_{d}{s}release(runtime.runtime_allocator);\n", .{reg.id, deref});
                    if (method_in_try) {
                        try writer.print("    reg_{d}{s} = runtime.php_object_call(", .{reg.id, star});
                    } else {
                        try writer.print("    reg_{d}{s} = try runtime.php_object_call(", .{reg.id, star});
                    }
                    try self.writeRegRef(writer, op.object.id);
                    try writer.print(", \"{s}\", ", .{escaped_method});
                    try self.writeValueArgsArray(writer, op.args);
                    if (method_in_try) {
                        try writer.writeAll(") catch runtime.Value.initNull();\n");
                    } else {
                        try writer.writeAll(");\n");
                    }
                } else {
                    if (method_in_try) {
                        try writer.writeAll("    _ = runtime.php_object_call(");
                    } else {
                        try writer.writeAll("    _ = try runtime.php_object_call(");
                    }
                    try self.writeRegRef(writer, op.object.id);
                    try writer.print(", \"{s}\", ", .{escaped_method});
                    try self.writeValueArgsArray(writer, op.args);
                    if (method_in_try) {
                        try writer.writeAll(") catch {};\n");
                    } else {
                        try writer.writeAll(");\n");
                    }
                }

                try writer.writeAll("    if (runtime.hasException()) {\n");
                try writer.writeAll("        @branchHint(.unlikely);\n");
                try self.generateCleanupCode(writer);
                if (self.current_exception_handler) |handler_idx| {
                    try writer.print("        current_block = {d};\n", .{handler_idx});
                    try writer.print("        continue;\n", .{});
                } else {
                    try writer.writeAll("        return error.RuntimeError;\n");
                }
                try writer.writeAll("    }\n");
            },
            .static_method_call => |op| blk: {
                const escaped_class = try self.escapeString(op.class_name);
                defer self.allocator.free(escaped_class);
                const escaped_method = try self.escapeString(op.method_name);
                defer self.allocator.free(escaped_method);

                const direct_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ op.class_name, op.method_name });
                defer self.allocator.free(direct_name);

                if (self.func_return_types.contains(direct_name)) {
                    const escaped_direct = try self.escapeString(direct_name);
                    defer self.allocator.free(escaped_direct);
                    const has_return = self.func_return_types.get(direct_name) orelse false;

                    // 设置ClassContext
                    try writer.print("    {{\n", .{});
                    try writer.print("        const meta = runtime.findClass(\"{s}\");\n", .{escaped_class});
                    try writer.writeAll("        const guard = if (meta) |m| runtime.ClassContext.init(m, m) else null;\n");
                    try writer.writeAll("        defer if (guard) |*g| g.deinit();\n");

                    if (inst.result) |reg| {
                        try writer.print("        reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                        if (has_return) {
                            try writer.print("        reg_{d} = try @\"{s}\"(runtime.Value.initNull(), ", .{ reg.id, escaped_direct });
                            try self.writeValueArgsArray(writer, op.args);
                            try writer.writeAll(", runtime.runtime_allocator);\n");
                        } else {
                            try writer.print("        _ = try @\"{s}\"(runtime.Value.initNull(), ", .{escaped_direct});
                            try self.writeValueArgsArray(writer, op.args);
                            try writer.writeAll(", runtime.runtime_allocator);\n");
                            try writer.print("        reg_{d} = runtime.Value.initNull();\n", .{reg.id});
                        }
                    } else {
                        try writer.print("        _ = try @\"{s}\"(runtime.Value.initNull(), ", .{escaped_direct});
                        try self.writeValueArgsArray(writer, op.args);
                        try writer.writeAll(", runtime.runtime_allocator);\n");
                    }

                    try writer.writeAll("        if (runtime.hasException()) {\n");
                    try writer.writeAll("            @branchHint(.unlikely);\n");
                    try self.generateCleanupCode(writer);
                    if (self.current_exception_handler) |handler_idx| {
                        try writer.print("            current_block = {d};\n", .{handler_idx});
                        try writer.print("            continue;\n", .{});
                    } else {
                        try writer.writeAll("            return error.RuntimeError;\n");
                    }
                    try writer.writeAll("        }\n");
                    try writer.writeAll("    }\n");
                    break :blk;
                }

                // 检测是否是 parent:: 调用，需要传递 ctx
                const is_parent_call = std.mem.eql(u8, op.class_name, "parent");

                const in_try = self.current_exception_handler != null;
                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                    if (is_parent_call) {
                        if (in_try) {
                            try writer.print("    reg_{d} = runtime.php_call_static_with_ctx(ctx, \"{s}\", \"{s}\", ", .{ reg.id, escaped_class, escaped_method });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_call_static_with_ctx(ctx, \"{s}\", \"{s}\", ", .{ reg.id, escaped_class, escaped_method });
                        }
                    } else {
                        if (in_try) {
                            try writer.print("    reg_{d} = runtime.php_call_static(\"{s}\", \"{s}\", ", .{ reg.id, escaped_class, escaped_method });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_call_static(\"{s}\", \"{s}\", ", .{ reg.id, escaped_class, escaped_method });
                        }
                    }
                    try self.writeValueArgsArray(writer, op.args);
                    if (in_try) {
                        try writer.writeAll(", runtime.runtime_allocator) catch runtime.Value.initNull();\n");
                    } else {
                        try writer.writeAll(", runtime.runtime_allocator);\n");
                    }
                } else {
                    if (is_parent_call) {
                        if (in_try) {
                            try writer.print("    _ = runtime.php_call_static_with_ctx(ctx, \"{s}\", \"{s}\", ", .{ escaped_class, escaped_method });
                        } else {
                            try writer.print("    _ = try runtime.php_call_static_with_ctx(ctx, \"{s}\", \"{s}\", ", .{ escaped_class, escaped_method });
                        }
                    } else {
                        if (in_try) {
                            try writer.print("    _ = runtime.php_call_static(\"{s}\", \"{s}\", ", .{ escaped_class, escaped_method });
                        } else {
                            try writer.print("    _ = try runtime.php_call_static(\"{s}\", \"{s}\", ", .{ escaped_class, escaped_method });
                        }
                    }
                    try self.writeValueArgsArray(writer, op.args);
                    if (in_try) {
                        try writer.writeAll(", runtime.runtime_allocator) catch {};\n");
                    } else {
                        try writer.writeAll(", runtime.runtime_allocator);\n");
                    }
                }

                try writer.writeAll("    if (runtime.hasException()) {\n");
                try writer.writeAll("        @branchHint(.unlikely);\n");
                try self.generateCleanupCode(writer);
                if (self.current_exception_handler) |handler_idx| {
                    try writer.print("        current_block = {d};\n", .{handler_idx});
                    try writer.print("        continue;\n", .{});
                } else {
                    try writer.writeAll("        return error.RuntimeError;\n");
                }
                try writer.writeAll("    }\n");
            },
            .static_property_get => |op| {
                if (inst.result) |reg| {
                    const escaped_class = try self.escapeString(op.class_name);
                    defer self.allocator.free(escaped_class);
                    const escaped_prop = try self.escapeString(op.property_name);
                    defer self.allocator.free(escaped_prop);

                    const is_special = std.mem.eql(u8, op.class_name, "static") or
                        std.mem.eql(u8, op.class_name, "self") or
                        std.mem.eql(u8, op.class_name, "parent");

                    if (!is_special) {
                        // 具体类名：设置 ClassContext
                        try writer.print("    {{\n", .{});
                        try writer.print("        const meta = runtime.findClass(\"{s}\");\n", .{escaped_class});
                        try writer.writeAll("        const guard = if (meta) |m| runtime.ClassContext.init(m, m) else null;\n");
                        try writer.writeAll("        defer if (guard) |*g| g.deinit();\n");
                        try writer.print("        reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                        try writer.print("        reg_{d} = try runtime.php_get_static_property(\"{s}\", \"{s}\");\n", .{ reg.id, escaped_class, escaped_prop });
                        try writer.writeAll("    }\n");
                    } else {
                        // static/self/parent：不覆盖 ClassContext，运行时 resolveSpecialClassName 使用已有上下文
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                        try writer.print("    reg_{d} = try runtime.php_get_static_property(\"{s}\", \"{s}\");\n", .{ reg.id, escaped_class, escaped_prop });
                    }
                }
            },
            .static_property_set => |op| {
                const value_type_tag = @as(std.meta.Tag(IR.Type), op.value.type_);

                const escaped_class = try self.escapeString(op.class_name);
                defer self.allocator.free(escaped_class);
                const escaped_prop = try self.escapeString(op.property_name);
                defer self.allocator.free(escaped_prop);

                const is_special = std.mem.eql(u8, op.class_name, "static") or
                    std.mem.eql(u8, op.class_name, "self") or
                    std.mem.eql(u8, op.class_name, "parent");

                if (!is_special) {
                    // 具体类名：设置 ClassContext
                    try writer.print("    {{\n", .{});
                    try writer.print("        const meta = runtime.findClass(\"{s}\");\n", .{escaped_class});
                    try writer.writeAll("        const guard = if (meta) |m| runtime.ClassContext.init(m, m) else null;\n");
                    try writer.writeAll("        defer if (guard) |*g| g.deinit();\n");
                    try writer.print("        _ = try runtime.php_set_static_property(\"{s}\", \"{s}\", ", .{ escaped_class, escaped_prop });
                    try self.writePhpValueExpr(writer, value_type_tag, op.value.id);
                    try writer.writeAll(");\n");
                    try writer.writeAll("    }\n");
                } else {
                    // static/self/parent：不覆盖 ClassContext
                    try writer.print("    _ = try runtime.php_set_static_property(\"{s}\", \"{s}\", ", .{ escaped_class, escaped_prop });
                    try self.writePhpValueExpr(writer, value_type_tag, op.value.id);
                    try writer.writeAll(");\n");
                }
            },
            // ============ 异常处理指令 ============
            .try_begin => {
                try writer.writeAll("    // Try block begin\n");
            },
            .try_end => {
                try writer.writeAll("    // Try block end\n");
            },
            .catch_ => |op| {
                if (op.exception_type) |exc_type| {
                    try writer.print("    // Catch {s}\n", .{exc_type});
                } else {
                    try writer.writeAll("    // Catch all\n");
                }
                if (inst.result) |reg| {
                    const is_alloca = if (self.current_alloca_regs) |regs| regs.contains(reg.id) else false;
                    if (is_alloca) {
                        try writer.print("    reg_{d}.*.release(runtime.runtime_allocator);\n", .{reg.id});
                    } else {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                    }
                    try self.writeRegAssignmentFmt(writer, reg.id, "runtime.getException();\n", .{});
                } else {
                    try writer.writeAll("    if (runtime.hasException()) {\n");
                    try writer.writeAll("        var ignored_ex = runtime.getException();\n");
                    try writer.writeAll("        ignored_ex.release(runtime.runtime_allocator);\n");
                    try writer.writeAll("    }\n");
                }
            },
            .get_exception => {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                    try writer.print("    reg_{d} = runtime.getException();\n", .{reg.id});
                }
            },
            .peek_exception => {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                    try writer.print("    reg_{d} = runtime.peekException();\n", .{reg.id});
                }
            },
            .clear_exception => {
                try writer.writeAll("    runtime.clearException();\n");
            },
            .global_get => |op| {
                // 从全局表读取变量
                if (inst.result) |reg| {
                    const escaped_name = try self.escapeString(op.name);
                    defer self.allocator.free(escaped_name);
                    const is_alloca = if (self.current_alloca_regs) |regs| regs.contains(reg.id) else false;
                    try writer.print("    reg_{d}", .{reg.id});
                    if (is_alloca) {
                        try writer.writeAll(".*");
                    }
                    try writer.writeAll(".release(runtime.runtime_allocator);\n");
                    const is_byref = if (self.current_byref_regs) |br| br.contains(reg.id) else false;
                    const is_switch_val = if (self.current_switch_value_regs) |sv| sv.contains(reg.id) else false;
                    const is_concat_operand = if (self.current_concat_operand_regs) |cr| cr.contains(reg.id) else false;
                    const is_coalesce = if (self.current_coalesce_nowarn_regs) |cr| cr.contains(reg.id) else false;
                    if (is_switch_val) {
                        // switch 值：不在此处发 Warning，改为在每个 case 比较处发
                        try writer.print("    const __sw_undef_{d} = !globalVarIsDefined(\"{s}\");\n", .{ reg.id, escaped_name });
                        try self.writeRegAssignmentPrefix(writer, reg.id);
                        try writer.print("getGlobalVarNoWarn(\"{s}\");\n", .{escaped_name});
                    } else if (is_byref or is_concat_operand or is_coalesce) {
                        try self.writeRegAssignmentPrefix(writer, reg.id);
                        try writer.print("getGlobalVarNoWarn(\"{s}\");\n", .{escaped_name});
                    } else {
                        try self.writeRegAssignmentPrefix(writer, reg.id);
                        try writer.print("getGlobalVar(\"{s}\");\n", .{escaped_name});
                    }
                }
            },
            .global_set => |op| {
                // 写入全局表
                if (op.value) |val| {
                    const escaped_name = try self.escapeString(op.name);
                    defer self.allocator.free(escaped_name);
                    const is_alloca = if (self.current_alloca_regs) |regs| regs.contains(val.id) else false;
                    if (is_alloca) {
                        try writer.print("    try setGlobalVar(\"{s}\", reg_{d}.*);\n", .{ escaped_name, val.id });
                    } else {
                        try writer.print("    try setGlobalVar(\"{s}\", reg_{d});\n", .{ escaped_name, val.id });
                        // setGlobalVar 会 retain 值，全局变量表持有一个引用
                        // 寄存器继续持有原引用，由后续的正常清理逻辑处理
                        // 不在这里释放寄存器，避免影响后续使用该寄存器的指令
                    }
                }
            },
            .global_get_dynamic => |op| {
                // 动态全局变量读取：$$var
                if (inst.result) |reg| {
                    const is_alloca = if (self.current_alloca_regs) |regs| regs.contains(reg.id) else false;
                    try writer.print("    reg_{d}", .{reg.id});
                    if (is_alloca) {
                        try writer.writeAll(".*");
                    }
                    try writer.writeAll(".release(runtime.runtime_allocator);\n");
                    try self.writeRegAssignmentPrefix(writer, reg.id);
                    try writer.print("try getGlobalVarDynamic(reg_{d});\n", .{op.name_reg.id});
                }
            },
            .global_set_dynamic => |op| {
                // 动态全局变量写入：$$var = value
                const name_is_alloca = if (self.current_alloca_regs) |regs| regs.contains(op.name_reg.id) else false;
                const val_is_alloca = if (self.current_alloca_regs) |regs| regs.contains(op.value.id) else false;

                try writer.writeAll("    try setGlobalVarDynamic(");
                if (name_is_alloca) {
                    try writer.print("reg_{d}.*, ", .{op.name_reg.id});
                } else {
                    try writer.print("reg_{d}, ", .{op.name_reg.id});
                }
                if (val_is_alloca) {
                    try writer.print("reg_{d}.*);\n", .{op.value.id});
                } else {
                    try writer.print("reg_{d});\n", .{op.value.id});
                }
            },
            .global_ref_bind => |op| {
                // 全局变量引用绑定: $target = &$source
                const escaped_target = try self.escapeString(op.target);
                defer self.allocator.free(escaped_target);
                const escaped_source = try self.escapeString(op.source);
                defer self.allocator.free(escaped_source);
                try writer.print("    try bindGlobalRef(\"{s}\", \"{s}\");\n", .{ escaped_target, escaped_source });
            },
            .global_unset => |op| {
                // 从全局变量表中删除
                const is_alloca = if (self.current_alloca_regs) |regs| regs.contains(op.name.id) else false;
                if (is_alloca) {
                    try writer.print("    try unsetGlobalVar(reg_{d}.*);\n", .{op.name.id});
                } else {
                    try writer.print("    try unsetGlobalVar(reg_{d});\n", .{op.name.id});
                }
            },
            .cast => |op| {
                // cast: 类型转换
                if (inst.result) |reg| {
                    // 调试
                    if (reg.id == 3) {
                        // std.debug.print("CAST reg_3: from={s}, to={s}, value.id={d}, value.type={s}\n", .{
                        //     @tagName(@as(std.meta.Tag(IR.Type), op.from_type)),
                        //     @tagName(@as(std.meta.Tag(IR.Type), op.to_type)),
                        //     op.value.id,
                        //     @tagName(@as(std.meta.Tag(IR.Type), op.value.type_)),
                        // });
                    }

                    // Get the actual type of the source register
                    const src_fallback = if (self.current_reg_types) |types|
                        (types.get(op.value.id) orelse op.value.type_)
                    else if (self.current_register_types) |types|
                        (types.get(op.value.id) orelse op.value.type_)
                    else
                        op.value.type_;
                    const src_real_type = self.getInferredRegType(op.value.id, src_fallback);
                    const src_tag = @as(std.meta.Tag(IR.Type), src_real_type);
                    const to_tag = @as(std.meta.Tag(IR.Type), op.to_type);

                    if (reg.id == 3) {
                        // std.debug.print("  src_real_type={s}, src_tag={s}, to_tag={s}\n", .{
                        //     @tagName(@as(std.meta.Tag(IR.Type), src_real_type)),
                        //     @tagName(src_tag),
                        //     @tagName(to_tag),
                        // });
                    }

                    const dest_is_alloca = if (self.current_alloca_regs) |alloca_regs|
                        alloca_regs.contains(reg.id)
                    else
                        false;

                    // 根据目标类型生成不同的转换代码
                    if (to_tag == .php_value) {
                        // 转换到php_value

                        // 优化：如果源也是 php_value（实际类型），直接赋值
                        if (src_tag == .php_value) {
                            // php_value -> php_value：直接赋值（无意义的 cast）
                            var src_buf: [32]u8 = undefined;
                            const src_ref = try self.getOperandRef(&src_buf, op.value.id);
                            if (!dest_is_alloca and self.shouldReleaseReg(reg.id) and self.regMayHeap(reg.id)) {
                                try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                            }
                            if (dest_is_alloca) {
                                try writer.print("    reg_{d}.* = {s};\n", .{ reg.id, src_ref });
                                try writer.print("    _ = reg_{d}.*.retain();\n", .{reg.id});
                            } else {
                                try writer.print("    reg_{d} = {s};\n", .{ reg.id, src_ref });
                                try writer.print("    _ = reg_{d}.retain();\n", .{reg.id});
                            }
                        } else if (src_tag == .i64 or src_tag == .f64 or src_tag == .bool) {
                            // 基本类型 -> php_value
                            // 所有寄存器实际都是 Value，需要生成包装代码
                            var src_buf: [128]u8 = undefined;
                            const src_wrapped = try self.getValueWrapper(&src_buf, op.value.id, src_tag);

                            if (!dest_is_alloca and self.shouldReleaseReg(reg.id) and self.regMayHeap(reg.id)) {
                                try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                            }
                            if (dest_is_alloca) {
                                try writer.print("    reg_{d}.* = {s};\n", .{ reg.id, src_wrapped });
                            } else {
                                try writer.print("    reg_{d} = {s};\n", .{ reg.id, src_wrapped });
                            }
                        } else {
                            if (!dest_is_alloca and self.shouldReleaseReg(reg.id) and self.regMayHeap(reg.id)) {
                                try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                            }

                            // 动态类型 -> php_value：必须 retain
                            var src_buf: [32]u8 = undefined;
                            const src = try self.getOperandRef(&src_buf, op.value.id);
                            if (dest_is_alloca) {
                                try writer.print("    reg_{d}.* = {s};\n", .{ reg.id, src });
                                try writer.print("    _ = reg_{d}.*.retain();\n", .{reg.id});
                            } else {
                                try writer.print("    reg_{d} = {s};\n", .{ reg.id, src });
                                try writer.print("    _ = reg_{d}.retain();\n", .{reg.id});
                            }
                        }
                    } else if (to_tag == .i64) {
                        var src_buf: [32]u8 = undefined;
                        const src = try self.getOperandRef(&src_buf, op.value.id);
                        if (src_tag == .i64) {
                            // 所有寄存器都是 Value 类型，需要包装
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initInt({s}.asInt());\n", .{src});
                        } else {
                            // 所有寄存器都是 Value 类型，需要包装
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initInt({s}.asInt());\n", .{src});
                        }
                    } else if (to_tag == .f64) {
                        var src_buf: [32]u8 = undefined;
                        const src = try self.getOperandRef(&src_buf, op.value.id);
                        if (src_tag == .f64) {
                            // 所有寄存器都是 Value 类型，需要包装
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initFloat({s}.asFloat());\n", .{src});
                        } else {
                            // 所有寄存器都是 Value 类型，需要包装
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initFloat({s}.asFloat());\n", .{src});
                        }
                    } else if (to_tag == .bool) {
                        var src_buf: [32]u8 = undefined;
                        const src = try self.getOperandRef(&src_buf, op.value.id);
                        if (src_tag == .bool) {
                            // 所有寄存器都是 Value 类型，需要包装
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool({s}.toBool());\n", .{src});
                        } else {
                            // 所有寄存器都是 Value 类型，需要包装
                            try self.writeRegAssignmentFmt(writer, reg.id, "runtime.Value.initBool({s}.toBool());\n", .{src});
                        }
                    } else {
                        var src_buf: [32]u8 = undefined;
                        const src = try self.getOperandRef(&src_buf, op.value.id);
                        try self.writeRegAssignmentFmt(writer, reg.id, "{s};\n", .{src});
                    }
                }
            },
            .move => |op| {
                // move: 简单的寄存器复制（用于替换冗余 cast）
                if (inst.result) |reg| {
                    const dst_fallback = if (self.current_reg_types) |types|
                        (types.get(reg.id) orelse reg.type_)
                    else if (self.current_register_types) |types|
                        (types.get(reg.id) orelse reg.type_)
                    else
                        reg.type_;
                    const dst_type = self.getInferredRegType(reg.id, dst_fallback);
                    const dst_tag = @as(std.meta.Tag(IR.Type), dst_type);

                    const src_fallback = if (self.current_reg_types) |types|
                        (types.get(op.operand.id) orelse op.operand.type_)
                    else if (self.current_register_types) |types|
                        (types.get(op.operand.id) orelse op.operand.type_)
                    else
                        op.operand.type_;
                    const src_type = self.getInferredRegType(op.operand.id, src_fallback);
                    var src_tag = @as(std.meta.Tag(IR.Type), src_type);

                    // 兜底：如果寄存器在当前函数被标记为 runtime.Value，则强制按 php_value 处理
                    if (self.current_reg_is_value) |is_val| {
                        if (op.operand.id < is_val.len and is_val[op.operand.id]) {
                            src_tag = .php_value;
                        }
                    }

                    if (reg.id == 120 or op.operand.id == 117) {
                        // std.debug.print("move: dst.id={d}, dst_tag={s}, src.id={d}, src_tag={s}\n", .{
                        //     reg.id,
                        //     @tagName(dst_tag),
                        //     op.operand.id,
                        //     @tagName(src_tag),
                        // });
                    }

                    var src_buf: [32]u8 = undefined;
                    const src_ref = try self.getOperandRef(&src_buf, op.operand.id);

                    if (dst_tag == .i64 and src_tag == .php_value) {
                        try self.writeRegAssignmentFmt(writer, reg.id, "{s}.asInt();\n", .{src_ref});
                    } else if (dst_tag == .f64 and src_tag == .php_value) {
                        try self.writeRegAssignmentFmt(writer, reg.id, "{s}.asFloat();\n", .{src_ref});
                    } else if (dst_tag == .bool and src_tag == .php_value) {
                        try self.writeRegAssignmentFmt(writer, reg.id, "{s}.toBool();\n", .{src_ref});
                    } else if (dst_tag == .php_value and src_tag == .i64) {
                        // 所有寄存器都是 Value，需要类型转换
                        var src_buf2: [128]u8 = undefined;
                        const src_wrapped = try self.getValueWrapper(&src_buf2, op.operand.id, src_tag);
                        try self.writeRegAssignmentFmt(writer, reg.id, "{s};\n", .{src_wrapped});
                    } else if (dst_tag == .php_value and src_tag == .f64) {
                        var src_buf2: [128]u8 = undefined;
                        const src_wrapped = try self.getValueWrapper(&src_buf2, op.operand.id, src_tag);
                        try self.writeRegAssignmentFmt(writer, reg.id, "{s};\n", .{src_wrapped});
                    } else if (dst_tag == .php_value and src_tag == .bool) {
                        var src_buf2: [128]u8 = undefined;
                        const src_wrapped = try self.getValueWrapper(&src_buf2, op.operand.id, src_tag);
                        try self.writeRegAssignmentFmt(writer, reg.id, "{s};\n", .{src_wrapped});
                    } else {
                        try self.writeRegAssignmentFmt(writer, reg.id, "{s};\n", .{src_ref});
                    }
                }
            },
            .mutex_lock => {
                try writer.writeAll("    runtime.mutex_lock();\n");
            },
            .mutex_unlock => {
                try writer.writeAll("    runtime.mutex_unlock();\n");
            },
            .mutex_new => {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                    try writer.print("    reg_{d} = try runtime.mutex_new(runtime.runtime_allocator);\n", .{reg.id});
                }
            },
            .go_spawn => |op| {
                // 生成goroutine/协程启动代码
                try writer.writeAll("    _ = try runtime.go_spawn(\"");
                for (op.func_name) |c| {
                    switch (c) {
                        '\n' => try writer.writeAll("\\n"),
                        '\r' => try writer.writeAll("\\r"),
                        '\t' => try writer.writeAll("\\t"),
                        '\\' => try writer.writeAll("\\\\"),
                        '"' => try writer.writeAll("\\\""),
                        else => try writer.writeByte(c),
                    }
                }
                try writer.writeAll("\", ");
                try self.writeValueArgsArray(writer, op.args);
                try writer.writeAll(", runtime.runtime_allocator);\n");
            },
            .channel_new => |op| {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                    try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.channel_new({d}, runtime.runtime_allocator);\n", .{op.buffer_size});
                }
            },
            .channel_send => |op| {
                try writer.print("    try runtime.channel_send(reg_{d}, reg_{d});\n", .{ op.channel.id, op.value.id });
            },
            .channel_recv => |op| {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                    try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.channel_recv(reg_{d});\n", .{op.channel.id});
                }
            },
            .channel_close => |op| {
                try writer.print("    runtime.channel_close(reg_{d});\n", .{op.operand.id});
            },
            .select_ => {
                try self.handleUnsupportedOp(inst);
                try writer.writeAll("    // TODO: select statement\n");
            },
            .await_ => |op| {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                    try self.writeRegAssignmentFmt(writer, reg.id, "try runtime.await_result(reg_{d});\n", .{op.operand.id});
                }
            },
            .phi => {
                // PHI节点在terminator中处理，这里跳过
                // 生成一个注释说明
                if (inst.result) |reg| {
                    try writer.print("    // PHI: reg_{d} (handled in terminator)\n", .{reg.id});
                }
            },
            .retain => |op| {
                // retain: 增加引用计数
                const suffix = self.getRegSuffix(op.operand.id);
                try writer.print("    _ = reg_{d}{s}.retain();\n", .{ op.operand.id, suffix });
            },
            .release => |op| {
                // release: 减少引用计数，可能触发析构
                const suffix = self.getRegSuffix(op.operand.id);
                try writer.print("    if (reg_{d}{s}.isArray() or runtime.Value_isObject(reg_{d}{s}) or reg_{d}{s}.isFunction()) {{\n", .{ op.operand.id, suffix, op.operand.id, suffix, op.operand.id, suffix });
                try writer.print("        reg_{d}{s}.release(runtime.runtime_allocator);\n", .{ op.operand.id, suffix });
                try writer.print("        reg_{d}{s} = runtime.Value.initNull();\n", .{ op.operand.id, suffix });
                try writer.writeAll("    }\n");
            },
            .unset_var => |op| {
                // unset_var: 专门处理unset操作
                // op.operand是alloca指针寄存器
                const is_alloca = if (self.current_alloca_regs) |regs| regs.contains(op.operand.id) else false;

                if (is_alloca) {
                    // 记录已unset的寄存器
                    if (self.current_unset_regs) |regs| {
                        try regs.put(op.operand.id, {});
                    }

                    // alloca寄存器：通知弱引用 + release
                    try writer.print("    if (!reg_{d}.*.isNull()) {{\n", .{op.operand.id});
                    try writer.print("        runtime.php_weak_mark_dead(reg_{d}.*);\n", .{op.operand.id});
                    try writer.print("        reg_{d}.*.release(runtime.runtime_allocator);\n", .{op.operand.id});
                    try writer.print("        reg_{d}.*.release(runtime.runtime_allocator);\n", .{op.operand.id});
                    try writer.print("        reg_{d}.* = runtime.Value.initNull();\n", .{op.operand.id});
                    try writer.print("    }}\n", .{});
                } else {
                    // 普通寄存器：通知弱引用 + release
                    try writer.print("    if (!reg_{d}.isNull()) {{\n", .{op.operand.id});
                    try writer.print("        runtime.php_weak_mark_dead(reg_{d});\n", .{op.operand.id});
                    try writer.print("        reg_{d}.release(runtime.runtime_allocator);\n", .{op.operand.id});
                    try writer.print("        reg_{d}.release(runtime.runtime_allocator);\n", .{op.operand.id});
                    try writer.print("        reg_{d} = runtime.Value.initNull();\n", .{op.operand.id});
                    try writer.print("    }}\n", .{});
                }
            },
            else => {
                try self.handleUnsupportedOp(inst);
            },
        }
    }

    /// 生成控制流结构
    ///
    /// 本方法分析IR的基本块和终止指令，生成原生Zig控制流结构。
    /// 策略：
    /// 1. 单块函数（只有一个基本块且终止指令是ret）：直接生成线性代码
    /// 2. 简单if-else（2-3个块，第一个块是cond_br，then/else块都是ret）：生成原生if-else
    /// 3. 简单循环（while/for模式，有回边到条件块）：生成原生while循环
    /// 4. 复杂控制流：使用while(true) + switch实现状态机，每个基本块是一个状态
    fn generateControlFlow(self: *Self, writer: anytype, func: *const IR.Function, cleanup_regs: []const usize, reg_lifetime: *const std.AutoHashMap(usize, RegLifetime)) !void {
        _ = reg_lifetime; // 暂时未使用，后续会用于优化
        if (func.blocks.items.len == 0) return;

        // 优化1：单块函数直接生成线性代码（无状态机开销）
        // 条件：只有一个基本块 且 终止指令是ret（无跳转）
        if (func.blocks.items.len == 1) {
            const block = func.blocks.items[0];
            const is_simple_return = if (block.terminator) |term|
                @as(std.meta.Tag(IR.Terminator), term) == .ret
            else
                false;

            if (is_simple_return) {
                // 单块函数优化：直接生成线性代码
                try writer.writeAll("    // Single-block function: linear code generation (optimized)\n");

                // 禁用异常跳转（单块函数没有状态机）
                const prev_handler = self.current_exception_handler;
                self.current_exception_handler = null;

                // 生成所有指令
                for (block.instructions.items) |inst| {
                    try self.generateInstruction(writer, inst);
                }

                // 恢复异常处理器
                self.current_exception_handler = prev_handler;

                // 生成return语句
                if (block.terminator) |term| {
                    switch (term) {
                        .ret => |ret_val| {
                            // 在return之前执行cleanup
                            if (cleanup_regs.len > 0) {
                                try writer.writeAll("    // Cleanup: release all allocated values\n");
                                for (cleanup_regs) |reg_id| {
                                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                                    if (!self.shouldReleaseReg(reg_id)) continue;
                                }
                            }
                            if (ret_val) |reg| {
                                // 检查是否是 alloca 寄存器
                                const is_alloca = if (self.current_alloca_regs) |alloca_regs|
                                    alloca_regs.contains(reg.id)
                                else
                                    false;

                                if (is_alloca) {
                                    try writer.print("    return reg_{d}.*;\n", .{reg.id});
                                } else {
                                    try writer.print("    return reg_{d};\n", .{reg.id});
                                }
                            } else {
                                // void return - 返回null
                                try writer.writeAll("    return runtime.Value.initNull();\n");
                            }
                        },
                        else => unreachable,
                    }
                }
                return;
            }
        }

        // 优化2：简单if-else结构（避免状态机）
        // 检测模式：2-3个块，第一个块以cond_br终止，then/else块都以ret终止
        if (try self.tryGenerateSimpleIfElse(writer, func, cleanup_regs)) {
            return;
        }

        // 优化3：简单循环结构（避免状态机）
        // 检测模式：while/for循环（有回边到条件块）
        if (try self.tryGenerateSimpleLoop(writer, func, cleanup_regs)) {
            return;
        }

        // 优化4：直接生成结构化控制流（消除状态机开销）
        // 策略：分析控制流图，生成 while 循环而不是状态机
        if (try self.tryGenerateStructuredControlFlow(writer, func, cleanup_regs)) {
            return;
        }

        // 回退：复杂控制流使用优化的状态机
        try writer.writeAll("    // Optimized state machine with branch hints\n");
        try writer.writeAll("    var current_block: u32 = 0;\n");
        try writer.writeAll("    _ = &current_block;\n");
        try writer.writeAll("    while (true) {\n");
        try writer.writeAll("        switch (current_block) {\n");

        // 为每个基本块生成一个case
        for (func.blocks.items, 0..) |block, block_idx| {
            try writer.print("            {d} => {{ // {s}\n", .{ block_idx, block.label });

            // 生成块内的指令
            for (block.instructions.items) |inst| {
                try writer.writeAll("    ");
                try self.generateInstruction(writer, inst);
            }

            // 生成终止指令
            if (block.terminator) |term| {
                try self.generateTerminatorStateMachine(writer, term, func, cleanup_regs, block_idx);
            } else {
                // 没有终止指令，跳转到下一个块
                if (block_idx + 1 < func.blocks.items.len) {
                    try writer.print("                current_block = {d};\n", .{block_idx + 1});
                } else {
                    // 最后一个块，执行cleanup并返回
                    if (cleanup_regs.len > 0) {
                        try writer.writeAll("                // Cleanup: release all allocated values\n");
                        for (cleanup_regs) |reg_id| {
                            try writer.print("                reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                        }
                    }
                    try writer.writeAll("                return runtime.Value.initNull();\n");
                }
            }

            try writer.writeAll("            },\n");
        }

        try writer.writeAll("            else => unreachable,\n");
        try writer.writeAll("        }\n");
        try writer.writeAll("    }\n");
    }

    /// 尝试生成结构化控制流（新版本，使用 ArrayList writer）
    fn tryGenerateStructuredControlFlowNew(self: *Self, writer: anytype, func: *const IR.Function, cleanup_regs: []const usize, alloca_regs: *const std.AutoHashMap(usize, void)) !bool {
        // 保存并设置 alloca_regs（用于 writeRegRef）
        const prev_alloca_regs = self.current_alloca_regs;
        self.current_alloca_regs = alloca_regs;
        defer self.current_alloca_regs = prev_alloca_regs;

        // std.debug.print("tryGenerateStructuredControlFlowNew for {s}\n", .{func.name});

        // 分析控制流
        var cfg = ControlFlowAnalysis.init(self.allocator);
        defer cfg.deinit();

        try self.buildCFG(func, &cfg);
        try self.detectLoops(func, &cfg);

        // std.debug.print("Found {d} loops\n", .{cfg.loops.items.len});

        if (cfg.loops.items.len == 0) {
            return false;
        }

        // 生成结构化代码
        // std.debug.print("Calling generateStructuredCodeNew...\n", .{});
        const result = try self.generateStructuredCodeNew(writer, func, &cfg, cleanup_regs);
        std.debug.print("generateStructuredCodeNew returned {}\n", .{result});
        return result;
    }

    /// 生成结构化代码（新版本，支持多循环）
    fn generateStructuredCodeNew(self: *Self, writer: anytype, func: *const IR.Function, cfg: *ControlFlowAnalysis, cleanup_regs: []const usize) !bool {
        if (cfg.loops.items.len == 0) {
            return false;
        }

        // 寄存器声明已在 generateFunction 中处理，这里不再重复

        var processed = std.AutoHashMap(usize, void).init(self.allocator);
        defer processed.deinit();

        // 构建块到循环的映射（用于检测子循环）
        var block_to_loop = std.AutoHashMap(usize, usize).init(self.allocator); // block_idx -> loop_idx in all_loops
        defer block_to_loop.deinit();

        // 为每个循环的 header 建立映射
        for (cfg.all_loops.items, 0..) |loop, i| {
            try block_to_loop.put(loop.header, i);
        }

        // 生成第一个循环前的块
        const first_loop = cfg.loops.items[0];
        for (0..first_loop.header) |idx| {
            const block = func.blocks.items[idx];

            // 设置异常处理器（内联辅助逻辑）
            self.current_exception_handler = if (block.exception_handler) |h| h.index else null;

            try writer.print("    // Block {d}: {s}\n", .{ idx, block.label });
            for (block.instructions.items) |inst| {
                try writer.writeAll("    ");
                try self.generateInstruction(writer, inst);
            }
            try processed.put(idx, {});
        }

        // 生成顶层循环
        std.debug.print("Generating {d} top-level loops\n", .{cfg.loops.items.len});
        var last_return_reg: ?usize = null;

        for (cfg.loops.items) |loop| {
            std.debug.print("Calling generateLoopRecursive for loop header={d}\n", .{loop.header});
            try self.generateLoopRecursive(writer, func, loop, &processed, &block_to_loop, cfg.all_loops.items, cleanup_regs, 0);

            // 生成退出块（但不生成 return）
            if (loop.exit_block) |exit_idx| {
                if (!processed.contains(exit_idx)) {
                    const exit_block = func.blocks.items[exit_idx];
                    try writer.print("    // Block {d}: {s}\n", .{ exit_idx, exit_block.label });

                    // 生成指令并记录最后一个返回值
                    var exit_inst_list = writer.context.self;
                    for (exit_block.instructions.items) |inst| {
                        try exit_inst_list.appendSlice(self.allocator, "    ");
                        try self.generateInstructionSimple(exit_inst_list, inst);

                        // 记录最后一个非 alloca 赋值
                        if (inst.result) |res| {
                            const is_alloca = if (self.current_alloca_regs) |alloca_regs|
                                alloca_regs.contains(res.id)
                            else
                                false;
                            if (!is_alloca) {
                                last_return_reg = res.id;
                            }
                        }
                    }

                    // 处理 exit block 的终止指令（if/else 等）
                    if (exit_block.terminator) |term| {
                        var exit_code_list = writer.context.self;
                        switch (term) {
                            .cond_br => |cb| {
                                // 获取寄存器的实际声明类型
                                const decl_type: std.meta.Tag(IR.Type) = if (self.current_reg_types) |rt|
                                    @as(std.meta.Tag(IR.Type), rt.get(cb.cond.id) orelse IR.Type.php_value)
                                else
                                    .php_value;
                                if (decl_type == .bool) {
                                    try writer.print("    if (reg_{d}) {{\n", .{cb.cond.id});
                                } else if (decl_type == .i64) {
                                    try writer.print("    if (reg_{d} != 0) {{\n", .{cb.cond.id});
                                } else {
                                    try writer.print("    if (reg_{d}.toBool()) {{\n", .{cb.cond.id});
                                }
                                // 生成 then 块
                                const then_idx = @as(usize, cb.then_block.index);
                                const then_blk = func.blocks.items[then_idx];
                                for (then_blk.instructions.items) |inst| {
                                    try exit_code_list.appendSlice(self.allocator, "        ");
                                    try self.generateInstructionSimple(exit_code_list, inst);
                                }
                                try processed.put(then_idx, {});
                                try writer.writeAll("    } else {\n");
                                // 生成 else 块
                                const else_idx = @as(usize, cb.else_block.index);
                                const else_blk = func.blocks.items[else_idx];
                                for (else_blk.instructions.items) |inst| {
                                    try exit_code_list.appendSlice(self.allocator, "        ");
                                    try self.generateInstructionSimple(exit_code_list, inst);
                                }
                                try processed.put(else_idx, {});
                                try writer.writeAll("    }\n");
                                // 标记 merge 块为已处理
                                if (then_blk.terminator) |t_term| {
                                    if (t_term == .br) {
                                        const merge_idx = @as(usize, t_term.br.index);
                                        try processed.put(merge_idx, {});
                                    }
                                }
                            },
                            .ret => |ret_val| {
                                if (ret_val) |reg| {
                                    last_return_reg = reg.id;
                                }
                            },
                            else => {},
                        }
                    }

                    try processed.put(exit_idx, {});
                }
            }
        }

        // 收集循环后剩余的未处理块（if/else/merge 等）
        // 计算所有循环的 exit 块集合（用于排除假循环）
        var false_loop_blocks = std.AutoHashMap(usize, void).init(self.allocator);
        defer false_loop_blocks.deinit();
        for (cfg.loops.items) |lp| {
            const lp_header = func.blocks.items[lp.header];
            if (lp_header.terminator) |term| {
                if (term == .cond_br) {
                    const exit_idx = @as(usize, term.cond_br.else_block.index);
                    // 标记以 exit 块为 header 的假循环的所有块
                    for (cfg.all_loops.items) |sub_lp| {
                        if (sub_lp.header == exit_idx) {
                            var blk_it = sub_lp.blocks.iterator();
                            while (blk_it.next()) |entry| {
                                try false_loop_blocks.put(entry.key_ptr.*, {});
                            }
                        }
                    }
                }
            }
        }

        var remaining_blocks = try std.ArrayList(usize).initCapacity(self.allocator, 0);
        defer remaining_blocks.deinit(self.allocator);
        for (0..func.blocks.items.len) |idx| {
            if (processed.contains(idx)) continue;
            const block = func.blocks.items[idx];
            if (std.mem.indexOf(u8, block.label, "_unroll_") != null) continue;

            // 跳过属于真实循环的块（已由循环生成器处理）
            var in_real_loop = false;
            for (cfg.all_loops.items) |lp| {
                if (lp.blocks.contains(idx) and !false_loop_blocks.contains(idx)) {
                    in_real_loop = true;
                    break;
                }
            }
            if (in_real_loop) continue;

            try remaining_blocks.append(self.allocator, idx);
        }

        // 内联生成剩余块（if/else/merge 等）
        if (remaining_blocks.items.len > 0) {
            var code_list = writer.context.self;
            for (remaining_blocks.items) |idx| {
                const block = func.blocks.items[idx];
                try writer.print("    // Block {d}: {s}\n", .{ idx, block.label });
                for (block.instructions.items) |inst| {
                    try code_list.appendSlice(self.allocator, "    ");
                    try self.generateInstructionSimple(code_list, inst);
                }
                // 处理终止指令
                if (block.terminator) |term| {
                    switch (term) {
                        .ret => |ret_val| {
                            if (ret_val) |reg| {
                                last_return_reg = reg.id;
                            }
                        },
                        .cond_br => |cb| {
                            // 获取寄存器的实际声明类型
                            const decl_type: std.meta.Tag(IR.Type) = if (self.current_reg_types) |rt|
                                @as(std.meta.Tag(IR.Type), rt.get(cb.cond.id) orelse IR.Type.php_value)
                            else
                                .php_value;
                            if (decl_type == .bool) {
                                try writer.print("    if (reg_{d}) {{\n", .{cb.cond.id});
                            } else if (decl_type == .i64) {
                                try writer.print("    if (reg_{d} != 0) {{\n", .{cb.cond.id});
                            } else {
                                try writer.print("    if (reg_{d}.toBool()) {{\n", .{cb.cond.id});
                            }
                            // 生成 then 块内联
                            const then_idx = @as(usize, cb.then_block.index);
                            const then_block = func.blocks.items[then_idx];
                            for (then_block.instructions.items) |inst| {
                                try code_list.appendSlice(self.allocator, "        ");
                                try self.generateInstructionSimple(code_list, inst);
                            }
                            try writer.writeAll("    } else {\n");
                            // 生成 else 块内联
                            const else_idx = @as(usize, cb.else_block.index);
                            const else_block = func.blocks.items[else_idx];
                            for (else_block.instructions.items) |inst| {
                                try code_list.appendSlice(self.allocator, "        ");
                                try self.generateInstructionSimple(code_list, inst);
                            }
                            try writer.writeAll("    }\n");
                        },
                        else => {},
                    }
                }
            }
        }

        // 所有块已处理，统一生成 return
        if (last_return_reg) |reg| {
            if (self.current_reg_types) |reg_types| {
                const real_type = reg_types.get(reg) orelse IR.Type.php_value;
                const reg_type_tag = @as(std.meta.Tag(IR.Type), real_type);
                if (reg_type_tag == .i64) {
                    try writer.print("    return runtime.Value.initInt(reg_{d}.asInt());\n", .{reg});
                } else if (reg_type_tag == .f64) {
                    try writer.print("    return runtime.Value.initFloat(reg_{d}.asFloat());\n", .{reg});
                } else if (reg_type_tag == .bool) {
                    try writer.print("    return runtime.Value.initBool(reg_{d}.asBool());\n", .{reg});
                } else {
                    try writer.print("    return reg_{d};\n", .{reg});
                }
            } else {
                try writer.print("    return reg_{d};\n", .{reg});
            }
        } else {
            try writer.writeAll("    return runtime.Value.initNull();\n");
        }

        return true;
    }

    /// 递归生成块代码（支持嵌套循环）
    fn generateBlocksRecursive(self: *Self, writer: anytype, func: *const IR.Function, cfg: *ControlFlowAnalysis, cleanup_regs: []const usize, processed: *std.ArrayList(bool), start_idx: usize, end_idx: usize) !void {
        var current_block = start_idx;
        var code_list = writer.context.self;

        while (current_block < end_idx) {
            if (processed.items[current_block]) {
                current_block += 1;
                continue;
            }

            // 检查是否是循环头
            var is_loop_header = false;
            var loop_info: ?LoopInfo = null;
            for (cfg.loops.items) |loop| {
                if (loop.header == current_block) {
                    is_loop_header = true;
                    loop_info = loop;
                    break;
                }
            }

            if (is_loop_header) {
                const loop = loop_info.?;

                // 生成循环
                if (loop.is_for_loop) {
                    try self.generateForLoopStructuredNew(writer, func, loop, cleanup_regs);
                } else {
                    try self.generateWhileLoopStructuredNew(writer, func, loop, cleanup_regs);
                }

                // 标记循环内的所有块为已处理
                try self.markLoopBlocksProcessed(func, loop, processed);

                // 跳到循环退出块
                if (loop.exit_block) |exit_idx| {
                    current_block = exit_idx;
                } else {
                    current_block += 1;
                }
            } else {
                // 生成普通块
                const block = func.blocks.items[current_block];
                try writer.print("    // Block {d}: {s}\n", .{ current_block, block.label });

                for (block.instructions.items) |inst| {
                    try code_list.appendSlice(self.allocator, "    ");
                    try self.generateInstructionSimple(code_list, inst);
                }

                // 处理终止指令
                if (block.terminator) |term| {
                    switch (term) {
                        .ret => |maybe_reg| {
                            if (cleanup_regs.len > 0) {
                                try writer.writeAll("    // Cleanup\n");
                                for (cleanup_regs) |reg_id| {
                                    if (!self.shouldReleaseReg(reg_id)) continue;
                                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                                }
                            }
                            if (maybe_reg) |reg| {
                                // 类型转换
                                if (self.current_reg_types) |reg_types| {
                                    const real_type = reg_types.get(reg.id) orelse reg.type_;
                                    const reg_type_tag = @as(std.meta.Tag(IR.Type), real_type);
                                    if (reg_type_tag == .i64) {
                                        try writer.print("    return runtime.Value.initInt(reg_{d}.asInt());\n", .{reg.id});
                                    } else if (reg_type_tag == .f64) {
                                        try writer.print("    return runtime.Value.initFloat(reg_{d}.asFloat());\n", .{reg.id});
                                    } else if (reg_type_tag == .bool) {
                                        try writer.print("    return runtime.Value.initBool(reg_{d}.asBool());\n", .{reg.id});
                                    } else {
                                        try writer.print("    return reg_{d};\n", .{reg.id});
                                    }
                                } else {
                                    try writer.print("    return reg_{d};\n", .{reg.id});
                                }
                            } else {
                                try writer.writeAll("    return runtime.Value.initNull();\n");
                            }
                        },
                        else => {},
                    }
                }

                processed.items[current_block] = true;
                current_block += 1;
            }
        }
    }

    /// 标记循环内的所有块为已处理
    fn markLoopBlocksProcessed(self: *Self, func: *const IR.Function, loop: LoopInfo, processed: *std.ArrayList(bool)) !void {
        _ = self;

        // 标记 header
        processed.items[loop.header] = true;

        // 标记 body
        processed.items[loop.body_start] = true;

        // 标记 increment
        if (loop.increment) |inc| {
            processed.items[inc] = true;
        }

        // 标记循环内的所有块（通过遍历找到属于循环的块）
        for (func.blocks.items, 0..) |block, idx| {
            if (idx >= loop.header and idx < (loop.exit_block orelse func.blocks.items.len)) {
                if (idx != loop.header and idx != loop.body_start and idx != (loop.increment orelse 9999)) {
                    // 检查是否是循环内的块
                    if (block.terminator) |term| {
                        switch (term) {
                            .br => |target| {
                                // 如果跳转到 header，说明是循环内的块
                                for (func.blocks.items, 0..) |b, i| {
                                    if (b == target and i == loop.header) {
                                        processed.items[idx] = true;
                                        break;
                                    }
                                }
                            },
                            else => {},
                        }
                    }
                }
            }
        }
    }

    /// 生成结构化 while 循环（新版本）
    fn generateWhileLoopStructuredNew(self: *Self, writer: anytype, func: *const IR.Function, loop: LoopInfo, cleanup_regs: []const usize) !void {
        _ = cleanup_regs;

        try writer.writeAll("    // Optimized: structured while loop\n");

        var code_list = writer.context.self;

        const header_block = func.blocks.items[loop.header];

        // 初始化 PHI 节点（从 init 块或第一个 incoming 获取初始值）
        for (header_block.instructions.items) |inst| {
            if (inst.op == .phi) {
                const phi_op = inst.op.phi;
                if (inst.result) |res| {
                    if (phi_op.incoming.len == 0) continue;

                    var init_value: ?IR.Register = null;
                    for (phi_op.incoming) |incoming| {
                        if (isInitBlock(incoming.block, loop)) {
                            init_value = incoming.value;
                            break;
                        }
                    }
                    if (init_value == null) {
                        init_value = phi_op.incoming[0].value;
                    }

                    if (init_value) |val| {
                        try self.generatePhiValueAssignment(writer, res, val, "    ");
                    }
                }
            }
        }

        var cond_reg_id: ?usize = null;
        if (header_block.terminator) |term| {
            if (term == .cond_br) {
                cond_reg_id = term.cond_br.cond.id;
            }
        }

        // 第一遍：提取循环不变量到循环外
        for (header_block.instructions.items) |inst| {
            if (inst.result) |result_reg| {
                if (cond_reg_id) |cond_id| {
                    if (result_reg.id == cond_id) continue;
                }
            }

            const is_invariant = switch (inst.op) {
                .const_int, .const_float, .const_string, .const_bool, .const_null => true,
                else => false,
            };

            if (is_invariant) {
                try code_list.appendSlice(self.allocator, "    ");
                try self.generateInstructionSimple(code_list, inst);
            }
        }

        try writer.writeAll("    while (true) {\n");
        try writer.print("        // Header: {s}\n", .{header_block.label});

        // 处理 phi 节点：在循环头部，phi 的值来自前驱块
        // 第一次进入：来自 init 块
        // 后续迭代：来自 increment 块
        // 我们需要在循环体末尾更新 phi 值
        const PhiUpdate = struct { phi_reg: usize, value_reg: usize };
        var phi_updates = std.ArrayListUnmanaged(PhiUpdate){};
        defer phi_updates.deinit(self.allocator);

        // 从 phi 节点的 incoming 值中提取更新信息
        for (header_block.instructions.items) |inst| {
            if (inst.op != .phi) continue;
            const result_reg = inst.result orelse continue;
            const phi_op = inst.op.phi;

            // 查找来自循环体的 incoming 值
            for (phi_op.incoming) |incoming| {
                // 检查这个 incoming 块是否在循环内（不是 header）
                var is_loop_body = false;
                var blk_iter = loop.blocks.keyIterator();
                while (blk_iter.next()) |blk_idx_ptr| {
                    const blk_idx = blk_idx_ptr.*;
                    if (blk_idx == loop.header) continue;
                    const scan_block = func.blocks.items[blk_idx];
                    if (scan_block == incoming.block) {
                        is_loop_body = true;
                        break;
                    }
                }

                if (is_loop_body) {
                    // 这是来自循环体的更新值
                    try phi_updates.append(self.allocator, .{ .phi_reg = result_reg.id, .value_reg = incoming.value.id });
                    break;
                }
            }
        }

        // 第二遍：生成非常量指令
        for (header_block.instructions.items) |inst| {
            if (inst.result) |result_reg| {
                if (cond_reg_id) |cond_id| {
                    if (result_reg.id == cond_id) continue;
                }
            }

            const is_invariant = switch (inst.op) {
                .const_int, .const_float, .const_string, .const_bool, .const_null => true,
                else => false,
            };

            if (!is_invariant) {
                try code_list.appendSlice(self.allocator, "        ");
                try self.generateInstructionSimple(code_list, inst);
            }
        }

        // 生成条件判断（内联条件表达式）
        if (header_block.terminator) |term| {
            if (term == .cond_br) {
                try writer.writeAll("        if (!(");

                // 内联条件表达式
                var found_cond = false;
                if (cond_reg_id) |cond_id| {
                    // 找到生成条件的指令
                    for (header_block.instructions.items) |inst| {
                        if (inst.result) |result_reg| {
                            if (result_reg.id == cond_id) {
                                // 内联这条指令的表达式
                                try self.writeInlinedConditionExpr(writer, inst);
                                found_cond = true;
                                break;
                            }
                        }
                    }

                    // 如果没找到指令（被优化删除），直接使用寄存器
                    if (!found_cond) {
                        const cond_type = if (self.current_reg_types) |types|
                            types.get(cond_id) orelse IR.Type.bool
                        else
                            IR.Type.bool;
                        const type_tag = @as(std.meta.Tag(IR.Type), cond_type);
                        try self.writeBoolExpr(writer, type_tag, cond_id);
                    }
                }

                try writer.writeAll(")) break;\n");
            }
        }

        // 生成循环体
        const body_block = func.blocks.items[loop.body_start];
        try writer.print("        // Body: {s}\n", .{body_block.label});

        for (body_block.instructions.items) |inst| {
            try code_list.appendSlice(self.allocator, "        ");
            try self.generateInstructionSimple(code_list, inst);
        }

        // while 循环的 phi 更新必须在循环体末尾回写，否则会导致循环变量不递增
        for (phi_updates.items) |update| {
            var src_buf: [32]u8 = undefined;
            const src_ref = try self.getOperandRef(&src_buf, update.value_reg);
            try writer.print("        reg_{d} = {s};\n", .{ update.phi_reg, src_ref });
        }

        // 生成增量块（如果有且不是 for 循环）
        if (loop.increment) |inc_idx| {
            if (!loop.is_for_loop) {
                const inc_block = func.blocks.items[inc_idx];
                try writer.print("        // Increment: {s}\n", .{inc_block.label});
                for (inc_block.instructions.items) |inst| {
                    try code_list.appendSlice(self.allocator, "        ");
                    try self.generateInstructionSimple(code_list, inst);
                }
            }
        }

        try writer.writeAll("    }\n");
    }

    /// 生成结构化 for 循环（新版本）
    fn generateForLoopStructuredNew(self: *Self, writer: anytype, func: *const IR.Function, loop: LoopInfo, cleanup_regs: []const usize) !void {
        _ = cleanup_regs;
        try writer.writeAll("    // Optimized: structured for loop\n");

        // 🔥 LICM 代码生成层优化：检测并提升循环不变量
        try self.hoistLoopInvariantsAtCodegen(writer, func, loop);

        // 🔥 初始化 PHI 节点（从 init 块或第一个 incoming 获取初始值）
        const header_block = func.blocks.items[loop.header];
        for (header_block.instructions.items) |inst| {
            if (inst.op == .phi) {
                const phi_op = inst.op.phi;
                if (inst.result) |res| {
                    if (phi_op.incoming.len == 0) continue;

                    // 查找循环外来源的 incoming（基于 LoopMetadata）
                    var init_value: ?usize = null;
                    for (phi_op.incoming) |incoming| {
                        if (isInitBlock(incoming.block, loop)) {
                            init_value = incoming.value.id;
                            break;
                        }
                    }

                    // 回退：使用第一个 incoming
                    if (init_value == null) {
                        init_value = phi_op.incoming[0].value.id;
                    }

                    if (init_value) |val| {
                        const phi_type = if (self.current_reg_types) |rt|
                            rt.get(res.id) orelse res.type_
                        else
                            res.type_;
                        const value_type = if (self.current_reg_types) |rt|
                            rt.get(val) orelse IR.Type.php_value
                        else
                            IR.Type.php_value;
                        const phi_tag = @as(std.meta.Tag(IR.Type), phi_type);
                        const value_tag = @as(std.meta.Tag(IR.Type), value_type);

                        var src_buf: [32]u8 = undefined;
                        const src_ref = try self.getOperandRef(&src_buf, val);

                        if (phi_tag == value_tag) {
                            try writer.print("    reg_{d} = {s};\n", .{ res.id, src_ref });
                        } else if (phi_tag == .i64 and value_tag == .php_value) {
                            // 所有寄存器都是 Value，需要包装
                            try writer.print("    reg_{d} = runtime.Value.initInt({s}.asInt());\n", .{ res.id, src_ref });
                        } else if (phi_tag == .f64 and value_tag == .php_value) {
                            try writer.print("    reg_{d} = runtime.Value.initFloat({s}.asFloat());\n", .{ res.id, src_ref });
                        } else if (phi_tag == .bool and value_tag == .php_value) {
                            try writer.print("    reg_{d} = runtime.Value.initBool({s}.toBool());\n", .{ res.id, src_ref });
                        } else if (phi_tag == .php_value and value_tag == .i64) {
                            try writer.print("    reg_{d} = runtime.Value.initInt({s}.asInt());\n", .{ res.id, src_ref });
                        } else if (phi_tag == .php_value and value_tag == .f64) {
                            try writer.print("    reg_{d} = runtime.Value.initFloat({s}.asFloat());\n", .{ res.id, src_ref });
                        } else if (phi_tag == .php_value and value_tag == .bool) {
                            try writer.print("    reg_{d} = runtime.Value.initBool({s}.toBool());\n", .{ res.id, src_ref });
                        } else {
                            try writer.print("    reg_{d} = {s};\n", .{ res.id, src_ref });
                        }
                    }
                }
            }
        }

        // 分析循环变量：查找在 increment 块中被修改的 alloca 寄存器
        var loop_var_reg: ?usize = null;
        if (loop.increment) |inc_idx| {
            const inc_block = func.blocks.items[inc_idx];
            // 查找 val_assign 操作
            for (inc_block.instructions.items) |inst| {
                if (inst.op == .call) {
                    if (inst.op.call.args.len >= 2) {
                        const first_arg = inst.op.call.args[0];
                        // 检查是否是 alloca 寄存器
                        if (self.current_alloca_regs) |alloca_regs| {
                            if (alloca_regs.contains(first_arg.id)) {
                                loop_var_reg = first_arg.id;
                                break;
                            }
                        }
                    }
                }
            }
        }

        // 如果找到循环变量，生成优化的循环
        if (loop_var_reg) |var_reg| {
            try self.generateOptimizedForLoop(writer, func, loop, var_reg);
        } else {
            try self.generateStandardForLoop(writer, func, loop);
        }

        // 注意：退出块由 generateStructuredCodeNew 统一处理
    }

    /// 🔥 代码生成层 LICM：检测并提升循环不变量
    /// 策略：扫描循环体，找到 load(循环不变地址) + call(纯函数) 序列，提升到循环前
    fn hoistLoopInvariantsAtCodegen(self: *Self, writer: anytype, func: *const IR.Function, loop: LoopInfo) !void {
        // 纯函数白名单（无副作用，结果只依赖参数）
        const pure_functions = std.StaticStringMap(void).initComptime(.{
            .{ "array_sum", {} },
            .{ "array_product", {} },
            .{ "count", {} },
            .{ "strlen", {} },
            .{ "array_count", {} },
            .{ "sizeof", {} },
            .{ "abs", {} },
            .{ "max", {} },
            .{ "min", {} },
            .{ "array_key_exists", {} },
            .{ "in_array", {} },
            .{ "array_keys", {} },
            .{ "array_values", {} },
            .{ "implode", {} },
            .{ "join", {} },
        });

        // 收集循环内所有块
        var loop_blocks = try std.ArrayList(usize).initCapacity(self.allocator, 0);
        defer loop_blocks.deinit(self.allocator);

        // 添加 body（只检查 body，不包括 header 和 increment）
        try loop_blocks.append(self.allocator, loop.body_start);

        // 收集循环内修改的地址（store 的目标）
        var modified_addrs = std.AutoHashMap(usize, void).init(self.allocator);
        defer modified_addrs.deinit();

        // 扫描所有循环块（包括 header 和 increment）
        const all_blocks = [_]?usize{ loop.header, loop.body_start, loop.increment };
        for (all_blocks) |maybe_idx| {
            if (maybe_idx) |block_idx| {
                const block = func.blocks.items[block_idx];
                for (block.instructions.items) |inst| {
                    if (inst.op == .store) {
                        try modified_addrs.put(inst.op.store.ptr.id, {});
                    }
                }
            }
        }

        // 扫描循环体，找到可提升的指令并生成
        var hoisted_count: usize = 0;
        for (loop_blocks.items) |block_idx| {
            const block = func.blocks.items[block_idx];

            var i: usize = 0;
            while (i < block.instructions.items.len) : (i += 1) {
                const inst = block.instructions.items[i];

                // 检测模式：load + call(纯函数)
                if (inst.op == .load) {
                    const load_ptr = inst.op.load.ptr.id;
                    const load_result = inst.result orelse continue;

                    // 检查地址是否循环不变（不在 modified_addrs 中）
                    if (modified_addrs.contains(load_ptr)) {
                        continue;
                    }

                    // 查找使用 load 结果的 call
                    if (i + 1 < block.instructions.items.len) {
                        const next_inst = block.instructions.items[i + 1];
                        if (next_inst.op == .call) {
                            const call_op = next_inst.op.call;

                            // 检查是否是纯函数
                            if (!pure_functions.has(call_op.func_name)) {
                                continue;
                            }

                            // 检查参数是否是 load 的结果
                            if (call_op.args.len > 0 and call_op.args[0].id == load_result.id) {
                                // 🎯 找到可提升的序列！生成提升后的代码（在循环前）
                                try writer.writeAll("    // LICM: hoisted loop-invariant call\n");

                                // 生成 load
                                const suffix = self.getRegSuffix(load_result.id);
                                if (self.regMayHeap(load_result.id)) {
                                    try writer.print("    reg_{d}{s}.release(runtime.runtime_allocator);\n", .{ load_result.id, suffix });
                                }
                                try writer.print("    reg_{d}{s} = ", .{ load_result.id, suffix });
                                try self.generateLoadValue(writer, inst.op.load.ptr);
                                try writer.writeAll(";\n");

                                // 生成 call
                                if (next_inst.result) |call_result| {
                                    const call_suffix = self.getRegSuffix(call_result.id);
                                    if (self.regMayHeap(call_result.id)) {
                                        try writer.print("    reg_{d}{s}.release(runtime.runtime_allocator);\n", .{ call_result.id, call_suffix });
                                    }
                                    try writer.print("    reg_{d}{s} = try runtime.php_{s}(reg_{d}{s}", .{
                                        call_result.id,
                                        call_suffix,
                                        call_op.func_name,
                                        load_result.id,
                                        suffix,
                                    });
                                    // 其他参数
                                    for (call_op.args[1..]) |arg| {
                                        try writer.print(", reg_{d}", .{arg.id});
                                    }
                                    try writer.writeAll(");\n");

                                    // 标记这两条指令为已提升（在循环体生成时跳过）
                                    try self.markInstructionHoisted(inst);
                                    try self.markInstructionHoisted(next_inst);
                                }

                                hoisted_count += 1;
                                i += 1; // 跳过 call 指令
                            }
                        }
                    }
                }
            }
        }

        if (hoisted_count > 0) {
            try writer.print("    // LICM: hoisted {d} loop-invariant sequence(s)\n\n", .{hoisted_count});
        }
    }

    /// 标记指令为已提升（在循环体生成时跳过）
    fn markInstructionHoisted(self: *Self, inst: *const IR.Instruction) !void {
        if (self.hoisted_instructions == null) {
            self.hoisted_instructions = std.AutoHashMap(*const IR.Instruction, void).init(self.allocator);
        }
        try self.hoisted_instructions.?.put(inst, {});
    }

    /// 检查指令是否已提升
    fn isInstructionHoisted(self: *Self, inst: *const IR.Instruction) bool {
        if (self.hoisted_instructions) |*map| {
            return map.contains(inst);
        }
        return false;
    }

    /// 生成 load 指令的值读取代码
    fn generateLoadValue(self: *Self, writer: anytype, ptr_reg: IR.Register) !void {
        const suffix = self.getRegSuffix(ptr_reg.id);
        try writer.print("runtime.val_deref(&reg_{d}{s}).*", .{ ptr_reg.id, suffix });
    }

    /// 检测并优化增量模式: load → const → add → store → reg += const
    fn tryOptimizeIncrement(self: *Self, writer: anytype, block: *const IR.BasicBlock) !bool {
        const insts = block.instructions.items;
        if (insts.len < 3) return false;

        var load_reg: ?usize = null;
        var const_val: ?i64 = null;
        var add_result: ?usize = null;
        var target_reg: ?usize = null;

        for (insts) |inst| {
            switch (inst.op) {
                .load => |op| {
                    if (inst.result) |res| {
                        load_reg = res.id;
                        target_reg = op.ptr.id;
                    }
                },
                .const_int => |val| const_val = val,
                .add => |op| {
                    if (load_reg != null and const_val != null and op.lhs.id == load_reg.?) {
                        if (inst.result) |res| add_result = res.id;
                    }
                },
                .store => |op| {
                    if (add_result != null and target_reg != null and
                        op.value.id == add_result.? and op.ptr.id == target_reg.?)
                    {
                        // 检查 target_reg 是否是 alloca
                        const is_alloca = if (self.current_alloca_regs) |alloca_regs|
                            alloca_regs.contains(target_reg.?)
                        else
                            false;

                        if (is_alloca) {
                            // alloca: 生成 load → add → store
                            try writer.print("        reg_{d}.* = runtime.Value.initInt(reg_{d}.*.asInt() + {d});\n", .{ target_reg.?, target_reg.?, const_val.? });
                        } else {
                            // 非 alloca: 直接 +=
                            try writer.print("        reg_{d} += {d};\n", .{ target_reg.?, const_val.? });
                        }
                        return true;
                    }
                },
                else => {},
            }
        }

        return false;
    }

    fn generateStandardForLoop(self: *Self, writer: anytype, func: *const IR.Function, loop: LoopInfo) !void {
        self.current_function_for_resolve = func;
        defer self.current_function_for_resolve = null;

        var code_list = writer.context.self;

        const PhiUpdate = struct { phi_reg: usize, value_reg: usize };

        // 在标准循环内递归生成循环体控制流（cond_br / br），用于 break/continue 场景。
        // 仅用于循环内部的块，避免遗漏 if_then/if_merge 等块导致语义缺失。
        const LoopBodyIndent = struct {
            fn writeIndent(dst: *std.ArrayList(u8), allocator: std.mem.Allocator, depth: usize) !void {
                var i: usize = 0;
                while (i < depth) : (i += 1) {
                    try dst.appendSlice(allocator, "    ");
                }
            }
        };

        const SelfPtr = *Self;
        const generateLoopBodyFromBlock = struct {
            fn emitIncAndPhi(
                self_: SelfPtr,
                writer_: anytype,
                code_: *std.ArrayList(u8),
                func_: *const IR.Function,
                loop_: LoopInfo,
                phi_updates_: []const PhiUpdate,
                depth: usize,
            ) anyerror!void {
                if (loop_.increment) |inc_idx| {
                    const inc_block = func_.blocks.items[inc_idx];
                    for (inc_block.instructions.items) |inst| {
                        if (inst.op == .phi) continue;
                        try LoopBodyIndent.writeIndent(code_, self_.allocator, depth);
                        try self_.generateInstructionSimple(code_, inst);
                    }
                }

                for (phi_updates_) |update| {
                    // 移除错误的自增优化，使用标准 phi 更新
                    // if (update.phi_reg == update.value_reg) {
                    //     try LoopBodyIndent.writeIndent(code_, self_.allocator, depth);
                    //     try writer_.print("reg_{d} = try runtime.php_add(reg_{d}, runtime.Value.initInt(1));\n", .{ update.phi_reg, update.phi_reg });
                    //     continue;
                    // }

                    const phi_type = if (self_.current_reg_types) |rt| rt.get(update.phi_reg) orelse IR.Type.php_value else IR.Type.php_value;
                    const value_type = if (self_.current_reg_types) |rt| rt.get(update.value_reg) orelse IR.Type.php_value else IR.Type.php_value;
                    const phi_tag = @as(std.meta.Tag(IR.Type), phi_type);
                    const value_tag = @as(std.meta.Tag(IR.Type), value_type);

                    try LoopBodyIndent.writeIndent(code_, self_.allocator, depth);
                    if (phi_tag == value_tag) {
                        if (phi_tag == .php_value) {
                            // php_value 需要 retain 以保持引用计数正确
                            try writer_.print("reg_{d} = reg_{d};\n", .{ update.phi_reg, update.value_reg });
                            try LoopBodyIndent.writeIndent(code_, self_.allocator, depth);
                            try writer_.print("_ = reg_{d}.retain();\n", .{update.phi_reg});
                        } else {
                            try writer_.print("reg_{d} = reg_{d};\n", .{ update.phi_reg, update.value_reg });
                        }
                    } else if (phi_tag == .i64 and value_tag == .php_value) {
                        // 所有寄存器都是 Value 类型，需要包装
                        try writer_.print("reg_{d} = runtime.Value.initInt(reg_{d}.asInt());\n", .{ update.phi_reg, update.value_reg });
                    } else if (phi_tag == .f64 and value_tag == .php_value) {
                        // 所有寄存器都是 Value 类型，需要包装
                        try writer_.print("reg_{d} = runtime.Value.initFloat(reg_{d}.asFloat());\n", .{ update.phi_reg, update.value_reg });
                    } else if (phi_tag == .php_value and value_tag == .i64) {
                        // 所有寄存器都是 Value，需要 asInt()
                        try writer_.print("reg_{d} = runtime.Value.initInt(reg_{d}.asInt());\n", .{ update.phi_reg, update.value_reg });
                    } else if (phi_tag == .php_value and value_tag == .f64) {
                        try writer_.print("reg_{d} = runtime.Value.initFloat(reg_{d}.asFloat());\n", .{ update.phi_reg, update.value_reg });
                    } else if (phi_tag == .php_value and value_tag == .bool) {
                        try writer_.print("reg_{d} = runtime.Value.initBool(reg_{d}.toBool());\n", .{ update.phi_reg, update.value_reg });
                    } else {
                        try writer_.print("reg_{d} = reg_{d};\n", .{ update.phi_reg, update.value_reg });
                    }
                }
            }

            fn go(
                self_: SelfPtr,
                writer_: anytype,
                code_: *std.ArrayList(u8),
                func_: *const IR.Function,
                loop_: LoopInfo,
                phi_updates_: []const PhiUpdate,
                block_idx: usize,
                visited: *std.AutoHashMap(usize, void),
                depth: usize,
                source_block_idx: ?usize, // 前驱块索引
            ) anyerror!void {
                if (visited.contains(block_idx)) return;
                try visited.put(block_idx, {});

                const block = func_.blocks.items[block_idx];

                // 生成该块的 phi 赋值（来自 source_block）
                if (source_block_idx) |src_idx| {
                    const source_block = func_.blocks.items[src_idx];
                    for (block.instructions.items) |inst| {
                        if (inst.op == .phi) {
                            const phi_op = inst.op.phi;
                            if (inst.result) |phi_res| {
                                // 查找来自 source_block 的 incoming
                                for (phi_op.incoming) |incoming| {
                                    if (incoming.block == source_block) {
                                        try LoopBodyIndent.writeIndent(code_, self_.allocator, depth);
                                        try writer_.print("reg_{d} = reg_{d};\n", .{ phi_res.id, incoming.value.id });
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }

                for (block.instructions.items) |inst| {
                    if (inst.op == .phi) continue;
                    try LoopBodyIndent.writeIndent(code_, self_.allocator, depth);
                    try self_.generateInstructionSimple(code_, inst);
                }

                const term_opt = block.terminator;
                if (term_opt == null) return;

                switch (term_opt.?) {
                    .br => |br| {
                        const target = @as(usize, br.index);
                        if (loop_.increment) |inc| {
                            if (target == inc or target == loop_.header) {
                                try emitIncAndPhi(self_, writer_, code_, func_, loop_, phi_updates_, depth);
                                try LoopBodyIndent.writeIndent(code_, self_.allocator, depth);
                                try writer_.writeAll("continue;\n");
                                return;
                            }
                        }
                        if (loop_.exit_block) |exit_idx| {
                            if (target == exit_idx) {
                                try LoopBodyIndent.writeIndent(code_, self_.allocator, depth);
                                try writer_.writeAll("break;\n");
                                return;
                            }
                        }
                        if (loop_.blocks.contains(target)) {
                            try go(self_, writer_, code_, func_, loop_, phi_updates_, target, visited, depth, block_idx);
                        }
                    },
                    .cond_br => |cbr| {
                        try LoopBodyIndent.writeIndent(code_, self_.allocator, depth);
                        try writer_.writeAll("if (");

                        // 尽量内联条件表达式，否则回退到 toBool
                        var inlined = false;
                        for (block.instructions.items) |inst| {
                            if (inst.result) |rr| {
                                if (rr.id == cbr.cond.id) {
                                    try self_.writeInlinedConditionExpr(writer_, inst);
                                    inlined = true;
                                    break;
                                }
                            }
                        }
                        if (!inlined) {
                            const cond_type = self_.getInferredRegType(cbr.cond.id, cbr.cond.type_);
                            const cond_tag = @as(std.meta.Tag(IR.Type), cond_type);
                            try self_.writeBoolExpr(writer_, cond_tag, cbr.cond.id);
                        }

                        try writer_.writeAll(") {\n");

                        const then_target = @as(usize, cbr.then_block.index);
                        if (loop_.increment) |inc| {
                            if (then_target == inc or then_target == loop_.header) {
                                try emitIncAndPhi(self_, writer_, code_, func_, loop_, phi_updates_, depth + 1);
                                try LoopBodyIndent.writeIndent(code_, self_.allocator, depth + 1);
                                try writer_.writeAll("continue;\n");
                            } else if (loop_.exit_block) |exit_idx| {
                                if (then_target == exit_idx) {
                                    try LoopBodyIndent.writeIndent(code_, self_.allocator, depth + 1);
                                    try writer_.writeAll("break;\n");
                                } else if (loop_.blocks.contains(then_target)) {
                                    try go(self_, writer_, code_, func_, loop_, phi_updates_, then_target, visited, depth + 1, block_idx);
                                }
                            } else if (loop_.blocks.contains(then_target)) {
                                try go(self_, writer_, code_, func_, loop_, phi_updates_, then_target, visited, depth + 1, block_idx);
                            }
                        } else if (loop_.blocks.contains(then_target)) {
                            try go(self_, writer_, code_, func_, loop_, phi_updates_, then_target, visited, depth + 1, block_idx);
                        }

                        try LoopBodyIndent.writeIndent(code_, self_.allocator, depth);
                        try writer_.writeAll("} else {\n");

                        const else_target = @as(usize, cbr.else_block.index);

                        // 如果 else_target 已经被访问，手动生成 phi 赋值
                        if (visited.contains(else_target)) {
                            const else_block = func_.blocks.items[else_target];
                            for (else_block.instructions.items) |inst| {
                                if (inst.op == .phi) {
                                    const phi_op = inst.op.phi;
                                    if (inst.result) |phi_res| {
                                        // 查找来自当前块的 incoming
                                        for (phi_op.incoming) |incoming| {
                                            if (incoming.block == block) {
                                                try LoopBodyIndent.writeIndent(code_, self_.allocator, depth + 1);
                                                try writer_.print("reg_{d} = reg_{d};\n", .{ phi_res.id, incoming.value.id });
                                                break;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if (loop_.increment) |inc2| {
                            if (else_target == inc2 or else_target == loop_.header) {
                                try emitIncAndPhi(self_, writer_, code_, func_, loop_, phi_updates_, depth + 1);
                                try LoopBodyIndent.writeIndent(code_, self_.allocator, depth + 1);
                                try writer_.writeAll("continue;\n");
                            } else if (loop_.exit_block) |exit_idx2| {
                                if (else_target == exit_idx2) {
                                    try LoopBodyIndent.writeIndent(code_, self_.allocator, depth + 1);
                                    try writer_.writeAll("break;\n");
                                } else if (loop_.blocks.contains(else_target)) {
                                    try go(self_, writer_, code_, func_, loop_, phi_updates_, else_target, visited, depth + 1, block_idx);
                                }
                            } else if (loop_.blocks.contains(else_target)) {
                                try go(self_, writer_, code_, func_, loop_, phi_updates_, else_target, visited, depth + 1, block_idx);
                            }
                        } else if (loop_.blocks.contains(else_target)) {
                            try go(self_, writer_, code_, func_, loop_, phi_updates_, else_target, visited, depth + 1, block_idx);
                        }

                        try LoopBodyIndent.writeIndent(code_, self_.allocator, depth);
                        try writer_.writeAll("}\n");
                    },
                    else => {},
                }
            }
        }.go;

        const header_block = func.blocks.items[loop.header];
        const body_block = func.blocks.items[loop.body_start];

        // 先获取条件寄存器 ID（用于识别循环变量）
        var cond_reg_id: ?usize = null;
        if (header_block.terminator) |term| {
            if (term == .cond_br) {
                cond_reg_id = term.cond_br.cond.id;
            }
        }

        // 收集 phi 节点更新信息
        var phi_updates = std.ArrayListUnmanaged(PhiUpdate){};
        defer phi_updates.deinit(self.allocator);

        for (header_block.instructions.items) |inst| {
            if (inst.op == .phi) {
                const phi_op = inst.op.phi;
                const result_reg = inst.result orelse continue;

                // std.debug.print("Processing phi reg_{d}, incoming count={d}\n", .{ result_reg.id, phi_op.incoming.len });

                // 策略：在实际生成的块中查找更新，避免使用被展开破坏的 PHI incoming
                var update_reg: ?usize = null;

                // 1. 在当前循环的所有块中查找（累加器更新可能在 if/else 分支块里）
                // 注意：只扫 loop.blocks，避免跨出循环范围。
                var blk_iter = loop.blocks.keyIterator();
                while (blk_iter.next()) |blk_idx_ptr| {
                    const blk_idx = blk_idx_ptr.*;
                    // 跳过 header 本身（这里主要找 body/子块中的更新）
                    if (blk_idx == loop.header) continue;

                    const scan_block = func.blocks.items[blk_idx];
                    for (scan_block.instructions.items) |scan_inst| {
                        if (scan_inst.result) |scan_res| {
                            switch (scan_inst.op) {
                                .add, .sub => |op| {
                                    if (op.lhs.id == result_reg.id) {
                                        update_reg = scan_res.id;
                                        std.debug.print(
                                            "  Found update in loop block {d}: reg_{d} = reg_{d} +/- ...\n",
                                            .{ blk_idx, scan_res.id, op.lhs.id },
                                        );
                                        break;
                                    }
                                },
                                else => {},
                            }
                        }
                    }

                    if (update_reg != null) break;
                }

                // 2. 如果在 body 块未找到，在 increment 块查找（循环变量）
                if (update_reg == null and loop.increment != null) {
                    const inc_block = func.blocks.items[loop.increment.?];
                    const is_unroll = std.mem.indexOf(u8, inc_block.label, "_unroll_") != null;
                    if (!is_unroll) {
                        for (inc_block.instructions.items) |inc_inst| {
                            if (inc_inst.result) |inc_result| {
                                switch (inc_inst.op) {
                                    .add, .sub => |op| {
                                        if (op.lhs.id == result_reg.id) {
                                            update_reg = inc_result.id;
                                            std.debug.print("  Found update in increment: reg_{d} = reg_{d} +/- ...\n", .{ inc_result.id, op.lhs.id });
                                            break;
                                        }
                                    },
                                    else => {},
                                }
                            }
                        }
                    }
                }

                if (update_reg) |ureg| {
                    std.debug.print("phi: reg_{d} <- reg_{d}\n", .{ result_reg.id, ureg });
                    try phi_updates.append(self.allocator, .{ .phi_reg = result_reg.id, .value_reg = ureg });
                } else {
                    // 未找到更新指令，可能是循环变量（$i++）
                    // 检查是否在条件判断中使用（循环变量的特征）
                    var is_loop_var = false;
                    if (cond_reg_id) |cond_id| {
                        for (header_block.instructions.items) |cond_inst| {
                            if (cond_inst.result) |cond_result| {
                                if (cond_result.id == cond_id) {
                                    switch (cond_inst.op) {
                                        .lt, .le, .gt, .ge => |op| {
                                            if (op.lhs.id == result_reg.id or op.rhs.id == result_reg.id) {
                                                is_loop_var = true;
                                                break;
                                            }
                                        },
                                        else => {},
                                    }
                                }
                            }
                        }
                    }

                    if (is_loop_var) {
                        // 循环变量：生成简单自增 reg = reg + 1
                        std.debug.print("  Loop variable detected: reg_{d}, generating simple increment\n", .{result_reg.id});
                        // 使用特殊标记表示需要生成 reg = reg + 1
                        try phi_updates.append(self.allocator, .{ .phi_reg = result_reg.id, .value_reg = result_reg.id });
                    } else {
                        // 其他情况：使用 fallback
                        std.debug.print("  Warning: No update found for phi reg_{d}, using fallback\n", .{result_reg.id});
                        for (phi_op.incoming) |incoming| {
                            if (!isInitBlock(incoming.block, loop)) {
                                const resolved_reg = self.resolveUnrolledReg(func, incoming.value.id, loop);
                                try phi_updates.append(self.allocator, .{ .phi_reg = result_reg.id, .value_reg = resolved_reg });
                                break;
                            }
                        }
                    }
                }
            }
        }

        // 构建死代码集合：条件中被解析的寄存器
        var dead_regs = std.AutoHashMap(usize, void).init(self.allocator);
        defer dead_regs.deinit();

        if (cond_reg_id) |cond_id| {
            for (header_block.instructions.items) |inst| {
                if (inst.result) |res| {
                    if (res.id == cond_id) {
                        // 检查条件操作数是否会被解析
                        switch (inst.op) {
                            .lt, .le, .gt, .ge, .eq, .ne => |op| {
                                const lhs_resolved = self.resolveLoadSource(op.lhs.id);
                                const rhs_resolved = self.resolveLoadSource(op.rhs.id);
                                if (lhs_resolved != op.lhs.id) try dead_regs.put(op.lhs.id, {});
                                if (rhs_resolved != op.rhs.id) try dead_regs.put(op.rhs.id, {});
                            },
                            else => {},
                        }
                        break;
                    }
                }
            }
        }

        // 检测完全展开：禁用（bug：无法正确模拟循环变量）
        const full_unroll_count: ?usize = null;

        // 检测数学化简：禁用（导致嵌套循环问题）
        const math_simplify: ?struct { target_reg: usize, loop_count_reg: usize } = null;

        // 检测无效循环：循环体只有常量赋值
        const dead_loop = blk: {
            if (math_simplify != null or full_unroll_count != null) break :blk false;

            // 检查循环体是否只有 const + store
            var only_const_store = true;
            for (body_block.instructions.items) |inst| {
                const is_const = switch (inst.op) {
                    .const_int, .const_float, .const_string, .const_bool, .const_null => true,
                    else => false,
                };
                if (!is_const and inst.op != .store) {
                    only_const_store = false;
                    break;
                }
            }

            break :blk only_const_store;
        };

        // 检测循环展开和剥离
        const unroll_factor: usize = 1; // 禁用展开直到修复计算 bug
        const enable_peeling = false;

        // 提取所有循环不变量到循环外（header + body + increment）
        for (header_block.instructions.items) |inst| {
            if (inst.result) |result_reg| {
                if (cond_reg_id) |cond_id| {
                    if (result_reg.id == cond_id) continue;
                }
            }

            const is_invariant = switch (inst.op) {
                .const_int, .const_float, .const_string, .const_bool, .const_null => true,
                else => false,
            };

            if (is_invariant) {
                try code_list.appendSlice(self.allocator, "    ");
                try self.generateInstructionSimple(code_list, inst);
            }
        }

        // 提取循环体的常量
        for (body_block.instructions.items) |inst| {
            const is_invariant = switch (inst.op) {
                .const_int, .const_float, .const_string, .const_bool, .const_null => true,
                else => false,
            };

            if (is_invariant) {
                try code_list.appendSlice(self.allocator, "    ");
                try self.generateInstructionSimple(code_list, inst);
            }
        }

        // 提取增量块的常量
        if (loop.increment) |inc_idx| {
            const inc_block = func.blocks.items[inc_idx];
            for (inc_block.instructions.items) |inst| {
                const is_invariant = switch (inst.op) {
                    .const_int, .const_float, .const_string, .const_bool, .const_null => true,
                    else => false,
                };

                if (is_invariant) {
                    try code_list.appendSlice(self.allocator, "    ");
                    try self.generateInstructionSimple(code_list, inst);
                }
            }
        }

        // 数学化简：sum += 1 循环 → sum += N
        if (math_simplify) |ms| {
            try writer.print("    // Mathematical simplification: sum += N\n", .{});

            // 检查是否是优化的 alloca
            const target_is_opt_alloca = if (self.current_optimized_alloca_regs) |opt_regs|
                opt_regs.contains(ms.target_reg)
            else
                false;

            // 检查类型并生成正确的代码
            const ms_target_type = if (self.current_reg_types) |rt| rt.get(ms.target_reg) orelse IR.Type.php_value else IR.Type.php_value;
            const ms_count_type = if (self.current_reg_types) |rt| rt.get(ms.loop_count_reg) orelse IR.Type.i64 else IR.Type.i64;
            const ms_target_tag = @as(std.meta.Tag(IR.Type), ms_target_type);
            const ms_count_tag = @as(std.meta.Tag(IR.Type), ms_count_type);

            // 如果是优化的 alloca，强制为 i64
            if (target_is_opt_alloca or ms_target_tag == .i64) {
                if (ms_count_tag == .i64) {
                    try writer.print("    reg_{d} += reg_{d};\n", .{ ms.target_reg, ms.loop_count_reg });
                } else if (ms_count_tag == .php_value) {
                    try writer.print("    reg_{d} += reg_{d}.asInt();\n", .{ ms.target_reg, ms.loop_count_reg });
                } else {
                    try writer.print("    reg_{d} += reg_{d};\n", .{ ms.target_reg, ms.loop_count_reg });
                }
            } else if (ms_target_tag == .php_value) {
                if (ms_count_tag == .i64) {
                    try writer.print("    reg_{d} = try runtime.php_add(reg_{d}, runtime.Value.initInt(reg_{d}));\n", .{ ms.target_reg, ms.target_reg, ms.loop_count_reg });
                } else {
                    try writer.print("    reg_{d} = try runtime.php_add(reg_{d}, reg_{d});\n", .{ ms.target_reg, ms.target_reg, ms.loop_count_reg });
                }
            } else {
                // 默认：直接加法
                try writer.print("    reg_{d} += reg_{d};\n", .{ ms.target_reg, ms.loop_count_reg });
            }

            // 更新循环变量到上界
            if (loop.increment) |inc_idx| {
                const inc_block = func.blocks.items[inc_idx];
                for (inc_block.instructions.items) |inst| {
                    if (inst.op == .store) {
                        const inc_reg = inst.op.store.ptr.id;

                        // 获取两个寄存器的类型
                        const inc_type = if (self.current_reg_types) |rt| rt.get(inc_reg) orelse IR.Type.php_value else IR.Type.php_value;
                        const count_type = if (self.current_reg_types) |rt| rt.get(ms.loop_count_reg) orelse IR.Type.i64 else IR.Type.i64;
                        const inc_tag = @as(std.meta.Tag(IR.Type), inc_type);
                        const count_tag = @as(std.meta.Tag(IR.Type), count_type);

                        // 检查是否是优化的 alloca
                        const is_optimized_alloca = if (self.current_optimized_alloca_regs) |opt_regs|
                            opt_regs.contains(inc_reg)
                        else
                            false;

                        // 生成赋值
                        var src_buf: [32]u8 = undefined;
                        const src_ref = try self.getOperandRef(&src_buf, ms.loop_count_reg);

                        if (is_optimized_alloca or inc_tag == .i64) {
                            // 目标是 i64 - 但所有寄存器都是 Value
                            if (count_tag == .i64) {
                                try writer.print("    reg_{d} = {s};\n", .{ inc_reg, src_ref });
                            } else if (count_tag == .php_value) {
                                // 需要包装
                                try writer.print("    reg_{d} = runtime.Value.initInt({s}.asInt());\n", .{ inc_reg, src_ref });
                            } else {
                                try writer.print("    reg_{d} = {s};\n", .{ inc_reg, src_ref });
                            }
                        } else if (inc_tag == .php_value) {
                            // 目标是 Value - 所有寄存器都是 Value，需要类型转换
                            if (count_tag == .i64) {
                                var src_buf2: [128]u8 = undefined;
                                const src_wrapped = try self.getValueWrapper(&src_buf2, ms.loop_count_reg, count_tag);
                                try writer.print("    reg_{d} = {s};\n", .{ inc_reg, src_wrapped });
                            } else {
                                try writer.print("    reg_{d} = {s};\n", .{ inc_reg, src_ref });
                            }
                        } else {
                            // 其他情况
                            var src_buf2: [32]u8 = undefined;
                            const src_ref2 = try self.getOperandRef(&src_buf2, ms.loop_count_reg);
                            try writer.print("    reg_{d} = {s};\n", .{ inc_reg, src_ref2 });
                        }
                        break;
                    }
                }
            }
        } else if (full_unroll_count) |count| {
            try writer.print("    // Fully unrolled loop ({d} iterations)\n", .{count});

            // 完全展开：生成每次迭代
            var iter: usize = 0;
            while (iter < count) : (iter += 1) {
                // 生成循环体指令
                for (body_block.instructions.items) |inst| {
                    try code_list.appendSlice(self.allocator, "    ");
                    try self.generateInstructionSimple(code_list, inst);
                }
            }

            // 更新循环变量到最终值
            if (loop.increment) |inc_idx| {
                const inc_block = func.blocks.items[inc_idx];
                for (inc_block.instructions.items) |inst| {
                    if (inst.op == .store) {
                        const inc_reg = inst.op.store.ptr.id;
                        try writer.print("    reg_{d} = {d};\n", .{ inc_reg, count });
                        break;
                    }
                }
            }
        } else if (false and dead_loop) { // 暂时禁用 dead_loop 优化
            // 无效循环：只执行最后一次赋值
            try writer.print("    // Dead loop eliminated\n", .{});

            for (body_block.instructions.items) |inst| {
                if (inst.op == .store) {
                    try code_list.appendSlice(self.allocator, "    ");
                    try self.generateInstructionSimple(code_list, inst);
                }
            }

            // 更新循环变量到上界
            if (loop.increment) |inc_idx| {
                const inc_block = func.blocks.items[inc_idx];
                var loop_limit_reg: ?usize = null;
                if (cond_reg_id) |cond_id| {
                    for (header_block.instructions.items) |inst| {
                        if (inst.result) |res| {
                            if (res.id == cond_id and inst.op == .lt) {
                                loop_limit_reg = inst.op.lt.rhs.id;
                                break;
                            }
                        }
                    }
                }

                if (loop_limit_reg) |limit_reg| {
                    for (inc_block.instructions.items) |inst| {
                        if (inst.op == .store) {
                            const inc_reg = inst.op.store.ptr.id;
                            var src_buf: [32]u8 = undefined;
                            const src_ref = try self.getOperandRef(&src_buf, limit_reg);
                            try writer.print("    reg_{d} = {s};\n", .{ inc_reg, src_ref });
                            break;
                        }
                    }
                }
            }
        } else {

            // 循环剥离：提取第一次迭代
            if (enable_peeling) {
                try writer.writeAll("    // Loop peeling: first iteration\n");
                try writer.writeAll("    if (");

                // 生成条件
                if (cond_reg_id) |cond_id| {
                    for (header_block.instructions.items) |inst| {
                        if (inst.result) |result_reg| {
                            if (result_reg.id == cond_id) {
                                try self.writeInlinedConditionExpr(writer, inst);
                                break;
                            }
                        }
                    }
                }

                try writer.writeAll(") {\n");

                // 循环体
                if (!try self.tryOptimizeIncrement(writer, body_block)) {
                    for (body_block.instructions.items) |inst| {
                        const is_invariant = switch (inst.op) {
                            .const_int, .const_float, .const_string, .const_bool, .const_null => true,
                            else => false,
                        };
                        if (!is_invariant) {
                            // 🔥 LICM: 跳过已提升的指令
                            if (!self.isInstructionHoisted(inst)) {
                                try code_list.appendSlice(self.allocator, "        ");
                                try self.generateInstructionSimple(code_list, inst);
                            }
                        }
                    }
                }

                // 增量
                if (loop.increment) |inc_idx| {
                    const inc_block = func.blocks.items[inc_idx];
                    if (!try self.tryOptimizeIncrement(writer, inc_block)) {
                        for (inc_block.instructions.items) |inst| {
                            const is_invariant = switch (inst.op) {
                                .const_int, .const_float, .const_string, .const_bool, .const_null => true,
                                else => false,
                            };
                            if (!is_invariant) {
                                // 🔥 LICM: 跳过已提升的指令
                                if (!self.isInstructionHoisted(inst)) {
                                    try code_list.appendSlice(self.allocator, "        ");
                                    try self.generateInstructionSimple(code_list, inst);
                                }
                            }
                        }
                    }
                }

                try writer.writeAll("    }\n");
            }

            // 主循环（展开）
            if (unroll_factor > 1) {
                try writer.writeAll("    // Unrolled main loop\n");
            }

            // 🔥 初始化 PHI 节点（从 init 块获取初始值）
            for (header_block.instructions.items) |inst| {
                if (inst.op == .phi) {
                    const phi_op = inst.op.phi;
                    if (inst.result) |res| {
                        // 查找循环外来源的 incoming（基于 LoopMetadata）
                        for (phi_op.incoming) |incoming| {
                            if (isInitBlock(incoming.block, loop)) {
                                var src_buf: [32]u8 = undefined;
                                const src_ref = try self.getOperandRef(&src_buf, incoming.value.id);
                                try writer.print("    reg_{d} = {s};\n", .{ res.id, src_ref });
                                break;
                            }
                        }
                    }
                }
            }

            try writer.writeAll("    while (true) {\n");
            try writer.print("        // Header: {s}\n", .{header_block.label});

            // 条件检查（展开时需要确保至少有 unroll_factor 次迭代）
            if (unroll_factor > 1) {
                if (header_block.terminator) |term| {
                    if (term == .cond_br) {
                        if (cond_reg_id) |cond_id| {
                            for (header_block.instructions.items) |inst| {
                                if (inst.result) |result_reg| {
                                    if (result_reg.id == cond_id) {
                                        switch (inst.op) {
                                            .lt => |op| {
                                                const lhs_resolved = self.resolveLoadSource(op.lhs.id);
                                                const rhs_resolved = self.resolveLoadSource(op.rhs.id);
                                                try writer.print("        if (!(reg_{d} + {d} < reg_{d})) {{ @branchHint(.unlikely); break; }}\n", .{ lhs_resolved, unroll_factor - 1, rhs_resolved });
                                            },
                                            else => {
                                                try writer.writeAll("        if (!(");
                                                try self.writeInlinedConditionExpr(writer, inst);
                                                try writer.writeAll(")) { @branchHint(.unlikely); break; }\n");
                                            },
                                        }
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                // 第二遍：生成非常量指令
                for (header_block.instructions.items) |inst| {
                    if (inst.result) |result_reg| {
                        if (cond_reg_id) |cond_id| {
                            if (result_reg.id == cond_id) continue;
                        }
                        // 移除 dead_regs 检查 - 所有指令都需要生成
                    }

                    const is_invariant = switch (inst.op) {
                        .const_int, .const_float, .const_string, .const_bool, .const_null => true,
                        else => false,
                    };

                    if (!is_invariant) {
                        try code_list.appendSlice(self.allocator, "        ");
                        try self.generateInstructionSimple(code_list, inst);
                    }
                }

                if (header_block.terminator) |term| {
                    if (term == .cond_br) {
                        try writer.writeAll("        if (!(");

                        if (cond_reg_id) |cond_id| {
                            for (header_block.instructions.items) |inst| {
                                if (inst.result) |result_reg| {
                                    if (result_reg.id == cond_id) {
                                        try self.writeInlinedConditionExpr(writer, inst);
                                        break;
                                    }
                                }
                            }
                        }

                        try writer.writeAll(")) { @branchHint(.unlikely); break; }\n");
                    }
                }
            }

            try writer.print("        // Body: {s}\n", .{body_block.label});

            // 检测循环体是否为纯常量赋值（死存储）
            const body_is_dead_store = blk: {
                if (unroll_factor == 1) break :blk false;

                // 检查是否只有 load + store（赋值常量）
                var has_only_assign = true;
                for (body_block.instructions.items) |inst| {
                    const is_const = switch (inst.op) {
                        .const_int, .const_float, .const_string, .const_bool, .const_null => true,
                        else => false,
                    };
                    if (!is_const and inst.op != .load and inst.op != .store) {
                        has_only_assign = false;
                        break;
                    }
                }
                break :blk has_only_assign;
            };

            // 循环体（展开 unroll_factor 次）
            // 优化：如果循环体是简单的 reg += 1，合并为 reg += unroll_factor
            const body_is_simple_inc = blk: {
                if (unroll_factor == 1) break :blk false;
                if (body_block.instructions.items.len != 4) break :blk false; // load, const, add, store

                var has_add = false;
                for (body_block.instructions.items) |inst| {
                    if (inst.op == .add) {
                        has_add = true;
                        break;
                    }
                }
                break :blk has_add;
            };

            if (body_is_dead_store) {
                // 死存储：只执行一次赋值
                if (!try self.tryOptimizeIncrement(writer, body_block)) {
                    for (body_block.instructions.items) |inst| {
                        const is_invariant = switch (inst.op) {
                            .const_int, .const_float, .const_string, .const_bool, .const_null => true,
                            else => false,
                        };
                        if (!is_invariant) {
                            try code_list.appendSlice(self.allocator, "        ");
                            try self.generateInstructionSimple(code_list, inst);
                        }
                    }
                }
            } else if (body_is_simple_inc) {
                // 找到 store 指令的目标寄存器
                for (body_block.instructions.items) |inst| {
                    if (inst.op == .store) {
                        const target_reg = inst.op.store.ptr.id;
                        try writer.print("        reg_{d} += {d};\n", .{ target_reg, unroll_factor });
                        break;
                    }
                }
            } else {
                var i: usize = 0;
                while (i < unroll_factor) : (i += 1) {
                    if (!try self.tryOptimizeIncrement(writer, body_block)) {
                        if (body_block.terminator != null and
                            (body_block.terminator.? == .cond_br))
                        {
                            var visited = std.AutoHashMap(usize, void).init(self.allocator);
                            defer visited.deinit();
                            try generateLoopBodyFromBlock(self, writer, code_list, func, loop, phi_updates.items, loop.body_start, &visited, 2, null);
                        } else {
                            for (body_block.instructions.items) |inst| {
                                const is_invariant = switch (inst.op) {
                                    .const_int, .const_float, .const_string, .const_bool, .const_null => true,
                                    else => false,
                                };

                                if (!is_invariant) {
                                    try code_list.appendSlice(self.allocator, "        ");
                                    try self.generateInstructionSimple(code_list, inst);
                                }
                            }
                        }
                    }
                }
            }

            // 增量（一次性增加 unroll_factor）
            if (loop.increment) |inc_idx| {
                const inc_block = func.blocks.items[inc_idx];
                try writer.print("        // Increment: {s} (x{d})\n", .{ inc_block.label, unroll_factor });

                if (unroll_factor > 1) {
                    // 找到 store 指令的目标寄存器
                    for (inc_block.instructions.items) |inst| {
                        if (inst.op == .store) {
                            const target_reg = inst.op.store.ptr.id;
                            // 检查是否是 alloca
                            const is_alloca = if (self.current_alloca_regs) |alloca_regs|
                                alloca_regs.contains(target_reg)
                            else
                                false;

                            if (is_alloca) {
                                try writer.print("        reg_{d}.* = runtime.Value.initInt(reg_{d}.*.asInt() + {d});\n", .{ target_reg, target_reg, unroll_factor });
                            } else {
                                try writer.print("        reg_{d} += {d};\n", .{ target_reg, unroll_factor });
                            }
                            break;
                        }
                    }
                } else {
                    if (!try self.tryOptimizeIncrement(writer, inc_block)) {
                        for (inc_block.instructions.items) |inst| {
                            const is_invariant = switch (inst.op) {
                                .const_int, .const_float, .const_string, .const_bool, .const_null => true,
                                else => false,
                            };

                            if (!is_invariant) {
                                try code_list.appendSlice(self.allocator, "        ");
                                try self.generateInstructionSimple(code_list, inst);
                            }
                        }
                    }
                }
            }

            // 更新 phi 节点的值（在循环末尾）
            for (phi_updates.items) |update| {
                // 移除错误的自增优化
                // if (update.phi_reg == update.value_reg) {
                //     try writer.print("        reg_{d} = try runtime.php_add(reg_{d}, runtime.Value.initInt(1));\n", .{ update.phi_reg, update.phi_reg });
                //     continue;
                // }

                // 检查类型是否匹配
                const phi_type = if (self.current_reg_types) |rt| rt.get(update.phi_reg) orelse IR.Type.php_value else IR.Type.php_value;
                const value_type = if (self.current_reg_types) |rt| rt.get(update.value_reg) orelse IR.Type.php_value else IR.Type.php_value;

                const phi_tag = @as(std.meta.Tag(IR.Type), phi_type);
                const value_tag = @as(std.meta.Tag(IR.Type), value_type);

                var src_buf: [32]u8 = undefined;
                const src_ref = try self.getOperandRef(&src_buf, update.value_reg);

                if (phi_tag == value_tag) {
                    // 类型匹配，直接赋值
                    try writer.print("        reg_{d} = {s};\n", .{ update.phi_reg, src_ref });
                    if (phi_tag == .php_value) {
                        // php_value 需要 retain
                        try writer.print("        _ = reg_{d}.retain();\n", .{update.phi_reg});
                    }
                } else if (phi_tag == .i64 and value_tag == .php_value) {
                    // phi 是 i64，value 是 php_value - 所有寄存器都是 Value，需要包装
                    try writer.print("        reg_{d} = runtime.Value.initInt({s}.asInt());\n", .{ update.phi_reg, src_ref });
                } else if (phi_tag == .f64 and value_tag == .php_value) {
                    try writer.print("        reg_{d} = runtime.Value.initFloat({s}.asFloat());\n", .{ update.phi_reg, src_ref });
                } else if (phi_tag == .bool and value_tag == .php_value) {
                    try writer.print("        reg_{d} = runtime.Value.initBool({s}.toBool());\n", .{ update.phi_reg, src_ref });
                } else if (phi_tag == .php_value and value_tag == .i64) {
                    try writer.print("        reg_{d} = runtime.Value.initInt({s}.asInt());\n", .{ update.phi_reg, src_ref });
                } else if (phi_tag == .php_value and value_tag == .f64) {
                    try writer.print("        reg_{d} = runtime.Value.initFloat({s}.asFloat());\n", .{ update.phi_reg, src_ref });
                } else if (phi_tag == .php_value and value_tag == .bool) {
                    try writer.print("        reg_{d} = runtime.Value.initBool({s}.toBool());\n", .{ update.phi_reg, src_ref });
                } else {
                    // 其他情况，尝试直接赋值
                    try writer.print("        reg_{d} = {s};\n", .{ update.phi_reg, src_ref });
                }
            }

            try writer.writeAll("    }\n");

            // Epilogue：处理剩余迭代（< unroll_factor）
            if (unroll_factor > 1) {
                try writer.writeAll("    // Epilogue: remaining iterations\n");
                try writer.writeAll("    while (true) {\n");
                try writer.print("        // Header: {s}\n", .{header_block.label});

                // 条件检查
                if (header_block.terminator) |term| {
                    if (term == .cond_br) {
                        try writer.writeAll("        if (!(");

                        if (cond_reg_id) |cond_id| {
                            for (header_block.instructions.items) |inst| {
                                if (inst.result) |result_reg| {
                                    if (result_reg.id == cond_id) {
                                        try self.writeInlinedConditionExpr(writer, inst);
                                        break;
                                    }
                                }
                            }
                        }

                        try writer.writeAll(")) { @branchHint(.unlikely); break; }\n");
                    }
                }

                // 循环体
                if (!try self.tryOptimizeIncrement(writer, body_block)) {
                    for (body_block.instructions.items) |inst| {
                        const is_invariant = switch (inst.op) {
                            .const_int, .const_float, .const_string, .const_bool, .const_null => true,
                            else => false,
                        };

                        if (!is_invariant) {
                            try code_list.appendSlice(self.allocator, "        ");
                            try self.generateInstructionSimple(code_list, inst);
                        }
                    }
                }

                // 增量
                if (loop.increment) |inc_idx| {
                    const inc_block = func.blocks.items[inc_idx];
                    if (!try self.tryOptimizeIncrement(writer, inc_block)) {
                        for (inc_block.instructions.items) |inst| {
                            const is_invariant = switch (inst.op) {
                                .const_int, .const_float, .const_string, .const_bool, .const_null => true,
                                else => false,
                            };

                            if (!is_invariant) {
                                try code_list.appendSlice(self.allocator, "        ");
                                try self.generateInstructionSimple(code_list, inst);
                            }
                        }
                    }
                }

                // 更新 phi 节点的值（在循环末尾）
                for (phi_updates.items) |update| {
                    // 检查类型是否匹配
                    const phi_type = if (self.current_reg_types) |rt| rt.get(update.phi_reg) orelse IR.Type.php_value else IR.Type.php_value;
                    const value_type = if (self.current_reg_types) |rt| rt.get(update.value_reg) orelse IR.Type.php_value else IR.Type.php_value;

                    const phi_tag = @as(std.meta.Tag(IR.Type), phi_type);
                    const value_tag = @as(std.meta.Tag(IR.Type), value_type);

                    var src_buf: [32]u8 = undefined;
                    const src_ref = try self.getOperandRef(&src_buf, update.value_reg);

                    if (phi_tag == value_tag) {
                        try writer.print("        reg_{d} = {s};\n", .{ update.phi_reg, src_ref });
                    } else if (phi_tag == .i64 and value_tag == .php_value) {
                        // 所有寄存器都是 Value，需要包装
                        try writer.print("        reg_{d} = runtime.Value.initInt({s}.asInt());\n", .{ update.phi_reg, src_ref });
                    } else if (phi_tag == .f64 and value_tag == .php_value) {
                        try writer.print("        reg_{d} = runtime.Value.initFloat({s}.asFloat());\n", .{ update.phi_reg, src_ref });
                    } else if (phi_tag == .bool and value_tag == .php_value) {
                        try writer.print("        reg_{d} = runtime.Value.initBool({s}.toBool());\n", .{ update.phi_reg, src_ref });
                    } else if (phi_tag == .php_value and value_tag == .i64) {
                        try writer.print("        reg_{d} = runtime.Value.initInt({s}.asInt());\n", .{ update.phi_reg, src_ref });
                    } else if (phi_tag == .php_value and value_tag == .f64) {
                        try writer.print("        reg_{d} = runtime.Value.initFloat({s}.asFloat());\n", .{ update.phi_reg, src_ref });
                    } else if (phi_tag == .php_value and value_tag == .bool) {
                        try writer.print("        reg_{d} = runtime.Value.initBool({s}.toBool());\n", .{ update.phi_reg, src_ref });
                    } else {
                        try writer.print("        reg_{d} = {s};\n", .{ update.phi_reg, src_ref });
                    }
                }

                try writer.writeAll("    }\n");
            }
        } // 完全展开的 else 分支结束
    }

    /// 解析 load 源寄存器（复制传播）
    fn resolveLoadSource(self: *Self, reg_id: usize) usize {
        // 如果寄存器本身是优化的 alloca，直接返回
        if (self.current_optimized_alloca_regs) |opt_regs| {
            if (opt_regs.contains(reg_id)) return reg_id;
        }

        // 否则，检查当前函数的指令，查找 reg_id = load from reg_X
        // 如果 reg_X 是优化的 alloca，返回 reg_X
        if (self.current_function_for_resolve) |func| {
            for (func.blocks.items) |block| {
                for (block.instructions.items) |inst| {
                    if (inst.result) |res| {
                        if (res.id == reg_id and inst.op == .load) {
                            const ptr_id = inst.op.load.ptr.id;
                            if (self.current_optimized_alloca_regs) |opt_regs| {
                                if (opt_regs.contains(ptr_id)) return ptr_id;
                            }
                        }
                    }
                }
            }
        }

        return reg_id;
    }

    fn generateOptimizedForLoop(self: *Self, writer: anytype, func: *const IR.Function, loop: LoopInfo, loop_var_reg: usize) !void {
        // TODO: 实现优化的循环
        // 暂时回退到标准循环
        try self.generateStandardForLoop(writer, func, loop);
        _ = loop_var_reg;
    }

    /// 写布尔表达式到 writer
    fn writeBoolExprToWriter(self: *Self, writer: anytype, type_tag: std.meta.Tag(IR.Type), reg_id: usize) !void {
        _ = self;

        switch (type_tag) {
            .i64 => try writer.print("reg_{d}.asInt() != 0", .{reg_id}),
            .f64 => try writer.print("reg_{d}.asFloat() != 0.0", .{reg_id}),
            .bool => try writer.print("reg_{d}.toBool()", .{reg_id}), // 所有寄存器都是 Value
            .php_value => try writer.print("reg_{d}.toBool()", .{reg_id}),
            else => try writer.print("reg_{d}.toBool()", .{reg_id}),
        }
    }

    /// 内联条件表达式（用于结构化循环优化）
    fn writeInlinedConditionExpr(self: *Self, writer: anytype, inst: *const IR.Instruction) !void {
        switch (inst.op) {
            .cast => |op| {
                // cast 到 bool：内联为 .asBool()
                if (op.to_type == .bool) {
                    try writer.print("reg_{d}.asBool()", .{op.value.id});
                } else {
                    // 其他 cast：使用寄存器
                    if (inst.result) |reg| {
                        try writer.print("reg_{d}", .{reg.id});
                    }
                }
            },
            .lt => |op| {
                const lhs_corrected = if (self.current_register_types) |types|
                    types.get(op.lhs.id) orelse op.lhs.type_
                else
                    op.lhs.type_;
                const rhs_corrected = if (self.current_register_types) |types|
                    types.get(op.rhs.id) orelse op.rhs.type_
                else
                    op.rhs.type_;

                const lhs_type_tag = @as(std.meta.Tag(IR.Type), lhs_corrected);
                const rhs_type_tag = @as(std.meta.Tag(IR.Type), rhs_corrected);

                // 检查实际寄存器类型（所有寄存器都是 Value）
                // 如果推断类型是 i64/f64，需要转换
                if (lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                    // 复制传播：解析操作数
                    const lhs_id = self.resolveLoadSource(op.lhs.id);
                    const rhs_id = self.resolveLoadSource(op.rhs.id);
                    try writer.print("reg_{d}.asInt() < reg_{d}.asInt()", .{ lhs_id, rhs_id });
                } else if (lhs_type_tag == .f64 and rhs_type_tag == .f64) {
                    const lhs_id = self.resolveLoadSource(op.lhs.id);
                    const rhs_id = self.resolveLoadSource(op.rhs.id);
                    try writer.print("reg_{d}.asFloat() < reg_{d}.asFloat()", .{ lhs_id, rhs_id });
                } else {
                    try writer.writeAll("(try runtime.php_lt(");
                    try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                    try writer.writeAll(", ");
                    try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                    try writer.writeAll(")).toBool()");
                }
            },
            .le => |op| {
                const lhs_corrected = if (self.current_register_types) |types|
                    types.get(op.lhs.id) orelse op.lhs.type_
                else
                    op.lhs.type_;
                const rhs_corrected = if (self.current_register_types) |types|
                    types.get(op.rhs.id) orelse op.rhs.type_
                else
                    op.rhs.type_;

                const lhs_type_tag = @as(std.meta.Tag(IR.Type), lhs_corrected);
                const rhs_type_tag = @as(std.meta.Tag(IR.Type), rhs_corrected);

                if (lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                    try writer.print("reg_{d}.asInt() <= reg_{d}.asInt()", .{ op.lhs.id, op.rhs.id });
                } else if (lhs_type_tag == .f64 and rhs_type_tag == .f64) {
                    try writer.print("reg_{d}.asFloat() <= reg_{d}.asFloat()", .{ op.lhs.id, op.rhs.id });
                } else {
                    try writer.writeAll("(try runtime.php_le(");
                    try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                    try writer.writeAll(", ");
                    try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                    try writer.writeAll(")).toBool()");
                }
            },
            .gt => |op| {
                const lhs_corrected = if (self.current_register_types) |types|
                    types.get(op.lhs.id) orelse op.lhs.type_
                else
                    op.lhs.type_;
                const rhs_corrected = if (self.current_register_types) |types|
                    types.get(op.rhs.id) orelse op.rhs.type_
                else
                    op.rhs.type_;

                const lhs_type_tag = @as(std.meta.Tag(IR.Type), lhs_corrected);
                const rhs_type_tag = @as(std.meta.Tag(IR.Type), rhs_corrected);

                if (lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                    try writer.print("reg_{d}.asInt() > reg_{d}.asInt()", .{ op.lhs.id, op.rhs.id });
                } else if (lhs_type_tag == .f64 and rhs_type_tag == .f64) {
                    try writer.print("reg_{d}.asFloat() > reg_{d}.asFloat()", .{ op.lhs.id, op.rhs.id });
                } else {
                    try writer.writeAll("(try runtime.php_gt(");
                    try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                    try writer.writeAll(", ");
                    try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                    try writer.writeAll(")).toBool()");
                }
            },
            .ge => |op| {
                const lhs_corrected = if (self.current_register_types) |types|
                    types.get(op.lhs.id) orelse op.lhs.type_
                else
                    op.lhs.type_;
                const rhs_corrected = if (self.current_register_types) |types|
                    types.get(op.rhs.id) orelse op.rhs.type_
                else
                    op.rhs.type_;

                const lhs_type_tag = @as(std.meta.Tag(IR.Type), lhs_corrected);
                const rhs_type_tag = @as(std.meta.Tag(IR.Type), rhs_corrected);

                if (lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                    try writer.print("reg_{d}.asInt() >= reg_{d}.asInt()", .{ op.lhs.id, op.rhs.id });
                } else if (lhs_type_tag == .f64 and rhs_type_tag == .f64) {
                    try writer.print("reg_{d}.asFloat() >= reg_{d}.asFloat()", .{ op.lhs.id, op.rhs.id });
                } else {
                    try writer.writeAll("(try runtime.php_ge(");
                    try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                    try writer.writeAll(", ");
                    try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                    try writer.writeAll(")).toBool()");
                }
            },
            .eq => |op| {
                const lhs_corrected = if (self.current_register_types) |types|
                    types.get(op.lhs.id) orelse op.lhs.type_
                else
                    op.lhs.type_;
                const rhs_corrected = if (self.current_register_types) |types|
                    types.get(op.rhs.id) orelse op.rhs.type_
                else
                    op.rhs.type_;

                const lhs_type_tag = @as(std.meta.Tag(IR.Type), lhs_corrected);
                const rhs_type_tag = @as(std.meta.Tag(IR.Type), rhs_corrected);

                if (lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                    try writer.print("reg_{d}.asInt() == reg_{d}.asInt()", .{ op.lhs.id, op.rhs.id });
                } else {
                    try writer.writeAll("(try runtime.php_eq(");
                    try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                    try writer.writeAll(", ");
                    try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                    try writer.writeAll(")).toBool()");
                }
            },
            .ne => |op| {
                const lhs_corrected = if (self.current_register_types) |types|
                    types.get(op.lhs.id) orelse op.lhs.type_
                else
                    op.lhs.type_;
                const rhs_corrected = if (self.current_register_types) |types|
                    types.get(op.rhs.id) orelse op.rhs.type_
                else
                    op.rhs.type_;

                const lhs_type_tag = @as(std.meta.Tag(IR.Type), lhs_corrected);
                const rhs_type_tag = @as(std.meta.Tag(IR.Type), rhs_corrected);

                if (lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                    try writer.print("reg_{d} != reg_{d}", .{ op.lhs.id, op.rhs.id });
                } else {
                    try writer.writeAll("(try runtime.php_ne(");
                    try self.writePhpValueExpr(writer, lhs_type_tag, op.lhs.id);
                    try writer.writeAll(", ");
                    try self.writePhpValueExpr(writer, rhs_type_tag, op.rhs.id);
                    try writer.writeAll(")).toBool()");
                }
            },
            else => {
                // 其他操作，回退到寄存器
                if (inst.result) |reg| {
                    const reg_type = self.current_reg_types.?.get(reg.id) orelse IR.Type{ .php_value = {} };
                    const type_tag = @as(std.meta.Tag(IR.Type), reg_type);
                    try self.writeBoolExprToWriter(writer, type_tag, reg.id);
                }
            },
        }
    }

    /// 控制流分析结果
    const ControlFlowAnalysis = struct {
        allocator: std.mem.Allocator,
        /// 顶层循环信息
        loops: std.ArrayList(LoopInfo),
        /// 所有循环（包括子循环）
        all_loops: std.ArrayList(LoopInfo),
        /// 支配树（用于确定块的嵌套关系）
        dominators: std.AutoHashMap(usize, usize),
        /// 后继块映射
        successors: std.AutoHashMap(usize, std.ArrayList(usize)),
        /// 前驱块映射
        predecessors: std.AutoHashMap(usize, std.ArrayList(usize)),

        fn init(allocator: std.mem.Allocator) ControlFlowAnalysis {
            return .{
                .allocator = allocator,
                .loops = std.ArrayList(LoopInfo){},
                .all_loops = std.ArrayList(LoopInfo){},
                .dominators = std.AutoHashMap(usize, usize).init(allocator),
                .successors = std.AutoHashMap(usize, std.ArrayList(usize)).init(allocator),
                .predecessors = std.AutoHashMap(usize, std.ArrayList(usize)).init(allocator),
            };
        }

        fn deinit(self: *ControlFlowAnalysis) void {
            self.loops.deinit(self.allocator);
            for (self.all_loops.items) |*loop| {
                loop.deinit(self.allocator);
            }
            self.all_loops.deinit(self.allocator);
            self.dominators.deinit();

            var succ_iter = self.successors.valueIterator();
            while (succ_iter.next()) |list| {
                list.deinit(self.allocator);
            }
            self.successors.deinit();

            var pred_iter = self.predecessors.valueIterator();
            while (pred_iter.next()) |list| {
                list.deinit(self.allocator);
            }
            self.predecessors.deinit();
        }
    };

    /// 循环信息
    const LoopInfo = struct {
        header: usize, // 循环头（条件块）
        body_start: usize, // 循环体起始块
        body_end: usize, // 循环体结束块
        exit_block: ?usize, // 循环出口块
        increment: ?usize, // 增量块（for 循环）
        is_for_loop: bool, // 是否是 for 循环
        parent: ?usize = null, // 父循环索引
        children: std.ArrayList(usize), // 子循环索引列表
        blocks: std.AutoHashMap(usize, void), // 所有属于此循环的块

        pub fn init(allocator: Allocator) !LoopInfo {
            return .{
                .header = 0,
                .body_start = 0,
                .body_end = 0,
                .exit_block = null,
                .increment = null,
                .is_for_loop = false,
                .parent = null,
                .children = try std.ArrayList(usize).initCapacity(allocator, 0),
                .blocks = std.AutoHashMap(usize, void).init(allocator),
            };
        }

        pub fn deinit(self: *LoopInfo, allocator: Allocator) void {
            self.children.deinit(allocator);
            self.blocks.deinit();
        }

        pub fn contains(self: *const LoopInfo, block_idx: usize) bool {
            return self.blocks.contains(block_idx);
        }
    };

    /// 尝试生成结构化控制流（最激进的优化）
    ///
    /// 策略：
    /// 1. 分析控制流图，构建前驱/后继关系
    /// 2. 检测循环（回边分析）
    /// 3. 识别循环类型（for/while）
    /// 4. 直接生成结构化代码
    ///
    /// 返回true表示成功生成，false表示需要回退到状态机
    fn tryGenerateStructuredControlFlow(self: *Self, writer: anytype, func: *const IR.Function, cleanup_regs: []const usize) !bool {
        // std.debug.print("=== tryGenerateStructuredControlFlow: blocks={d} ===\n", .{func.blocks.items.len});

        // 分析控制流
        var cfg = ControlFlowAnalysis.init(self.allocator);
        defer cfg.deinit();

        // 构建前驱/后继关系
        try self.buildCFG(func, &cfg);
        // std.debug.print("CFG built\n", .{});

        // 检测循环
        try self.detectLoops(func, &cfg);

        // 如果没有检测到循环，返回 false
        if (cfg.loops.items.len == 0) {
            // std.debug.print("No loops detected, falling back to state machine\n", .{});
            return false;
        }

        // 生成结构化代码
        const result = try self.generateStructuredCode(writer, func, &cfg, cleanup_regs);
        // std.debug.print("generateStructuredCode returned: {}\n", .{result});
        return result;
    }

    /// 构建控制流图（CFG）
    fn buildCFG(self: *Self, func: *const IR.Function, cfg: *ControlFlowAnalysis) !void {
        // std.debug.print("buildCFG: blocks={d}\n", .{func.blocks.items.len});

        // 第一步：为所有块初始化后继和前驱列表
        for (0..func.blocks.items.len) |idx| {
            const succ_list = try std.ArrayList(usize).initCapacity(self.allocator, 0);
            const pred_list = try std.ArrayList(usize).initCapacity(self.allocator, 0);
            try cfg.successors.put(idx, succ_list);
            try cfg.predecessors.put(idx, pred_list);
        }

        // 第二步：分析终止指令，添加后继关系
        for (func.blocks.items, 0..) |block, idx| {
            // std.debug.print("  Block {d}: {s}, term={}\n", .{ idx, block.label, block.terminator != null });

            if (block.terminator) |term| {
                switch (term) {
                    .br => |target| {
                        const target_idx = self.findBlockIndex(func, target);
                        try cfg.successors.getPtr(idx).?.append(self.allocator, target_idx);
                        try cfg.predecessors.getPtr(target_idx).?.append(self.allocator, idx);
                    },
                    .cond_br => |cond_br| {
                        const then_idx = self.findBlockIndex(func, cond_br.then_block);
                        const else_idx = self.findBlockIndex(func, cond_br.else_block);

                        try cfg.successors.getPtr(idx).?.append(self.allocator, then_idx);
                        try cfg.successors.getPtr(idx).?.append(self.allocator, else_idx);

                        try cfg.predecessors.getPtr(then_idx).?.append(self.allocator, idx);
                        try cfg.predecessors.getPtr(else_idx).?.append(self.allocator, idx);
                    },
                    .switch_ => |switch_data| {
                        for (switch_data.cases) |case| {
                            const case_idx = self.findBlockIndex(func, case.block);
                            try cfg.successors.getPtr(idx).?.append(self.allocator, case_idx);
                            try cfg.predecessors.getPtr(case_idx).?.append(self.allocator, idx);
                        }
                        const default_idx = self.findBlockIndex(func, switch_data.default);
                        try cfg.successors.getPtr(idx).?.append(self.allocator, default_idx);
                        try cfg.predecessors.getPtr(default_idx).?.append(self.allocator, idx);
                    },
                    .ret, .throw, .unreachable_ => {
                        // 没有后继
                    },
                }
            } else if (idx + 1 < func.blocks.items.len) {
                // 没有终止指令，fallthrough 到下一个块
                try cfg.successors.getPtr(idx).?.append(self.allocator, idx + 1);
                try cfg.predecessors.getPtr(idx + 1).?.append(self.allocator, idx);
            }
        }
    }

    /// 检测循环（回边分析）
    /// 递归收集所有循环（包括子循环）
    fn collectAllLoops(self: *Self, loops: []const LoopInfo, result: *std.ArrayList(*const LoopInfo)) !void {
        _ = self;
        for (loops) |*loop| {
            try result.append(result.allocator, loop);
            // 子循环的索引存储在 loop.children 中
            // 但我们需要从 cfg.all_loops 中获取
            // 这里简化：只收集顶层循环，子循环通过 children 索引访问
        }
    }

    /// 递归生成循环（包括子循环）
    fn generateLoopRecursive(
        self: *Self,
        writer: anytype,
        func: *const IR.Function,
        loop: LoopInfo,
        processed: *std.AutoHashMap(usize, void),
        block_to_loop: *std.AutoHashMap(usize, usize),
        all_loops: []const LoopInfo,
        cleanup_regs: []const usize,
        depth: usize,
    ) !void {
        std.debug.print("generateLoopRecursive: header={d}, is_for={}, children={d}, depth={d}\n", .{ loop.header, loop.is_for_loop, loop.children.items.len, depth });

        // 标记循环块为已处理
        try processed.put(loop.header, {});
        if (loop.increment) |inc| try processed.put(inc, {});

        // 生成循环结构
        if (loop.is_for_loop) {
            std.debug.print("  -> calling generateForLoopWithChildren\n", .{});
            try self.generateForLoopWithChildren(writer, func, loop, processed, block_to_loop, all_loops, cleanup_regs, depth);
        } else {
            std.debug.print("  -> calling generateWhileLoopWithChildren\n", .{});
            try self.generateWhileLoopWithChildren(writer, func, loop, processed, block_to_loop, all_loops, cleanup_regs);
        }
    }

    // ============================================================================
    // 旧的嵌套循环代码生成（已废弃，保留用于回溯）
    // 标记：DEPRECATED_NESTED_LOOP_V1
    // 废弃原因：PHI 节点处理过于复杂，累加器值传递链断裂
    // 重写版本：generateForLoopWithChildrenV2
    // ============================================================================

    /// 生成 for 循环（支持子循环）- V1 已废弃
    /// @deprecated 使用新的 generateForLoopWithChildren (V2)
    /// 此函数已被禁用，如果被调用会产生编译错误
    /// 生成 for 循环（支持子循环）- V1 已废弃
    /// @deprecated 使用新的 generateForLoopWithChildren (V2)
    fn generateForLoopWithChildren_DEPRECATED_V1(
        self: *Self,
        writer: anytype,
        func: *const IR.Function,
        loop: LoopInfo,
        processed: *std.AutoHashMap(usize, void),
        block_to_loop: *std.AutoHashMap(usize, usize),
        all_loops: []const LoopInfo,
        cleanup_regs: []const usize,
    ) anyerror!void {
        _ = self;
        _ = writer;
        _ = func;
        _ = loop;
        _ = processed;
        _ = block_to_loop;
        _ = all_loops;
        _ = cleanup_regs;
        @compileError("DEPRECATED: Use generateForLoopWithChildren V2 instead");
    }
    // 旧函数体已移除，保存在 git tag: before-nested-loop-rewrite

    /// 累加器信息
    const AccumulatorInfo = struct {
        reg_id: usize,
        type_: IR.Type,
        init_reg: ?usize,
    };

    /// 判断一个 PHI incoming 块是否为循环外初始值来源
    /// 优先使用 LoopMetadata.role，回退到循环块包含检查
    fn isInitBlock(
        incoming_block: *const IR.BasicBlock,
        loop: LoopInfo,
    ) bool {
        // 优先：基于 LoopMetadata 判断
        const role = incoming_block.loop_metadata.role;
        if (role == .init) return true;
        if (role == .header or role == .body or role == .latch or role == .exit) return false;

        // 回退：role == .none 时，检查是否在循环块集合中
        // 不在循环块集合中的即为 init
        return !loop.contains(incoming_block.index);
    }

    /// 查找寄存器的定义指令
    fn findRegDef(
        func: *const IR.Function,
        reg_id: usize,
    ) ?*const IR.Instruction {
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.result) |r| {
                    if (r.id == reg_id) return inst;
                }
            }
        }
        return null;
    }

    /// 检查寄存器是否是循环归纳变量（递增常量步长）
    fn isInductionVar(
        func: *const IR.Function,
        loop_value_reg: usize,
    ) bool {
        const def = findRegDef(func, loop_value_reg) orelse
            return false;
        if (def.op != .add) return false;
        const rhs_def = findRegDef(
            func,
            def.op.add.rhs.id,
        ) orelse return false;
        return rhs_def.op == .const_int;
    }

    fn analyzeLoopAccumulators(
        self: *Self,
        func: *const IR.Function,
        loop: LoopInfo,
    ) !std.ArrayList(AccumulatorInfo) {
        var accumulators = try std.ArrayList(AccumulatorInfo)
            .initCapacity(self.allocator, 0);

        const header_block = func.blocks.items[loop.header];

        for (header_block.instructions.items) |inst| {
            if (inst.op != .phi) continue;
            const phi_op = inst.op.phi;
            const result_reg = inst.result orelse continue;
            if (phi_op.incoming.len < 2) continue;

            var init_value: ?usize = null;
            var loop_value: ?usize = null;

            for (phi_op.incoming) |incoming| {
                if (isInitBlock(incoming.block, loop)) {
                    init_value = incoming.value.id;
                } else {
                    loop_value = incoming.value.id;
                }
            }

            // 回退：如果仍未区分，首项为 init
            if (init_value == null and loop_value == null and
                phi_op.incoming.len >= 2)
            {
                init_value = phi_op.incoming[0].value.id;
                loop_value = phi_op.incoming[1].value.id;
            }

            if (loop_value) |lv| {
                if (!isInductionVar(func, lv)) {
                    try accumulators.append(self.allocator, .{
                        .reg_id = result_reg.id,
                        .type_ = result_reg.type_,
                        .init_reg = init_value,
                    });
                }
            }
        }

        return accumulators;
    }

    /// 生成 for 循环（支持子循环）- V2 新实现
    fn generateForLoopWithChildren(
        self: *Self,
        writer: anytype,
        func: *const IR.Function,
        loop: LoopInfo,
        processed: *std.AutoHashMap(usize, void),
        block_to_loop: *std.AutoHashMap(usize, usize),
        all_loops: []const LoopInfo,
        cleanup_regs: []const usize,
        depth: usize,
    ) anyerror!void {
        // TODO: 使用 depth 生成动态缩进
        // var indent_buf: [256]u8 = undefined;
        // var indent_len: usize = 0;
        // var d: usize = 0;
        // while (d <= depth) : (d += 1) {
        //     @memcpy(indent_buf[indent_len..][0..4], "    ");
        //     indent_len += 4;
        // }
        // const base_indent = indent_buf[0..indent_len];

        std.debug.print("=== V2: generateForLoopWithChildren header={d}, children={d}, depth={d} ===\n", .{ loop.header, loop.children.items.len, depth });

        // 分析当前循环的累加器
        var accumulators = try self.analyzeLoopAccumulators(func, loop);
        defer accumulators.deinit(self.allocator);

        // 如果没有子循环，根据 body 是否包含 cond_br 选择不同路径：
        // - 无 cond_br：走 StructuredNew（更紧凑）
        // - 有 cond_br：走 generateStandardForLoop（覆盖 break/continue 等控制流）
        // 这里仍需初始化 PHI 节点。
        const body_block = func.blocks.items[loop.body_start];
        const body_has_cond = if (body_block.terminator) |term| term == .cond_br else false;

        if (loop.children.items.len == 0) {
            // 简化路径：无子循环，无条件分支
            // 但仍需初始化 PHI 节点
            const header_block = func.blocks.items[loop.header];

            // 初始化 PHI 节点（从循环外块获取初始值）
            for (header_block.instructions.items) |inst| {
                if (inst.op == .phi) {
                    const phi_op = inst.op.phi;
                    if (inst.result) |res| {
                        for (phi_op.incoming) |incoming| {
                            if (isInitBlock(incoming.block, loop)) {
                                var src_buf: [32]u8 = undefined;
                                const src_ref = try self.getOperandRef(&src_buf, incoming.value.id);
                                try writer.print("        reg_{d} = {s};\n", .{ res.id, src_ref });
                                break;
                            }
                        }
                    }
                }
            }

            if (body_has_cond) {
                try self.generateForLoopStructured(writer, func, loop, cleanup_regs);
            } else {
                try self.generateForLoopStructuredNew(writer, func, loop, cleanup_regs);
            }
            return;
        }

        // 有子循环：使用新的生成策略
        var code_list = writer.context.self;

        const header_block = func.blocks.items[loop.header];

        // 初始化 PHI 寄存器（从 init 块 incoming 获取初始值）
        for (header_block.instructions.items) |inst| {
            if (inst.op == .phi) {
                const phi_op = inst.op.phi;
                if (inst.result) |res| {
                    for (phi_op.incoming) |incoming| {
                        if (isInitBlock(incoming.block, loop)) {
                            var src_buf: [32]u8 = undefined;
                            const src_ref = try self.getOperandRef(&src_buf, incoming.value.id);
                            try writer.print("    reg_{d} = {s};\n", .{ res.id, src_ref });
                            break;
                        }
                    }
                }
            }
        }

        // 生成外层循环结构
        try writer.writeAll("    while (true) {\n");
        try writer.print("        // Header: {s}\n", .{header_block.label});

        // 生成 header 指令
        for (header_block.instructions.items) |inst| {
            try code_list.appendSlice(self.allocator, "        ");
            try self.generateInstructionSimple(code_list, inst);
        }

        // 生成条件判断
        if (header_block.terminator) |term| {
            if (term == .cond_br) {
                try writer.writeAll("        if (!(");
                for (header_block.instructions.items) |inst| {
                    if (inst.result) |result_reg| {
                        if (term.cond_br.cond.id == result_reg.id) {
                            try self.writeInlinedConditionExpr(writer, inst);
                            break;
                        }
                    }
                }
                try writer.writeAll(")) break;\n");
            }
        }

        // 生成 body
        try writer.print("        // Body: {s}\n", .{body_block.label});
        for (body_block.instructions.items) |inst| {
            try code_list.appendSlice(self.allocator, "        ");
            try self.generateInstructionSimple(code_list, inst);
        }

        // 计算当前循环的 exit 块索引（cond_br 的 false target）
        // 用于过滤被误识别为子循环的 exit 块
        const exit_block_idx: ?usize = if (header_block.terminator) |term| blk: {
            if (term == .cond_br) {
                break :blk @as(usize, term.cond_br.else_block.index);
            }
            break :blk null;
        } else null;

        // 规范化 increment 块：优先使用非 _unroll_ 的原始块，避免引用展开寄存器
        var effective_inc_idx: ?usize = loop.increment;
        if (loop.increment) |inc_idx| {
            const raw_inc_block = func.blocks.items[inc_idx];
            const is_unroll_inc = std.mem.indexOf(u8, raw_inc_block.label, "_unroll_") != null;
            if (is_unroll_inc) {
                if (findOriginalBlockLabel(raw_inc_block.label)) |orig_label| {
                    for (func.blocks.items) |candidate| {
                        const candidate_is_unroll = std.mem.indexOf(u8, candidate.label, "_unroll_") != null;
                        if (!candidate_is_unroll and std.mem.eql(u8, candidate.label, orig_label)) {
                            effective_inc_idx = @as(usize, candidate.index);
                            break;
                        }
                    }
                }
            }
        }

        // 生成子循环
        for (loop.children.items) |child_idx| {
            const child_loop = all_loops[child_idx];

            // 跳过被误识别为循环的 exit 块（unroll 假阳性）
            if (exit_block_idx) |exit_idx| {
                if (child_loop.header == exit_idx) {
                    std.debug.print("  [SKIP] child loop header={d} is exit block, skipping\n", .{child_loop.header});
                    continue;
                }
            }

            try writer.writeAll("        // Nested loop\n");
            try self.generateLoopRecursive(writer, func, child_loop, processed, block_to_loop, all_loops, cleanup_regs, depth + 1);

            // 生成 increment 块
            if (effective_inc_idx) |inc_idx| {
                const inc_block = func.blocks.items[inc_idx];
                try writer.print("        // Increment: {s}\n", .{inc_block.label});
                for (inc_block.instructions.items) |inst| {
                    if (inst.op != .phi) { // PHI 在后面统一处理
                        try code_list.appendSlice(self.allocator, "        ");
                        try self.generateInstructionSimple(code_list, inst);
                    }
                }
            }

            // 更新所有 PHI 节点
            for (header_block.instructions.items) |inst| {
                if (inst.op == .phi) {
                    const phi_op = inst.op.phi;
                    const result_reg = inst.result orelse continue;

                    std.debug.print("  PHI reg_{d}: checking incoming for update\n", .{result_reg.id});
                    if (effective_inc_idx) |inc_idx| {
                        std.debug.print("    increment block index: {d}\n", .{inc_idx});
                    }
                    for (phi_op.incoming) |incoming| {
                        std.debug.print("    incoming: reg_{d} from block_{d}\n", .{ incoming.value.id, incoming.block.index });
                    }

                    // 找到来自 increment 或 body 的值
                    var update_value: ?usize = null;
                    if (effective_inc_idx) |inc_idx| {
                        const inc_block = func.blocks.items[inc_idx];
                        for (phi_op.incoming) |incoming| {
                            if (incoming.block == inc_block) {
                                update_value = incoming.value.id;
                                std.debug.print("    -> Found update from increment: reg_{d}\n", .{update_value.?});
                                break;
                            }
                        }
                    }

                    if (update_value == null) {
                        for (phi_op.incoming) |incoming| {
                            if (incoming.block == body_block) {
                                update_value = incoming.value.id;
                                break;
                            }
                        }
                    }

                    // 判定当前 PHI 是否为循环条件变量（如 i < N 里的 i）
                    var is_loop_var = false;
                    for (header_block.instructions.items) |cond_inst| {
                        switch (cond_inst.op) {
                            .lt, .le, .gt, .ge => |op| {
                                if (op.lhs.id == result_reg.id or op.rhs.id == result_reg.id) {
                                    is_loop_var = true;
                                    break;
                                }
                            },
                            else => {},
                        }
                    }

                    if (update_value) |val_reg| {
                        // 解析展开块寄存器：当 val_reg 定义在 _unroll_* 块中时，
                        // 追踪到原始块中的等价寄存器
                        const resolved_reg = self.resolveUnrolledReg(func, val_reg, loop);
                        const phi_type = self.getInferredRegType(result_reg.id, result_reg.type_);
                        const value_type = self.getInferredRegType(resolved_reg, IR.Type.php_value);

                        const phi_tag = @as(std.meta.Tag(IR.Type), phi_type);
                        const value_tag = @as(std.meta.Tag(IR.Type), value_type);

                        // 移除错误的循环变量优化
                        // if (is_loop_var) {
                        //     try writer.print("        reg_{d} = try runtime.php_add(reg_{d}, runtime.Value.initInt(1));\n", .{ result_reg.id, result_reg.id });
                        // } else {
                        var src_buf: [32]u8 = undefined;
                        const src_ref = try self.getOperandRef(&src_buf, resolved_reg);

                        if (phi_tag == value_tag) {
                            try writer.print("        reg_{d} = {s};\n", .{ result_reg.id, src_ref });
                        } else if (phi_tag == .i64 and value_tag == .php_value) {
                            // 所有寄存器都是 Value，需要包装
                            try writer.print("        reg_{d} = runtime.Value.initInt({s}.asInt());\n", .{ result_reg.id, src_ref });
                        } else if (phi_tag == .f64 and value_tag == .php_value) {
                            try writer.print("        reg_{d} = runtime.Value.initFloat({s}.asFloat());\n", .{ result_reg.id, src_ref });
                        } else if (phi_tag == .bool and value_tag == .php_value) {
                            try writer.print("        reg_{d} = runtime.Value.initBool({s}.toBool());\n", .{ result_reg.id, src_ref });
                        } else if (phi_tag == .php_value and value_tag == .i64) {
                            try writer.print("        reg_{d} = runtime.Value.initInt({s}.asInt());\n", .{ result_reg.id, src_ref });
                        } else if (phi_tag == .php_value and value_tag == .f64) {
                            try writer.print("        reg_{d} = runtime.Value.initFloat({s}.asFloat());\n", .{ result_reg.id, src_ref });
                        } else if (phi_tag == .php_value and value_tag == .bool) {
                            try writer.print("        reg_{d} = runtime.Value.initBool({s}.toBool());\n", .{ result_reg.id, src_ref });
                        } else {
                            try writer.print("        reg_{d} = {s};\n", .{ result_reg.id, src_ref });
                        }
                        // }
                    }
                }
            }

            try writer.writeAll("    }\n");
        }
    }

    /// 从展开块标签中提取原始块名
    /// 格式：_unroll_N_<original_label> → <original_label>
    fn findOriginalBlockLabel(unroll_label: []const u8) ?[]const u8 {
        // 查找 "_unroll_" 前缀
        const prefix = "_unroll_";
        if (!std.mem.startsWith(u8, unroll_label, prefix)) return null;
        const after_prefix = unroll_label[prefix.len..];
        // 跳过数字 N
        var i: usize = 0;
        while (i < after_prefix.len and after_prefix[i] >= '0' and after_prefix[i] <= '9') : (i += 1) {}
        // 跳过下划线分隔符
        if (i < after_prefix.len and after_prefix[i] == '_') {
            return after_prefix[i + 1 ..];
        }
        return null;
    }

    /// 解析展开块中的寄存器到原始块中的等价寄存器（深度增强版）
    /// 当 IR 优化器展开循环（_unroll_*）后，PHI incoming 可能引用展开块中的寄存器，
    /// 但代码生成器只处理原始块。此函数追踪定义链回到已处理块。
    ///
    /// 增强功能：
    /// - 支持 PHI 节点的位置匹配
    /// - 支持 move 指令的源寄存器追踪
    /// - 支持 add/sub/mul/div 等运算指令的操作数追踪
    /// - 递归解析操作数链，直到找到原始块寄存器
    /// - 循环检测和深度限制，防止无限递归
    fn resolveUnrolledReg(
        self: *Self,
        func: *const IR.Function,
        reg_id: usize,
        loop: LoopInfo,
    ) usize {
        // 使用访问集合防止循环
        var visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer visited.deinit();

        return self.resolveUnrolledRegWithDepth(func, reg_id, loop, &visited, 0) catch reg_id;
    }

    /// 带深度限制的递归解析函数
    fn resolveUnrolledRegWithDepth(
        self: *Self,
        func: *const IR.Function,
        reg_id: usize,
        loop: LoopInfo,
        visited: *std.AutoHashMap(usize, void),
        depth: usize,
    ) std.mem.Allocator.Error!usize {
        // 深度限制：防止无限递归
        const max_depth = 50;
        if (depth >= max_depth) {
            std.debug.print("resolveUnrolledReg: max depth reached for reg_{d}\n", .{reg_id});
            return reg_id;
        }

        // 循环检测：如果已访问过此寄存器，直接返回
        if (visited.contains(reg_id)) {
            return reg_id;
        }
        try visited.put(reg_id, {});

        // 查找 reg_id 的定义块和指令
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst_item| {
                if (inst_item.result) |res| {
                    if (res.id == reg_id) {
                        // 检查定义块是否是展开块（_unroll_* 前缀）
                        const is_unroll_block = std.mem.indexOf(u8, block.label, "_unroll_") != null;

                        if (is_unroll_block) {
                            std.debug.print("resolveUnrolledReg: reg_{d} defined in unroll block {s}\n", .{ reg_id, block.label });

                            // 策略 1: PHI 节点 - 通过位置匹配找到原始块的 PHI
                            if (inst_item.op == .phi) {
                                const unroll_label = block.label;
                                if (findOriginalBlockLabel(unroll_label)) |orig_label| {
                                    for (func.blocks.items) |orig_block| {
                                        if (std.mem.eql(u8, orig_block.label, orig_label)) {
                                            var phi_idx: usize = 0;
                                            var target_phi_idx: usize = 0;
                                            for (block.instructions.items) |blk_inst| {
                                                if (blk_inst.op == .phi) {
                                                    if (blk_inst.result) |br_res| {
                                                        if (br_res.id == reg_id) {
                                                            target_phi_idx = phi_idx;
                                                            break;
                                                        }
                                                    }
                                                    phi_idx += 1;
                                                }
                                            }
                                            var orig_phi_idx: usize = 0;
                                            for (orig_block.instructions.items) |oi| {
                                                if (oi.op == .phi) {
                                                    if (orig_phi_idx == target_phi_idx) {
                                                        if (oi.result) |orig_res| {
                                                            std.debug.print("  -> Resolved PHI: reg_{d} -> reg_{d}\n", .{ reg_id, orig_res.id });
                                                            return orig_res.id;
                                                        }
                                                    }
                                                    orig_phi_idx += 1;
                                                }
                                            }
                                            break;
                                        }
                                    }
                                }
                            }

                            // 策略 2: 对于展开块，通过指令位置匹配找到原始块的对应寄存器
                            const unroll_label = block.label;
                            if (findOriginalBlockLabel(unroll_label)) |orig_label| {
                                for (func.blocks.items) |orig_block| {
                                    if (std.mem.eql(u8, orig_block.label, orig_label)) {
                                        // 找到原始块，计算当前指令在展开块中的位置
                                        var inst_idx: usize = 0;
                                        var target_inst_idx: usize = 0;
                                        for (block.instructions.items, 0..) |blk_inst, idx| {
                                            if (blk_inst.result) |blk_res| {
                                                if (blk_res.id == reg_id) {
                                                    target_inst_idx = inst_idx;
                                                    std.debug.print("  Found at instruction index {d} in unroll block\n", .{idx});
                                                    break;
                                                }
                                            }
                                            if (blk_inst.op != .phi) inst_idx += 1;
                                        }

                                        // 在原始块中找同位置的指令（跳过 PHI）
                                        var orig_inst_idx: usize = 0;
                                        for (orig_block.instructions.items) |orig_inst| {
                                            if (orig_inst.op != .phi) {
                                                if (orig_inst_idx == target_inst_idx) {
                                                    if (orig_inst.result) |orig_res| {
                                                        if (findRegDef(func, orig_res.id) != null) {
                                                            std.debug.print("  -> Resolved by position: reg_{d} -> reg_{d}\n", .{ reg_id, orig_res.id });
                                                            return orig_res.id;
                                                        }
                                                        std.debug.print("  -> Skip invalid position mapping: reg_{d} -> reg_{d} (no def)\n", .{ reg_id, orig_res.id });
                                                    }
                                                }
                                                orig_inst_idx += 1;
                                            }
                                        }
                                        break;
                                    }
                                }
                            }

                            // 策略 3: 追踪指令的操作数（递归解析）
                            // 对于运算指令（add/sub/mul等），尝试解析其操作数
                            const resolved = try self.resolveInstructionOperands(func, inst_item, loop, visited, depth + 1);
                            if (resolved != reg_id) {
                                std.debug.print("  -> Resolved operand: reg_{d} -> reg_{d}\n", .{ reg_id, resolved });
                                return resolved;
                            }
                        }

                        // 非展开块，直接返回
                        return reg_id;
                    }
                }
            }
        }

        // 未找到定义，原样返回
        return reg_id;
    }

    /// 解析指令的操作数，尝试找到原始块的寄存器
    /// 支持 move、add、sub、mul、div 等指令
    fn resolveInstructionOperands(
        self: *Self,
        func: *const IR.Function,
        inst: *const IR.Instruction,
        loop: LoopInfo,
        visited: *std.AutoHashMap(usize, void),
        depth: usize,
    ) std.mem.Allocator.Error!usize {
        const inst_result = inst.result orelse return inst.result.?.id;

        switch (inst.op) {
            .move => |op| {
                // move 指令：直接追踪源寄存器
                return try self.resolveUnrolledRegWithDepth(func, op.operand.id, loop, visited, depth);
            },
            .add => |op| {
                // add 指令：优先追踪 lhs（通常是累加器）
                const lhs_resolved = try self.resolveUnrolledRegWithDepth(func, op.lhs.id, loop, visited, depth);
                if (lhs_resolved != op.lhs.id) {
                    return lhs_resolved;
                }
                // 如果 lhs 无法解析，尝试 rhs
                const rhs_resolved = try self.resolveUnrolledRegWithDepth(func, op.rhs.id, loop, visited, depth);
                if (rhs_resolved != op.rhs.id) {
                    return rhs_resolved;
                }
            },
            .sub => |op| {
                const lhs_resolved = try self.resolveUnrolledRegWithDepth(func, op.lhs.id, loop, visited, depth);
                if (lhs_resolved != op.lhs.id) {
                    return lhs_resolved;
                }
            },
            .mul => |op| {
                const lhs_resolved = try self.resolveUnrolledRegWithDepth(func, op.lhs.id, loop, visited, depth);
                if (lhs_resolved != op.lhs.id) {
                    return lhs_resolved;
                }
                const rhs_resolved = try self.resolveUnrolledRegWithDepth(func, op.rhs.id, loop, visited, depth);
                if (rhs_resolved != op.rhs.id) {
                    return rhs_resolved;
                }
            },
            .div => |op| {
                const lhs_resolved = try self.resolveUnrolledRegWithDepth(func, op.lhs.id, loop, visited, depth);
                if (lhs_resolved != op.lhs.id) {
                    return lhs_resolved;
                }
            },
            .cast => |op| {
                // cast 指令：追踪源值
                return try self.resolveUnrolledRegWithDepth(func, op.value.id, loop, visited, depth);
            },
            else => {
                // 其他指令类型：无法解析，返回原值
            },
        }

        return inst_result.id;
    }

    /// 静态版本的展开寄存器解析（已废弃，保留用于兼容性）
    /// 新代码应使用 resolveUnrolledReg
    fn resolveUnrolledRegStatic(
        func: *const IR.Function,
        reg_id: usize,
        loop: LoopInfo,
    ) usize {
        _ = loop;
        // 简化版本：只处理 move 指令的一层追踪
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst_item| {
                if (inst_item.result) |res| {
                    if (res.id == reg_id) {
                        if (std.mem.indexOf(u8, block.label, "_unroll_") != null) {
                            if (inst_item.op == .move) {
                                return inst_item.op.move.operand.id;
                            }
                        }
                        return reg_id;
                    }
                }
            }
        }
        return reg_id;
    }

    /// 生成 while 循环（支持子循环）
    fn generateWhileLoopWithChildren(
        self: *Self,
        writer: anytype,
        func: *const IR.Function,
        loop: LoopInfo,
        processed: *std.AutoHashMap(usize, void),
        block_to_loop: *std.AutoHashMap(usize, usize),
        all_loops: []const LoopInfo,
        cleanup_regs: []const usize,
    ) !void {
        _ = all_loops;
        _ = block_to_loop;
        _ = processed;

        // 简化实现：先生成基本的 while 循环
        try self.generateWhileLoopStructuredNew(writer, func, loop, cleanup_regs);
    }

    fn detectLoops(self: *Self, func: *const IR.Function, cfg: *ControlFlowAnalysis) !void {
        // 第一步：检测所有循环（回边分析）
        var raw_loops = try std.ArrayList(LoopInfo).initCapacity(self.allocator, 0);
        defer {
            for (raw_loops.items) |*loop| {
                loop.deinit(self.allocator);
            }
            raw_loops.deinit(self.allocator);
        }

        for (func.blocks.items, 0..) |block, header_idx| {
            const term = block.terminator orelse continue;
            if (term != .cond_br) continue;

            const preds = cfg.predecessors.get(header_idx) orelse continue;

            var has_back_edge = false;
            var back_edge_source: usize = 0;

            for (preds.items) |pred_idx| {
                if (pred_idx >= header_idx) {
                    has_back_edge = true;
                    back_edge_source = pred_idx;
                    break;
                }
            }

            if (has_back_edge) {
                if (try self.analyzeLoop(func, cfg, header_idx, back_edge_source)) |loop_info| {
                    try raw_loops.append(self.allocator, loop_info);
                }
            }
        }

        // 第二步：计算每个循环包含的所有块（使用 DFS）
        std.debug.print("Computing loop blocks...\n", .{});
        for (raw_loops.items, 0..) |*loop, i| {
            std.debug.print("Computing blocks for loop {d}\n", .{i});
            try self.computeLoopBlocks(func, cfg, loop);
            std.debug.print("Loop {d}: blocks count={d}\n", .{ i, loop.blocks.count() });
        }

        // 第三步：构建循环嵌套树（基于块包含关系）
        try self.buildLoopNestingTree(&raw_loops);

        // 第四步：保存所有循环到 cfg.all_loops
        for (raw_loops.items) |loop| {
            var copied_loop = loop;
            copied_loop.children = try std.ArrayList(usize).initCapacity(self.allocator, loop.children.items.len);
            try copied_loop.children.appendSlice(self.allocator, loop.children.items);
            copied_loop.blocks = std.AutoHashMap(usize, void).init(self.allocator);
            var it = loop.blocks.iterator();
            while (it.next()) |entry| {
                try copied_loop.blocks.put(entry.key_ptr.*, {});
            }
            try cfg.all_loops.append(self.allocator, copied_loop);
        }

        // 第五步：只保留顶层循环到 cfg.loops
        for (raw_loops.items) |loop| {
            if (loop.parent == null) {
                // 深拷贝顶层循环
                var top_loop = loop;
                top_loop.children = try std.ArrayList(usize).initCapacity(self.allocator, loop.children.items.len);
                try top_loop.children.appendSlice(self.allocator, loop.children.items);
                top_loop.blocks = std.AutoHashMap(usize, void).init(self.allocator);
                var it = loop.blocks.iterator();
                while (it.next()) |entry| {
                    try top_loop.blocks.put(entry.key_ptr.*, {});
                }
                try cfg.loops.append(self.allocator, top_loop);
            }
        }
    }

    /// 计算循环包含的所有块（DFS 从 header 到 exit）
    fn computeLoopBlocks(self: *Self, func: *const IR.Function, cfg: *ControlFlowAnalysis, loop: *LoopInfo) !void {
        var visited = std.AutoHashMap(usize, void).init(cfg.allocator);
        defer visited.deinit();

        var stack = try std.ArrayList(usize).initCapacity(cfg.allocator, 0);
        defer stack.deinit(cfg.allocator);

        try stack.append(cfg.allocator, loop.header);
        try loop.blocks.put(loop.header, {});

        while (stack.items.len > 0) {
            const current = stack.pop() orelse break;
            if (visited.contains(current)) continue;
            try visited.put(current, {});

            // 不要越过 exit 块
            if (loop.exit_block) |exit| {
                if (current == exit) continue;
            }

            // 遍历后继
            const block = func.blocks.items[current];
            const term = block.terminator orelse continue;

            switch (term) {
                .br => |target| {
                    const target_idx = self.tryFindBlockIndex(func, target);
                    if (target_idx) |idx| {
                        if (!visited.contains(idx)) {
                            try stack.append(cfg.allocator, idx);
                            try loop.blocks.put(idx, {});
                        }
                    }
                },
                .cond_br => |cond| {
                    const then_idx = self.tryFindBlockIndex(func, cond.then_block);
                    const else_idx = self.tryFindBlockIndex(func, cond.else_block);

                    if (then_idx) |idx| {
                        if (!visited.contains(idx)) {
                            try stack.append(cfg.allocator, idx);
                            try loop.blocks.put(idx, {});
                        }
                    }
                    if (else_idx) |idx| {
                        if (!visited.contains(idx)) {
                            try stack.append(cfg.allocator, idx);
                            try loop.blocks.put(idx, {});
                        }
                    }
                },
                else => {},
            }
        }
    }

    /// 构建循环嵌套树（基于块包含关系）
    fn buildLoopNestingTree(self: *Self, loops: *std.ArrayList(LoopInfo)) !void {

        // 对于每个循环，找到它的最内层父循环
        for (loops.items, 0..) |*loop, i| {
            var parent_idx: ?usize = null;
            var min_blocks: usize = std.math.maxInt(usize);

            std.debug.print("Checking loop {d} (header={d}, blocks={d})\n", .{ i, loop.header, loop.blocks.count() });

            for (loops.items, 0..) |*other, j| {
                if (i == j) continue;

                std.debug.print("  vs loop {d} (header={d}, blocks={d}): contains header? {}\n", .{ j, other.header, other.blocks.count(), other.contains(loop.header) });

                // 如果 other 包含 loop 的 header，且 other 的块数更少（更内层）
                if (other.contains(loop.header) and other.blocks.count() < min_blocks) {
                    parent_idx = j;
                    min_blocks = other.blocks.count();
                    std.debug.print("    -> potential parent\n", .{});
                }
            }

            if (parent_idx) |p| {
                loop.parent = p;
                try loops.items[p].children.append(self.allocator, i);
                std.debug.print("  => parent is loop {d}\n", .{p});
            } else {
                std.debug.print("  => top-level\n", .{});
            }
        }
    }

    /// 分析循环结构
    fn analyzeLoop(self: *Self, func: *const IR.Function, cfg: *ControlFlowAnalysis, header: usize, back_edge_source: usize) !?LoopInfo {
        _ = cfg;

        // 循环头必须是条件分支
        const header_block = func.blocks.items[header];
        const header_term = header_block.terminator orelse return null;

        if (header_term != .cond_br) {
            return null;
        }

        // 使用地址比较找到 then 和 else 块的索引
        const then_ptr = @intFromPtr(header_term.cond_br.then_block);
        const else_ptr = @intFromPtr(header_term.cond_br.else_block);

        var then_idx: ?usize = null;
        var else_idx: ?usize = null;

        for (func.blocks.items, 0..) |block, i| {
            const block_ptr = @intFromPtr(block);
            if (block_ptr == then_ptr) {
                then_idx = i;
            }
            if (block_ptr == else_ptr) {
                else_idx = i;
            }
        }

        if (then_idx == null or else_idx == null) {
            return null;
        }

        // 确定循环体和出口
        var body_start: usize = 0;
        var exit: usize = 0;

        if (then_idx.? > header and then_idx.? <= back_edge_source) {
            body_start = then_idx.?;
            exit = else_idx.?;
        } else if (else_idx.? > header and else_idx.? <= back_edge_source) {
            body_start = else_idx.?;
            exit = then_idx.?;
        } else {
            return null;
        }

        // 检查是否是 for 循环（有增量块）
        var is_for_loop = false;
        var increment: ?usize = null;

        if (back_edge_source > body_start and back_edge_source != body_start) {
            is_for_loop = true;
            increment = back_edge_source;
        }

        const body_end = if (exit > body_start) exit - 1 else back_edge_source;

        var loop = try LoopInfo.init(self.allocator);
        loop.header = header;
        loop.body_start = body_start;
        loop.body_end = body_end;
        loop.exit_block = exit;
        loop.increment = increment;
        loop.is_for_loop = is_for_loop;

        return loop;
    }

    /// 生成结构化代码
    fn generateStructuredCode(self: *Self, writer: anytype, func: *const IR.Function, cfg: *ControlFlowAnalysis, cleanup_regs: []const usize) !bool {
        // 目前只处理单个循环的情况
        if (cfg.loops.items.len != 1) {
            return false;
        }

        const loop = cfg.loops.items[0];

        // 生成 entry 块（循环前的初始化）
        if (loop.header > 0) {
            for (0..loop.header) |idx| {
                const block = func.blocks.items[idx];
                try writer.print("    // Block {d}: {s}\n", .{ idx, block.label });

                for (block.instructions.items) |inst| {
                    try writer.writeAll("    ");
                    try self.generateInstruction(writer, inst);
                }

                // 处理终止指令（如果不是跳转到循环头）
                if (block.terminator) |term| {
                    if (term == .br) {
                        const target_idx = self.findBlockIndex(func, term.br);
                        if (target_idx != loop.header) {
                            // 不是跳转到循环头，需要处理
                            return false;
                        }
                    } else {
                        // 其他终止指令，暂不支持
                        return false;
                    }
                }
            }
        }

        // 生成循环
        if (loop.is_for_loop) {
            try self.generateForLoopStructured(writer, func, loop, cleanup_regs);
        } else {
            try self.generateWhileLoopStructured(writer, func, loop, cleanup_regs);
        }

        // 生成 exit 块（循环后的代码）
        if (loop.exit_block) |exit_idx| {
            if (exit_idx < func.blocks.items.len) {
                for (exit_idx..func.blocks.items.len) |idx| {
                    const block = func.blocks.items[idx];
                    try writer.print("    // Block {d}: {s}\n", .{ idx, block.label });

                    for (block.instructions.items) |inst| {
                        try writer.writeAll("    ");
                        try self.generateInstruction(writer, inst);
                    }

                    // 处理终止指令
                    if (block.terminator) |term| {
                        switch (term) {
                            .ret => |maybe_reg| {
                                if (cleanup_regs.len > 0) {
                                    try writer.writeAll("    // Cleanup\n");
                                    for (cleanup_regs) |reg_id| {
                                        if (!self.shouldReleaseReg(reg_id)) continue;
                                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                                    }
                                }
                                if (maybe_reg) |reg| {
                                    try writer.print("    return reg_{d};\n", .{reg.id});
                                } else {
                                    try writer.writeAll("    return runtime.Value.initNull();\n");
                                }
                            },
                            else => {
                                // 其他终止指令，暂不支持
                                return false;
                            },
                        }
                    }
                }
            }
        }

        return true;
    }

    /// 生成结构化 while 循环
    fn generateWhileLoopStructured(self: *Self, writer: anytype, func: *const IR.Function, loop: LoopInfo, cleanup_regs: []const usize) !void {
        _ = cleanup_regs;

        try writer.writeAll("    // Optimized: structured while loop\n");
        try writer.writeAll("    while (true) {\n");

        // 生成循环头（条件）
        const header_block = func.blocks.items[loop.header];
        try writer.print("        // Header: {s}\n", .{header_block.label});

        for (header_block.instructions.items) |inst| {
            try writer.writeAll("        ");
            try self.generateInstruction(writer, inst);
        }

        // 生成条件判断
        if (header_block.terminator) |term| {
            if (term == .cond_br) {
                const cond_reg = term.cond_br.cond.id;
                const reg_type = self.current_reg_types.?.get(cond_reg) orelse IR.Type{ .php_value = {} };
                const type_tag = @as(std.meta.Tag(IR.Type), reg_type);

                try writer.writeAll("        if (!(");
                try self.writeBoolExpr(writer, type_tag, cond_reg);
                try writer.writeAll(")) break;\n");
            }
        }

        // 生成循环体
        const body_block = func.blocks.items[loop.body_start];
        try writer.print("        // Body: {s}\n", .{body_block.label});

        for (body_block.instructions.items) |inst| {
            try writer.writeAll("        ");
            try self.generateInstruction(writer, inst);
        }

        try writer.writeAll("    }\n");
    }

    /// 生成结构化 for 循环
    fn generateForLoopStructured(self: *Self, writer: anytype, func: *const IR.Function, loop: LoopInfo, cleanup_regs: []const usize) !void {
        // 复用 generateStandardForLoop 的完整逻辑（包括 PHI 更新修复）
        try self.generateStandardForLoop(writer, func, loop);
        _ = cleanup_regs;
    }

    /// 直接生成 while 循环
    fn generateWhileLoopDirect(self: *Self, writer: anytype, func: *const IR.Function, cleanup_regs: []const usize, cond_idx: usize, body_idx: usize, exit_idx: usize) !bool {
        try writer.writeAll("    // Optimized: direct while loop generation\n");

        // 生成 entry 块
        const entry = func.blocks.items[0];
        try writer.writeAll("    // entry\n");
        for (entry.instructions.items) |inst| {
            try writer.writeAll("    ");
            try self.generateInstruction(writer, inst);
        }

        // 生成 while 循环
        const cond = func.blocks.items[cond_idx];
        const body = func.blocks.items[body_idx];

        try writer.writeAll("    while (true) {\n");

        // 生成条件块
        try writer.writeAll("        // condition\n");
        for (cond.instructions.items) |inst| {
            try writer.writeAll("        ");
            try self.generateInstruction(writer, inst);
        }

        // 生成条件判断
        if (cond.terminator) |term| {
            if (term == .cond_br) {
                const cond_reg = term.cond_br.cond.id;
                const reg_type = self.current_reg_types.?.get(cond_reg) orelse IR.Type{ .php_value = {} };
                const type_tag = @as(std.meta.Tag(IR.Type), reg_type);

                try writer.writeAll("        if (!(");
                try self.writeBoolExpr(writer, type_tag, cond_reg);
                try writer.writeAll(")) break;\n");
            }
        }

        // 生成循环体
        try writer.writeAll("        // body\n");
        for (body.instructions.items) |inst| {
            try writer.writeAll("        ");
            try self.generateInstruction(writer, inst);
        }

        try writer.writeAll("    }\n");

        // 生成 exit 块
        if (exit_idx < func.blocks.items.len) {
            const exit = func.blocks.items[exit_idx];
            try writer.writeAll("    // exit\n");
            for (exit.instructions.items) |inst| {
                try writer.writeAll("    ");
                try self.generateInstruction(writer, inst);
            }

            // 生成 exit 的终止指令
            if (exit.terminator) |term| {
                if (term == .ret) {
                    if (cleanup_regs.len > 0) {
                        try writer.writeAll("    // Cleanup\n");
                        for (cleanup_regs) |reg_id| {
                            try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                            if (!self.shouldReleaseReg(reg_id)) continue;
                        }
                    }
                    if (term.ret) |reg| {
                        try writer.print("    return reg_{d};\n", .{reg.id});
                    } else {
                        try writer.writeAll("    return runtime.Value.initNull();\n");
                    }
                }
            }
        }

        return true;
    }

    /// 直接生成 for 循环
    fn generateForLoopDirect(self: *Self, writer: anytype, func: *const IR.Function, cleanup_regs: []const usize, cond_idx: usize, body_idx: usize, loop_idx: usize, exit_idx: usize) !bool {
        try writer.writeAll("    // Optimized: direct for loop generation\n");

        // 生成 entry 块（初始化）
        const entry = func.blocks.items[0];
        try writer.writeAll("    // initialization\n");
        for (entry.instructions.items) |inst| {
            try writer.writeAll("    ");
            try self.generateInstruction(writer, inst);
        }

        // 生成 while 循环（for 循环的实现）
        const cond = func.blocks.items[cond_idx];
        const body = func.blocks.items[body_idx];
        const loop = func.blocks.items[loop_idx];

        try writer.writeAll("    while (true) {\n");

        // 生成条件块
        try writer.writeAll("        // condition\n");
        for (cond.instructions.items) |inst| {
            try writer.writeAll("        ");
            try self.generateInstruction(writer, inst);
        }

        // 生成条件判断
        if (cond.terminator) |term| {
            if (term == .cond_br) {
                const cond_reg = term.cond_br.cond.id;
                const reg_type = self.current_reg_types.?.get(cond_reg) orelse IR.Type{ .php_value = {} };
                const type_tag = @as(std.meta.Tag(IR.Type), reg_type);

                try writer.writeAll("        if (!(");
                try self.writeBoolExpr(writer, type_tag, cond_reg);
                try writer.writeAll(")) break;\n");
            }
        }

        // 生成循环体
        try writer.writeAll("        // body\n");
        for (body.instructions.items) |inst| {
            try writer.writeAll("        ");
            try self.generateInstruction(writer, inst);
        }

        // 生成增量表达式
        try writer.writeAll("        // increment\n");
        for (loop.instructions.items) |inst| {
            try writer.writeAll("        ");
            try self.generateInstruction(writer, inst);
        }

        try writer.writeAll("    }\n");

        // 生成 exit 块
        if (exit_idx < func.blocks.items.len) {
            const exit = func.blocks.items[exit_idx];
            try writer.writeAll("    // exit\n");
            for (exit.instructions.items) |inst| {
                try writer.writeAll("    ");
                try self.generateInstruction(writer, inst);
            }

            // 生成 exit 的终止指令
            if (exit.terminator) |term| {
                if (term == .ret) {
                    if (cleanup_regs.len > 0) {
                        try writer.writeAll("    // Cleanup\n");
                        for (cleanup_regs) |reg_id| {
                            try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                        }
                    }
                    if (term.ret) |reg| {
                        try writer.print("    return reg_{d};\n", .{reg.id});
                    } else {
                        try writer.writeAll("    return runtime.Value.initNull();\n");
                    }
                }
            }
        }

        return true;
    }

    /// 尝试生成简单的循环结构（优化：避免状态机）
    ///
    /// 检测while循环模式：
    /// - 第一个块跳转到条件块（br）
    /// - 条件块以cond_br终止（then_block=body, else_block=exit）
    /// - body块跳转回条件块（回边）
    /// - exit块是循环后的代码
    ///
    /// 检测for循环模式：
    /// - 第一个块包含初始化，跳转到条件块
    /// - 条件块以cond_br终止
    /// - body块跳转到loop块
    /// - loop块包含增量表达式，跳转回条件块
    /// - exit块是循环后的代码
    ///
    /// 返回true表示成功生成简单循环，false表示需要使用状态机
    fn tryGenerateSimpleLoop(self: *Self, writer: anytype, func: *const IR.Function, cleanup_regs: []const usize) !bool {
        _ = self;
        _ = writer;
        _ = func;
        _ = cleanup_regs;

        // 禁用旧的循环检测，使用新的结构化控制流生成
        return false;
    }

    /// 尝试生成while循环
    ///
    /// 模式：
    /// - entry块：br -> cond块
    /// - cond块：cond_br -> body块 / exit块
    /// - body块：br -> cond块（回边）
    /// - exit块：循环后的代码
    fn tryGenerateWhileLoop(self: *Self, writer: anytype, func: *const IR.Function, cleanup_regs: []const usize) !bool {
        // 需要至少4个块：entry, cond, body, exit
        if (func.blocks.items.len < 4) {
            return false;
        }

        const entry_block = func.blocks.items[0];

        // entry块必须以br终止，跳转到条件块
        const entry_term = entry_block.terminator orelse return false;
        if (entry_term != .br) {
            return false;
        }

        const cond_block_ptr = entry_term.br;
        const cond_idx = self.findBlockIndex(func, cond_block_ptr);

        // 条件块必须存在且不是entry块
        if (cond_idx == 0) {
            return false;
        }

        const cond_block = func.blocks.items[cond_idx];

        // 条件块必须以cond_br终止
        const cond_term = cond_block.terminator orelse return false;
        if (cond_term != .cond_br) {
            return false;
        }

        const cond_br = cond_term.cond_br;
        const body_idx = self.findBlockIndex(func, cond_br.then_block);
        const exit_idx = self.findBlockIndex(func, cond_br.else_block);

        // body块和exit块必须不同
        if (body_idx == exit_idx) {
            return false;
        }

        const body_block = func.blocks.items[body_idx];

        // body块必须以br终止，跳转回条件块（回边）
        const body_term = body_block.terminator orelse return false;
        if (body_term != .br) {
            return false;
        }

        const body_target_idx = self.findBlockIndex(func, body_term.br);
        if (body_target_idx != cond_idx) {
            // body块不是跳转回条件块，不是简单while循环
            return false;
        }

        // 所有条件满足，生成while循环
        try writer.writeAll("    // Simple while loop (optimized, no state machine)\n");

        // 生成entry块的指令（初始化代码）
        for (entry_block.instructions.items) |inst| {
            try self.generateInstruction(writer, inst);
        }

        // 生成while循环
        try writer.writeAll("    while (true) {\n");

        // 生成条件块的指令
        for (cond_block.instructions.items) |inst| {
            try writer.writeAll("    ");
            try self.generateInstruction(writer, inst);
        }

        // 生成循环条件判断（取反，不满足则 break）
        try writer.writeAll("        if (!(");
        try self.writeConditionExpr(writer, cond_br.cond.id, cond_br.cond.type_);
        try writer.writeAll(")) break;\n");

        // 生成body块的指令
        try writer.writeAll("        // Loop body\n");

        for (body_block.instructions.items) |inst| {
            try writer.writeAll("    ");
            try self.generateInstruction(writer, inst);
        }

        // 在循环体结束时释放临时对象
        try writer.writeAll("        // Release temporary values\n");
        for (body_block.instructions.items) |inst| {
            if (inst.result) |result_reg| {
                switch (inst.op) {
                    .const_string, .concat, .array_new, .new_object, .interpolate => {
                        try writer.print("        reg_{d}.release(runtime.runtime_allocator);\n", .{result_reg.id});
                    },
                    .call => {
                        // 函数调用返回的值需要释放（如果是Value类型）
                        if (result_reg.type_ == .php_value) {
                            try writer.print("        reg_{d}.release(runtime.runtime_allocator);\n", .{result_reg.id});
                        }
                    },
                    else => {},
                }
            }
        }

        try writer.writeAll("    }\n");

        // 生成exit块的代码
        const exit_block = func.blocks.items[exit_idx];
        try writer.writeAll("    // After loop\n");
        for (exit_block.instructions.items) |inst| {
            try self.generateInstruction(writer, inst);
        }

        // 处理exit块的终止指令
        if (exit_block.terminator) |term| {
            if (term == .ret) {
                if (cleanup_regs.len > 0) {
                    try writer.writeAll("    // Cleanup: release all allocated values\n");
                    for (cleanup_regs) |reg_id| {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                    }
                }
                if (term.ret) |reg| {
                    // 检查是否是 alloca 寄存器
                    const is_alloca = if (self.current_alloca_regs) |alloca_regs|
                        alloca_regs.contains(reg.id)
                    else
                        false;

                    if (is_alloca) {
                        try writer.print("    return reg_{d}.*;\n", .{reg.id});
                    } else {
                        try writer.print("    return reg_{d};\n", .{reg.id});
                    }
                } else {
                    try writer.writeAll("    return runtime.Value.initNull();\n");
                }
            } else {
                // exit块有其他终止指令，不是简单while循环
                return false;
            }
        }

        return true;
    }

    /// 尝试生成for循环
    ///
    /// 模式：
    /// - entry块：包含初始化，br -> cond块
    /// - cond块：cond_br -> body块 / exit块
    /// - body块：br -> loop块
    /// - loop块：包含增量表达式，br -> cond块（回边）
    /// - exit块：循环后的代码
    fn tryGenerateForLoop(self: *Self, writer: anytype, func: *const IR.Function, cleanup_regs: []const usize) !bool {
        // 需要至少5个块：entry, cond, body, loop, exit
        if (func.blocks.items.len < 5) {
            return false;
        }

        const entry_block = func.blocks.items[0];

        // entry块必须以br终止，跳转到条件块
        const entry_term = entry_block.terminator orelse return false;
        if (entry_term != .br) {
            return false;
        }

        const cond_block_ptr = entry_term.br;
        const cond_idx = self.findBlockIndex(func, cond_block_ptr);

        // 条件块必须存在且不是entry块
        if (cond_idx == 0) {
            return false;
        }

        const cond_block = func.blocks.items[cond_idx];

        // 条件块必须以cond_br终止
        const cond_term = cond_block.terminator orelse return false;
        if (cond_term != .cond_br) {
            return false;
        }

        const cond_br = cond_term.cond_br;
        const body_idx = self.findBlockIndex(func, cond_br.then_block);
        const exit_idx = self.findBlockIndex(func, cond_br.else_block);

        // body块和exit块必须不同
        if (body_idx == exit_idx) {
            return false;
        }

        const body_block = func.blocks.items[body_idx];

        // body块必须以br终止，跳转到loop块
        const body_term = body_block.terminator orelse return false;
        if (body_term != .br) {
            return false;
        }

        const loop_idx = self.findBlockIndex(func, body_term.br);

        // loop块不能是条件块（那是while循环）
        if (loop_idx == cond_idx) {
            return false;
        }

        const loop_block = func.blocks.items[loop_idx];

        // loop块必须以br终止，跳转回条件块（回边）
        const loop_term = loop_block.terminator orelse return false;
        if (loop_term != .br) {
            return false;
        }

        const loop_target_idx = self.findBlockIndex(func, loop_term.br);
        if (loop_target_idx != cond_idx) {
            // loop块不是跳转回条件块，不是简单for循环
            return false;
        }

        // 所有条件满足，生成for循环
        try writer.writeAll("    // Simple for loop (optimized, no state machine)\n");

        // 生成entry块的指令（初始化代码）
        for (entry_block.instructions.items) |inst| {
            try self.generateInstruction(writer, inst);
        }

        // 生成while循环（Zig没有for循环，用while模拟）
        try writer.writeAll("    while (true) {\n");

        // 生成条件块的指令
        for (cond_block.instructions.items) |inst| {
            try writer.writeAll("    ");
            try self.generateInstruction(writer, inst);
        }

        // 生成循环条件判断（取反，不满足则 break）
        try writer.writeAll("        if (!(");
        try self.writeConditionExpr(writer, cond_br.cond.id, cond_br.cond.type_);
        try writer.writeAll(")) break;\n");

        // 生成body块的指令
        try writer.writeAll("        // Loop body\n");
        for (body_block.instructions.items) |inst| {
            try writer.writeAll("    ");
            try self.generateInstruction(writer, inst);
        }

        // 生成loop块的指令（增量表达式）
        try writer.writeAll("        // Loop increment\n");
        for (loop_block.instructions.items) |inst| {
            try writer.writeAll("    ");
            try self.generateInstruction(writer, inst);
        }

        // 在循环体结束时释放临时对象（包括body和loop块）
        try writer.writeAll("        // Release temporary values (body)\n");
        for (body_block.instructions.items) |inst| {
            if (inst.result) |result_reg| {
                switch (inst.op) {
                    .const_string, .concat, .array_new, .new_object, .interpolate => {
                        try writer.print("        reg_{d}.release(runtime.runtime_allocator);\n", .{result_reg.id});
                    },
                    .call => {
                        if (result_reg.type_ == .php_value) {
                            try writer.print("        reg_{d}.release(runtime.runtime_allocator);\n", .{result_reg.id});
                        }
                    },
                    else => {},
                }
            }
        }

        try writer.writeAll("        // Release temporary values (increment)\n");
        for (loop_block.instructions.items) |inst| {
            if (inst.result) |result_reg| {
                switch (inst.op) {
                    .const_string, .concat, .array_new, .new_object, .interpolate => {
                        try writer.print("        reg_{d}.release(runtime.runtime_allocator);\n", .{result_reg.id});
                    },
                    .call => {
                        if (result_reg.type_ == .php_value) {
                            try writer.print("        reg_{d}.release(runtime.runtime_allocator);\n", .{result_reg.id});
                        }
                    },
                    else => {},
                }
            }
        }

        try writer.writeAll("    }\n");

        // 生成exit块的代码
        const exit_block = func.blocks.items[exit_idx];
        try writer.writeAll("    // After loop\n");
        for (exit_block.instructions.items) |inst| {
            try self.generateInstruction(writer, inst);
        }

        // 处理exit块的终止指令
        if (exit_block.terminator) |term| {
            if (term == .ret) {
                if (cleanup_regs.len > 0) {
                    try writer.writeAll("    // Cleanup: release all allocated values\n");
                    for (cleanup_regs) |reg_id| {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                    }
                }
                if (term.ret) |reg| {
                    // 检查是否是 alloca 寄存器
                    const is_alloca = if (self.current_alloca_regs) |alloca_regs|
                        alloca_regs.contains(reg.id)
                    else
                        false;

                    if (is_alloca) {
                        try writer.print("    return reg_{d}.*;\n", .{reg.id});
                    } else {
                        try writer.print("    return reg_{d};\n", .{reg.id});
                    }
                } else {
                    try writer.writeAll("    return runtime.Value.initNull();\n");
                }
            } else {
                // exit块有其他终止指令，不是简单for循环
                return false;
            }
        }

        return true;
    }

    /// 尝试生成简单的if-else结构（优化：避免状态机）
    ///
    /// 检测模式：
    /// - 2-4个基本块（entry + then + else + 可选的merge块）
    /// - 第一个块以cond_br终止
    /// - then块和else块都以ret终止（无循环回边）
    /// - 如果有merge块，它应该是不可达的（因为then/else都已经return）
    /// - 没有复杂的跳转结构
    ///
    /// 返回true表示成功生成简单if-else，false表示需要使用状态机
    fn tryGenerateSimpleIfElse(self: *Self, writer: anytype, func: *const IR.Function, cleanup_regs: []const usize) !bool {
        // 必须是2-4个块（entry + then + else + 可选merge）
        if (func.blocks.items.len < 2 or func.blocks.items.len > 4) {
            return false;
        }

        // 第一个块必须以cond_br终止
        const entry_block = func.blocks.items[0];
        const entry_term = entry_block.terminator orelse return false;
        if (entry_term != .cond_br) {
            return false;
        }

        const cond_br = entry_term.cond_br;

        // 找到then块和else块的索引
        const then_idx = self.findBlockIndex(func, cond_br.then_block);
        const else_idx = self.findBlockIndex(func, cond_br.else_block);

        // then块和else块必须存在且不同
        if (then_idx == else_idx) {
            return false;
        }

        // 检查then块和else块是否都以ret终止（无循环回边）
        const then_block = func.blocks.items[then_idx];
        const else_block = func.blocks.items[else_idx];

        const then_term = then_block.terminator orelse return false;
        const else_term = else_block.terminator orelse return false;

        if (then_term != .ret or else_term != .ret) {
            return false;
        }

        // 所有条件满足，生成简单if-else结构
        try writer.writeAll("    // Simple if-else structure (optimized, no state machine)\n");

        // 生成entry块的指令
        for (entry_block.instructions.items) |inst| {
            try self.generateInstruction(writer, inst);
        }

        // 生成条件判断
        try writer.writeAll("    if (");
        try self.writeConditionExpr(writer, cond_br.cond.id, cond_br.cond.type_);
        try writer.writeAll(") {\n");

        // 生成then块
        try writer.writeAll("        // Then branch\n");
        for (then_block.instructions.items) |inst| {
            try writer.writeAll("    ");
            try self.generateInstruction(writer, inst);
        }

        // then块的return（不需要cleanup，因为简单if-else中的值会在return时自动处理）
        if (then_term.ret) |reg| {
            // 检查是否是 alloca 寄存器
            const is_alloca = if (self.current_alloca_regs) |alloca_regs|
                alloca_regs.contains(reg.id)
            else
                false;

            if (is_alloca) {
                try writer.print("        return reg_{d}.*;\n", .{reg.id});
            } else {
                try writer.print("        return reg_{d};\n", .{reg.id});
            }
        } else {
            try writer.writeAll("        return runtime.Value.initNull();\n");
        }

        try writer.writeAll("    } else {\n");

        // 生成else块
        try writer.writeAll("        // Else branch\n");
        for (else_block.instructions.items) |inst| {
            try writer.writeAll("    ");
            try self.generateInstruction(writer, inst);
        }

        // else块的return（不需要cleanup，因为简单if-else中的值会在return时自动处理）
        if (else_term.ret) |reg| {
            // 检查是否是 alloca 寄存器
            const is_alloca = if (self.current_alloca_regs) |alloca_regs|
                alloca_regs.contains(reg.id)
            else
                false;

            if (is_alloca) {
                try writer.print("        return reg_{d}.*;\n", .{reg.id});
            } else {
                try writer.print("        return reg_{d};\n", .{reg.id});
            }
        } else {
            try writer.writeAll("        return runtime.Value.initNull();\n");
        }

        try writer.writeAll("    }\n");

        // 注意：如果有merge块，它是不可达的（因为then/else都已经return），所以不需要生成代码
        // 注意：cleanup_regs在简单if-else中不需要显式释放，因为return的值会被调用者管理
        _ = cleanup_regs;

        return true;
    }

    /// 生成终止指令（状态机模式）
    fn generateTerminatorStateMachine(self: *Self, writer: anytype, term: IR.Terminator, func: *const IR.Function, cleanup_regs: []const usize, alloca_regs: *const std.AutoHashMap(usize, void), source_block_idx: usize) !void {
        switch (term) {
            .ret => |maybe_reg| {
                // 在return之前执行cleanup
                if (cleanup_regs.len > 0) {
                    try writer.writeAll("                // Cleanup: release all allocated values\n");
                    for (cleanup_regs) |reg_id| {
                        // 检查是否是返回值寄存器
                        const is_return_reg = if (maybe_reg) |reg| reg.id == reg_id else false;
                        if (!is_return_reg and self.shouldReleaseReg(reg_id)) {
                            if (alloca_regs.contains(reg_id)) {
                                try writer.print("                reg_{d}.*.release(runtime.runtime_allocator);\n", .{reg_id});
                            } else {
                                try writer.print("                reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                            }
                        }
                    }
                }
                if (maybe_reg) |reg| {
                    // 检查是否是 alloca 寄存器
                    const is_alloca = alloca_regs.contains(reg.id);
                    if (is_alloca) {
                        try writer.print("                return reg_{d}.*;\n", .{reg.id});
                    } else {
                        try writer.print("                return reg_{d};\n", .{reg.id});
                    }
                } else {
                    // void return - 返回null
                    try writer.writeAll("                return runtime.Value.initNull();\n");
                }
            },
            .br => |target_block| {
                // 无条件跳转：找到目标块的索引
                const target_idx = self.findBlockIndex(func, target_block);

                // 检查目标块是否有PHI节点，如果有则设置PHI结果
                try self.generatePhiAssignments(writer, func, target_block, source_block_idx);

                try writer.print("                current_block = {d};\n", .{target_idx});
            },
            .cond_br => |cond_br| {
                // 条件跳转
                const then_idx = self.findBlockIndex(func, cond_br.then_block);
                const else_idx = self.findBlockIndex(func, cond_br.else_block);

                // 获取条件寄存器的实际类型
                const reg_type = self.current_reg_types.?.get(cond_br.cond.id) orelse IR.Type{ .php_value = {} };
                const type_tag = @as(std.meta.Tag(IR.Type), reg_type);

                try writer.writeAll("                if (");
                try self.writeBoolExpr(writer, type_tag, cond_br.cond.id);
                try writer.writeAll(") {\n");

                // 检查then块是否有PHI节点
                try self.generatePhiAssignments(writer, func, cond_br.then_block, source_block_idx);

                try writer.print("                    current_block = {d};\n", .{then_idx});
                try writer.writeAll("                } else {\n");

                // 检查else块是否有PHI节点
                try self.generatePhiAssignments(writer, func, cond_br.else_block, source_block_idx);

                try writer.print("                    current_block = {d};\n", .{else_idx});
                try writer.writeAll("                }\n");
            },
            .switch_ => |switch_data| {
                const sw_var_name2 = if (self.current_global_get_names) |gn| gn.get(switch_data.value.id) else null;
                const src_file2 = blk_src2: {
                    if (func.location.file.len > 0 and !std.mem.eql(u8, func.location.file, "<unknown>")) break :blk_src2 func.location.file;
                    for (func.blocks.items) |blk_s| {
                        for (blk_s.instructions.items) |inst_s| {
                            if (inst_s.location.line > 0 and inst_s.location.file.len > 0) break :blk_src2 inst_s.location.file;
                        }
                    }
                    break :blk_src2 "<unknown>";
                };

                if (sw_var_name2 != null and switch_data.cases.len > 0) {
                    try writer.print("                {{\n", .{});
                    try writer.print("                    const __sw_v = reg_{d}.toInt();\n", .{switch_data.value.id});
                    try writer.print("                    var __sw_done: bool = false;\n", .{});
                    try writer.print("                    _ = &__sw_done;\n", .{});

                    for (switch_data.cases) |case| {
                        const case_idx = self.findBlockIndex(func, case.block);
                        try writer.print("                    if (!__sw_done) {{\n", .{});
                        if (case.source_line > 0) {
                            try writer.print("                        runtime.setSourceLocation(\"{s}\", {d});\n", .{ src_file2, case.source_line });
                        }
                        try writer.print("                        if (__sw_undef_{d}) runtime.emitWarning(\"Undefined variable {s}\");\n", .{ switch_data.value.id, sw_var_name2.? });
                        try writer.print("                        if (__sw_v == {d}) {{ current_block = {d}; __sw_done = true; }}\n", .{ case.value, case_idx });
                        try writer.print("                    }}\n", .{});
                    }

                    const default_idx = self.findBlockIndex(func, switch_data.default);
                    try writer.print("                    if (!__sw_done) {{ current_block = {d}; }}\n", .{default_idx});
                    try writer.print("                }}\n", .{});
                } else {
                    try writer.print("                switch (reg_{d}.toInt()) {{\n", .{switch_data.value.id});
                    for (switch_data.cases) |case| {
                        const case_idx = self.findBlockIndex(func, case.block);
                        try writer.print("                    {d} => current_block = {d},\n", .{ case.value, case_idx });
                    }
                    const default_idx = self.findBlockIndex(func, switch_data.default);
                    try writer.print("                    else => current_block = {d},\n", .{default_idx});
                    try writer.writeAll("                }\n");
                }
            },
            .throw => |exception_reg| {
                // 返回 null 而非 error，让调用方的 hasException() 检查路由到 catch 块
                try writer.print("                return runtime.Value.initNull(); // Exception: reg_{d}\n", .{exception_reg.id});
            },
            .unreachable_ => {
                try writer.writeAll("                unreachable;\n");
            },
        }
    }

    /// 生成PHI节点的赋值语句
    /// 在跳转到目标块之前，检查目标块是否有PHI节点，如果有则设置PHI结果
    fn generatePhiAssignments(self: *Self, writer: anytype, func: *const IR.Function, target_block: *const IR.BasicBlock, source_block_idx: usize) !void {
        // 用于结构化循环的 phi 赋值（20 个空格缩进）
        const source_block = func.blocks.items[source_block_idx];

        for (target_block.instructions.items) |inst| {
            if (inst.op == .phi) {
                const phi_op = inst.op.phi;
                const result_reg = inst.result orelse continue;

                // 查找来自当前块的incoming值
                for (phi_op.incoming) |incoming| {
                    if (incoming.block == source_block) {
                        try self.generatePhiValueAssignment(writer, result_reg, incoming.value, "                    ");
                        break;
                    }
                }
            }
        }
    }

    /// 查找基本块在函数中的索引
    fn findBlockIndex(self: *const Self, func: *const IR.Function, target: *const IR.BasicBlock) usize {
        _ = self;
        const target_ptr = @intFromPtr(target);
        for (func.blocks.items, 0..) |block, i| {
            const block_ptr = @intFromPtr(block);
            if (block_ptr == target_ptr) {
                return i;
            }
        }
        std.debug.panic("Block not found in function", .{});
    }

    fn tryFindBlockIndex(self: *const Self, func: *const IR.Function, target: *const IR.BasicBlock) ?usize {
        _ = self;
        const target_ptr = @intFromPtr(target);
        for (func.blocks.items, 0..) |block, i| {
            const block_ptr = @intFromPtr(block);
            if (block_ptr == target_ptr) {
                return i;
            }
        }
        return null;
    }

    /// 记录指令中使用的所有寄存器
    /// 用于生命周期分析，确定何时可以释放寄存器
    fn recordRegisterUses(
        self: *Self,
        inst: *const IR.Instruction,
        block_idx: usize,
        inst_idx: usize,
        reg_last_use: *std.AutoHashMap(usize, RegUseInfo),
    ) !void {
        _ = self; // 避免未使用警告

        const use_info = RegUseInfo{ .block_idx = block_idx, .inst_idx = inst_idx };

        // 根据指令类型记录使用的寄存器
        switch (inst.op) {
            // 二元运算
            .add, .sub, .mul, .div, .mod, .pow, .eq, .ne, .lt, .le, .gt, .ge, .identical, .not_identical, .and_, .or_, .concat => |op| {
                try reg_last_use.put(op.lhs.id, use_info);
                try reg_last_use.put(op.rhs.id, use_info);
            },

            // 一元运算
            .neg, .not => |op| {
                try reg_last_use.put(op.operand.id, use_info);
            },

            // 变量操作
            .store => |op| {
                try reg_last_use.put(op.ptr.id, use_info);
                try reg_last_use.put(op.value.id, use_info);
            },
            .load => |op| {
                try reg_last_use.put(op.ptr.id, use_info);
            },

            // 函数调用
            .call => |op| {
                for (op.args) |arg| {
                    try reg_last_use.put(arg.id, use_info);
                }
            },

            // 数组操作
            .array_get => |op| {
                try reg_last_use.put(op.array.id, use_info);
                try reg_last_use.put(op.key.id, use_info);
            },
            .array_set => |op| {
                try reg_last_use.put(op.array.id, use_info);
                try reg_last_use.put(op.key.id, use_info);
                try reg_last_use.put(op.value.id, use_info);
            },
            .array_set_nested => |op| {
                try reg_last_use.put(op.outer_array.id, use_info);
                try reg_last_use.put(op.outer_key.id, use_info);
                try reg_last_use.put(op.inner_key.id, use_info);
                try reg_last_use.put(op.value.id, use_info);
            },
            .array_push => |op| {
                try reg_last_use.put(op.array.id, use_info);
                try reg_last_use.put(op.value.id, use_info);
            },
            .array_count => |op| {
                try reg_last_use.put(op.operand.id, use_info);
            },

            // 类型转换
            .cast => |op| {
                try reg_last_use.put(op.value.id, use_info);
            },

            else => {},
        }
    }

    /// 记录指令中使用的所有寄存器（用于完整生命周期分析）
    fn recordRegisterUsesForLifetime(
        self: *Self,
        inst: *const IR.Instruction,
        block_idx: usize,
        inst_idx: usize,
        reg_lifetime: *std.AutoHashMap(usize, RegLifetime),
    ) !void {
        _ = self; // 避免未使用警告

        // 辅助函数：更新寄存器使用信息
        const updateUse = struct {
            fn call(
                lifetime_map: *std.AutoHashMap(usize, RegLifetime),
                reg_id: usize,
                blk_idx: usize,
                ins_idx: usize,
            ) !void {
                if (lifetime_map.getPtr(reg_id)) |lifetime| {
                    lifetime.last_use_block = blk_idx;
                    lifetime.last_use_inst = ins_idx;
                    lifetime.use_count += 1;
                }
            }
        }.call;

        // 根据指令类型记录使用的寄存器
        switch (inst.op) {
            // 二元运算
            .add, .sub, .mul, .div, .mod, .pow, .eq, .ne, .lt, .le, .gt, .ge, .identical, .not_identical, .and_, .or_, .concat => |op| {
                try updateUse(reg_lifetime, op.lhs.id, block_idx, inst_idx);
                try updateUse(reg_lifetime, op.rhs.id, block_idx, inst_idx);
            },

            // 一元运算
            .neg, .not => |op| {
                try updateUse(reg_lifetime, op.operand.id, block_idx, inst_idx);
            },

            // 变量操作
            .store => |op| {
                try updateUse(reg_lifetime, op.ptr.id, block_idx, inst_idx);
                try updateUse(reg_lifetime, op.value.id, block_idx, inst_idx);
            },
            .load => |op| {
                try updateUse(reg_lifetime, op.ptr.id, block_idx, inst_idx);
            },

            // 函数调用
            .call => |op| {
                for (op.args) |arg| {
                    try updateUse(reg_lifetime, arg.id, block_idx, inst_idx);
                }
            },

            // 数组操作
            .array_get => |op| {
                try updateUse(reg_lifetime, op.array.id, block_idx, inst_idx);
                try updateUse(reg_lifetime, op.key.id, block_idx, inst_idx);
            },
            .array_set => |op| {
                try updateUse(reg_lifetime, op.array.id, block_idx, inst_idx);
                try updateUse(reg_lifetime, op.key.id, block_idx, inst_idx);
                try updateUse(reg_lifetime, op.value.id, block_idx, inst_idx);
            },
            .array_set_nested => |op| {
                try updateUse(reg_lifetime, op.outer_array.id, block_idx, inst_idx);
                try updateUse(reg_lifetime, op.outer_key.id, block_idx, inst_idx);
                try updateUse(reg_lifetime, op.inner_key.id, block_idx, inst_idx);
                try updateUse(reg_lifetime, op.value.id, block_idx, inst_idx);
            },
            .array_push => |op| {
                try updateUse(reg_lifetime, op.array.id, block_idx, inst_idx);
                try updateUse(reg_lifetime, op.value.id, block_idx, inst_idx);
            },
            .array_count => |op| {
                try updateUse(reg_lifetime, op.operand.id, block_idx, inst_idx);
            },

            // 类型转换
            .cast => |op| {
                try updateUse(reg_lifetime, op.value.id, block_idx, inst_idx);
            },

            else => {},
        }
    }

    /// 生成指令
    fn generateInstruction(self: *Self, writer: anytype, inst: *const IR.Instruction) !void {
        // Add source location comment
        if (inst.location.line > 0) {
            try writer.print("        // {s}:{d}\n", .{ inst.location.file, inst.location.line });
        }

        // 生成结果寄存器名称（如果有）
        var result_buf: [32]u8 = undefined;
        const result_reg = if (inst.result) |r|
            try std.fmt.bufPrint(&result_buf, "reg_{d}", .{r.id})
        else
            null;

        switch (inst.op) {
            // ========================================================================
            // 常量指令
            // ========================================================================
            // 常量指令
            // ========================================================================
            .const_int => |val| {
                // 所有寄存器都是 Value 类型
                if (inst.result) |_| {
                    try writer.print("        {s} = runtime.Value.initInt({d});\n", .{ result_reg.?, val });
                }
            },
            .const_float => |val| {
                if (inst.result) |_| {
                    try writer.print("        {s} = runtime.Value.initFloat({d});\n", .{ result_reg.?, val });
                }
            },
            .const_bool => |val| {
                if (inst.result) |_| {
                    try writer.print("        {s} = runtime.Value.initBool({});\n", .{ result_reg.?, val });
                }
            },
            .const_string => |string_id| {
                // 字符串常量需要从字符串表中获取
                try writer.print("        {s} = runtime.Value.initString(try runtime.PHPString.init(runtime.runtime_allocator, string_table[{d}]));\n", .{ result_reg.?, string_id });
            },
            .const_null => {
                try writer.print("        {s} = runtime.Value.initNull();\n", .{result_reg.?});
            },
            .param => |op| {
                if (inst.result) |_| {
                    if (std.mem.eql(u8, op.name, "this")) {
                        try writer.print("        {s} = ctx;\n", .{result_reg.?});
                    } else {
                        const arg_idx = if (self.current_function_has_this) op.index - 1 else op.index;

                        // 检查是否是可变参数
                        const is_variadic = blk: {
                            if (self.current_function_for_resolve) |func| {
                                if (op.index < func.params.items.len) {
                                    break :blk func.params.items[op.index].is_variadic;
                                }
                            }
                            break :blk false;
                        };

                        if (is_variadic) {
                            // 可变参数：收集从 arg_idx 开始的所有参数到数组
                            try writer.print("        {s} = runtime.Value.initNull();\n", .{result_reg.?});
                            try writer.print("        {{\n", .{});
                            try writer.print("            var variadic_array = try runtime.PHPArray.init(runtime.runtime_allocator);\n", .{});
                            try writer.print("            var i: usize = {d};\n", .{arg_idx});
                            try writer.print("            while (i < args.len) : (i += 1) {{\n", .{});
                            try writer.print("                try variadic_array.push(runtime.runtime_allocator, args[i]);\n", .{});
                            try writer.print("            }}\n", .{});
                            try writer.print("            {s} = runtime.Value.initArray(variadic_array);\n", .{result_reg.?});
                            try writer.print("        }}\n", .{});
                        } else {
                            try writer.print("        {s} = if (args.len > {d}) args[{d}] else runtime.Value.initNull();\n", .{ result_reg.?, arg_idx, arg_idx });
                        }
                    }
                }
            },
            .capture_get => |op| {
                if (inst.result) |_| {
                    try writer.print("        {s} = ctx.asFunction().captures[{d}];\n", .{ result_reg.?, op.index });
                }
            },
            .arg_count => {
                if (inst.result) |_| {
                    try writer.print("        {s} = @intCast(args.len);\n", .{result_reg.?});
                }
            },

            // ========================================================================
            // 内存操作指令
            // ========================================================================
            .alloca => {
                // alloca在Zig中不需要显式生成代码，变量已经在声明时分配
                // 这里只需要生成一个注释
                try writer.print("        // alloca: {s}\n", .{result_reg.?});
            },
            .load => |op| {
                // 检查 ptr 的实际类型（可能被 mem2reg 提升）
                const ptr_type = if (self.current_register_types) |types|
                    types.get(op.ptr.id) orelse op.ptr.type_
                else
                    op.ptr.type_;
                const ptr_tag = @as(std.meta.Tag(IR.Type), ptr_type);

                // 如果 ptr 是指针类型，但不在 alloca_registers 中，说明被 mem2reg 提升了
                const is_real_alloca = if (self.current_alloca_regs) |regs| regs.contains(op.ptr.id) else false;
                const ptr_is_optimized = (ptr_tag == .ptr and !is_real_alloca) or ptr_tag != .ptr;

                var ptr_buf: [32]u8 = undefined;
                const ptr = try std.fmt.bufPrint(&ptr_buf, "reg_{d}", .{op.ptr.id});

                if (ptr_is_optimized) {
                    // by-ref 闭包捕获：需要解引用读取堆单元值
                    if (self.current_ref_capture_allocas) |rca| {
                        if (rca.contains(op.ptr.id)) {
                            try writer.print("        {s} = runtime.val_deref(&{s}).*;\n", .{ result_reg.?, ptr });
                            try writer.print("        _ = {s}.retain();\n", .{result_reg.?});
                            return;
                        }
                    }
                    // mem2reg 优化：直接读取
                    try writer.print("        {s} = {s};\n", .{ result_reg.?, ptr });
                } else {
                    // 智能处理类型转换
                    if (inst.result) |reg| {
                        const result_type = reg.type_;
                        const load_type = op.type_;

                        const result_tag = @as(std.meta.Tag(IR.Type), result_type);
                        const load_tag = @as(std.meta.Tag(IR.Type), load_type);

                        // 如果结果类型和加载类型不匹配，需要转换
                        if (result_tag != load_tag) {
                            // 从Value类型转换到基本类型
                            if (load_tag == .php_value and result_tag == .i64) {
                                try writer.print("        {s} = {s}.*.toInt();\n", .{ result_reg.?, ptr });
                            } else if (load_tag == .php_value and result_tag == .f64) {
                                try writer.print("        {s} = {s}.*.toFloat();\n", .{ result_reg.?, ptr });
                            } else if (load_tag == .php_value and result_tag == .bool) {
                                try writer.print("        {s} = {s}.*.toBool();\n", .{ result_reg.?, ptr });
                            } else if (result_tag == .i64 and load_tag == .i64) {
                                // i64到i64，直接加载
                                try writer.print("        {s} = {s}.*;\n", .{ result_reg.?, ptr });
                            } else if (result_tag == .php_value and load_tag == .i64) {
                                // i64到php_value，需要转换
                                try writer.print("        {s} = runtime.Value.initInt({s}.*);\n", .{ result_reg.?, ptr });
                            } else if (result_tag == .f64 and load_tag == .f64) {
                                // f64到f64，直接加载
                                try writer.print("        {s} = {s}.*;\n", .{ result_reg.?, ptr });
                            } else if (result_tag == .php_value and load_tag == .f64) {
                                // f64到php_value，需要转换
                                try writer.print("        {s} = runtime.Value.initFloat({s}.*);\n", .{ result_reg.?, ptr });
                            } else if (result_tag == .bool and load_tag == .bool) {
                                // bool到bool，直接加载
                                try writer.print("        {s} = {s}.*;\n", .{ result_reg.?, ptr });
                            } else if (result_tag == .php_value and load_tag == .bool) {
                                // bool到php_value，需要转换
                                try writer.print("        {s} = runtime.Value.initBool({s}.*);\n", .{ result_reg.?, ptr });
                            } else {
                                // 默认：直接加载
                                try writer.print("        {s} = {s}.*;\n", .{ result_reg.?, ptr });
                            }
                        } else {
                            // 类型匹配，直接加载
                            try writer.print("        {s} = {s}.*;\n", .{ result_reg.?, ptr });
                        }
                    }
                }
            },
            .store => |op| {
                // by-ref 闭包捕获：后续 store 须经 php_ref_assign_ptr
                if (self.current_ref_capture_allocas) |rca| {
                    if (rca.get(op.ptr.id)) |init_cap_reg| {
                        if (op.value.id != init_cap_reg) {
                            const is_real = if (self.current_alloca_regs) |regs| regs.contains(op.ptr.id) else false;
                            const v_is_alloca = if (self.current_alloca_regs) |regs| regs.contains(op.value.id) else false;
                            const vs = if (v_is_alloca) ".*" else "";
                            if (is_real) {
                                try writer.print("        _ = try runtime.php_ref_assign_ptr(reg_{d}, reg_{d}{s});\n", .{ op.ptr.id, op.value.id, vs });
                            } else {
                                try writer.print("        _ = try runtime.php_ref_assign_ptr(&reg_{d}, reg_{d}{s});\n", .{ op.ptr.id, op.value.id, vs });
                            }
                            if (self.current_var_name_map) |vnm| {
                                if (vnm.get(op.ptr.id)) |_| {
                                    try writer.print("        __def_{d} = true;\n", .{op.ptr.id});
                                }
                            }
                            return;
                        }
                    }
                }

                // make_ref'd alloca：使用 ref_aware_store 写穿引用槽
                if (self.current_make_ref_allocas) |mra| {
                    if (mra.contains(op.ptr.id)) {
                        const value_is_alloca = if (self.current_alloca_regs) |regs| regs.contains(op.value.id) else false;
                        const val_suffix = if (value_is_alloca) ".*" else "";
                        try writer.print("        runtime.ref_aware_store(reg_{d}, reg_{d}{s});\n", .{ op.ptr.id, op.value.id, val_suffix });
                        if (self.current_var_name_map) |vnm| {
                            if (vnm.get(op.ptr.id)) |_| {
                                try writer.print("        __def_{d} = true;\n", .{op.ptr.id});
                            }
                        }
                        return;
                    }
                }

                // 检查 ptr 的实际类型（可能被 mem2reg 提升）
                const ptr_type = if (self.current_register_types) |types|
                    types.get(op.ptr.id) orelse op.ptr.type_
                else
                    op.ptr.type_;
                const ptr_tag = @as(std.meta.Tag(IR.Type), ptr_type);

                // 如果 ptr 是指针类型，但不在 alloca_registers 中，说明被 mem2reg 提升了
                const is_real_alloca = if (self.current_alloca_regs) |regs| regs.contains(op.ptr.id) else false;
                const ptr_is_optimized = (ptr_tag == .ptr and !is_real_alloca) or ptr_tag != .ptr;

                var ptr_buf: [32]u8 = undefined;
                var value_buf: [32]u8 = undefined;
                const ptr = try std.fmt.bufPrint(&ptr_buf, "reg_{d}", .{op.ptr.id});

                // 获取 value 的实际类型
                const store_value_type = if (self.current_register_types) |types|
                    types.get(op.value.id) orelse op.value.type_
                else
                    op.value.type_;
                const store_value_tag = @as(std.meta.Tag(IR.Type), store_value_type);

                if (ptr_is_optimized) {
                    // mem2reg 优化：直接赋值，但需要类型转换
                    // 如果 ptr 需要 php_value，但 value 是基本类型，需要转换
                    if (ptr_tag == .php_value and store_value_tag != .php_value) {
                        if (store_value_tag == .i64) {
                            try writer.print("        {s} = runtime.Value.initInt(reg_{d});\n", .{ ptr, op.value.id });
                        } else if (store_value_tag == .f64) {
                            try writer.print("        {s} = runtime.Value.initFloat(reg_{d});\n", .{ ptr, op.value.id });
                        } else if (store_value_tag == .bool) {
                            try writer.print("        {s} = runtime.Value.initBool(reg_{d});\n", .{ ptr, op.value.id });
                        } else {
                            const value = try std.fmt.bufPrint(&value_buf, "reg_{d}", .{op.value.id});
                            try writer.print("        {s} = {s};\n", .{ ptr, value });
                        }
                    } else {
                        const value = try std.fmt.bufPrint(&value_buf, "reg_{d}", .{op.value.id});
                        try writer.print("        {s} = {s};\n", .{ ptr, value });
                    }
                } else {
                    // 真实的指针存储
                    const value = try std.fmt.bufPrint(&value_buf, "reg_{d}", .{op.value.id});

                    // 获取指针指向的类型
                    const ptr_inner_type = switch (op.ptr.type_) {
                        .ptr => |inner| inner.*,
                        else => .php_value,
                    };

                    // 在存储新值之前，释放旧值（如果是引用类型）
                    if (ptr_inner_type == .php_value) {
                        try writer.print("        {s}.*.release(runtime.runtime_allocator);\n", .{ptr});
                    }

                    // 存储新值 - 需要类型转换
                    const ptr_inner_tag = @as(std.meta.Tag(IR.Type), ptr_inner_type);
                    const value_tag = @as(std.meta.Tag(IR.Type), op.value.type_);

                    if (ptr_inner_tag == value_tag) {
                        // 类型匹配，直接赋值
                        try writer.print("        {s}.* = {s};\n", .{ ptr, value });
                    } else {
                        // 类型不匹配，需要转换
                        if (ptr_inner_tag == .php_value) {
                            // 存储到php_value指针，需要从基本类型转换
                            switch (value_tag) {
                                .i64 => try writer.print("        {s}.* = runtime.Value.initInt({s});\n", .{ ptr, value }),
                                .f64 => try writer.print("        {s}.* = runtime.Value.initFloat({s});\n", .{ ptr, value }),
                                .bool => try writer.print("        {s}.* = runtime.Value.initBool({s});\n", .{ ptr, value }),
                                else => try writer.print("        {s}.* = {s};\n", .{ ptr, value }),
                            }
                        } else if (value_tag == .php_value) {
                            // 从php_value存储到基本类型指针，需要提取
                            switch (ptr_inner_tag) {
                                .i64 => try writer.print("        {s}.* = {s}.asInt();\n", .{ ptr, value }),
                                .f64 => try writer.print("        {s}.* = {s}.asFloat();\n", .{ ptr, value }),
                                .bool => try writer.print("        {s}.* = {s}.asBool();\n", .{ ptr, value }),
                                else => try writer.print("        {s}.* = {s};\n", .{ ptr, value }),
                            }
                        } else {
                            // 基本类型之间的转换
                            try writer.print("        {s}.* = @as({s}, {s});\n", .{ ptr, @tagName(ptr_tag), value });
                        }
                    }
                }
            },

            // ========================================================================
            // 算术运算指令
            // ========================================================================
            .add => |op| {
                var lhs_buf: [32]u8 = undefined;
                var rhs_buf: [32]u8 = undefined;
                const lhs = try std.fmt.bufPrint(&lhs_buf, "reg_{d}", .{op.lhs.id});
                const rhs = try std.fmt.bufPrint(&rhs_buf, "reg_{d}", .{op.rhs.id});
                // 根据操作数类型生成不同的代码
                if (inst.result) |reg| {
                    if (reg.type_ == .i64 and op.lhs.type_ == .i64 and op.rhs.type_ == .i64) {
                        // 直接i64加法（内部计算用）
                        try writer.print("        {s} = {s} + {s};\n", .{ result_reg.?, lhs, rhs });
                    } else {
                        // 使用运行时函数（运行时边界）
                        try writer.print("        {s} = try runtime.php_add({s}, {s});\n", .{ result_reg.?, lhs, rhs });
                    }
                }
            },
            .sub => |op| {
                var lhs_buf: [32]u8 = undefined;
                var rhs_buf: [32]u8 = undefined;
                const lhs = try std.fmt.bufPrint(&lhs_buf, "reg_{d}", .{op.lhs.id});
                const rhs = try std.fmt.bufPrint(&rhs_buf, "reg_{d}", .{op.rhs.id});
                // 快速路径：纯整数/浮点
                if (inst.result) |reg| {
                    if (reg.type_ == .i64 and op.lhs.type_ == .i64 and op.rhs.type_ == .i64) {
                        try writer.print("        {s} = {s} - {s};\n", .{ result_reg.?, lhs, rhs });
                    } else if (reg.type_ == .f64 and op.lhs.type_ == .f64 and op.rhs.type_ == .f64) {
                        try writer.print("        {s} = {s} - {s};\n", .{ result_reg.?, lhs, rhs });
                    } else {
                        try writer.print("        {s} = try runtime.php_sub({s}, {s});\n", .{ result_reg.?, lhs, rhs });
                    }
                } else {
                    try writer.print("        _ = try runtime.php_sub({s}, {s});\n", .{ lhs, rhs });
                }
            },
            .mul => |op| {
                // 所有寄存器都是 Value 类型，必须使用 php_mul
                if (inst.result) |_| {
                    try writer.print("        {s} = try runtime.php_mul(reg_{d}, reg_{d});\n", .{ result_reg.?, op.lhs.id, op.rhs.id });
                } else {
                    try writer.print("        _ = try runtime.php_mul(reg_{d}, reg_{d});\n", .{ op.lhs.id, op.rhs.id });
                }
            },
            .div => |op| {
                // 所有寄存器都是 Value 类型，必须使用 php_div
                if (inst.result) |_| {
                    try writer.print("        {s} = try runtime.php_div(reg_{d}, reg_{d});\n", .{ result_reg.?, op.lhs.id, op.rhs.id });
                }
                try writer.writeAll("        if (runtime.hasException()) return error.RuntimeError;\n");
            },
            .mod => |op| {
                // 设置源码位置，供 Deprecated 警告使用
                if (inst.location.line > 0) {
                    try writer.print("    runtime.setSourceLocation(\"{s}\", {d});\n", .{ inst.location.file, inst.location.line });
                }
                if (inst.result) |_| {
                    try writer.print("        {s} = try runtime.php_mod(reg_{d}, reg_{d});\n", .{ result_reg.?, op.lhs.id, op.rhs.id });
                }
                try writer.writeAll("        if (runtime.hasException()) return error.RuntimeError;\n");
            },
            .pow => |op| {
                if (inst.result) |reg| {
                    const lhs_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    try writer.print("    reg_{d} = try runtime.php_pow(", .{reg.id});
                    try self.writePhpValueExpr(writer, lhs_tag, op.lhs.id);
                    try writer.writeAll(", ");
                    try self.writePhpValueExpr(writer, rhs_tag, op.rhs.id);
                    try writer.writeAll(");\n");
                }
            },
            .neg => |op| {
                var operand_buf: [32]u8 = undefined;
                const operand = try std.fmt.bufPrint(&operand_buf, "reg_{d}", .{op.operand.id});
                try writer.print("        {s} = try runtime.php_sub(runtime.Value.initInt(0), {s});\n", .{ result_reg.?, operand });
            },

            // ========================================================================
            // 比较运算指令
            // ========================================================================
            .eq => |op| {
                if (inst.result) |reg| {
                    const lhs_type = if (self.current_reg_types) |types|
                        types.get(op.lhs.id) orelse op.lhs.type_
                    else
                        op.lhs.type_;
                    const rhs_type = if (self.current_reg_types) |types|
                        types.get(op.rhs.id) orelse op.rhs.type_
                    else
                        op.rhs.type_;
                    const result_type = if (self.current_reg_types) |types|
                        types.get(reg.id) orelse reg.type_
                    else
                        reg.type_;

                    const lhs_tag = @as(std.meta.Tag(IR.Type), lhs_type);
                    const rhs_tag = @as(std.meta.Tag(IR.Type), rhs_type);
                    const result_tag = @as(std.meta.Tag(IR.Type), result_type);

                    if (lhs_tag == .i64 and rhs_tag == .i64) {
                        if (result_tag == .bool) {
                            try writer.print("        {s} = reg_{d} == reg_{d};\n", .{ result_reg.?, op.lhs.id, op.rhs.id });
                        } else {
                            try writer.print("        {s} = runtime.Value.initBool(reg_{d} == reg_{d});\n", .{ result_reg.?, op.lhs.id, op.rhs.id });
                        }
                    } else {
                        if (result_tag == .bool) {
                            try writer.print("        {s} = (try runtime.php_eq(", .{result_reg.?});
                            try self.writePhpValueExpr(writer, lhs_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_tag, op.rhs.id);
                            try writer.writeAll(")).toBool();\n");
                        } else {
                            try writer.print("        {s} = try runtime.php_eq(", .{result_reg.?});
                            try self.writePhpValueExpr(writer, lhs_tag, op.lhs.id);
                            try writer.writeAll(", ");
                            try self.writePhpValueExpr(writer, rhs_tag, op.rhs.id);
                            try writer.writeAll(");\n");
                        }
                    }
                }
            },
            .ne => |op| {
                var lhs_buf: [32]u8 = undefined;
                var rhs_buf: [32]u8 = undefined;
                const lhs = try std.fmt.bufPrint(&lhs_buf, "reg_{d}", .{op.lhs.id});
                const rhs = try std.fmt.bufPrint(&rhs_buf, "reg_{d}", .{op.rhs.id});
                try writer.print("        {s} = try runtime.php_ne({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .lt => |op| {
                if (inst.result) |reg| {
                    // 获取修正后的类型
                    const lhs_type = if (self.current_reg_types) |types|
                        types.get(op.lhs.id) orelse op.lhs.type_
                    else
                        op.lhs.type_;
                    const rhs_type = if (self.current_reg_types) |types|
                        types.get(op.rhs.id) orelse op.rhs.type_
                    else
                        op.rhs.type_;
                    const result_type = if (self.current_reg_types) |types|
                        types.get(reg.id) orelse reg.type_
                    else
                        reg.type_;

                    const lhs_tag = @as(std.meta.Tag(IR.Type), lhs_type);
                    const rhs_tag = @as(std.meta.Tag(IR.Type), rhs_type);
                    const result_tag = @as(std.meta.Tag(IR.Type), result_type);

                    if (lhs_tag == .i64 and rhs_tag == .i64 and result_tag == .bool) {
                        try writer.print("        {s} = reg_{d} < reg_{d};\n", .{ result_reg.?, op.lhs.id, op.rhs.id });
                    } else {
                        try writer.print("        {s} = try runtime.php_lt(", .{result_reg.?});
                        try self.writePhpValueExpr(writer, lhs_tag, op.lhs.id);
                        try writer.writeAll(", ");
                        try self.writePhpValueExpr(writer, rhs_tag, op.rhs.id);
                        try writer.writeAll(");\n");
                    }
                }
            },
            .le => |op| {
                var lhs_buf: [32]u8 = undefined;
                var rhs_buf: [32]u8 = undefined;
                const lhs = try std.fmt.bufPrint(&lhs_buf, "reg_{d}", .{op.lhs.id});
                const rhs = try std.fmt.bufPrint(&rhs_buf, "reg_{d}", .{op.rhs.id});
                try writer.print("        {s} = try runtime.php_le({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .gt => |op| {
                var lhs_buf: [32]u8 = undefined;
                var rhs_buf: [32]u8 = undefined;
                const lhs = try std.fmt.bufPrint(&lhs_buf, "reg_{d}", .{op.lhs.id});
                const rhs = try std.fmt.bufPrint(&rhs_buf, "reg_{d}", .{op.rhs.id});
                try writer.print("        {s} = try runtime.php_gt({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .ge => |op| {
                var lhs_buf: [32]u8 = undefined;
                var rhs_buf: [32]u8 = undefined;
                const lhs = try std.fmt.bufPrint(&lhs_buf, "reg_{d}", .{op.lhs.id});
                const rhs = try std.fmt.bufPrint(&rhs_buf, "reg_{d}", .{op.rhs.id});
                try writer.print("        {s} = try runtime.php_ge({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .identical => |op| {
                var lhs_buf: [32]u8 = undefined;
                var rhs_buf: [32]u8 = undefined;
                const lhs = try std.fmt.bufPrint(&lhs_buf, "reg_{d}", .{op.lhs.id});
                const rhs = try std.fmt.bufPrint(&rhs_buf, "reg_{d}", .{op.rhs.id});
                try writer.print("        {s} = try runtime.php_identical({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .not_identical => |op| {
                var lhs_buf: [32]u8 = undefined;
                var rhs_buf: [32]u8 = undefined;
                const lhs = try std.fmt.bufPrint(&lhs_buf, "reg_{d}", .{op.lhs.id});
                const rhs = try std.fmt.bufPrint(&rhs_buf, "reg_{d}", .{op.rhs.id});
                try writer.print("        {s} = try runtime.php_not_identical({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },

            // ========================================================================
            // 位运算指令
            // ========================================================================
            .bit_and => |op| {
                if (inst.result) |_| {
                    try writer.print("        {s} = runtime.Value.initInt(reg_{d}.toInt() & reg_{d}.toInt());\n", .{ result_reg.?, op.lhs.id, op.rhs.id });
                }
            },
            .bit_or => |op| {
                if (inst.result) |_| {
                    try writer.print("        {s} = runtime.Value.initInt(reg_{d}.toInt() | reg_{d}.toInt());\n", .{ result_reg.?, op.lhs.id, op.rhs.id });
                }
            },
            .bit_xor => |op| {
                if (inst.result) |_| {
                    try writer.print("        {s} = runtime.Value.initInt(reg_{d}.toInt() ^ reg_{d}.toInt());\n", .{ result_reg.?, op.lhs.id, op.rhs.id });
                }
            },
            .shl => |op| {
                if (inst.result) |_| {
                    try writer.print("        {s} = runtime.Value.initInt(reg_{d}.toInt() << @as(u6, @intCast(@min(63, @max(0, reg_{d}.toInt())))));\n", .{ result_reg.?, op.lhs.id, op.rhs.id });
                }
            },
            .shr => |op| {
                if (inst.result) |_| {
                    try writer.print("        {s} = runtime.Value.initInt(reg_{d}.toInt() >> @as(u6, @intCast(@min(63, @max(0, reg_{d}.toInt())))));\n", .{ result_reg.?, op.lhs.id, op.rhs.id });
                }
            },

            // ========================================================================
            // 逻辑运算指令
            // ========================================================================
            .and_ => |op| {
                var lhs_buf: [32]u8 = undefined;
                var rhs_buf: [32]u8 = undefined;
                const lhs = try std.fmt.bufPrint(&lhs_buf, "reg_{d}", .{op.lhs.id});
                const rhs = try std.fmt.bufPrint(&rhs_buf, "reg_{d}", .{op.rhs.id});
                try writer.print("        {s} = try runtime.php_and({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .or_ => |op| {
                var lhs_buf: [32]u8 = undefined;
                var rhs_buf: [32]u8 = undefined;
                const lhs = try std.fmt.bufPrint(&lhs_buf, "reg_{d}", .{op.lhs.id});
                const rhs = try std.fmt.bufPrint(&rhs_buf, "reg_{d}", .{op.rhs.id});
                try writer.print("        {s} = try runtime.php_or({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .xor_ => |op| {
                var lhs_buf: [32]u8 = undefined;
                var rhs_buf: [32]u8 = undefined;
                const lhs = try std.fmt.bufPrint(&lhs_buf, "reg_{d}", .{op.lhs.id});
                const rhs = try std.fmt.bufPrint(&rhs_buf, "reg_{d}", .{op.rhs.id});
                try writer.print("        {s} = try runtime.php_xor({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .not => |op| {
                var operand_buf: [32]u8 = undefined;
                const operand_type = op.operand.type_;
                const operand_tag = @as(std.meta.Tag(IR.Type), operand_type);
                const operand = if (operand_tag == .i64)
                    try std.fmt.bufPrint(&operand_buf, "runtime.Value.initInt(reg_{d}.asInt())", .{op.operand.id})
                else if (operand_tag == .f64)
                    try std.fmt.bufPrint(&operand_buf, "runtime.Value.initFloat(reg_{d}.asFloat())", .{op.operand.id})
                else if (operand_tag == .bool)
                    try std.fmt.bufPrint(&operand_buf, "runtime.Value.initBool(reg_{d}.toBool())", .{op.operand.id})
                else
                    try std.fmt.bufPrint(&operand_buf, "reg_{d}", .{op.operand.id});
                try writer.print("        {s} = try runtime.php_not({s});\n", .{ result_reg.?, operand });
            },

            // ========================================================================
            // 字符串运算指令
            // ========================================================================
            .concat => |op| {
                var lhs_buf: [128]u8 = undefined;
                var rhs_buf: [128]u8 = undefined;
                const lhs_name = if (self.current_global_get_names) |gn| gn.get(op.lhs.id) else null;
                const rhs_name = if (self.current_global_get_names) |gn| gn.get(op.rhs.id) else null;
                const use_undef_helper = lhs_name != null or rhs_name != null;

                // 检查操作数类型，需要时转换为 Value
                const lhs_type = op.lhs.type_;
                const rhs_type = op.rhs.type_;
                const lhs_tag = @as(std.meta.Tag(IR.Type), lhs_type);
                const rhs_tag = @as(std.meta.Tag(IR.Type), rhs_type);

                // 所有寄存器都是 Value，需要类型转换
                const lhs = if (lhs_tag == .i64)
                    try std.fmt.bufPrint(&lhs_buf, "runtime.Value.initInt(reg_{d}.asInt())", .{op.lhs.id})
                else if (lhs_tag == .f64)
                    try std.fmt.bufPrint(&lhs_buf, "runtime.Value.initFloat(reg_{d}.asFloat())", .{op.lhs.id})
                else if (lhs_tag == .bool)
                    try std.fmt.bufPrint(&lhs_buf, "runtime.Value.initBool(reg_{d}.toBool())", .{op.lhs.id})
                else
                    try std.fmt.bufPrint(&lhs_buf, "reg_{d}", .{op.lhs.id});

                const rhs = if (rhs_tag == .i64)
                    try std.fmt.bufPrint(&rhs_buf, "runtime.Value.initInt(reg_{d}.asInt())", .{op.rhs.id})
                else if (rhs_tag == .f64)
                    try std.fmt.bufPrint(&rhs_buf, "runtime.Value.initFloat(reg_{d}.asFloat())", .{op.rhs.id})
                else if (rhs_tag == .bool)
                    try std.fmt.bufPrint(&rhs_buf, "runtime.Value.initBool(reg_{d}.toBool())", .{op.rhs.id})
                else
                    try std.fmt.bufPrint(&rhs_buf, "reg_{d}", .{op.rhs.id});

                if (use_undef_helper) {
                    if (lhs_name) |ln| {
                        const escaped_ln = try self.escapeString(ln);
                        defer self.allocator.free(escaped_ln);
                        if (rhs_name) |rn| {
                            const escaped_rn = try self.escapeString(rn);
                            defer self.allocator.free(escaped_rn);
                            try writer.print("        {s} = try runtime.php_concat_with_undef({s}, {s}, !globalVarIsDefined(\"{s}\"), \"{s}\", !globalVarIsDefined(\"{s}\"), \"{s}\", runtime.runtime_allocator);\n", .{ result_reg.?, lhs, rhs, escaped_ln, escaped_ln, escaped_rn, escaped_rn });
                        } else {
                            try writer.print("        {s} = try runtime.php_concat_with_undef({s}, {s}, !globalVarIsDefined(\"{s}\"), \"{s}\", false, \"\", runtime.runtime_allocator);\n", .{ result_reg.?, lhs, rhs, escaped_ln, escaped_ln });
                        }
                    } else if (rhs_name) |rn| {
                        const escaped_rn = try self.escapeString(rn);
                        defer self.allocator.free(escaped_rn);
                        try writer.print("        {s} = try runtime.php_concat_with_undef({s}, {s}, false, \"\", !globalVarIsDefined(\"{s}\"), \"{s}\", runtime.runtime_allocator);\n", .{ result_reg.?, lhs, rhs, escaped_rn, escaped_rn });
                    }
                } else {
                    try writer.print("        {s} = try runtime.php_concat({s}, {s}, runtime.runtime_allocator);\n", .{ result_reg.?, lhs, rhs });
                }
            },

            // ========================================================================
            // 函数调用指令
            // ========================================================================
            // 异常处理说明：
            // - 在 try 块中（current_exception_handler != null）：
            //   使用 catch 捕获错误，不传播到外层
            // - 在 try 块外：
            //   使用 try 传播错误到调用者
            // ========================================================================
            .call => |op| {
                // @ 错误抑制运算符：直接调用运行时函数
                if (std.mem.eql(u8, op.func_name, "php_error_suppress_push")) {
                    try writer.writeAll("    runtime.php_error_suppress_push();\n");
                } else if (std.mem.eql(u8, op.func_name, "php_error_suppress_pop")) {
                    try writer.writeAll("    runtime.php_error_suppress_pop();\n");
                } else {

                // 检查是否是内置函数
                const is_builtin = self.isBuiltinFunction(op.func_name);
                const is_runtime_declare = std.mem.startsWith(u8, op.func_name, "__declare_function__::");
                const in_try_block = self.current_exception_handler != null;

                // 生成函数调用
                if (is_runtime_declare) {
                    const declared_name = op.func_name["__declare_function__::".len..];
                    if (self.ir_module) |module| {
                        if (module.findFunction(declared_name)) |func| {
                            try writer.print("        try runtime.registerUserFunctionWithLocation(\"{s}\", @\"{s}\", \"{s}\", {d});\n", .{ declared_name, declared_name, func.location.file, func.location.line });
                            // 注册函数元数据
                            const pc = func.params.items.len;
                            var rc: usize = 0;
                            for (func.params.items) |p| {
                                if (!p.has_default and !p.is_variadic) rc += 1;
                            }
                            try writer.print("        runtime.registerFunctionMeta(\"{s}\", {d}, {d});\n", .{ declared_name, pc, rc });
                        }
                    }
                    if (result_reg) |r| {
                        try writer.print("        {s} = runtime.Value.initNull();\n", .{r});
                    }
                } else if (result_reg) |r| {
                    if (is_builtin) {
                        const runtime_name = self.mapToRuntimeFunction(op.func_name);
                        const needs_alloc = self.functionNeedsAllocator(op.func_name);

                        if (std.mem.eql(u8, runtime_name, "php_str_getcsv")) {
                            if (op.args.len < 4) {
                                try writer.writeAll("        runtime.emitDeprecatedStrGetcsvEscape();\n");
                            }
                            if (in_try_block) {
                                try writer.print("        {s} = runtime.{s}(", .{ r, runtime_name });
                            } else {
                                try writer.print("        {s} = try runtime.{s}(", .{ r, runtime_name });
                            }
                            try self.writeStrGetcsvArgs(writer, op.args);
                            try writer.writeAll(", runtime.runtime_allocator");
                            if (in_try_block) {
                                try writer.writeAll(") catch runtime.Value.initNull();\n");
                            } else {
                                try writer.writeAll(");\n");
                            }
                        } else if (std.mem.eql(u8, runtime_name, "php_in_array")) {
                            // in_array(needle, haystack, strict = false)
                            if (in_try_block) {
                                try writer.print("        {s} = runtime.{s}(", .{ r, runtime_name });
                            } else {
                                try writer.print("        {s} = try runtime.{s}(", .{ r, runtime_name });
                            }
                            for (op.args, 0..) |arg, i| {
                                if (i > 0) try writer.writeAll(", ");
                                try self.writeRegRef(writer, arg.id);
                            }
                            if (op.args.len < 3) {
                                try writer.writeAll(", runtime.Value.initBool(false)");
                            }
                            if (in_try_block) {
                                try writer.writeAll(") catch runtime.Value.initNull();\n");
                            } else {
                                try writer.writeAll(");\n");
                            }
                        } else {
                            if (in_try_block) {
                                try writer.print("        {s} = runtime.{s}(", .{ r, runtime_name });
                            } else {
                                try writer.print("        {s} = try runtime.{s}(", .{ r, runtime_name });
                            }

                            const max_args = if (std.mem.eql(u8, op.func_name, "file_put_contents"))
                                @min(op.args.len, 2)
                            else
                                op.args.len;

                            for (op.args[0..max_args], 0..) |arg, i| {
                                if (i > 0) try writer.writeAll(", ");
                                try self.writeRegRef(writer, arg.id);
                            }
                            if (needs_alloc) {
                                try writer.writeAll(", runtime.runtime_allocator");
                            }
                            if (in_try_block) {
                                try writer.writeAll(") catch runtime.Value.initNull();\n");
                            } else {
                                try writer.writeAll(");\n");
                            }
                        }
                    } else if (!self.isUserDefinedFunction(op.func_name)) {
                        // 函数未定义：生成运行时 Fatal error
                        const escaped_func_name = try self.escapeString(op.func_name);
                        defer self.allocator.free(escaped_func_name);
                        if (inst.location.line > 0) {
                            try writer.print("        runtime.setSourceLocation(\"{s}\", {d});\n", .{ inst.location.file, inst.location.line });
                        }
                        try writer.print("        runtime.php_call_undefined_function(\"{s}\");\n", .{escaped_func_name});
                    } else {
                        const escaped_func_name = try self.escapeString(op.func_name);
                        defer self.allocator.free(escaped_func_name);
                        // 用户定义函数 - 构建参数数组
                        if (op.args.len == 0) {
                            if (in_try_block) {
                                try writer.print("        {s} = @\"{s}\"(runtime.Value.initNull(), &[_]runtime.Value{{}}, runtime.runtime_allocator) catch runtime.Value.initNull();\n", .{ r, escaped_func_name });
                            } else {
                                try writer.print("        {s} = try @\"{s}\"(runtime.Value.initNull(), &[_]runtime.Value{{}}, runtime.runtime_allocator);\n", .{ r, escaped_func_name });
                            }
                        } else {
                            if (in_try_block) {
                                try writer.print("        {s} = @\"{s}\"(runtime.Value.initNull(), &[_]runtime.Value{{", .{ r, escaped_func_name });
                            } else {
                                try writer.print("        {s} = try @\"{s}\"(runtime.Value.initNull(), &[_]runtime.Value{{", .{ r, escaped_func_name });
                            }
                            for (op.args, 0..) |arg, i| {
                                if (i > 0) try writer.writeAll(", ");
                                try self.writeRegRef(writer, arg.id);
                            }
                            if (in_try_block) {
                                try writer.writeAll("}, runtime.runtime_allocator) catch runtime.Value.initNull();\n");
                            } else {
                                try writer.writeAll("}, runtime.runtime_allocator);\n");
                            }
                        }
                    }
                } else {
                    if (is_runtime_declare) {
                        const declared_name = op.func_name["__declare_function__::".len..];
                        if (self.ir_module) |module| {
                            if (module.findFunction(declared_name)) |func| {
                                try writer.print("        try runtime.registerUserFunctionWithLocation(\"{s}\", @\"{s}\", \"{s}\", {d});\n", .{ declared_name, declared_name, func.location.file, func.location.line });
                                // 注册函数元数据
                                const pc = func.params.items.len;
                                var rc: usize = 0;
                                for (func.params.items) |p| {
                                    if (!p.has_default and !p.is_variadic) rc += 1;
                                }
                                try writer.print("        runtime.registerFunctionMeta(\"{s}\", {d}, {d});\n", .{ declared_name, pc, rc });
                            }
                        }
                    } else if (is_builtin) {
                        const runtime_name = self.mapToRuntimeFunction(op.func_name);
                        const needs_alloc = self.functionNeedsAllocator(op.func_name);

                        if (std.mem.eql(u8, runtime_name, "php_str_getcsv")) {
                            if (op.args.len < 4) {
                                try writer.writeAll("        runtime.emitDeprecatedStrGetcsvEscape();\n");
                            }
                            try writer.print("        _ = try runtime.{s}(", .{runtime_name});
                            try self.writeStrGetcsvArgs(writer, op.args);
                            try writer.writeAll(", runtime.runtime_allocator);\n");
                        } else {
                            try writer.print("        _ = try runtime.{s}(", .{runtime_name});
                            for (op.args, 0..) |arg, i| {
                                if (i > 0) try writer.writeAll(", ");
                                try self.writeRegRef(writer, arg.id);
                            }
                            if (needs_alloc) {
                                try writer.writeAll(", runtime.runtime_allocator");
                            }
                            try writer.writeAll(");\n");
                        }
                    } else if (!self.isUserDefinedFunction(op.func_name)) {
                        // 函数未定义：生成运行时 Fatal error
                        const escaped_func_name = try self.escapeString(op.func_name);
                        defer self.allocator.free(escaped_func_name);
                        if (inst.location.line > 0) {
                            try writer.print("        runtime.setSourceLocation(\"{s}\", {d});\n", .{ inst.location.file, inst.location.line });
                        }
                        try writer.print("        runtime.php_call_undefined_function(\"{s}\");\n", .{escaped_func_name});
                    } else {
                        const escaped_func_name = try self.escapeString(op.func_name);
                        defer self.allocator.free(escaped_func_name);
                        // 用户定义函数 - 构建参数数组
                        if (op.args.len == 0) {
                            try writer.print("        _ = try @\"{s}\"(runtime.Value.initNull(), &[_]runtime.Value{{}}, runtime.runtime_allocator);\n", .{escaped_func_name});
                        } else {
                            try writer.print("        _ = try @\"{s}\"(runtime.Value.initNull(), &[_]runtime.Value{{", .{escaped_func_name});
                            for (op.args, 0..) |arg, i| {
                                if (i > 0) try writer.writeAll(", ");
                                try self.writeRegRef(writer, arg.id);
                            }
                            try writer.writeAll("}, runtime.runtime_allocator);\n");
                        }
                    }
                }
                } // end else (not error_suppress)
            },

            // ========================================================================
            // 数组操作指令
            // ========================================================================
            .array_new => |op| {
                _ = op;
                try self.writeRegAssignment(writer, inst.result.?.id, "runtime.Value.initArray(try runtime.PHPArray.init(runtime.runtime_allocator))");
            },
            .array_get => |op| {
                var array_buf: [32]u8 = undefined;
                var key_buf: [32]u8 = undefined;
                const array = try std.fmt.bufPrint(&array_buf, "reg_{d}", .{op.array.id});
                const key = try std.fmt.bufPrint(&key_buf, "reg_{d}", .{op.key.id});

                try writer.print("        {s} = try runtime.php_array_get({s}, {s}, runtime.runtime_allocator);\n", .{ result_reg.?, array, key });
            },
            .array_set => |op| {
                try writer.writeAll("        try ");
                try self.writeRegRef(writer, op.array.id);
                try writer.writeAll(".asArray().setByValue(runtime.runtime_allocator, ");
                try self.writeRegRef(writer, op.key.id);
                try writer.writeAll(", ");
                try self.writeRegRef(writer, op.value.id);
                try writer.writeAll(");\n");
            },
            .array_set_nested => |op| {
                // 嵌套数组赋值，支持 auto-vivification
                try writer.writeAll(
                    \\        {
                    \\            const outer_arr = reg_
                );
                try writer.print("{d}", .{op.outer_array.id});
                try writer.writeAll(
                    \\.asArray();
                    \\            var inner = outer_arr.getByValue(reg_
                );
                try writer.print("{d}", .{op.outer_key.id});
                try writer.writeAll(
                    \\);
                    \\            if (inner == null or inner.?.isNull()) {
                    \\                const new_arr = try runtime.PHPArray.init(runtime.runtime_allocator);
                    \\                const new_val = runtime.Value.initArray(new_arr);
                    \\                try outer_arr.setByValue(runtime.runtime_allocator, reg_
                );
                try writer.print("{d}", .{op.outer_key.id});
                try writer.writeAll(
                    \\, new_val);
                    \\                inner = new_val;
                    \\            }
                    \\            try inner.?.asArray().setByValue(runtime.runtime_allocator, reg_
                );
                try writer.print("{d}", .{op.inner_key.id});
                try writer.writeAll(", reg_");
                try writer.print("{d}", .{op.value.id});
                try writer.writeAll(
                    \\);
                    \\        }
                    \\
                );
            },
            .array_push => |op| {
                var array_buf: [32]u8 = undefined;
                var value_buf: [32]u8 = undefined;
                const array = try std.fmt.bufPrint(&array_buf, "reg_{d}", .{op.array.id});
                const value = try std.fmt.bufPrint(&value_buf, "reg_{d}", .{op.value.id});

                // 简化：所有寄存器都是 Value 类型，直接使用
                try writer.print("        try {s}.asArray().push(runtime.runtime_allocator, {s});\n", .{ array, value });
            },
            .array_count => |op| {
                var array_buf: [32]u8 = undefined;
                const array = try std.fmt.bufPrint(&array_buf, "reg_{d}", .{op.operand.id});
                // 根据结果寄存器类型生成不同的代码
                if (inst.result) |reg| {
                    if (reg.type_ == .i64) {
                        // 直接返回i64类型（内部计算用）
                        try writer.print("        {s} = @intCast({s}.asArray().count());\n", .{ result_reg.?, array });
                    } else {
                        // 返回Value类型（运行时边界）
                        try writer.print("        {s} = runtime.Value.initInt(@intCast({s}.asArray().count()));\n", .{ result_reg.?, array });
                    }
                }
            },

            // ========================================================================
            // 类型转换指令
            // ========================================================================
            .cast => |op| {
                var value_buf: [32]u8 = undefined;
                const value = try self.getOperandRef(&value_buf, op.value.id);

                // 获取源寄存器的实际类型（可能被 phi 特化修改）
                const src_real_type = if (self.current_register_types) |types|
                    types.get(op.value.id) orelse op.value.type_
                else
                    op.value.type_;
                const src_tag = @as(std.meta.Tag(IR.Type), src_real_type);
                const to_tag = @as(std.meta.Tag(IR.Type), op.to_type);

                // 根据目标类型生成不同的转换代码
                if (to_tag == .php_value) {
                    // 从基本类型转换到php_value
                    if (src_tag == .i64) {
                        try writer.print("        {s} = runtime.Value.initInt({s});\n", .{ result_reg.?, value });
                    } else if (src_tag == .f64) {
                        try writer.print("        {s} = runtime.Value.initFloat({s});\n", .{ result_reg.?, value });
                    } else if (src_tag == .bool) {
                        try writer.print("        {s} = runtime.Value.initBool({s});\n", .{ result_reg.?, value });
                    } else {
                        try writer.print("        {s} = {s};\n", .{ result_reg.?, value });
                    }
                } else if (to_tag == .i64) {
                    // 转换到i64
                    if (src_tag == .i64) {
                        try writer.print("        {s} = {s};\n", .{ result_reg.?, value });
                    } else {
                        try writer.print("        {s} = {s}.asInt();\n", .{ result_reg.?, value });
                    }
                } else if (to_tag == .f64) {
                    // 转换到f64
                    if (src_tag == .f64) {
                        try writer.print("        {s} = {s};\n", .{ result_reg.?, value });
                    } else {
                        try writer.print("        {s} = {s}.asFloat();\n", .{ result_reg.?, value });
                    }
                } else if (to_tag == .bool) {
                    // 转换到bool
                    if (src_tag == .bool) {
                        try writer.print("        {s} = {s};\n", .{ result_reg.?, value });
                    } else {
                        try writer.print("        {s} = {s}.asBool();\n", .{ result_reg.?, value });
                    }
                } else {
                    // 默认：直接赋值
                    try writer.print("        {s} = {s};\n", .{ result_reg.?, value });
                }
            },

            // ========================================================================
            // Box/Unbox 操作
            // ========================================================================
            .box => |op| {
                var value_buf: [32]u8 = undefined;
                const value = try self.getOperandRef(&value_buf, op.value.id);

                const from_tag = @as(std.meta.Tag(IR.Type), op.from_type);

                // 从基本类型转换到php_value
                if (from_tag == .i64) {
                    try writer.print("        {s} = runtime.Value.initInt({s});\n", .{ result_reg.?, value });
                } else if (from_tag == .f64) {
                    try writer.print("        {s} = runtime.Value.initFloat({s});\n", .{ result_reg.?, value });
                } else if (from_tag == .bool) {
                    try writer.print("        {s} = runtime.Value.initBool({s});\n", .{ result_reg.?, value });
                } else if (from_tag == .php_string) {
                    try writer.print("        {s} = runtime.Value.initString({s});\n", .{ result_reg.?, value });
                } else {
                    // 已经是php_value，直接赋值
                    try writer.print("        {s} = {s};\n", .{ result_reg.?, value });
                }
            },

            .unbox => |op| {
                var value_buf: [32]u8 = undefined;
                const value = try self.getOperandRef(&value_buf, op.value.id);

                const to_tag = @as(std.meta.Tag(IR.Type), op.to_type);

                // 从php_value提取基本类型
                if (to_tag == .i64) {
                    try writer.print("        {s} = {s}.asInt();\n", .{ result_reg.?, value });
                } else if (to_tag == .f64) {
                    try writer.print("        {s} = {s}.asFloat();\n", .{ result_reg.?, value });
                } else if (to_tag == .bool) {
                    try writer.print("        {s} = {s}.asBool();\n", .{ result_reg.?, value });
                } else {
                    try writer.print("        {s} = {s};\n", .{ result_reg.?, value });
                }
            },

            // ========================================================================
            // 异常处理指令
            // ========================================================================
            // try_begin: 标记 try 块的开始（仅用于注释）
            // try_end: 标记 try 块的结束（仅用于注释）
            // catch_: 捕获异常对象，调用 runtime.getException()
            // get_exception: 获取当前异常对象
            // clear_exception: 清除当前异常
            // ========================================================================
            .try_begin => {
                // Zig中不需要特殊的try_begin指令，但我们可以用来标记
                try writer.print("        // try begin\n", .{});
            },
            .try_end => {
                try writer.print("        // try end\n", .{});
            },
            .catch_ => |op| {
                _ = op;
                // catch块的开始 - 获取当前异常对象
                try writer.print("        // catch clause\n", .{});
                if (inst.result) |_| {
                    try writer.print("        {s} = runtime.getException();\n", .{result_reg.?});
                }
            },
            .get_exception => {
                // 获取当前捕获的异常
                if (inst.result) |_| {
                    try writer.print("        {s} = runtime.getException();\n", .{result_reg.?});
                }
            },
            .peek_exception => {
                // 查看当前异常但不消费（用于 catch 类型分派）
                if (inst.result) |_| {
                    try writer.print("        {s} = runtime.peekException();\n", .{result_reg.?});
                }
            },

            // ========================================================================
            // PHI指令（用于三元运算符等控制流合并）
            // ========================================================================
            .phi => |op| {
                // PHI 节点：根据前驱块选择值
                // 在状态机中，我们在每个前驱块跳转前设置 phi 结果
                // 这里生成默认值（第一个 incoming）
                if (inst.result) |phi_result| {
                    if (op.incoming.len > 0) {
                        const first_value = op.incoming[0].value;
                        var src_buf: [32]u8 = undefined;
                        const src_ref = try self.getOperandRef(&src_buf, first_value.id);
                        try writer.print("        reg_{d} = {s}; // PHI default\n", .{ phi_result.id, src_ref });
                    }
                }
            },

            // ========================================================================
            // 其他指令（fallback 到 Simple 版本）
            // ========================================================================
            else => {
                // Fallback: 使用 generateInstructionSimple
                var code = try std.ArrayList(u8).initCapacity(self.allocator, 0);
                defer code.deinit(self.allocator);
                try self.generateInstructionSimple(&code, inst);
                try writer.writeAll(code.items);
            },
        }

        // 使用 self 避免编译器警告
        _ = self.config.verbose;
    }

    /// Escape a string for use in Zig source code
    fn escapeString(self: *Self, str: []const u8) ![]const u8 {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(self.allocator);
        const writer = buf.writer(self.allocator);
        for (str) |c| {
            switch (c) {
                '\\' => try writer.writeAll("\\\\"),
                '"' => try writer.writeAll("\\\""),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => try writer.writeByte(c),
            }
        }
        return buf.toOwnedSlice(self.allocator);
    }

    /// 编译 Zig 代码为可执行文件
    pub fn compileToExecutable(
        self: *Self,
        zig_code: []const u8,
        output_path: []const u8,
    ) !void {
        // 创建临时目录
        const temp_dir = try self.createTempDir();

        // 写入 Zig 源文件
        const zig_file_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ temp_dir, "main.zig" },
        );
        defer self.allocator.free(zig_file_path);

        if (self.config.dump_zig) {
            const debug_path = self.config.dump_zig_path orelse "debug_aot.zig";
            const debug_file = try std.fs.cwd().createFile(debug_path, .{});
            defer debug_file.close();
            try debug_file.writeAll(zig_code);
        }

        // 检查文件是否需要更新（内容是否改变）
        var need_update = true;
        if (std.fs.cwd().openFile(zig_file_path, .{})) |existing_file| {
            defer existing_file.close();
            const existing_content = existing_file.readToEndAlloc(self.allocator, 100 * 1024 * 1024) catch null;
            if (existing_content) |content| {
                defer self.allocator.free(content);
                need_update = !std.mem.eql(u8, content, zig_code);
            }
        } else |_| {
            need_update = true;
        }

        // 只在内容改变时写入
        if (need_update) {
            const file = try std.fs.cwd().createFile(zig_file_path, .{});
            defer file.close();
            try file.writeAll(zig_code);
        }

        // 复制运行时库
        try self.copyRuntimeLib(temp_dir);

        // 调用 Zig 编译器（传入临时目录）
        try self.invokeZigCompiler(temp_dir, output_path);

        if (self.config.verbose) {
            // std.debug.print("  Compilation successful: {s}\n", .{output_path});
        }
    }

    /// 复制运行时库到临时目录
    fn copyRuntimeLib(self: *Self, temp_dir: []const u8) !void {
        // 尝试多个可能的路径
        const possible_base_paths = [_][]const u8{
            ".", // 当前目录
            "..", // 上级目录
            "../..", // 上上级目录
        };

        var found = false;
        for (possible_base_paths) |base| {
            const template_path = try std.fs.path.join(
                self.allocator,
                &[_][]const u8{ base, "src/aot/runtime_lib_template.zig" },
            );
            defer self.allocator.free(template_path);

            const template_content = std.fs.cwd().readFileAlloc(
                self.allocator,
                template_path,
                10 * 1024 * 1024,
            ) catch continue;
            defer self.allocator.free(template_content);

            const runtime_path = try std.fs.path.join(
                self.allocator,
                &[_][]const u8{ temp_dir, "runtime_lib.zig" },
            );
            defer self.allocator.free(runtime_path);

            const file = try std.fs.cwd().createFile(runtime_path, .{});
            defer file.close();
            try file.writeAll(template_content);

            // 复制其他运行时文件
            try self.copyOtherRuntimeFiles(temp_dir, base);
            found = true;
            break;
        }

        if (!found) {
            return error.FileNotFound;
        }
    }

    fn copyOtherRuntimeFiles(self: *Self, temp_dir: []const u8, base_path: []const u8) !void {
        const files = [_]struct { src: []const u8, dst: []const u8 }{
            .{ .src = "src/aot/profiler.zig", .dst = "profiler.zig" },
            .{ .src = "src/aot/flamegraph.zig", .dst = "flamegraph.zig" },
            .{ .src = "src/aot/pprof.zig", .dst = "pprof.zig" },
            .{ .src = "src/aot/concurrency_runtime.zig", .dst = "concurrency_runtime.zig" },
            .{ .src = "src/aot/array_ops_shared.zig", .dst = "array_ops_shared.zig" },
            .{ .src = "src/aot/nanbox_abi.zig", .dst = "nanbox_abi.zig" },
        };

        for (files) |f| {
            const src_path = try std.fs.path.join(
                self.allocator,
                &[_][]const u8{ base_path, f.src },
            );
            defer self.allocator.free(src_path);

            const content = std.fs.cwd().readFileAlloc(
                self.allocator,
                src_path,
                10 * 1024 * 1024,
            ) catch {
                continue;
            };
            defer self.allocator.free(content);

            const dest = try std.fs.path.join(
                self.allocator,
                &[_][]const u8{ temp_dir, f.dst },
            );
            defer self.allocator.free(dest);

            const dest_file = try std.fs.cwd().createFile(dest, .{});
            defer dest_file.close();
            try dest_file.writeAll(content);
        }

        if (self.config.verbose) {
            // std.debug.print("  Copied runtime libraries to {s}\n", .{temp_dir});
        }
    }

    /// 调用 Zig 编译器
    fn invokeZigCompiler(self: *Self, temp_dir: []const u8, output_path: []const u8) !void {
        var args = std.ArrayList([]const u8){};
        defer args.deinit(self.allocator);

        // 基本命令
        try args.append(self.allocator, "zig");
        try args.append(self.allocator, "build-exe");

        // 使用相对路径 main.zig（因为我们会在临时目录中运行）
        try args.append(self.allocator, "main.zig");

        // 输出路径（转换为绝对路径）
        const abs_output_path = if (std.fs.path.isAbsolute(output_path))
            output_path
        else blk: {
            const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
            defer self.allocator.free(cwd);
            break :blk try std.fs.path.join(self.allocator, &[_][]const u8{ cwd, output_path });
        };
        defer if (!std.fs.path.isAbsolute(output_path)) self.allocator.free(abs_output_path);

        const output_arg = try std.fmt.allocPrint(
            self.allocator,
            "-femit-bin={s}",
            .{abs_output_path},
        );
        defer self.allocator.free(output_arg);
        try args.append(self.allocator, output_arg);

        // 优化级别
        const opt_flag = try std.fmt.allocPrint(
            self.allocator,
            "-O{s}",
            .{self.config.optimize_level.toZigOptimize()},
        );
        defer self.allocator.free(opt_flag);
        try args.append(self.allocator, opt_flag);

        if (self.config.optimize_level != .debug) {
            try args.append(self.allocator, "-fomit-frame-pointer");
            try args.append(self.allocator, "-fno-unwind-tables");
            try args.append(self.allocator, "-fno-error-tracing");
        }

        if (self.config.optimize_level == .release_fast or self.config.optimize_level == .release_small) {
            try args.append(self.allocator, "-flto");
        }

        // 目标平台
        const target_str = try self.getTargetString();
        defer self.allocator.free(target_str);
        try args.append(self.allocator, "-target");
        try args.append(self.allocator, target_str);

        if (self.config.mcpu) |cpu| {
            if (cpu.len > 0) {
                const mcpu_arg = try std.fmt.allocPrint(self.allocator, "-mcpu={s}", .{cpu});
                defer self.allocator.free(mcpu_arg);
                try args.append(self.allocator, mcpu_arg);
            }
        }

        for (self.config.extra_zig_flags) |flag| {
            try args.append(self.allocator, flag);
        }

        // 链接PCRE2库（正则表达式支持）
        try args.append(self.allocator, "-lpcre2-8");
        // 添加库搜索路径（仅在目录存在时）
        if (self.config.target.os == .macos) {
            const has_homebrew_lib = blk: {
                std.fs.accessAbsolute("/opt/homebrew/lib", .{}) catch |err| switch (err) {
                    error.FileNotFound => break :blk false,
                    else => return err,
                };
                break :blk true;
            };
            if (has_homebrew_lib) {
                try args.append(self.allocator, "-L/opt/homebrew/lib");
            }

            const has_usr_local_lib = blk: {
                std.fs.accessAbsolute("/usr/local/lib", .{}) catch |err| switch (err) {
                    error.FileNotFound => break :blk false,
                    else => return err,
                };
                break :blk true;
            };
            if (has_usr_local_lib) {
                try args.append(self.allocator, "-L/usr/local/lib");
            }
        }

        // 静态链接（macOS 不支持）
        if (self.config.static_link and self.config.target.os != .macos) {
            try args.append(self.allocator, "-static");
        }

        const want_strip = self.config.strip_symbols or (!self.config.debug_info and self.config.optimize_level != .debug);
        if (want_strip) {
            try args.append(self.allocator, "-fstrip");
        }

        if (self.config.emit_asm_path) |p| {
            if (p.len == 0) {
                const derived = try std.fmt.allocPrint(self.allocator, "{s}.s", .{output_path});
                defer self.allocator.free(derived);
                const emit = try std.fmt.allocPrint(self.allocator, "-femit-asm={s}", .{derived});
                defer self.allocator.free(emit);
                try args.append(self.allocator, emit);
            } else {
                const emit = try std.fmt.allocPrint(self.allocator, "-femit-asm={s}", .{p});
                defer self.allocator.free(emit);
                try args.append(self.allocator, emit);
            }
        }

        if (self.config.emit_llvm_ir_path) |p| {
            if (p.len == 0) {
                const derived = try std.fmt.allocPrint(self.allocator, "{s}.ll", .{output_path});
                defer self.allocator.free(derived);
                const emit = try std.fmt.allocPrint(self.allocator, "-femit-llvm-ir={s}", .{derived});
                defer self.allocator.free(emit);
                try args.append(self.allocator, emit);
            } else {
                const emit = try std.fmt.allocPrint(self.allocator, "-femit-llvm-ir={s}", .{p});
                defer self.allocator.free(emit);
                try args.append(self.allocator, emit);
            }
        }

        if (self.config.emit_llvm_bc_path) |p| {
            if (p.len == 0) {
                const derived = try std.fmt.allocPrint(self.allocator, "{s}.bc", .{output_path});
                defer self.allocator.free(derived);
                const emit = try std.fmt.allocPrint(self.allocator, "-femit-llvm-bc={s}", .{derived});
                defer self.allocator.free(emit);
                try args.append(self.allocator, emit);
            } else {
                const emit = try std.fmt.allocPrint(self.allocator, "-femit-llvm-bc={s}", .{p});
                defer self.allocator.free(emit);
                try args.append(self.allocator, emit);
            }
        }

        if (self.config.verbose) {
            // std.debug.print("  Invoking Zig compiler: ", .{});
            for (args.items) |_| {
                // std.debug.print("{s} ", .{arg});
            }
            // std.debug.print("\n", .{});
        }

        // 执行编译命令（在临时目录中运行）
        var child = std.process.Child.init(args.items, self.allocator);
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        child.cwd = temp_dir;

        const term = try child.spawnAndWait();
        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    self.diagnostics.reportError(
                        .{ .line = 0, .column = 0 },
                        "Zig compiler failed with exit code {d}",
                        .{code},
                    );
                    return error.CompilationFailed;
                }
            },
            else => {
                self.diagnostics.reportError(
                    .{ .line = 0, .column = 0 },
                    "Zig compiler terminated abnormally",
                    .{},
                );
                return error.CompilationFailed;
            },
        }
    }

    /// 获取目标平台字符串
    fn getTargetString(self: *Self) ![]const u8 {
        const arch_str = switch (self.config.target.arch) {
            .x86_64 => "x86_64",
            .aarch64 => "aarch64",
            .arm => "arm",
        };

        const os_str = switch (self.config.target.os) {
            .linux => "linux",
            .macos => "macos",
            .windows => "windows",
        };

        const abi_str = switch (self.config.target.abi) {
            .gnu => "gnu",
            .musl => "musl",
            .msvc => "msvc",
            .none => "",
        };

        if (abi_str.len > 0) {
            return try std.fmt.allocPrint(
                self.allocator,
                "{s}-{s}-{s}",
                .{ arch_str, os_str, abi_str },
            );
        } else {
            return try std.fmt.allocPrint(
                self.allocator,
                "{s}-{s}",
                .{ arch_str, os_str },
            );
        }
    }
};
