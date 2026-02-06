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
    /// 详细输出
    verbose: bool = false,
    /// Dump generated Zig code
    dump_zig: bool = false,
    /// Path to dump Zig code (optional)
    dump_zig_path: ?[]const u8 = null,
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
    allocator: Allocator,
    config: NativeLinkerConfig,
    diagnostics: *DiagnosticEngine,
    temp_dir: ?[]const u8,
    func_return_types: std.StringHashMap(bool), // 函数名 -> 是否有返回值
    current_reg_types: ?*const std.AutoHashMap(usize, IR.Type),
    current_reg_is_value: ?[]bool,
    current_function_has_this: bool = false,
    current_exception_handler: ?u32 = null,
    current_cleanup_regs: ?[]const usize = null,
    current_alloca_regs: ?*const std.AutoHashMap(usize, void) = null,

    const Self = @This();

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
            .current_function_has_this = false,
            .current_exception_handler = null,
            .current_cleanup_regs = null,
            .current_alloca_regs = null,
        };
        return self;
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        if (self.temp_dir) |dir| {
            // 清理临时目录（调试时可以注释掉以保留生成的代码）
            // 暂时保留生成的代码以便调试
            // if (!self.config.verbose) {
            //     std.fs.cwd().deleteTree(dir) catch {};
            // }
            self.allocator.free(dir);
        }
        self.func_return_types.deinit();
        self.allocator.destroy(self);
    }

    /// 创建临时目录
    fn createTempDir(self: *Self) ![]const u8 {
        if (self.temp_dir) |dir| {
            return dir;
        }

        // 使用固定的临时目录名
        const temp_name = try self.allocator.dupe(u8, ".zigphp_aot_build");
        errdefer self.allocator.free(temp_name);

        // 如果目录已存在，先删除
        std.fs.cwd().deleteTree(temp_name) catch {};

        // 创建目录
        try std.fs.cwd().makeDir(temp_name);
        self.temp_dir = temp_name;

        return temp_name;
    }

    /// 将 IR 模块转换为 Zig 代码
    pub fn generateZigCode(self: *Self, ir_module: *const IR.Module) ![]const u8 {
        var code = std.ArrayList(u8){};
        errdefer code.deinit(self.allocator);

        // 创建writer并确保它的生命周期覆盖整个函数
        var writer = code.writer(self.allocator);

        // 收集所有函数的返回类型信息
        self.func_return_types.clearRetainingCapacity();

        for (ir_module.functions.items) |func| {
            // 检查函数是否有返回值
            var has_return_value = false;
            for (func.blocks.items) |block| {
                if (block.terminator) |term| {
                    if (term == .ret and term.ret != null) {
                        has_return_value = true;
                        break;
                    }
                }
            }
            try self.func_return_types.put(func.name, has_return_value);
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
        }

        // 生成全局变量
        for (ir_module.globals.items) |global| {
            try self.generateGlobalVariable(writer, global);
        }

        // 生成函数
        for (ir_module.functions.items) |func| {
            try self.generateFunction(&code, func);
        }

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
        for (ir_module.functions.items) |func| {
            if (std.mem.eql(u8, func.name, "get_class_methods")) has_get_class_methods = true;
            if (std.mem.eql(u8, func.name, "get_class_vars")) has_get_class_vars = true;
            if (std.mem.eql(u8, func.name, "get_object_vars")) has_get_object_vars = true;
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

        // 生成类注册函数
        try self.generateClassRegistration(writer, ir_module);

        // 生成函数注册函数
        try self.generateFunctionRegistration(writer, ir_module);

        // 生成主入口
        try writer.writeAll(
            \\
            \\pub fn main() !void {
            \\    const allocator = std.heap.page_allocator;
            \\    
            \\    runtime.initRuntime(allocator);
            \\    defer runtime.deinitRuntime();
            \\    
            \\    // 注册所有类
            \\    registerAllClasses(allocator) catch {};
            \\    // 注册所有函数
            \\    registerAllFunctions() catch {};
            \\    defer runtime.cleanupAllClasses();
            \\    
            \\    _ = try @"__main__"(runtime.Value.initNull(), &[_]runtime.Value{}, allocator);
            \\    _ = runtime.php_go_wait_all(runtime.Value.initNull(), &[_]runtime.Value{}, allocator) catch {};
            \\}
            \\
        );

        return code.toOwnedSlice(self.allocator);
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

            // 直接注册函数，因为函数签名已经统一
            try writer.print("    try runtime.registerUserFunction(\"{s}\", @\"{s}\");\n", .{func.name, func.name});
        }

        try writer.writeAll(
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
        var class_names: [64][]const u8 = undefined;
        var type_def_idx: [64]?usize = [_]?usize{null} ** 64;
        var method_lists: [64][64][]const u8 = undefined;
        var method_counts: [64]usize = [_]usize{0} ** 64;

        for (ir_module.types.items, 0..) |td_ptr, idx| {
            const td = td_ptr.*;
            if (td.kind != .class) continue;
            if (class_count >= 64) break;
            class_names[class_count] = td.name;
            type_def_idx[class_count] = idx;
            class_count += 1;
        }

        for (ir_module.functions.items) |func| {
            if (std.mem.indexOf(u8, func.name, "::")) |sep_pos| {
                const cname = func.name[0..sep_pos];
                const mname = func.name[sep_pos + 2 ..];

                var found_idx: ?usize = null;
                for (0..class_count) |i| {
                    if (std.mem.eql(u8, class_names[i], cname)) {
                        found_idx = i;
                        break;
                    }
                }

                if (found_idx) |idx| {
                    if (method_counts[idx] < 64) {
                        method_lists[idx][method_counts[idx]] = mname;
                        method_counts[idx] += 1;
                    }
                }
            }
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
            const cname = class_names[ci];
            try writer.print("    const {s}_meta = try runtime.ClassMeta.init(allocator, \"{s}\");\n", .{ cname, cname });

            if (type_def_idx[ci]) |tdi| {
                const td = ir_module.types.items[tdi].*;
                for (td.properties) |prop| {
                    const is_public = prop.visibility == .public;
                    try writer.print("    try {s}_meta.addProperty(.{{ .name = \"{s}\", .default_value = ", .{ cname, prop.name });
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
                            else => try writer.writeAll("runtime.Value.initNull()"),
                        }
                    } else {
                        try writer.writeAll("runtime.Value.initNull()");
                    }
                    try writer.print(", .is_static = {}, .is_public = {}, .is_readonly = false }});\n", .{ prop.is_static, is_public });

                    if (prop.is_static) {
                        try writer.print("    try {s}_meta.setStaticProperty(\"{s}\", ", .{ cname, prop.name });
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
                                else => try writer.writeAll("runtime.Value.initNull()"),
                            }
                        } else {
                            try writer.writeAll("runtime.Value.initNull()");
                        }
                        try writer.writeAll(");\n");
                    }
                }

                for (td.traits) |tname| {
                    var trait_td: ?*const IR.TypeDef = null;
                    for (ir_module.types.items) |tptr| {
                        const tdef = tptr.*;
                        if (tdef.kind == .trait and std.mem.eql(u8, tdef.name, tname)) {
                            trait_td = tptr;
                            break;
                        }
                    }

                    if (trait_td) |tptr| {
                        const tdef = tptr.*;
                        for (tdef.properties) |prop| {
                            const is_public = prop.visibility == .public;
                            try writer.print("    if ({s}_meta.properties.get(\"{s}\") == null) {{\n", .{ cname, prop.name });
                            try writer.print("        try {s}_meta.addProperty(.{{ .name = \"{s}\", .default_value = ", .{ cname, prop.name });
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
                                    else => try writer.writeAll("runtime.Value.initNull()"),
                                }
                            } else {
                                try writer.writeAll("runtime.Value.initNull()");
                            }
                            try writer.print(", .is_static = {}, .is_public = {}, .is_readonly = false }});\n", .{ prop.is_static, is_public });

                            if (prop.is_static) {
                                try writer.print("        try {s}_meta.setStaticProperty(\"{s}\", ", .{ cname, prop.name });
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
                                        else => try writer.writeAll("runtime.Value.initNull()"),
                                    }
                                } else {
                                    try writer.writeAll("runtime.Value.initNull()");
                                }
                                try writer.writeAll(");\n");
                            }
                            try writer.writeAll("    }\n");
                        }
                    }
                }
            }

            for (0..method_counts[ci]) |mi| {
                const mname = method_lists[ci][mi];
                const full_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ cname, mname });
                defer self.allocator.free(full_name);

                var is_static: bool = false;
                if (self.findFunction(ir_module, full_name)) |method_func| {
                    if (!(method_func.params.items.len > 0 and std.mem.eql(u8, method_func.params.items[0].name, "this"))) {
                        is_static = true;
                    }
                }

                try writer.print("    try {s}_meta.addMethod(.{{ .name = \"{s}\", .func = @\"{s}::{s}\", .is_static = {} }});\n", .{ cname, mname, cname, mname, is_static });
            }

            if (type_def_idx[ci]) |tdi| {
                const td = ir_module.types.items[tdi].*;
                for (td.traits) |tname| {
                    for (ir_module.functions.items) |tfunc| {
                        if (std.mem.indexOf(u8, tfunc.name, "::")) |sep_pos| {
                            const tcname = tfunc.name[0..sep_pos];
                            if (!std.mem.eql(u8, tcname, tname)) continue;
                            const tmname = tfunc.name[sep_pos + 2 ..];

                            var is_static: bool = false;
                            if (!(tfunc.params.items.len > 0 and std.mem.eql(u8, tfunc.params.items[0].name, "this"))) {
                                is_static = true;
                            }

                            try writer.print(
                                "    if ({s}_meta.methods.get(\"{s}\") == null) try {s}_meta.addMethod(.{{ .name = \"{s}\", .func = @\"{s}::{s}\", .is_static = {} }});\n",
                                .{ cname, tmname, cname, tmname, tname, tmname, is_static },
                            );
                        }
                    }
                }
            }

            try writer.print("    try runtime.registerClass({s}_meta);\n", .{cname});
        }

        for (0..class_count) |ci| {
            if (type_def_idx[ci]) |tdi| {
                const td = ir_module.types.items[tdi].*;
                if (td.parent) |parent_name| {
                    const escaped_parent = try self.escapeString(parent_name);
                    defer self.allocator.free(escaped_parent);
                    try writer.print(
                        "    {s}_meta.parent = if (runtime.findClass(\"{s}\")) |p| p else null;\n",
                        .{ class_names[ci], escaped_parent },
                    );
                }
            }
        }

        for (0..class_count) |ci| {
            const cname = class_names[ci];
            try writer.print("    if ({s}_meta.findMethod(\"__construct\")) |m| {{ {s}_meta.magic_construct = m.func; }}\n", .{ cname, cname });
            try writer.print("    if ({s}_meta.findMethod(\"__destruct\")) |m| {{ {s}_meta.magic_destruct = m.func; }}\n", .{ cname, cname });
            try writer.print("    if ({s}_meta.findMethod(\"__get\")) |m| {{ {s}_meta.magic_get = m.func; }}\n", .{ cname, cname });
            try writer.print("    if ({s}_meta.findMethod(\"__set\")) |m| {{ {s}_meta.magic_set = m.func; }}\n", .{ cname, cname });
            try writer.print("    if ({s}_meta.findMethod(\"__call\")) |m| {{ {s}_meta.magic_call = m.func; }}\n", .{ cname, cname });
            try writer.print("    if ({s}_meta.findMethod(\"__callStatic\")) |m| {{ {s}_meta.magic_callStatic = m.func; }}\n", .{ cname, cname });
            try writer.print("    if ({s}_meta.findMethod(\"__sleep\")) |m| {{ {s}_meta.magic_sleep = m.func; }}\n", .{ cname, cname });
            try writer.print("    if ({s}_meta.findMethod(\"__wakeup\")) |m| {{ {s}_meta.magic_wakeup = m.func; }}\n", .{ cname, cname });
            try writer.print("    if ({s}_meta.findMethod(\"__serialize\")) |m| {{ {s}_meta.magic_serialize = m.func; }}\n", .{ cname, cname });
            try writer.print("    if ({s}_meta.findMethod(\"__unserialize\")) |m| {{ {s}_meta.magic_unserialize = m.func; }}\n", .{ cname, cname });
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

        const needs_allocator = [_][]const u8{
            // 字符串函数
            "strtoupper",  "strtolower",   "trim",       "ltrim",        "rtrim",
            "str_replace", "str_repeat",   "str_pad",    "strrev",       "ucfirst",
            "lcfirst",     "ucwords",      "explode",    "implode",      "str_split",
            "strcasecmp",  "substr",       "strval",

            // 数组函数
                "array_push",   "array_pop",
            "array_slice", "array_merge",  "array_keys", "array_values",
            "array_map",   "array_filter", "array_reduce", "array_chunk",

            // 时间函数
            "microtime",
            "date",

            // 文件函数
            "file_get_contents", "file_put_contents",
            "basename", "dirname",

            // 随机数函数
                   "random_bytes",

            // 其他
            "php_concat",
            "php_array_iter_init",
            "php_array_iter_key",
            "php_array_iter_free",
            "php_create_closure",
            "php_define",
            "define",
            "php_constant_get",
            "go",
            "php_go_builtin",
            "class_exists",
            "get_class",
            "serialize",
            "unserialize",
        };

        for (needs_allocator) |name| {
            if (std.mem.eql(u8, func_name, name)) return true;
        }

        return false;
    }

    /// 检查是否是内置函数
    fn isBuiltinFunction(self: *const Self, func_name: []const u8) bool {
        _ = self;

        // 已经是php_前缀的是内置函数
        if (std.mem.startsWith(u8, func_name, "php_")) return true;

        // 常见的PHP内置函数
        const builtins = [_][]const u8{
            // 输出函数
            "echo",             "print",        "var_dump",     "print_r",         "var_export",

            // 常量函数
            "define",           "defined",

            // 字符串函数
            "strlen",           "substr",       "strpos",       "strtoupper",      "strtolower",
            "trim",             "ltrim",        "rtrim",        "str_replace",     "str_repeat",
            "str_pad",          "strrev",       "str_contains", "str_starts_with", "str_ends_with",
            "ucfirst",          "lcfirst",      "ucwords",      "explode",         "implode",
            "join",             "str_split",    "strcmp",       "strcasecmp",

            // 数组函数
            "count",
            "array_push",       "array_pop",    "array_shift",  "array_unshift",   "in_array",
            "array_key_exists", "array_keys",   "array_values", "array_slice",     "array_merge",
            "array_map",        "array_filter", "array_reduce", "array_chunk",

            // 数学函数
            "abs",              "sqrt",         "round",        "floor",           "ceil",
            "min",              "max",          "pow",          "sin",             "cos",
            "tan",              "asin",         "acos",         "atan",            "atan2",
            "log",              "log10",        "exp",          "fmod",            "hypot",
            "deg2rad",          "rad2deg",      "pi",           "rand",            "mt_rand",

            // 时间函数
            "time",             "microtime",    "date",
            "sleep",            "usleep",

            // 随机数函数
                    "srand",           "mt_srand",
            "random_int",       "random_bytes",

            // 类型检查函数
            "is_null",      "is_bool",         "is_int",
            "is_float",         "is_string",    "is_array",

            // 类型转换函数
            "intval",           "floatval",
            "strval",           "boolval",

            // 文件函数
            "file_get_contents", "file_put_contents", "file_exists", "is_file", "is_dir",
            "filesize", "unlink", "rename", "copy", "mkdir", "rmdir", "basename", "dirname",

            // 其他
            "isset",            "empty",            "unset",
            "die",              "exit",
            "go",
            "class_exists",     "method_exists",    "property_exists",
            "get_class",
            "serialize",        "unserialize",
        };

        for (builtins) |builtin| {
            if (std.mem.eql(u8, func_name, builtin)) return true;
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

        // 映射表
        if (std.mem.eql(u8, func_name, "echo")) return "php_echo";
        if (std.mem.eql(u8, func_name, "print")) return "php_print";
        if (std.mem.eql(u8, func_name, "var_dump")) return "php_var_dump";

        // 常量函数
        if (std.mem.eql(u8, func_name, "define")) return "php_define";
        if (std.mem.eql(u8, func_name, "defined")) return "php_defined";

        // 反射/对象查询
        if (std.mem.eql(u8, func_name, "class_exists")) return "php_class_exists";
        if (std.mem.eql(u8, func_name, "method_exists")) return "php_method_exists";
        if (std.mem.eql(u8, func_name, "property_exists")) return "php_property_exists";
        if (std.mem.eql(u8, func_name, "get_class")) return "php_get_class";
        if (std.mem.eql(u8, func_name, "serialize")) return "php_serialize";
        if (std.mem.eql(u8, func_name, "unserialize")) return "php_unserialize";

        // 字符串函数
        if (std.mem.eql(u8, func_name, "strlen")) return "php_strlen";
        if (std.mem.eql(u8, func_name, "substr")) return "php_substr";
        if (std.mem.eql(u8, func_name, "strpos")) return "php_strpos";
        if (std.mem.eql(u8, func_name, "strtoupper")) return "php_strtoupper";
        if (std.mem.eql(u8, func_name, "strtolower")) return "php_strtolower";
        if (std.mem.eql(u8, func_name, "trim")) return "php_trim";
        if (std.mem.eql(u8, func_name, "ltrim")) return "php_ltrim";
        if (std.mem.eql(u8, func_name, "rtrim")) return "php_rtrim";
        if (std.mem.eql(u8, func_name, "str_replace")) return "php_str_replace";
        if (std.mem.eql(u8, func_name, "str_repeat")) return "php_str_repeat";
        if (std.mem.eql(u8, func_name, "str_pad")) return "php_str_pad";
        if (std.mem.eql(u8, func_name, "strrev")) return "php_strrev";
        if (std.mem.eql(u8, func_name, "str_contains")) return "php_str_contains";
        if (std.mem.eql(u8, func_name, "str_starts_with")) return "php_str_starts_with";
        if (std.mem.eql(u8, func_name, "str_ends_with")) return "php_str_ends_with";
        if (std.mem.eql(u8, func_name, "ucfirst")) return "php_ucfirst";
        if (std.mem.eql(u8, func_name, "lcfirst")) return "php_lcfirst";
        if (std.mem.eql(u8, func_name, "ucwords")) return "php_ucwords";
        if (std.mem.eql(u8, func_name, "explode")) return "php_explode";
        if (std.mem.eql(u8, func_name, "implode")) return "php_implode";
        if (std.mem.eql(u8, func_name, "str_split")) return "php_str_split";
        if (std.mem.eql(u8, func_name, "strcmp")) return "php_strcmp";
        if (std.mem.eql(u8, func_name, "strcasecmp")) return "php_strcasecmp";

        // 数组函数
        if (std.mem.eql(u8, func_name, "count")) return "php_count";
        if (std.mem.eql(u8, func_name, "array_push")) return "php_array_push";
        if (std.mem.eql(u8, func_name, "array_pop")) return "php_array_pop";
        if (std.mem.eql(u8, func_name, "in_array")) return "php_in_array";
        if (std.mem.eql(u8, func_name, "array_keys")) return "php_array_keys";
        if (std.mem.eql(u8, func_name, "array_values")) return "php_array_values";
        if (std.mem.eql(u8, func_name, "array_slice")) return "php_array_slice";
        if (std.mem.eql(u8, func_name, "array_merge")) return "php_array_merge";
        if (std.mem.eql(u8, func_name, "array_map")) return "php_array_map";
        if (std.mem.eql(u8, func_name, "array_filter")) return "php_array_filter";
        if (std.mem.eql(u8, func_name, "array_reduce")) return "php_array_reduce";
        if (std.mem.eql(u8, func_name, "array_chunk")) return "php_array_chunk";

        // 数学函数
        if (std.mem.eql(u8, func_name, "abs")) return "php_abs";
        if (std.mem.eql(u8, func_name, "sqrt")) return "php_sqrt";
        if (std.mem.eql(u8, func_name, "round")) return "php_round";
        if (std.mem.eql(u8, func_name, "floor")) return "php_floor";
        if (std.mem.eql(u8, func_name, "ceil")) return "php_ceil";
        if (std.mem.eql(u8, func_name, "min")) return "php_min";
        if (std.mem.eql(u8, func_name, "max")) return "php_max";
        if (std.mem.eql(u8, func_name, "pow")) return "php_pow_func";
        if (std.mem.eql(u8, func_name, "sin")) return "php_sin";
        if (std.mem.eql(u8, func_name, "cos")) return "php_cos";
        if (std.mem.eql(u8, func_name, "tan")) return "php_tan";
        if (std.mem.eql(u8, func_name, "asin")) return "php_asin";
        if (std.mem.eql(u8, func_name, "acos")) return "php_acos";
        if (std.mem.eql(u8, func_name, "atan")) return "php_atan";
        if (std.mem.eql(u8, func_name, "atan2")) return "php_atan2";
        if (std.mem.eql(u8, func_name, "log")) return "php_log";
        if (std.mem.eql(u8, func_name, "log10")) return "php_log10";
        if (std.mem.eql(u8, func_name, "exp")) return "php_exp";
        if (std.mem.eql(u8, func_name, "fmod")) return "php_fmod";
        if (std.mem.eql(u8, func_name, "hypot")) return "php_hypot";
        if (std.mem.eql(u8, func_name, "deg2rad")) return "php_deg2rad";
        if (std.mem.eql(u8, func_name, "rad2deg")) return "php_rad2deg";
        if (std.mem.eql(u8, func_name, "pi")) return "php_pi";
        if (std.mem.eql(u8, func_name, "rand")) return "php_rand";
        if (std.mem.eql(u8, func_name, "mt_rand")) return "php_mt_rand";

        // 时间函数
        if (std.mem.eql(u8, func_name, "time")) return "php_time";
        if (std.mem.eql(u8, func_name, "microtime")) return "php_microtime";
        if (std.mem.eql(u8, func_name, "date")) return "php_date";
        if (std.mem.eql(u8, func_name, "sleep")) return "php_sleep";
        if (std.mem.eql(u8, func_name, "usleep")) return "php_usleep";

        // 随机数函数
        if (std.mem.eql(u8, func_name, "srand")) return "php_srand";
        if (std.mem.eql(u8, func_name, "mt_srand")) return "php_mt_srand";
        if (std.mem.eql(u8, func_name, "random_int")) return "php_random_int";
        if (std.mem.eql(u8, func_name, "random_bytes")) return "php_random_bytes";

        // 类型检查函数
        if (std.mem.eql(u8, func_name, "is_null")) return "php_is_null";
        if (std.mem.eql(u8, func_name, "is_bool")) return "php_is_bool";
        if (std.mem.eql(u8, func_name, "is_int")) return "php_is_int";
        if (std.mem.eql(u8, func_name, "is_float")) return "php_is_float";
        if (std.mem.eql(u8, func_name, "is_string")) return "php_is_string";
        if (std.mem.eql(u8, func_name, "is_array")) return "php_is_array";

        // 类型转换函数
        if (std.mem.eql(u8, func_name, "intval")) return "php_intval";
        if (std.mem.eql(u8, func_name, "floatval")) return "php_floatval";
        if (std.mem.eql(u8, func_name, "strval")) return "php_strval";
        if (std.mem.eql(u8, func_name, "boolval")) return "php_boolval";

        // 文件函数
        if (std.mem.eql(u8, func_name, "file_get_contents")) return "php_file_get_contents";
        if (std.mem.eql(u8, func_name, "file_put_contents")) return "php_file_put_contents";
        if (std.mem.eql(u8, func_name, "file_exists")) return "php_file_exists";
        if (std.mem.eql(u8, func_name, "is_file")) return "php_is_file";
        if (std.mem.eql(u8, func_name, "is_dir")) return "php_is_dir";
        if (std.mem.eql(u8, func_name, "filesize")) return "php_filesize";
        if (std.mem.eql(u8, func_name, "unlink")) return "php_unlink";
        if (std.mem.eql(u8, func_name, "rename")) return "php_rename";
        if (std.mem.eql(u8, func_name, "copy")) return "php_copy";
        if (std.mem.eql(u8, func_name, "mkdir")) return "php_mkdir";
        if (std.mem.eql(u8, func_name, "rmdir")) return "php_rmdir";
        if (std.mem.eql(u8, func_name, "basename")) return "php_basename";
        if (std.mem.eql(u8, func_name, "dirname")) return "php_dirname";

        if (std.mem.eql(u8, func_name, "go")) return "php_go_builtin";

        // 默认：添加php_前缀
        // 注意：这里应该分配新的字符串，但为了简单起见，我们假设调用者会处理
        return func_name;
    }

    /// 生成函数
    fn generateFunction(self: *Self, code: *std.ArrayList(u8), func: *const IR.Function) !void {
        const has_this = func.params.items.len > 0 and std.mem.eql(u8, func.params.items[0].name, "this");
        self.current_function_has_this = has_this;

        // 验证函数名
        if (func.name.len == 0 or !std.unicode.utf8ValidateSlice(func.name)) {
            return error.InvalidFunctionName;
        }

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
        try code.appendSlice(self.allocator, "\npub fn @\"");
        try code.appendSlice(self.allocator, func.name);
        try code.appendSlice(self.allocator, "\"(");

        // 统一函数签名：(ctx: runtime.Value, args: []const runtime.Value, allocator: std.mem.Allocator) !runtime.Value
        try code.appendSlice(self.allocator, "ctx: runtime.Value, args: []const runtime.Value, allocator: std.mem.Allocator) !runtime.Value {\n");
        try code.appendSlice(self.allocator, "    _ = &ctx;\n");
        try code.appendSlice(self.allocator, "    _ = &args;\n");
        try code.appendSlice(self.allocator, "    _ = allocator;\n");
        try code.appendSlice(self.allocator, "    _ = runtime;\n");

        // 变量声明

        // 收集寄存器信息
        var all_registers = std.AutoHashMap(usize, IR.Type).init(self.allocator);
        defer all_registers.deinit();

        var alloca_registers = std.AutoHashMap(usize, void).init(self.allocator);
        defer alloca_registers.deinit();

        // 收集需要释放的寄存器（字符串、数组等）
        var cleanup_registers: std.ArrayList(usize) = .empty;
        defer cleanup_registers.deinit(self.allocator);

        // 收集寄存器定义
        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                if (inst.result) |reg| {
                    try all_registers.put(reg.id, reg.type_);
                    if (inst.op == .alloca) {
                        try alloca_registers.put(reg.id, {});
                    }

                    // 检查是否需要释放（字符串、数组等需要分配内存的类型）
                    if (inst.op != .alloca) {
                        // 检查是否是字符串或数组相关的指令
                        switch (inst.op) {
                            .const_string, .concat, .array_new, .new_object => {
                                // 这些指令创建新的Value，需要释放
                                try cleanup_registers.append(self.allocator, reg.id);
                            },
                            .call => {
                                // 内置函数调用可能返回需要释放的资源（如字符串、数组）
                                // 我们保守地释放所有Value类型的返回值
                                if (reg.type_ == .php_value) {
                                    try cleanup_registers.append(self.allocator, reg.id);
                                }
                            },
                            .load => {
                                if (reg.type_ == .php_value) {
                                    try cleanup_registers.append(self.allocator, reg.id);
                                }
                            },
                            else => {},
                        }
                    } else {
                        // alloca 指令（局部变量）也需要在函数结束时释放
                        try cleanup_registers.append(self.allocator, reg.id);
                    }
                }
            }
        }

        // 生成寄存器声明 - 使用简单的方式
        if (all_registers.count() > 0) {
            try code.appendSlice(self.allocator, "    // Register declarations\n");

            var reg_iter = all_registers.iterator();
            while (reg_iter.next()) |entry| {
                const reg_id = entry.key_ptr.*;
                const reg_type = entry.value_ptr.*;

                const is_alloca = alloca_registers.contains(reg_id);

                if (is_alloca) {
                    // alloca指令：声明为指针
                    try code.appendSlice(self.allocator, "    var reg_");
                    try code.writer(self.allocator).print("{d}", .{reg_id});
                    try code.appendSlice(self.allocator, "_storage: runtime.Value = runtime.Value.initNull();\n");
                    try code.appendSlice(self.allocator, "    const reg_");
                    try code.writer(self.allocator).print("{d}", .{reg_id});
                    try code.appendSlice(self.allocator, ": *runtime.Value = &reg_");
                    try code.writer(self.allocator).print("{d}", .{reg_id});
                    try code.appendSlice(self.allocator, "_storage;\n");
                    // 标记为可能未使用（避免Zig编译器警告）
                    try code.appendSlice(self.allocator, "    _ = &reg_");
                    try code.writer(self.allocator).print("{d}", .{reg_id});
                    try code.appendSlice(self.allocator, ";\n");
                } else {
                    // 普通寄存器：声明为值
                    const type_tag = @as(std.meta.Tag(IR.Type), reg_type);
                    try code.appendSlice(self.allocator, "    var reg_");
                    try code.writer(self.allocator).print("{d}", .{reg_id});
                    switch (type_tag) {
                        .i64 => try code.appendSlice(self.allocator, ": i64 = 0;\n"),
                        .f64 => try code.appendSlice(self.allocator, ": f64 = 0.0;\n"),
                        .bool => try code.appendSlice(self.allocator, ": bool = false;\n"),
                        else => try code.appendSlice(self.allocator, ": runtime.Value = runtime.Value.initNull();\n"),
                    }
                    // 标记为可能未使用（避免Zig编译器警告）
                    try code.appendSlice(self.allocator, "    _ = &reg_");
                    try code.writer(self.allocator).print("{d}", .{reg_id});
                    try code.appendSlice(self.allocator, ";\n");
                }
            }
            try code.appendSlice(self.allocator, "\n");
        }


        // 参数初始化现在由IR中的param和store指令处理

        self.current_reg_types = &all_registers;
        defer self.current_reg_types = null;
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

        self.current_alloca_regs = &alloca_registers;
        defer self.current_alloca_regs = null;

        self.current_cleanup_regs = cleanup_registers.items;
        defer self.current_cleanup_regs = null;

        // 生成代码体
        if (func.blocks.items.len == 1) {
            // 单基本块：直接生成线性代码
            try code.appendSlice(self.allocator, "    // Instructions\n");
            const block = func.blocks.items[0];
            for (block.instructions.items) |inst| {
                try self.generateInstructionSimple(code, inst);
            }

            // 生成terminator（return指令）
            if (block.terminator) |term| {
                switch (term) {
                    .ret => |ret_val| {
                        // 在return之前执行cleanup，但跳过即将返回的寄存器
                        if (cleanup_registers.items.len > 0) {
                            try code.appendSlice(self.allocator, "\n    // Cleanup: release allocated values (except return value)\n");
                            for (cleanup_registers.items) |reg_id| {
                                // 检查是否是返回值寄存器
                                const is_return_reg = if (ret_val) |reg| reg.id == reg_id else false;
                                if (!is_return_reg) {
                                    try code.appendSlice(self.allocator, "    reg_");
                                    try code.writer(self.allocator).print("{d}", .{reg_id});
                                    if (alloca_registers.contains(reg_id)) {
                                        try code.appendSlice(self.allocator, ".*.release(runtime.runtime_allocator);\n");
                                    } else {
                                        try code.appendSlice(self.allocator, ".release(runtime.runtime_allocator);\n");
                                    }
                                }
                            }
                        }

                        if (ret_val) |reg| {
                            const type_tag = @as(std.meta.Tag(IR.Type), all_registers.get(reg.id) orelse reg.type_);
                            if (type_tag == .i64) {
                                try code.writer(self.allocator).print("    return runtime.Value.initInt(reg_{d});\n", .{reg.id});
                            } else if (type_tag == .f64) {
                                try code.writer(self.allocator).print("    return runtime.Value.initFloat(reg_{d});\n", .{reg.id});
                            } else if (type_tag == .bool) {
                                try code.writer(self.allocator).print("    return runtime.Value.initBool(reg_{d});\n", .{reg.id});
                            } else {
                                try code.writer(self.allocator).print("    return reg_{d};\n", .{reg.id});
                            }
                        } else {
                            try code.appendSlice(self.allocator, "    return runtime.Value.initNull();\n");
                        }
                    },
                    else => {
                        // 其他terminator不应该出现在单基本块中
                        // 没有返回值，可以释放所有寄存器
                        if (cleanup_registers.items.len > 0) {
                            try code.appendSlice(self.allocator, "\n    // Cleanup: release allocated values\n");
                            for (cleanup_registers.items) |reg_id| {
                                try code.appendSlice(self.allocator, "    reg_");
                                try code.writer(self.allocator).print("{d}", .{reg_id});
                                if (alloca_registers.contains(reg_id)) {
                                    try code.appendSlice(self.allocator, ".*.release(runtime.runtime_allocator);\n");
                                } else {
                                    try code.appendSlice(self.allocator, ".release(runtime.runtime_allocator);\n");
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
                        try code.appendSlice(self.allocator, "    reg_");
                        try code.writer(self.allocator).print("{d}", .{reg_id});
                        if (alloca_registers.contains(reg_id)) {
                            try code.appendSlice(self.allocator, ".*.release(runtime.runtime_allocator);\n");
                        } else {
                            try code.appendSlice(self.allocator, ".release(runtime.runtime_allocator);\n");
                        }
                    }
                }

                try code.appendSlice(self.allocator, "    return runtime.Value.initNull();\n");
            }
        } else {
            try self.generateControlFlowStateMachine(code, func, cleanup_registers.items, &alloca_registers);
        }

        try code.appendSlice(self.allocator, "}\n");
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
                                if (!is_return_reg) {
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
                                    if (!is_return_reg) {
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
                                try code.appendSlice(self.allocator, ");\n");
                            } else if (reg_type_tag == .f64) {
                                try code.appendSlice(self.allocator, "        return runtime.Value.initFloat(reg_");
                                try code.writer(self.allocator).print("{d}", .{reg.id});
                                try code.appendSlice(self.allocator, ");\n");
                            } else if (reg_type_tag == .bool) {
                                try code.appendSlice(self.allocator, "        return runtime.Value.initBool(reg_");
                                try code.writer(self.allocator).print("{d}", .{reg.id});
                                try code.appendSlice(self.allocator, ");\n");
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
                                    if (!is_return_reg) {
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
                                if (!is_return_reg) {
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
                                    try code.appendSlice(self.allocator, ");\n");
                                } else if (reg_type_tag == .f64) {
                                    try code.appendSlice(self.allocator, "        return runtime.Value.initFloat(reg_");
                                    try code.writer(self.allocator).print("{d}", .{reg.id});
                                    try code.appendSlice(self.allocator, ");\n");
                                } else if (reg_type_tag == .bool) {
                                    try code.appendSlice(self.allocator, "        return runtime.Value.initBool(reg_");
                                    try code.writer(self.allocator).print("{d}", .{reg.id});
                                    try code.appendSlice(self.allocator, ");\n");
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
        try code.appendSlice(self.allocator, "    // Control flow state machine\n");
        try code.appendSlice(self.allocator, "    var current_block: u32 = 0;\n");
        try code.appendSlice(self.allocator, "    var prev_block: u32 = 0;\n");
        try code.appendSlice(self.allocator, "    while (true) {\n");
        try code.appendSlice(self.allocator, "        switch (current_block) {\n");

        // 检查函数是否有返回值
        const func_has_return_value = self.func_return_types.get(func.name) orelse false;

        const prev_cleanup_regs = self.current_cleanup_regs;
        const prev_alloca_regs = self.current_alloca_regs;
        self.current_cleanup_regs = cleanup_regs;
        self.current_alloca_regs = alloca_regs;
        defer {
            self.current_cleanup_regs = prev_cleanup_regs;
            self.current_alloca_regs = prev_alloca_regs;
        }

        for (func.blocks.items, 0..) |block, block_idx| {
            // 设置当前异常处理器
            if (block.exception_handler) |handler| {
                self.current_exception_handler = handler.index;
            } else {
                self.current_exception_handler = null;
            }

            const case_start = if (block.exception_handler) |handler|
                try std.fmt.allocPrint(self.allocator, "            {d} => {{ // {s} (handler: {d})\n", .{ block_idx, block.label, handler.index })
            else
                try std.fmt.allocPrint(self.allocator, "            {d} => {{ // {s}\n", .{ block_idx, block.label });
            defer self.allocator.free(case_start);
            try code.appendSlice(self.allocator, case_start);

            // 生成块内指令
            for (block.instructions.items) |inst| {
                try code.appendSlice(self.allocator, "    ");
                if (inst.op == .phi) {
                    try self.generatePhiInstructionStateMachine(code, inst, func);
                } else {
                    try self.generateInstructionSimple(code, inst);
                }
            }

            // 生成终止指令
            if (block.terminator) |term| {
                try self.generateTerminatorSimple(code, term, cleanup_regs, alloca_regs, func, block_idx, func_has_return_value);
            } else {
                if (block_idx + 1 < func.blocks.items.len) {
                    const jump = try std.fmt.allocPrint(self.allocator, "                prev_block = current_block;\n                current_block = {d};\n", .{block_idx + 1});
                    defer self.allocator.free(jump);
                    try code.appendSlice(self.allocator, jump);
                } else {
                    if (cleanup_regs.len > 0) {
                        try code.appendSlice(self.allocator, "                // Cleanup\n");
                        for (cleanup_regs) |reg_id| {
                            const suffix = if (alloca_regs.contains(reg_id)) ".*" else "";
                            const cleanup = try std.fmt.allocPrint(self.allocator, "                reg_{d}{s}.release(runtime.runtime_allocator);\n", .{ reg_id, suffix });
                            defer self.allocator.free(cleanup);
                            try code.appendSlice(self.allocator, cleanup);
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

    fn generatePhiInstructionStateMachine(self: *Self, code: *std.ArrayList(u8), inst: *const IR.Instruction, func: *const IR.Function) !void {
        const writer = code.writer(self.allocator);
        const phi = inst.op.phi;

        const result_reg = inst.result orelse return;
        const dest_tag = @as(std.meta.Tag(IR.Type), result_reg.type_);
        const dest_is_value = !(dest_tag == .i64 or dest_tag == .f64 or dest_tag == .bool);

        if (dest_is_value) {
            try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ result_reg.id });
        }

        try writer.writeAll("    switch (prev_block) {\n");
        for (phi.incoming) |incoming| {
            var pred_idx: ?u32 = null;
            for (func.blocks.items, 0..) |block, idx| {
                if (block == incoming.block) {
                    pred_idx = @intCast(idx);
                    break;
                }
            }
            
            if (pred_idx) |idx| {
                const src = incoming.value;
                const src_real_type = self.current_reg_types.?.get(src.id) orelse src.type_;
                const src_tag = @as(std.meta.Tag(IR.Type), src_real_type);
                const src_expr = blk: {
                    if (dest_is_value and src_tag == .i64) break :blk try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{src.id});
                    if (dest_is_value and src_tag == .f64) break :blk try std.fmt.allocPrint(self.allocator, "runtime.Value.initFloat(reg_{d})", .{src.id});
                    if (dest_is_value and src_tag == .bool) break :blk try std.fmt.allocPrint(self.allocator, "runtime.Value.initBool(reg_{d})", .{src.id});
                    if (!dest_is_value and src_tag == .php_value) {
                        if (dest_tag == .i64) break :blk try std.fmt.allocPrint(self.allocator, "reg_{d}.asInt()", .{src.id});
                        if (dest_tag == .f64) break :blk try std.fmt.allocPrint(self.allocator, "reg_{d}.asFloat()", .{src.id});
                        if (dest_tag == .bool) break :blk try std.fmt.allocPrint(self.allocator, "reg_{d}.toBool()", .{src.id});
                    }
                    break :blk try std.fmt.allocPrint(self.allocator, "reg_{d}", .{src.id});
                };
                defer self.allocator.free(src_expr);

                try writer.print("        {d} => {{ reg_{d} = {s};", .{ idx, result_reg.id, src_expr });
                if (dest_is_value) {
                    try writer.print(" reg_{d}.retain();", .{ result_reg.id });
                }
                try writer.writeAll(" },\n");
            } else {
                // Predecessor block not found (likely removed by optimization)
                // We just skip this case, assuming it will never be taken at runtime
                // because the block is unreachable.
            }
        }
        try writer.writeAll("        else => unreachable,\n");
        try writer.writeAll("    }\n");
    }

    /// 生成终止指令（简化版，用于状态机）
    fn generateTerminatorSimple(self: *Self, code: *std.ArrayList(u8), term: IR.Terminator, cleanup_regs: []const usize, alloca_regs: *const std.AutoHashMap(usize, void), func: *const IR.Function, _: usize, _: bool) !void {
        switch (term) {
            .ret => |ret_val| {
                if (cleanup_regs.len > 0) {
                    try code.appendSlice(self.allocator, "                // Cleanup (except return value)\n");
                    for (cleanup_regs) |reg_id| {
                        // 检查是否是返回值寄存器
                        const is_return_reg = if (ret_val) |reg| reg.id == reg_id else false;
                        if (!is_return_reg) {
                            const suffix = if (alloca_regs.contains(reg_id)) ".*" else "";
                            const cleanup = try std.fmt.allocPrint(self.allocator, "                reg_{d}{s}.release(runtime.runtime_allocator);\n", .{ reg_id, suffix });
                            defer self.allocator.free(cleanup);
                            try code.appendSlice(self.allocator, cleanup);
                        }
                    }
                }
                if (ret_val) |reg| {
                    const real_type = self.current_reg_types.?.get(reg.id) orelse reg.type_;
                    const reg_type_tag = @as(std.meta.Tag(IR.Type), real_type);
                    if (reg_type_tag == .i64) {
                        const ret_stmt = try std.fmt.allocPrint(self.allocator, "                return runtime.Value.initInt(reg_{d});\n", .{reg.id});
                        defer self.allocator.free(ret_stmt);
                        try code.appendSlice(self.allocator, ret_stmt);
                    } else if (reg_type_tag == .f64) {
                        const ret_stmt = try std.fmt.allocPrint(self.allocator, "                return runtime.Value.initFloat(reg_{d});\n", .{reg.id});
                        defer self.allocator.free(ret_stmt);
                        try code.appendSlice(self.allocator, ret_stmt);
                    } else if (reg_type_tag == .bool) {
                        const ret_stmt = try std.fmt.allocPrint(self.allocator, "                return runtime.Value.initBool(reg_{d});\n", .{reg.id});
                        defer self.allocator.free(ret_stmt);
                        try code.appendSlice(self.allocator, ret_stmt);
                    } else {
                        const ret_stmt = try std.fmt.allocPrint(self.allocator, "                return reg_{d};\n", .{reg.id});
                        defer self.allocator.free(ret_stmt);
                        try code.appendSlice(self.allocator, ret_stmt);
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
                const jump = try std.fmt.allocPrint(self.allocator, "                prev_block = current_block;\n                current_block = {d};\n", .{target_idx});
                defer self.allocator.free(jump);
                try code.appendSlice(self.allocator, jump);
            },
            .cond_br => |br| {
                // 找到then和else块的索引
                var then_idx: usize = 0;
                var else_idx: usize = 0;
                for (func.blocks.items, 0..) |block, idx| {
                    if (block == br.then_block) then_idx = idx;
                    if (block == br.else_block) else_idx = idx;
                }

                // 获取条件寄存器的实际类型
                const reg_type = self.current_reg_types.?.get(br.cond.id) orelse IR.Type{ .php_value = {} };
                const type_tag = @as(std.meta.Tag(IR.Type), reg_type);

                const cond_expr = if (type_tag == .bool)
                    try std.fmt.allocPrint(self.allocator, "reg_{d}", .{br.cond.id})
                else if (type_tag == .i64)
                    try std.fmt.allocPrint(self.allocator, "(reg_{d} != 0)", .{br.cond.id})
                else if (type_tag == .f64)
                    try std.fmt.allocPrint(self.allocator, "(reg_{d} != 0.0)", .{br.cond.id})
                else
                    try std.fmt.allocPrint(self.allocator, "reg_{d}.toBool()", .{br.cond.id});
                defer self.allocator.free(cond_expr);

                const cond = try std.fmt.allocPrint(self.allocator, "                prev_block = current_block;\n                if ({s}) {{\n                    current_block = {d};\n                }} else {{\n                    current_block = {d};\n                }}\n", .{ cond_expr, then_idx, else_idx });
                defer self.allocator.free(cond);
                try code.appendSlice(self.allocator, cond);
            },
            .throw => |ex_reg| {
                const ex_stmt = try std.fmt.allocPrint(self.allocator, "                runtime.setException(reg_{d});\n", .{ex_reg.id});
                defer self.allocator.free(ex_stmt);
                try code.appendSlice(self.allocator, ex_stmt);
                
                // 清理资源
                if (cleanup_regs.len > 0) {
                    try code.appendSlice(self.allocator, "                // Cleanup before throw\n");
                    for (cleanup_regs) |reg_id| {
                        // 不要释放异常对象本身，因为它已经被 setException 接管（retain）了？
                        // 不，setException 会 retain 它。所以这里 release 是正确的（释放当前寄存器的持有权）。
                        const suffix = if (alloca_regs.contains(reg_id)) ".*" else "";
                        const cleanup = try std.fmt.allocPrint(self.allocator, "                reg_{d}{s}.release(runtime.runtime_allocator);\n", .{ reg_id, suffix });
                        defer self.allocator.free(cleanup);
                        try code.appendSlice(self.allocator, cleanup);
                    }
                }

                if (self.current_exception_handler) |handler_idx| {
                    const jump = try std.fmt.allocPrint(self.allocator, "                current_block = {d};\n", .{handler_idx});
                    defer self.allocator.free(jump);
                    try code.appendSlice(self.allocator, jump);
                } else {
                    try code.appendSlice(self.allocator, "                return error.RuntimeError;\n");
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
        const cond_str = try std.fmt.allocPrint(self.allocator, "reg_{d}", .{cond_br.cond.id});
        defer self.allocator.free(cond_str);

        // 根据条件寄存器的类型生成不同的代码
        if (cond_br.cond.type_ == .bool) {
            try code.appendSlice(self.allocator, "        if (!");
            try code.appendSlice(self.allocator, cond_str);
            try code.appendSlice(self.allocator, ") break;\n");
        } else {
            try code.appendSlice(self.allocator, "        if (!");
            try code.appendSlice(self.allocator, cond_str);
            try code.appendSlice(self.allocator, ".toBool()) break;\n");
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
        const cond_str_for = try std.fmt.allocPrint(self.allocator, "reg_{d}", .{cond_br.cond.id});
        defer self.allocator.free(cond_str_for);

        // 根据条件寄存器的类型生成不同的代码
        if (cond_br.cond.type_ == .bool) {
            try code.appendSlice(self.allocator, "        if (!");
            try code.appendSlice(self.allocator, cond_str_for);
            try code.appendSlice(self.allocator, ") break;\n");
        } else {
            try code.appendSlice(self.allocator, "        if (!");
            try code.appendSlice(self.allocator, cond_str_for);
            try code.appendSlice(self.allocator, ".toBool()) break;\n");
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

        return true;
    }

    fn generateCleanupCode(self: *Self, writer: anytype) !void {
        if (self.current_cleanup_regs) |regs| {
            if (regs.len > 0) {
                try writer.writeAll("        // Cleanup on exception\n");
                for (regs) |reg_id| {
                    const suffix = if (self.current_alloca_regs.?.contains(reg_id)) ".*" else "";
                    try writer.print("        reg_{d}{s}.release(runtime.runtime_allocator);\n", .{ reg_id, suffix });
                }
            }
        }
    }

    /// 生成指令（简化版）
    fn generateInstructionSimple(self: *Self, code: *std.ArrayList(u8), inst: *const IR.Instruction) !void {
        const writer = code.writer(self.allocator);

        // Add source location comment
        if (inst.location.line > 0) {
            try writer.print("    // {s}:{d}\n", .{ inst.location.file, inst.location.line });
        }

        switch (inst.op) {
            .const_int => |val| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    if (type_tag == .i64) {
                        try writer.print("    reg_{d} = {d};\n", .{ reg.id, val });
                    } else {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                        try writer.print("    reg_{d} = runtime.Value.initInt({d});\n", .{ reg.id, val });
                    }
                }
            },
            .const_float => |val| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    if (type_tag == .f64) {
                        try writer.print("    reg_{d} = {d};\n", .{ reg.id, val });
                    } else {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                        try writer.print("    reg_{d} = runtime.Value.initFloat({d});\n", .{ reg.id, val });
                    }
                }
            },
            .const_bool => |val| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    if (type_tag == .bool) {
                        try writer.print("    reg_{d} = {};\n", .{ reg.id, val });
                    } else {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                        try writer.print("    reg_{d} = runtime.Value.initBool({});\n", .{ reg.id, val });
                    }
                }
            },
            .const_string => |string_id| {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                    try writer.print("    reg_{d} = runtime.Value.initString(try runtime.PHPString.init(runtime.runtime_allocator, string_table[{d}]));\n", .{ reg.id, string_id });
                }
            },
            .alloca => {
                // alloca不需要生成代码
            },
            .store => |op| {
                // 检查值的类型
                const value_type_tag = @as(std.meta.Tag(IR.Type), op.value.type_);
                // 检查是否是 alloca 寄存器（即指针类型）
                const is_ptr = if (self.current_alloca_regs) |regs| regs.contains(op.ptr.id) else false;
                const ptr_prefix = if (is_ptr) "" else "&";
                
                // 1. 释放旧值
                try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ op.ptr.id });

                // 2. 增加新值引用计数并赋值
                if (value_type_tag == .i64) {
                    try writer.print("    runtime.val_assign({s}reg_{d}, runtime.Value.initInt(reg_{d}));\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                } else if (value_type_tag == .f64) {
                    try writer.print("    runtime.val_assign({s}reg_{d}, runtime.Value.initFloat(reg_{d}));\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                } else if (value_type_tag == .bool) {
                    try writer.print("    runtime.val_assign({s}reg_{d}, runtime.Value.initBool(reg_{d}));\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                } else if (value_type_tag == .php_value or value_type_tag == .php_string or value_type_tag == .php_array or value_type_tag == .php_object or value_type_tag == .php_callable) {
                    // 已经是Value类型，需要retain
                    try writer.print("    reg_{d}.retain();\n", .{ op.value.id });
                    try writer.print("    runtime.val_assign({s}reg_{d}, reg_{d});\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                } else {
                    // Fallback for other types
                    try writer.print("    reg_{d}.retain();\n", .{ op.value.id });
                    try writer.print("    runtime.val_assign({s}reg_{d}, reg_{d});\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                }
            },
            .make_ref => |op| {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d} = try runtime.make_ref(reg_{d}, runtime.runtime_allocator);\n", .{ reg.id, op.ptr.id });
                }
            },
            .load => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    
                    if (type_tag != .i64 and type_tag != .f64 and type_tag != .bool) {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                    }

                    // 检查是否是 alloca 寄存器（即指针类型）
                    const is_ptr = if (self.current_alloca_regs) |regs| regs.contains(op.ptr.id) else false;
                    const ptr_prefix = if (is_ptr) "" else "&";

                    if (type_tag == .i64) {
                        try writer.print("    reg_{d} = runtime.val_deref({s}reg_{d}).*.asInt();\n", .{ reg.id, ptr_prefix, op.ptr.id });
                    } else if (type_tag == .f64) {
                        try writer.print("    reg_{d} = runtime.val_deref({s}reg_{d}).*.asFloat();\n", .{ reg.id, ptr_prefix, op.ptr.id });
                    } else if (type_tag == .bool) {
                        try writer.print("    reg_{d} = runtime.val_deref({s}reg_{d}).*.asBool();\n", .{ reg.id, ptr_prefix, op.ptr.id });
                    } else {
                        try writer.print("    reg_{d} = runtime.val_deref({s}reg_{d}).*;\n", .{ reg.id, ptr_prefix, op.ptr.id });
                        try writer.print("    reg_{d}.retain();\n", .{ reg.id });
                    }
                }
            },
            .concat => |op| {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });

                    // 检查操作数类型，必要时进行转换
                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    // 生成左操作数表达式
                    const lhs_expr = if (lhs_type_tag == .php_value or lhs_type_tag == .php_string)
                        try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.lhs.id})
                    else if (lhs_type_tag == .i64)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.lhs.id})
                    else if (lhs_type_tag == .f64)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initFloat(reg_{d})", .{op.lhs.id})
                    else if (lhs_type_tag == .bool)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initBool(reg_{d})", .{op.lhs.id})
                    else
                        try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.lhs.id});
                    defer self.allocator.free(lhs_expr);

                    // 生成右操作数表达式
                    const rhs_expr = if (rhs_type_tag == .php_value or rhs_type_tag == .php_string)
                        try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.rhs.id})
                    else if (rhs_type_tag == .i64)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.rhs.id})
                    else if (rhs_type_tag == .f64)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initFloat(reg_{d})", .{op.rhs.id})
                    else if (rhs_type_tag == .bool)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initBool(reg_{d})", .{op.rhs.id})
                    else
                        try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.rhs.id});
                    defer self.allocator.free(rhs_expr);

                    try writer.print("    reg_{d} = try runtime.php_concat({s}, {s}, runtime.runtime_allocator);\n", .{ reg.id, lhs_expr, rhs_expr });
                }
            },
            .add => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const lhs_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    if (type_tag == .i64 and lhs_tag == .i64 and rhs_tag == .i64) {
                        // 直接i64加法
                        try writer.print("    reg_{d} = reg_{d} + reg_{d};\n", .{ reg.id, op.lhs.id, op.rhs.id });
                    } else {
                        // 使用运行时函数，需要转换类型
                        if (lhs_tag == .i64 and rhs_tag == .i64) {
                            try writer.print("    reg_{d} = try runtime.php_add(runtime.Value.initInt(reg_{d}), runtime.Value.initInt(reg_{d}));\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else if (lhs_tag == .i64) {
                            try writer.print("    reg_{d} = try runtime.php_add(runtime.Value.initInt(reg_{d}), reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else if (rhs_tag == .i64) {
                            try writer.print("    reg_{d} = try runtime.php_add(reg_{d}, runtime.Value.initInt(reg_{d}));\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_add(reg_{d}, reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        }
                    }
                }
            },
            .sub => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const lhs_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    if (type_tag == .i64 and lhs_tag == .i64 and rhs_tag == .i64) {
                        try writer.print("    reg_{d} = reg_{d} - reg_{d};\n", .{ reg.id, op.lhs.id, op.rhs.id });
                    } else {
                        if (lhs_tag == .i64 and rhs_tag == .i64) {
                            try writer.print("    reg_{d} = try runtime.php_sub(runtime.Value.initInt(reg_{d}), runtime.Value.initInt(reg_{d}));\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else if (lhs_tag == .i64) {
                            try writer.print("    reg_{d} = try runtime.php_sub(runtime.Value.initInt(reg_{d}), reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else if (rhs_tag == .i64) {
                            try writer.print("    reg_{d} = try runtime.php_sub(reg_{d}, runtime.Value.initInt(reg_{d}));\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_sub(reg_{d}, reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        }
                    }
                }
            },
            .mul => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const lhs_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    if (type_tag == .i64 and lhs_tag == .i64 and rhs_tag == .i64) {
                        try writer.print("    reg_{d} = reg_{d} * reg_{d};\n", .{ reg.id, op.lhs.id, op.rhs.id });
                    } else {
                        if (lhs_tag == .i64 and rhs_tag == .i64) {
                            try writer.print("    reg_{d} = try runtime.php_mul(runtime.Value.initInt(reg_{d}), runtime.Value.initInt(reg_{d}));\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else if (lhs_tag == .i64) {
                            try writer.print("    reg_{d} = try runtime.php_mul(runtime.Value.initInt(reg_{d}), reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else if (rhs_tag == .i64) {
                            try writer.print("    reg_{d} = try runtime.php_mul(reg_{d}, runtime.Value.initInt(reg_{d}));\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_mul(reg_{d}, reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        }
                    }
                }
            },
            .div => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const lhs_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    if (type_tag == .i64 and lhs_tag == .i64 and rhs_tag == .i64) {
                        try writer.print("    reg_{d} = @divTrunc(reg_{d}, reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                    } else {
                        if (lhs_tag == .i64 and rhs_tag == .i64) {
                            try writer.print("    reg_{d} = try runtime.php_div(runtime.Value.initInt(reg_{d}), runtime.Value.initInt(reg_{d}));\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else if (lhs_tag == .i64) {
                            try writer.print("    reg_{d} = try runtime.php_div(runtime.Value.initInt(reg_{d}), reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else if (rhs_tag == .i64) {
                            try writer.print("    reg_{d} = try runtime.php_div(reg_{d}, runtime.Value.initInt(reg_{d}));\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_div(reg_{d}, reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        }
                    }
                }
            },
            .mod => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const lhs_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    if (type_tag == .i64 and lhs_tag == .i64 and rhs_tag == .i64) {
                        try writer.print("    reg_{d} = @rem(reg_{d}, reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                    } else {
                        if (lhs_tag == .i64 and rhs_tag == .i64) {
                            try writer.print("    reg_{d} = try runtime.php_mod(runtime.Value.initInt(reg_{d}), runtime.Value.initInt(reg_{d}));\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else if (lhs_tag == .i64) {
                            try writer.print("    reg_{d} = try runtime.php_mod(runtime.Value.initInt(reg_{d}), reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else if (rhs_tag == .i64) {
                            try writer.print("    reg_{d} = try runtime.php_mod(reg_{d}, runtime.Value.initInt(reg_{d}));\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_mod(reg_{d}, reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        }
                    }
                }
            },
            .shl => |op| {
                if (inst.result) |reg| {
                     try writer.print("    reg_{d} = reg_{d} << @as(u6, @intCast(reg_{d}));\n", .{ reg.id, op.lhs.id, op.rhs.id });
                }
            },
            .shr => |op| {
                if (inst.result) |reg| {
                     try writer.print("    reg_{d} = reg_{d} >> @as(u6, @intCast(reg_{d}));\n", .{ reg.id, op.lhs.id, op.rhs.id });
                }
            },
            .bit_and => |op| {
                if (inst.result) |reg| {
                     try writer.print("    reg_{d} = reg_{d} & reg_{d};\n", .{ reg.id, op.lhs.id, op.rhs.id });
                }
            },
            .nop => {},
            .param => |op| {
                if (inst.result) |reg| {
                    if (std.mem.eql(u8, op.name, "this")) {
                        try writer.print("    reg_{d} = ctx;\n", .{reg.id});
                    } else {
                        const arg_idx = if (self.current_function_has_this) op.index - 1 else op.index;
                        try writer.print("    reg_{d} = if (args.len > {d}) args[{d}] else runtime.Value.initNull();\n", .{ reg.id, arg_idx, arg_idx });
                    }
                }
            },
            .capture_get => |op| {
                if (inst.result) |reg| {
                    // ctx is the closure object
                    try writer.print("    reg_{d} = ctx.asFunction().captures[{d}];\n", .{ reg.id, op.index });
                }
            },
            .const_null => {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d} = runtime.Value.initNull();\n", .{reg.id});
                }
            },
            .arg_count => {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d} = @intCast(args.len);\n", .{reg.id});
                }
            },
            .eq => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    if (type_tag == .bool and lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                        try writer.print("    reg_{d} = reg_{d} == reg_{d};\n", .{ reg.id, op.lhs.id, op.rhs.id });
                    } else if (lhs_type_tag == .php_value and rhs_type_tag == .php_value) {
                        // 两个Value类型，直接调用运行时函数
                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_eq(reg_{d}, reg_{d})).toBool();\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_eq(reg_{d}, reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        }
                    } else {
                        // 混合类型，需要转换
                        const lhs_str = if (lhs_type_tag == .i64)
                            try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.lhs.id})
                        else
                            try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.lhs.id});
                        defer self.allocator.free(lhs_str);

                        const rhs_str = if (rhs_type_tag == .i64)
                            try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.rhs.id})
                        else
                            try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.rhs.id});
                        defer self.allocator.free(rhs_str);

                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_eq({s}, {s})).toBool();\n", .{ reg.id, lhs_str, rhs_str });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_eq({s}, {s});\n", .{ reg.id, lhs_str, rhs_str });
                        }
                    }
                }
            },
            .ne => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    if (type_tag == .bool and lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                        try writer.print("    reg_{d} = reg_{d} != reg_{d};\n", .{ reg.id, op.lhs.id, op.rhs.id });
                    } else if (lhs_type_tag == .php_value and rhs_type_tag == .php_value) {
                        // 两个Value类型，直接调用运行时函数
                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_ne(reg_{d}, reg_{d})).toBool();\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_ne(reg_{d}, reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        }
                    } else {
                        // 混合类型，需要转换
                        const lhs_str = if (lhs_type_tag == .i64)
                            try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.lhs.id})
                        else
                            try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.lhs.id});
                        defer self.allocator.free(lhs_str);

                        const rhs_str = if (rhs_type_tag == .i64)
                            try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.rhs.id})
                        else
                            try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.rhs.id});
                        defer self.allocator.free(rhs_str);

                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_ne({s}, {s})).toBool();\n", .{ reg.id, lhs_str, rhs_str });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_ne({s}, {s});\n", .{ reg.id, lhs_str, rhs_str });
                        }
                    }
                }
            },
            .identical => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    const lhs_str = if (lhs_type_tag == .i64)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.lhs.id})
                    else if (lhs_type_tag == .f64)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initFloat(reg_{d})", .{op.lhs.id})
                    else if (lhs_type_tag == .bool)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initBool(reg_{d})", .{op.lhs.id})
                    else
                        try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.lhs.id});
                    defer self.allocator.free(lhs_str);

                    const rhs_str = if (rhs_type_tag == .i64)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.rhs.id})
                    else if (rhs_type_tag == .f64)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initFloat(reg_{d})", .{op.rhs.id})
                    else if (rhs_type_tag == .bool)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initBool(reg_{d})", .{op.rhs.id})
                    else
                        try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.rhs.id});
                    defer self.allocator.free(rhs_str);

                    if (type_tag == .bool) {
                        try writer.print("    reg_{d} = (try runtime.php_identical({s}, {s})).toBool();\n", .{ reg.id, lhs_str, rhs_str });
                    } else {
                        try writer.print("    reg_{d} = try runtime.php_identical({s}, {s});\n", .{ reg.id, lhs_str, rhs_str });
                    }
                }
            },
            .not_identical => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    const lhs_str = if (lhs_type_tag == .i64)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.lhs.id})
                    else if (lhs_type_tag == .f64)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initFloat(reg_{d})", .{op.lhs.id})
                    else if (lhs_type_tag == .bool)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initBool(reg_{d})", .{op.lhs.id})
                    else
                        try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.lhs.id});
                    defer self.allocator.free(lhs_str);

                    const rhs_str = if (rhs_type_tag == .i64)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.rhs.id})
                    else if (rhs_type_tag == .f64)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initFloat(reg_{d})", .{op.rhs.id})
                    else if (rhs_type_tag == .bool)
                        try std.fmt.allocPrint(self.allocator, "runtime.Value.initBool(reg_{d})", .{op.rhs.id})
                    else
                        try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.rhs.id});
                    defer self.allocator.free(rhs_str);

                    if (type_tag == .bool) {
                        try writer.print("    reg_{d} = (try runtime.php_not_identical({s}, {s})).toBool();\n", .{ reg.id, lhs_str, rhs_str });
                    } else {
                        try writer.print("    reg_{d} = try runtime.php_not_identical({s}, {s});\n", .{ reg.id, lhs_str, rhs_str });
                    }
                }
            },
            .lt => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    // 检查操作数类型是否一致且为基本类型
                    if (type_tag == .bool and lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                        // 两个i64直接比较
                        try writer.print("    reg_{d} = reg_{d} < reg_{d};\n", .{ reg.id, op.lhs.id, op.rhs.id });
                    } else if (lhs_type_tag == .php_value and rhs_type_tag == .php_value) {
                        // 两个Value类型，直接调用运行时函数
                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_lt(reg_{d}, reg_{d})).toBool();\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_lt(reg_{d}, reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        }
                    } else {
                        // 混合类型，需要转换
                        const lhs_str = if (lhs_type_tag == .i64)
                            try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.lhs.id})
                        else
                            try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.lhs.id});
                        defer self.allocator.free(lhs_str);

                        const rhs_str = if (rhs_type_tag == .i64)
                            try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.rhs.id})
                        else
                            try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.rhs.id});
                        defer self.allocator.free(rhs_str);

                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_lt({s}, {s})).toBool();\n", .{ reg.id, lhs_str, rhs_str });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_lt({s}, {s});\n", .{ reg.id, lhs_str, rhs_str });
                        }
                    }
                }
            },
            .le => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    if (type_tag == .bool and lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                        try writer.print("    reg_{d} = reg_{d} <= reg_{d};\n", .{ reg.id, op.lhs.id, op.rhs.id });
                    } else if (lhs_type_tag == .php_value and rhs_type_tag == .php_value) {
                        // 两个Value类型，直接调用运行时函数
                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_le(reg_{d}, reg_{d})).toBool();\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_le(reg_{d}, reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        }
                    } else {
                        // 混合类型，需要转换
                        const lhs_str = if (lhs_type_tag == .i64)
                            try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.lhs.id})
                        else
                            try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.lhs.id});
                        defer self.allocator.free(lhs_str);

                        const rhs_str = if (rhs_type_tag == .i64)
                            try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.rhs.id})
                        else
                            try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.rhs.id});
                        defer self.allocator.free(rhs_str);

                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_le({s}, {s})).toBool();\n", .{ reg.id, lhs_str, rhs_str });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_le({s}, {s});\n", .{ reg.id, lhs_str, rhs_str });
                        }
                    }
                }
            },
            .gt => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    if (type_tag == .bool and lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                        try writer.print("    reg_{d} = reg_{d} > reg_{d};\n", .{ reg.id, op.lhs.id, op.rhs.id });
                    } else if (lhs_type_tag == .php_value and rhs_type_tag == .php_value) {
                        // 两个Value类型，直接调用运行时函数
                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_gt(reg_{d}, reg_{d})).toBool();\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_gt(reg_{d}, reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        }
                    } else {
                        // 混合类型，需要转换
                        const lhs_str = if (lhs_type_tag == .i64)
                            try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.lhs.id})
                        else
                            try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.lhs.id});
                        defer self.allocator.free(lhs_str);

                        const rhs_str = if (rhs_type_tag == .i64)
                            try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.rhs.id})
                        else
                            try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.rhs.id});
                        defer self.allocator.free(rhs_str);

                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_gt({s}, {s})).toBool();\n", .{ reg.id, lhs_str, rhs_str });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_gt({s}, {s});\n", .{ reg.id, lhs_str, rhs_str });
                        }
                    }
                }
            },
            .ge => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);

                    if (type_tag == .bool and lhs_type_tag == .i64 and rhs_type_tag == .i64) {
                        try writer.print("    reg_{d} = reg_{d} >= reg_{d};\n", .{ reg.id, op.lhs.id, op.rhs.id });
                    } else if (lhs_type_tag == .php_value and rhs_type_tag == .php_value) {
                        // 两个Value类型，直接调用运行时函数
                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_ge(reg_{d}, reg_{d})).toBool();\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_ge(reg_{d}, reg_{d});\n", .{ reg.id, op.lhs.id, op.rhs.id });
                        }
                    } else {
                        // 混合类型，需要转换
                        const lhs_str = if (lhs_type_tag == .i64)
                            try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.lhs.id})
                        else
                            try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.lhs.id});
                        defer self.allocator.free(lhs_str);

                        const rhs_str = if (rhs_type_tag == .i64)
                            try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.rhs.id})
                        else
                            try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.rhs.id});
                        defer self.allocator.free(rhs_str);

                        if (type_tag == .bool) {
                            try writer.print("    reg_{d} = (try runtime.php_ge({s}, {s})).toBool();\n", .{ reg.id, lhs_str, rhs_str });
                        } else {
                            try writer.print("    reg_{d} = try runtime.php_ge({s}, {s});\n", .{ reg.id, lhs_str, rhs_str });
                        }
                    }
                }
            },
            .and_ => |op| {
                if (inst.result) |reg| {
                    const lhs_str = try self.formatRegister(op.lhs);
                    defer self.allocator.free(lhs_str);
                    const rhs_str = try self.formatRegister(op.rhs);
                    defer self.allocator.free(rhs_str);
                    
                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);
                    
                    // Generate LHS boolean check
                    var lhs_check = std.ArrayList(u8){};
                    defer lhs_check.deinit(self.allocator);
                    if (lhs_type_tag == .i64) try lhs_check.writer(self.allocator).print("({s} != 0)", .{lhs_str})
                    else if (lhs_type_tag == .f64) try lhs_check.writer(self.allocator).print("({s} != 0.0)", .{lhs_str})
                    else if (lhs_type_tag == .bool) try lhs_check.writer(self.allocator).print("{s}", .{lhs_str})
                    else try lhs_check.writer(self.allocator).print("{s}.toBool()", .{lhs_str});

                    // Generate RHS boolean check
                    var rhs_check = std.ArrayList(u8){};
                    defer rhs_check.deinit(self.allocator);
                    if (rhs_type_tag == .i64) try rhs_check.writer(self.allocator).print("({s} != 0)", .{rhs_str})
                    else if (rhs_type_tag == .f64) try rhs_check.writer(self.allocator).print("({s} != 0.0)", .{rhs_str})
                    else if (rhs_type_tag == .bool) try rhs_check.writer(self.allocator).print("{s}", .{rhs_str})
                    else try rhs_check.writer(self.allocator).print("{s}.toBool()", .{rhs_str});

                    const res_type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    if (res_type_tag == .bool) {
                        try writer.print("    reg_{d} = {s} and {s};\n", .{ reg.id, lhs_check.items, rhs_check.items });
                    } else {
                        try writer.print("    reg_{d} = runtime.Value.initBool({s} and {s});\n", .{ reg.id, lhs_check.items, rhs_check.items });
                    }
                }
            },
            .or_ => |op| {
                if (inst.result) |reg| {
                    const lhs_str = try self.formatRegister(op.lhs);
                    defer self.allocator.free(lhs_str);
                    const rhs_str = try self.formatRegister(op.rhs);
                    defer self.allocator.free(rhs_str);
                    
                    const lhs_type_tag = @as(std.meta.Tag(IR.Type), op.lhs.type_);
                    const rhs_type_tag = @as(std.meta.Tag(IR.Type), op.rhs.type_);
                    
                    // Generate LHS boolean check
                    var lhs_check = std.ArrayList(u8){};
                    defer lhs_check.deinit(self.allocator);
                    if (lhs_type_tag == .i64) try lhs_check.writer(self.allocator).print("({s} != 0)", .{lhs_str})
                    else if (lhs_type_tag == .f64) try lhs_check.writer(self.allocator).print("({s} != 0.0)", .{lhs_str})
                    else if (lhs_type_tag == .bool) try lhs_check.writer(self.allocator).print("{s}", .{lhs_str})
                    else try lhs_check.writer(self.allocator).print("{s}.toBool()", .{lhs_str});

                    // Generate RHS boolean check
                    var rhs_check = std.ArrayList(u8){};
                    defer rhs_check.deinit(self.allocator);
                    if (rhs_type_tag == .i64) try rhs_check.writer(self.allocator).print("({s} != 0)", .{rhs_str})
                    else if (rhs_type_tag == .f64) try rhs_check.writer(self.allocator).print("({s} != 0.0)", .{rhs_str})
                    else if (rhs_type_tag == .bool) try rhs_check.writer(self.allocator).print("{s}", .{rhs_str})
                    else try rhs_check.writer(self.allocator).print("{s}.toBool()", .{rhs_str});

                    const res_type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    if (res_type_tag == .bool) {
                        try writer.print("    reg_{d} = {s} or {s};\n", .{ reg.id, lhs_check.items, rhs_check.items });
                    } else {
                        try writer.print("    reg_{d} = runtime.Value.initBool({s} or {s});\n", .{ reg.id, lhs_check.items, rhs_check.items });
                    }
                }
            },
            .neg => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const operand_type_tag = @as(std.meta.Tag(IR.Type), op.operand.type_);
                    
                    if (type_tag == .i64 and operand_type_tag == .i64) {
                         try writer.print("    reg_{d} = -reg_{d};\n", .{ reg.id, op.operand.id });
                    } else if (operand_type_tag == .php_value) {
                         if (type_tag == .i64) {
                             try writer.print("    reg_{d} = (try runtime.php_neg(reg_{d})).toInt();\n", .{ reg.id, op.operand.id });
                         } else {
                             try writer.print("    reg_{d} = try runtime.php_neg(reg_{d});\n", .{ reg.id, op.operand.id });
                         }
                    } else {
                         // Default to runtime call if not simple i64
                         // If operand is i64 but result is Value, wrap operand
                         if (operand_type_tag == .i64) {
                             try writer.print("    reg_{d} = try runtime.php_neg(runtime.Value.initInt(reg_{d}));\n", .{ reg.id, op.operand.id });
                         } else {
                             try writer.print("    reg_{d} = try runtime.php_neg(reg_{d});\n", .{ reg.id, op.operand.id });
                         }
                    }
                }
            },
            .not => |op| {
                if (inst.result) |reg| {
                    const operand_type_tag = @as(std.meta.Tag(IR.Type), op.operand.type_);
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    
                    if (type_tag == .bool) {
                        if (operand_type_tag == .bool) {
                            try writer.print("    reg_{d} = !reg_{d};\n", .{ reg.id, op.operand.id });
                        } else if (operand_type_tag == .php_value) {
                            try writer.print("    reg_{d} = (try runtime.php_not(reg_{d})).toBool();\n", .{ reg.id, op.operand.id });
                        } else if (operand_type_tag == .i64) {
                            try writer.print("    reg_{d} = reg_{d} == 0;\n", .{ reg.id, op.operand.id });
                        } else {
                            try writer.print("    reg_{d} = (try runtime.php_not(reg_{d})).toBool();\n", .{ reg.id, op.operand.id });
                        }
                    } else {
                        // Result is Value or something else
                        if (operand_type_tag == .php_value) {
                             try writer.print("    reg_{d} = try runtime.php_not(reg_{d});\n", .{ reg.id, op.operand.id });
                        } else {
                             const op_str = if (operand_type_tag == .i64)
                                 try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.operand.id})
                             else if (operand_type_tag == .bool)
                                 try std.fmt.allocPrint(self.allocator, "runtime.Value.initBool(reg_{d})", .{op.operand.id})
                             else
                                 try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.operand.id});
                             defer self.allocator.free(op_str);
                             
                             try writer.print("    reg_{d} = try runtime.php_not({s});\n", .{ reg.id, op_str });
                        }
                    }
                }
            },
            .call => |op| {
                // 生成函数调用
                // 检查是否是内置函数
                const is_builtin = self.isBuiltinFunction(op.func_name);

                // 格式化参数列表
                var args_buf = std.ArrayList(u8){};
                defer args_buf.deinit(self.allocator);
                const args_writer = args_buf.writer(self.allocator);

                for (op.args, 0..) |arg, i| {
                    if (i > 0) try args_writer.writeAll(", ");

                    const arg_type_tag = @as(std.meta.Tag(IR.Type), arg.type_);
                    if (arg_type_tag == .i64) {
                        try args_writer.print("runtime.Value.initInt(reg_{d})", .{arg.id});
                    } else if (arg_type_tag == .f64) {
                        try args_writer.print("runtime.Value.initFloat(reg_{d})", .{arg.id});
                    } else if (arg_type_tag == .bool) {
                        try args_writer.print("runtime.Value.initBool(reg_{d})", .{arg.id});
                    } else {
                        try args_writer.print("reg_{d}", .{arg.id});
                    }
                }

                // 生成函数调用
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    if (type_tag != .i64 and type_tag != .f64 and type_tag != .bool) {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                    }

                    // 有返回值寄存器
                    if (is_builtin) {
                        const runtime_name = self.mapToRuntimeFunction(op.func_name);

                        // 检查是否需要 allocator 参数
                        if (self.functionNeedsAllocator(op.func_name)) {
                            if (args_buf.items.len > 0) {
                                try writer.print("    reg_{d} = try runtime.{s}({s}, runtime.runtime_allocator);\n", .{ reg.id, runtime_name, args_buf.items });
                            } else {
                                try writer.print("    reg_{d} = try runtime.{s}(runtime.runtime_allocator);\n", .{ reg.id, runtime_name });
                            }
                        } else {
                            try writer.print("    reg_{d} = try runtime.{s}({s});\n", .{ reg.id, runtime_name, args_buf.items });
                        }
                    } else {
                        // 用户定义函数 - 检查是否返回值
                        const func_has_return_value = self.func_return_types.get(op.func_name) orelse false;
                        if (func_has_return_value) {
                            // 函数返回Value，直接赋值
                            try writer.print("    reg_{d} = try @\"{s}\"(runtime.Value.initNull(), &[_]runtime.Value{{ {s} }}, runtime.runtime_allocator);\n", .{ reg.id, op.func_name, args_buf.items });
                        } else {
                            // 函数返回void，调用后赋值null
                            try writer.print("    _ = try @\"{s}\"(runtime.Value.initNull(), &[_]runtime.Value{{ {s} }}, runtime.runtime_allocator);\n", .{ op.func_name, args_buf.items });
                            try writer.print("    reg_{d} = runtime.Value.initNull();\n", .{reg.id});
                        }
                    }

                    // 检查是否产生了异常
                    try writer.writeAll("    if (runtime.hasException()) {\n");
                    try self.generateCleanupCode(writer);
                    if (self.current_exception_handler) |handler_idx| {
                        try writer.print("        current_block = {d};\n", .{handler_idx});
                        try writer.print("        continue;\n", .{});
                    } else {
                        try writer.writeAll("        return error.RuntimeError;\n");
                    }
                    try writer.writeAll("    }\n");
                } else {
                    // 无返回值寄存器
                    if (is_builtin) {
                        const runtime_name = self.mapToRuntimeFunction(op.func_name);

                        // 检查是否需要 allocator 参数
                        if (self.functionNeedsAllocator(op.func_name)) {
                            if (args_buf.items.len > 0) {
                                try writer.print("    _ = try runtime.{s}({s}, runtime.runtime_allocator);\n", .{ runtime_name, args_buf.items });
                            } else {
                                try writer.print("    _ = try runtime.{s}(runtime.runtime_allocator);\n", .{runtime_name});
                            }
                        } else {
                            try writer.print("    _ = try runtime.{s}({s});\n", .{ runtime_name, args_buf.items });
                        }
                    } else {
                        // 用户定义函数
                        try writer.print("    _ = try @\"{s}\"(runtime.Value.initNull(), &[_]runtime.Value{{ {s} }}, runtime.runtime_allocator);\n", .{ op.func_name, args_buf.items });
                    }

                    // 检查是否产生了异常
                    try writer.writeAll("    if (runtime.hasException()) {\n");
                    try self.generateCleanupCode(writer);
                    if (self.current_exception_handler) |handler_idx| {
                        try writer.print("        current_block = {d};\n", .{handler_idx});
                        try writer.print("        continue;\n", .{});
                    } else {
                        try writer.writeAll("        return error.RuntimeError;\n");
                    }
                    try writer.writeAll("    }\n");
                }
            },
            .call_indirect => |op| {
                // 格式化参数列表
                var args_buf = std.ArrayList(u8){};
                defer args_buf.deinit(self.allocator);
                const args_writer = args_buf.writer(self.allocator);

                for (op.args, 0..) |arg, i| {
                    if (i > 0) try args_writer.writeAll(", ");

                    const arg_type_tag = @as(std.meta.Tag(IR.Type), arg.type_);
                    if (arg_type_tag == .i64) {
                        try args_writer.print("runtime.Value.initInt(reg_{d})", .{arg.id});
                    } else if (arg_type_tag == .f64) {
                        try args_writer.print("runtime.Value.initFloat(reg_{d})", .{arg.id});
                    } else if (arg_type_tag == .bool) {
                        try args_writer.print("runtime.Value.initBool(reg_{d})", .{arg.id});
                    } else {
                        try args_writer.print("reg_{d}", .{arg.id});
                    }
                }

                if (inst.result) |reg| {
                     try writer.print("    reg_{d} = try runtime.php_invoke_callable(reg_{d}, &[_]runtime.Value{{ {s} }}, runtime.runtime_allocator);\n", .{ reg.id, op.func_ptr.id, args_buf.items });
                } else {
                     try writer.print("    _ = try runtime.php_invoke_callable(reg_{d}, &[_]runtime.Value{{ {s} }}, runtime.runtime_allocator);\n", .{ op.func_ptr.id, args_buf.items });
                }
            },
            .array_new => |op| {
                _ = op; // 暂时忽略容量
                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                    try writer.print("    reg_{d} = runtime.Value.initArray(try runtime.PHPArray.init(runtime.runtime_allocator));\n", .{reg.id});
                }
            },
            .array_get => |op| {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });

                    const key_type_tag = @as(std.meta.Tag(IR.Type), op.key.type_);

                    if (key_type_tag == .i64) {
                        // 键是i64类型，直接使用
                        try writer.print("    reg_{d} = reg_{d}.asArray().get(runtime.ArrayKey{{ .integer = reg_{d} }}) orelse runtime.Value.initNull();\n", .{ reg.id, op.array.id, op.key.id });
                    } else {
                        // 键是Value类型，使用 getByValue
                        try writer.print("    reg_{d} = reg_{d}.asArray().getByValue(reg_{d}) orelse runtime.Value.initNull();\n", .{ reg.id, op.array.id, op.key.id });
                    }
                }
            },
            .array_set => |op| {
                const key_type_tag = @as(std.meta.Tag(IR.Type), op.key.type_);
                const value_type_tag = @as(std.meta.Tag(IR.Type), op.value.type_);

                // 生成值的表达式
                const value_expr = if (value_type_tag == .php_value)
                    try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.value.id})
                else if (value_type_tag == .i64)
                    try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.value.id})
                else if (value_type_tag == .f64)
                    try std.fmt.allocPrint(self.allocator, "runtime.Value.initFloat(reg_{d})", .{op.value.id})
                else if (value_type_tag == .bool)
                    try std.fmt.allocPrint(self.allocator, "runtime.Value.initBool(reg_{d})", .{op.value.id})
                else
                    try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.value.id});
                defer self.allocator.free(value_expr);

                if (key_type_tag == .i64) {
                    try writer.print("    try reg_{d}.asArray().set(runtime.runtime_allocator, runtime.ArrayKey{{ .integer = reg_{d} }}, {s});\n", .{ op.array.id, op.key.id, value_expr });
                } else {
                    // 假设是 Value 类型，使用 setByValue
                    try writer.print("    try reg_{d}.asArray().setByValue(runtime.runtime_allocator, reg_{d}, {s});\n", .{ op.array.id, op.key.id, value_expr });
                }
            },
            .array_push => |op| {
                const value_type_tag = @as(std.meta.Tag(IR.Type), op.value.type_);

                if (value_type_tag == .php_value) {
                    // 值已经是Value类型，直接使用
                    try writer.print("    try reg_{d}.asArray().push(runtime.runtime_allocator, reg_{d});\n", .{ op.array.id, op.value.id });
                } else if (value_type_tag == .i64) {
                    // 值是i64类型，需要转换
                    try writer.print("    try reg_{d}.asArray().push(runtime.runtime_allocator, runtime.Value.initInt(reg_{d}));\n", .{ op.array.id, op.value.id });
                } else if (value_type_tag == .f64) {
                    // 值是f64类型，需要转换
                    try writer.print("    try reg_{d}.asArray().push(runtime.runtime_allocator, runtime.Value.initFloat(reg_{d}));\n", .{ op.array.id, op.value.id });
                } else if (value_type_tag == .bool) {
                    // 值是bool类型，需要转换
                    try writer.print("    try reg_{d}.asArray().push(runtime.runtime_allocator, runtime.Value.initBool(reg_{d}));\n", .{ op.array.id, op.value.id });
                } else {
                    // 其他类型，默认直接使用
                    try writer.print("    try reg_{d}.asArray().push(runtime.runtime_allocator, reg_{d});\n", .{ op.array.id, op.value.id });
                }
            },
            .array_count => |op| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);

                    if (type_tag == .i64) {
                        // 直接返回i64类型（内部计算用）
                        try writer.print("    reg_{d} = @intCast(reg_{d}.asArray().count());\n", .{ reg.id, op.operand.id });
                    } else {
                        // 返回Value类型（运行时边界）
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                        try writer.print("    reg_{d} = runtime.Value.initInt(@intCast(reg_{d}.asArray().count()));\n", .{ reg.id, op.operand.id });
                    }
                }
            },
            .interpolate => |op| {
                // 字符串插值：将多个部分连接成一个字符串
                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });

                    if (op.parts.len == 0) {
                        // 空插值，返回空字符串
                        try writer.print("    reg_{d} = runtime.Value.initString(try runtime.PHPString.init(runtime.runtime_allocator, \"\"));\n", .{reg.id});
                    } else if (op.parts.len == 1) {
                        // 单个部分，直接转换为字符串
                        const part = op.parts[0];
                        const part_type_tag = @as(std.meta.Tag(IR.Type), part.type_);

                        if (part_type_tag == .php_value or part_type_tag == .php_string) {
                            // 已经是Value类型，调用toString
                            try writer.print("    reg_{d} = runtime.Value.initString(try reg_{d}.toString(runtime.runtime_allocator));\n", .{ reg.id, part.id });
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
                            try writer.print("    reg_{d} = runtime.Value.initString(try reg_{d}.toString(runtime.runtime_allocator));\n", .{ reg.id, part.id });
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
                    // 生成参数列表
                    var args_buf = std.ArrayList(u8){};
                    defer args_buf.deinit(self.allocator);
                    const args_writer = args_buf.writer(self.allocator);

                    for (op.args, 0..) |arg, i| {
                        if (i > 0) try args_writer.writeAll(", ");
                        const arg_type_tag = @as(std.meta.Tag(IR.Type), arg.type_);
                        if (arg_type_tag == .i64) {
                            try args_writer.print("runtime.Value.initInt(reg_{d})", .{arg.id});
                        } else if (arg_type_tag == .f64) {
                            try args_writer.print("runtime.Value.initFloat(reg_{d})", .{arg.id});
                        } else if (arg_type_tag == .bool) {
                            try args_writer.print("runtime.Value.initBool(reg_{d})", .{arg.id});
                        } else {
                            try args_writer.print("reg_{d}", .{arg.id});
                        }
                    }

                    // 创建对象
                    const escaped_class = try self.escapeString(op.class_name);
                    defer self.allocator.free(escaped_class);
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                    try writer.print("    reg_{d} = try runtime.php_object_new_with_constructor(\"{s}\", &[_]runtime.Value{{{s}}}, runtime.runtime_allocator);\n", .{ reg.id, escaped_class, args_buf.items });
                    
                    // 检查异常
                    try writer.writeAll("    if (runtime.hasException()) {\n");
                    try self.generateCleanupCode(writer);
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
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                    try writer.print("    reg_{d} = try runtime.php_object_get(reg_{d}, \"{s}\");\n", .{ reg.id, op.object.id, escaped_prop });
                }
            },
            .property_set => |op| {
                const value_type_tag = @as(std.meta.Tag(IR.Type), op.value.type_);

                const value_expr = if (value_type_tag == .php_value)
                    try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.value.id})
                else if (value_type_tag == .i64)
                    try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.value.id})
                else if (value_type_tag == .f64)
                    try std.fmt.allocPrint(self.allocator, "runtime.Value.initFloat(reg_{d})", .{op.value.id})
                else if (value_type_tag == .bool)
                    try std.fmt.allocPrint(self.allocator, "runtime.Value.initBool(reg_{d})", .{op.value.id})
                else
                    try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.value.id});
                defer self.allocator.free(value_expr);

                const escaped_prop = try self.escapeString(op.property_name);
                defer self.allocator.free(escaped_prop);
                try writer.print("    try runtime.php_object_set(reg_{d}, \"{s}\", {s});\n", .{ op.object.id, escaped_prop, value_expr });
            },
            .method_call => |op| {
                // 生成参数列表
                var args_buf = std.ArrayList(u8){};
                defer args_buf.deinit(self.allocator);
                const args_writer = args_buf.writer(self.allocator);

                for (op.args, 0..) |arg, i| {
                    if (i > 0) try args_writer.writeAll(", ");
                    const arg_type_tag = @as(std.meta.Tag(IR.Type), arg.type_);
                    if (arg_type_tag == .i64) {
                        try args_writer.print("runtime.Value.initInt(reg_{d})", .{arg.id});
                    } else if (arg_type_tag == .f64) {
                        try args_writer.print("runtime.Value.initFloat(reg_{d})", .{arg.id});
                    } else if (arg_type_tag == .bool) {
                        try args_writer.print("runtime.Value.initBool(reg_{d})", .{arg.id});
                    } else {
                        try args_writer.print("reg_{d}", .{arg.id});
                    }
                }

                const escaped_method = try self.escapeString(op.method_name);
                defer self.allocator.free(escaped_method);

                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                    try writer.print("    reg_{d} = try runtime.php_object_call(reg_{d}, \"{s}\", &[_]runtime.Value{{{s}}});\n", .{ reg.id, op.object.id, escaped_method, args_buf.items });
                } else {
                    try writer.print("    _ = try runtime.php_object_call(reg_{d}, \"{s}\", &[_]runtime.Value{{{s}}});\n", .{ op.object.id, escaped_method, args_buf.items });
                }

                // 检查异常
                try writer.writeAll("    if (runtime.hasException()) {\n");
                try self.generateCleanupCode(writer);
                if (self.current_exception_handler) |handler_idx| {
                    try writer.print("        current_block = {d};\n", .{handler_idx});
                    try writer.print("        continue;\n", .{});
                } else {
                    try writer.writeAll("        return error.RuntimeError;\n");
                }
                try writer.writeAll("    }\n");
            },
            .static_method_call => |op| {
                var args_buf = std.ArrayList(u8){};
                defer args_buf.deinit(self.allocator);
                const args_writer = args_buf.writer(self.allocator);

                for (op.args, 0..) |arg, i| {
                    if (i > 0) try args_writer.writeAll(", ");
                    const arg_type_tag = @as(std.meta.Tag(IR.Type), arg.type_);
                    if (arg_type_tag == .i64) {
                        try args_writer.print("runtime.Value.initInt(reg_{d})", .{arg.id});
                    } else if (arg_type_tag == .f64) {
                        try args_writer.print("runtime.Value.initFloat(reg_{d})", .{arg.id});
                    } else if (arg_type_tag == .bool) {
                        try args_writer.print("runtime.Value.initBool(reg_{d})", .{arg.id});
                    } else {
                        try args_writer.print("reg_{d}", .{arg.id});
                    }
                }

                const escaped_class = try self.escapeString(op.class_name);
                defer self.allocator.free(escaped_class);
                const escaped_method = try self.escapeString(op.method_name);
                defer self.allocator.free(escaped_method);

                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                    try writer.print(
                        "    reg_{d} = try runtime.php_call_static(\"{s}\", \"{s}\", &[_]runtime.Value{{{s}}}, runtime.runtime_allocator);\n",
                        .{ reg.id, escaped_class, escaped_method, args_buf.items },
                    );
                } else {
                    try writer.print(
                        "    _ = try runtime.php_call_static(\"{s}\", \"{s}\", &[_]runtime.Value{{{s}}}, runtime.runtime_allocator);\n",
                        .{ escaped_class, escaped_method, args_buf.items },
                    );
                }

                try writer.writeAll("    if (runtime.hasException()) {\n");
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
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                    try writer.print("    reg_{d} = try runtime.php_get_static_property(\"{s}\", \"{s}\");\n", .{ reg.id, escaped_class, escaped_prop });
                }
            },
            .static_property_set => |op| {
                const value_type_tag = @as(std.meta.Tag(IR.Type), op.value.type_);

                const value_expr = if (value_type_tag == .php_value)
                    try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.value.id})
                else if (value_type_tag == .i64)
                    try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt(reg_{d})", .{op.value.id})
                else if (value_type_tag == .f64)
                    try std.fmt.allocPrint(self.allocator, "runtime.Value.initFloat(reg_{d})", .{op.value.id})
                else if (value_type_tag == .bool)
                    try std.fmt.allocPrint(self.allocator, "runtime.Value.initBool(reg_{d})", .{op.value.id})
                else
                    try std.fmt.allocPrint(self.allocator, "reg_{d}", .{op.value.id});
                defer self.allocator.free(value_expr);

                const escaped_class = try self.escapeString(op.class_name);
                defer self.allocator.free(escaped_class);
                const escaped_prop = try self.escapeString(op.property_name);
                defer self.allocator.free(escaped_prop);
                try writer.print("    try runtime.php_set_static_property(\"{s}\", \"{s}\", {s});\n", .{ escaped_class, escaped_prop, value_expr });
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
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg.id});
                    try writer.print("    reg_{d} = runtime.getException();\n", .{reg.id});
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
                    try writer.print("    reg_{d} = runtime.Value.initNull();\n", .{reg.id});
                }
            },
            .clear_exception => {
                try writer.writeAll("    runtime.clearException();\n");
            },
            .cast => |op| {
                // cast: 类型转换
                if (inst.result) |reg| {
                    // Get the actual type of the source register
                    const src_real_type = self.current_reg_types.?.get(op.value.id) orelse op.value.type_;
                    const src_tag = @as(std.meta.Tag(IR.Type), src_real_type);

                    // 根据目标类型生成不同的转换代码
                    if (op.to_type == .php_value) {
                        try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                        // 从基本类型转换到php_value
                        if (src_tag == .i64) {
                            try writer.print("    reg_{d} = runtime.Value.initInt(reg_{d});\n", .{ reg.id, op.value.id });
                        } else if (src_tag == .f64) {
                            try writer.print("    reg_{d} = runtime.Value.initFloat(reg_{d});\n", .{ reg.id, op.value.id });
                        } else if (src_tag == .bool) {
                            try writer.print("    reg_{d} = runtime.Value.initBool(reg_{d});\n", .{ reg.id, op.value.id });
                        } else {
                            try writer.print("    reg_{d} = reg_{d}; // cast from {any} to {any}\n", .{ reg.id, op.value.id, src_tag, op.to_type });
                        }
                    } else if (op.to_type == .i64) {
                        // 转换到i64
                        if (src_tag == .i64) {
                            try writer.print("    reg_{d} = reg_{d};\n", .{ reg.id, op.value.id });
                        } else {
                            try writer.print("    reg_{d} = reg_{d}.asInt();\n", .{ reg.id, op.value.id });
                        }
                    } else if (op.to_type == .f64) {
                        // 转换到f64
                        if (src_tag == .f64) {
                            try writer.print("    reg_{d} = reg_{d};\n", .{ reg.id, op.value.id });
                        } else {
                            try writer.print("    reg_{d} = reg_{d}.asFloat();\n", .{ reg.id, op.value.id });
                        }
                    } else if (op.to_type == .bool) {
                        // 转换到bool
                        if (src_tag == .bool) {
                            try writer.print("    reg_{d} = reg_{d};\n", .{ reg.id, op.value.id });
                        } else {
                            try writer.print("    reg_{d} = reg_{d}.asBool();\n", .{ reg.id, op.value.id });
                        }
                    } else {
                        // 默认：直接赋值
                        try writer.print("    reg_{d} = reg_{d}; // cast\n", .{ reg.id, op.value.id });
                    }
                }
            },
            // ============ 并发操作指令 ============
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
                var args_buf = std.ArrayList(u8){};
                defer args_buf.deinit(self.allocator);
                const args_writer = args_buf.writer(self.allocator);

                for (op.args, 0..) |arg, i| {
                    if (i > 0) try args_writer.writeAll(", ");
                    const arg_type_tag = @as(std.meta.Tag(IR.Type), arg.type_);
                    if (arg_type_tag == .i64) {
                        try args_writer.print("runtime.Value.initInt(reg_{d})", .{arg.id});
                    } else {
                        try args_writer.print("reg_{d}", .{arg.id});
                    }
                }

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
                try writer.print("\", &[_]runtime.Value{{{s}}}, runtime.runtime_allocator);\n", .{args_buf.items});
            },
            .channel_new => |op| {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                    try writer.print("    reg_{d} = try runtime.channel_new({d}, runtime.runtime_allocator);\n", .{ reg.id, op.buffer_size });
                }
            },
            .channel_send => |op| {
                try writer.print("    try runtime.channel_send(reg_{d}, reg_{d});\n", .{ op.channel.id, op.value.id });
            },
            .channel_recv => |op| {
                if (inst.result) |reg| {
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                    try writer.print("    reg_{d} = try runtime.channel_recv(reg_{d});\n", .{ reg.id, op.channel.id });
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
                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{ reg.id });
                    try writer.print("    reg_{d} = try runtime.await_result(reg_{d});\n", .{ reg.id, op.operand.id });
                }
            },
            else => {
                try self.handleUnsupportedOp(inst);
            },
        }
    }

    /// 生成控制流结构（直接操作ArrayList）
    fn generateControlFlowDirect(self: *Self, code: *std.ArrayList(u8), func: *const IR.Function, cleanup_regs: []const usize) !void {
        if (func.blocks.items.len == 0) return;

        // 优化：单块函数直接生成线性代码
        if (func.blocks.items.len == 1) {
            const block = func.blocks.items[0];
            const is_simple_return = if (block.terminator) |term|
                @as(std.meta.Tag(IR.Terminator), term) == .ret
            else
                false;

            if (is_simple_return) {
                try code.appendSlice(self.allocator, "    // Single-block function: linear code generation (optimized)\n");

                // 生成所有指令
                for (block.instructions.items) |inst| {
                    // 创建一个临时writer
                    var inst_code = std.ArrayList(u8){};
                    defer inst_code.deinit(self.allocator);
                    const inst_writer = inst_code.writer(self.allocator);
                    try self.generateInstruction(inst_writer, inst);
                    try code.appendSlice(self.allocator, inst_code.items);
                }

                // 生成return语句
                if (block.terminator) |term| {
                    switch (term) {
                        .ret => |ret_val| {
                            // Cleanup (except return value)
                            if (cleanup_regs.len > 0) {
                                try code.appendSlice(self.allocator, "    // Cleanup: release allocated values (except return value)\n");
                                for (cleanup_regs) |reg_id| {
                                    // 检查是否是返回值寄存器
                                    const is_return_reg = if (ret_val) |reg| reg.id == reg_id else false;
                                    if (!is_return_reg) {
                                        const cleanup = try std.fmt.allocPrint(self.allocator, "    reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                                        defer self.allocator.free(cleanup);
                                        try code.appendSlice(self.allocator, cleanup);
                                    }
                                }
                            }
                            if (ret_val) |reg| {
                                const ret_stmt = try std.fmt.allocPrint(self.allocator, "    return reg_{d};\n", .{reg.id});
                                defer self.allocator.free(ret_stmt);
                                try code.appendSlice(self.allocator, ret_stmt);
                            } else {
                                try code.appendSlice(self.allocator, "    return runtime.Value.initNull();\n");
                            }
                        },
                        else => unreachable,
                    }
                }
                return;
            }
        }

        // 复杂控制流：使用状态机
        try code.appendSlice(self.allocator, "    // Control flow state machine\n");
        try code.appendSlice(self.allocator, "    var current_block: u32 = 0;\n");
        try code.appendSlice(self.allocator, "    while (true) {\n");
        try code.appendSlice(self.allocator, "        switch (current_block) {\n");

        for (func.blocks.items, 0..) |block, block_idx| {
            const case_start = try std.fmt.allocPrint(self.allocator, "            {d} => {{ // {s}\n", .{ block_idx, block.label });
            defer self.allocator.free(case_start);
            try code.appendSlice(self.allocator, case_start);

            // 生成块内指令
            for (block.instructions.items) |inst| {
                try code.appendSlice(self.allocator, "    ");
                try self.generateInstructionDirect(code, inst);
            }

            // 生成终止指令
            if (block.terminator) |term| {
                try self.generateTerminatorDirect(code, term, cleanup_regs, func);
            } else {
                if (block_idx + 1 < func.blocks.items.len) {
                    const jump = try std.fmt.allocPrint(self.allocator, "                current_block = {d};\n", .{block_idx + 1});
                    defer self.allocator.free(jump);
                    try code.appendSlice(self.allocator, jump);
                } else {
                    if (cleanup_regs.len > 0) {
                        try code.appendSlice(self.allocator, "                // Cleanup\n");
                        for (cleanup_regs) |reg_id| {
                            const cleanup = try std.fmt.allocPrint(self.allocator, "                reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                            defer self.allocator.free(cleanup);
                            try code.appendSlice(self.allocator, cleanup);
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

    /// 生成终止指令（直接操作ArrayList）
    fn generateTerminatorDirect(self: *Self, code: *std.ArrayList(u8), term: IR.Terminator, cleanup_regs: []const usize, func: *const IR.Function) !void {
        switch (term) {
            .ret => |ret_val| {
                if (cleanup_regs.len > 0) {
                    try code.appendSlice(self.allocator, "                // Cleanup (except return value)\n");
                    for (cleanup_regs) |reg_id| {
                        // 检查是否是返回值寄存器
                        const is_return_reg = if (ret_val) |reg| reg.id == reg_id else false;
                        if (!is_return_reg) {
                            const cleanup = try std.fmt.allocPrint(self.allocator, "                reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                            defer self.allocator.free(cleanup);
                            try code.appendSlice(self.allocator, cleanup);
                        }
                    }
                }
                if (ret_val) |reg| {
                    const ret_stmt = try std.fmt.allocPrint(self.allocator, "                return reg_{d};\n", .{reg.id});
                    defer self.allocator.free(ret_stmt);
                    try code.appendSlice(self.allocator, ret_stmt);
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
                const jump = try std.fmt.allocPrint(self.allocator, "                current_block = {d};\n", .{target_idx});
                defer self.allocator.free(jump);
                try code.appendSlice(self.allocator, jump);
            },
            .cond_br => |br| {
                // 找到then和else块的索引
                var then_idx: usize = 0;
                var else_idx: usize = 0;
                for (func.blocks.items, 0..) |block, idx| {
                    if (block == br.then_block) then_idx = idx;
                    if (block == br.else_block) else_idx = idx;
                }

                // 获取条件寄存器的实际类型
                const reg_type = self.current_reg_types.?.get(br.cond.id) orelse IR.Type{ .php_value = {} };
                const type_tag = @as(std.meta.Tag(IR.Type), reg_type);
                
                std.debug.print("DEBUG: cond_br reg_{d} type_tag = {s}\n", .{br.cond.id, @tagName(type_tag)});

                const cond_expr = if (type_tag == .bool)
                    try std.fmt.allocPrint(self.allocator, "reg_{d}", .{br.cond.id})
                else if (type_tag == .i64)
                    try std.fmt.allocPrint(self.allocator, "(reg_{d} != 0)", .{br.cond.id})
                else if (type_tag == .f64)
                    try std.fmt.allocPrint(self.allocator, "(reg_{d} != 0.0)", .{br.cond.id})
                else
                    try std.fmt.allocPrint(self.allocator, "reg_{d}.toBool()", .{br.cond.id});
                defer self.allocator.free(cond_expr);

                const cond = try std.fmt.allocPrint(self.allocator, "                if ({s}) {{\n                    current_block = {d};\n                }} else {{\n                    current_block = {d};\n                }}\n", .{ cond_expr, then_idx, else_idx });
                defer self.allocator.free(cond);
                try code.appendSlice(self.allocator, cond);
            },
            else => {
                try code.appendSlice(self.allocator, "                return runtime.Value.initNull();\n");
            },
        }
    }

    /// 生成指令（直接操作ArrayList）
    fn generateInstructionDirect(self: *Self, code: *std.ArrayList(u8), inst: *const IR.Instruction) !void {
        // Add source location comment
        if (inst.location.line > 0) {
            try code.writer(self.allocator).print("        // {s}:{d}\n", .{ inst.location.file, inst.location.line });
        }

        const result_reg = if (inst.result) |r| r.id else null;

        switch (inst.op) {
            .const_int => |val| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const is_value = !(type_tag == .i64 or type_tag == .f64 or type_tag == .bool);
                    const instr = if (!is_value)
                        try std.fmt.allocPrint(self.allocator, "        reg_{d} = {d};\n", .{ result_reg.?, val })
                    else
                        try std.fmt.allocPrint(self.allocator, "        reg_{d} = runtime.Value.initInt({d});\n", .{ result_reg.?, val });
                    defer self.allocator.free(instr);
                    try code.appendSlice(self.allocator, instr);
                }
            },
            .const_float => |val| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const is_value = !(type_tag == .i64 or type_tag == .f64 or type_tag == .bool);
                    const instr = if (!is_value)
                        try std.fmt.allocPrint(self.allocator, "        reg_{d} = {d};\n", .{ result_reg.?, val })
                    else
                        try std.fmt.allocPrint(self.allocator, "        reg_{d} = runtime.Value.initFloat({d});\n", .{ result_reg.?, val });
                    defer self.allocator.free(instr);
                    try code.appendSlice(self.allocator, instr);
                }
            },
            .const_bool => |val| {
                if (inst.result) |reg| {
                    const type_tag = @as(std.meta.Tag(IR.Type), reg.type_);
                    const is_value = !(type_tag == .i64 or type_tag == .f64 or type_tag == .bool);
                    const instr = if (!is_value)
                        try std.fmt.allocPrint(self.allocator, "        reg_{d} = {};\n", .{ result_reg.?, val })
                    else
                        try std.fmt.allocPrint(self.allocator, "        reg_{d} = runtime.Value.initBool({});\n", .{ result_reg.?, val });
                    defer self.allocator.free(instr);
                    try code.appendSlice(self.allocator, instr);
                }
            },
            .const_string => |string_id| {
                const instr = try std.fmt.allocPrint(self.allocator, "        reg_{d} = runtime.Value.initString(try runtime.PHPString.init(runtime.runtime_allocator, string_table[{d}]));\n", .{ result_reg.?, string_id });
                defer self.allocator.free(instr);
                try code.appendSlice(self.allocator, instr);
            },
            .const_null => {
                const instr = try std.fmt.allocPrint(self.allocator, "        reg_{d} = runtime.Value.initNull();\n", .{result_reg.?});
                defer self.allocator.free(instr);
                try code.appendSlice(self.allocator, instr);
            },
            .alloca => {
                const instr = try std.fmt.allocPrint(self.allocator, "        // alloca: reg_{d}\n", .{result_reg.?});
                defer self.allocator.free(instr);
                try code.appendSlice(self.allocator, instr);
            },
            .load => |op| {
                // 检查是否是 alloca 寄存器（即指针类型）
                const is_ptr = if (self.current_alloca_regs) |regs| regs.contains(op.ptr.id) else false;
                const ptr_prefix = if (is_ptr) "" else "&";
                const type_tag = @as(std.meta.Tag(IR.Type), inst.result.?.type_);
                
                var instr: []u8 = undefined;
                if (type_tag == .i64) {
                     instr = try std.fmt.allocPrint(self.allocator, "        reg_{d} = runtime.val_deref({s}reg_{d}).*.asInt();\n", .{ result_reg.?, ptr_prefix, op.ptr.id });
                } else if (type_tag == .f64) {
                     instr = try std.fmt.allocPrint(self.allocator, "        reg_{d} = runtime.val_deref({s}reg_{d}).*.asFloat();\n", .{ result_reg.?, ptr_prefix, op.ptr.id });
                } else if (type_tag == .bool) {
                     instr = try std.fmt.allocPrint(self.allocator, "        reg_{d} = runtime.val_deref({s}reg_{d}).*.asBool();\n", .{ result_reg.?, ptr_prefix, op.ptr.id });
                } else {
                     instr = try std.fmt.allocPrint(self.allocator, "        reg_{d} = runtime.val_deref({s}reg_{d}).*;\n", .{ result_reg.?, ptr_prefix, op.ptr.id });
                }
                defer self.allocator.free(instr);
                try code.appendSlice(self.allocator, instr);
            },
            .store => |op| {
                const value_type_tag = @as(std.meta.Tag(IR.Type), op.value.type_);
                // 检查是否是 alloca 寄存器（即指针类型）
                const is_ptr = if (self.current_alloca_regs) |regs| regs.contains(op.ptr.id) else false;
                const ptr_prefix = if (is_ptr) "" else "&";

                // 释放旧值
                const release = try std.fmt.allocPrint(self.allocator, "        reg_{d}.release(runtime.runtime_allocator);\n", .{op.ptr.id});
                defer self.allocator.free(release);
                try code.appendSlice(self.allocator, release);

                // 存储新值
                var instr: []u8 = undefined;
                if (value_type_tag == .i64) {
                    instr = try std.fmt.allocPrint(self.allocator, "        runtime.val_assign({s}reg_{d}, runtime.Value.initInt(reg_{d}));\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                } else if (value_type_tag == .f64) {
                    instr = try std.fmt.allocPrint(self.allocator, "        runtime.val_assign({s}reg_{d}, runtime.Value.initFloat(reg_{d}));\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                } else if (value_type_tag == .bool) {
                    instr = try std.fmt.allocPrint(self.allocator, "        runtime.val_assign({s}reg_{d}, runtime.Value.initBool(reg_{d}));\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                } else if (value_type_tag == .php_value or value_type_tag == .php_string or value_type_tag == .php_array or value_type_tag == .php_object or value_type_tag == .php_callable) {
                    const retain = try std.fmt.allocPrint(self.allocator, "        reg_{d}.retain();\n", .{op.value.id});
                    defer self.allocator.free(retain);
                    try code.appendSlice(self.allocator, retain);
                    instr = try std.fmt.allocPrint(self.allocator, "        runtime.val_assign({s}reg_{d}, reg_{d});\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                } else {
                    const retain = try std.fmt.allocPrint(self.allocator, "        reg_{d}.retain();\n", .{op.value.id});
                    defer self.allocator.free(retain);
                    try code.appendSlice(self.allocator, retain);
                    instr = try std.fmt.allocPrint(self.allocator, "        runtime.val_assign({s}reg_{d}, reg_{d});\n", .{ ptr_prefix, op.ptr.id, op.value.id });
                }
                defer self.allocator.free(instr);
                try code.appendSlice(self.allocator, instr);
            },
            .call => |op| {
                // 生成函数调用
                // 检查是否是内置函数
                const is_builtin = self.isBuiltinFunction(op.func_name);

                // 格式化参数列表
                var args_buf = std.ArrayList(u8){};
                defer args_buf.deinit(self.allocator);
                const args_writer = args_buf.writer(self.allocator);

                for (op.args, 0..) |arg, i| {
                    if (i > 0) try args_writer.writeAll(", ");

                    const arg_type_tag = @as(std.meta.Tag(IR.Type), arg.type_);
                    if (arg_type_tag == .i64) {
                        try args_writer.print("runtime.Value.initInt(reg_{d})", .{arg.id});
                    } else if (arg_type_tag == .f64) {
                        try args_writer.print("runtime.Value.initFloat(reg_{d})", .{arg.id});
                    } else if (arg_type_tag == .bool) {
                        try args_writer.print("runtime.Value.initBool(reg_{d})", .{arg.id});
                    } else {
                        try args_writer.print("reg_{d}", .{arg.id});
                    }
                }

                // 生成函数调用
                const instr = if (is_builtin) blk: {
                    const runtime_name = self.mapToRuntimeFunction(op.func_name);
                    break :blk try std.fmt.allocPrint(self.allocator, "        _ = try runtime.{s}({s});\n", .{ runtime_name, args_buf.items });
                } else blk: {
                    // 用户定义函数
                    break :blk try std.fmt.allocPrint(self.allocator, "        _ = try @\"{s}\"({s});\n", .{ op.func_name, args_buf.items });
                };
                defer self.allocator.free(instr);
                try code.appendSlice(self.allocator, instr);
            },
            else => {
                try self.handleUnsupportedOp(inst);
                const tag = std.meta.activeTag(inst.op);
                const comment = try std.fmt.allocPrint(self.allocator, "        // TODO: {s}\n", .{@tagName(tag)});
                defer self.allocator.free(comment);
                try code.appendSlice(self.allocator, comment);
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

                // 生成所有指令
                for (block.instructions.items) |inst| {
                    try self.generateInstruction(writer, inst);
                }

                // 生成return语句
                if (block.terminator) |term| {
                    switch (term) {
                        .ret => |ret_val| {
                            // 在return之前执行cleanup
                            if (cleanup_regs.len > 0) {
                                try writer.writeAll("    // Cleanup: release all allocated values\n");
                                for (cleanup_regs) |reg_id| {
                                    try writer.print("    reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                                }
                            }
                            if (ret_val) |reg| {
                                const reg_str = try self.formatRegister(reg);
                                defer self.allocator.free(reg_str);
                                try writer.print("    return {s};\n", .{reg_str});
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

        // 复杂控制流：使用状态机模式
        try writer.writeAll("    // Control flow state machine\n");
        try writer.writeAll("    var current_block: u32 = 0;\n");
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
        // 至少需要3个块：entry + cond + body + exit（while）
        // 或4个块：entry + cond + body + loop + exit（for）
        if (func.blocks.items.len < 3) {
            return false;
        }

        // 检测while循环模式
        if (try self.tryGenerateWhileLoop(writer, func, cleanup_regs)) {
            return true;
        }

        // 检测for循环模式
        if (try self.tryGenerateForLoop(writer, func, cleanup_regs)) {
            return true;
        }

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

        // 生成条件判断
        const cond_str = try self.formatRegister(cond_br.cond);
        defer self.allocator.free(cond_str);

        // 根据条件寄存器的类型生成不同的代码
        if (cond_br.cond.type_ == .bool) {
            try writer.print("        if (!{s}) break;\n", .{cond_str});
        } else {
            try writer.print("        if (!{s}.toBool()) break;\n", .{cond_str});
        }

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
                    const reg_str = try self.formatRegister(reg);
                    defer self.allocator.free(reg_str);
                    try writer.print("    return {s};\n", .{reg_str});
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

        // 生成条件判断
        const cond_str_for = try self.formatRegister(cond_br.cond);
        defer self.allocator.free(cond_str_for);

        // 根据条件寄存器的类型生成不同的代码
        if (cond_br.cond.type_ == .bool) {
            try writer.print("        if (!{s}) break;\n", .{cond_str_for});
        } else {
            try writer.print("        if (!{s}.toBool()) break;\n", .{cond_str_for});
        }

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
                    const reg_str = try self.formatRegister(reg);
                    defer self.allocator.free(reg_str);
                    try writer.print("    return {s};\n", .{reg_str});
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

        // 生成if-else结构
        const cond_str = try self.formatRegister(cond_br.cond);
        defer self.allocator.free(cond_str);

        // 获取条件寄存器的实际类型
        const reg_type = self.current_reg_types.?.get(cond_br.cond.id) orelse IR.Type{ .php_value = {} };
        const type_tag = @as(std.meta.Tag(IR.Type), reg_type);

        // 根据条件寄存器的类型生成不同的代码
        if (type_tag == .bool) {
            try writer.print("    if ({s}) {{\n", .{cond_str});
        } else if (type_tag == .i64) {
             try writer.print("    if ({s} != 0) {{\n", .{cond_str});
        } else if (type_tag == .f64) {
             try writer.print("    if ({s} != 0.0) {{\n", .{cond_str});
        } else {
            try writer.print("    if ({s}.toBool()) {{\n", .{cond_str});
        }

        // 生成then块
        try writer.writeAll("        // Then branch\n");
        for (then_block.instructions.items) |inst| {
            try writer.writeAll("    ");
            try self.generateInstruction(writer, inst);
        }

        // then块的return（不需要cleanup，因为简单if-else中的值会在return时自动处理）
        if (then_term.ret) |reg| {
            const reg_str = try self.formatRegister(reg);
            defer self.allocator.free(reg_str);
            try writer.print("        return {s};\n", .{reg_str});
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
            const reg_str = try self.formatRegister(reg);
            defer self.allocator.free(reg_str);
            try writer.print("        return {s};\n", .{reg_str});
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
                        if (!is_return_reg) {
                            if (alloca_regs.contains(reg_id)) {
                                try writer.print("                reg_{d}.*.release(runtime.runtime_allocator);\n", .{reg_id});
                            } else {
                                try writer.print("                reg_{d}.release(runtime.runtime_allocator);\n", .{reg_id});
                            }
                        }
                    }
                }
                if (maybe_reg) |reg| {
                    const reg_str = try self.formatRegister(reg);
                    defer self.allocator.free(reg_str);
                    try writer.print("                return {s};\n", .{reg_str});
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
                const cond_str = try self.formatRegister(cond_br.cond);
                defer self.allocator.free(cond_str);

                const then_idx = self.findBlockIndex(func, cond_br.then_block);
                const else_idx = self.findBlockIndex(func, cond_br.else_block);

                // 获取条件寄存器的实际类型
                const reg_type = self.current_reg_types.?.get(cond_br.cond.id) orelse IR.Type{ .php_value = {} };
                const type_tag = @as(std.meta.Tag(IR.Type), reg_type);

                if (type_tag == .i64) {
                    try writer.print("                if ({s} != 0) {{\n", .{cond_str});
                } else if (type_tag == .f64) {
                    try writer.print("                if ({s} != 0.0) {{\n", .{cond_str});
                } else {
                    try writer.print("                if ({s}.toBool()) {{\n", .{cond_str});
                }

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
                // Switch语句
                const value_str = try self.formatRegister(switch_data.value);
                defer self.allocator.free(value_str);

                try writer.print("                switch ({s}.toInt()) {{\n", .{value_str});
                for (switch_data.cases) |case| {
                    const case_idx = self.findBlockIndex(func, case.block);
                    try writer.print("                    {d} => current_block = {d},\n", .{ case.value, case_idx });
                }
                const default_idx = self.findBlockIndex(func, switch_data.default);
                try writer.print("                    else => current_block = {d},\n", .{default_idx});
                try writer.writeAll("                }\n");
            },
            .throw => |exception_reg| {
                const exc_str = try self.formatRegister(exception_reg);
                defer self.allocator.free(exc_str);
                try writer.print("                return error.PHPException; // Exception: {s}\n", .{exc_str});
            },
            .unreachable_ => {
                try writer.writeAll("                unreachable;\n");
            },
        }
    }

    /// 生成PHI节点的赋值语句
    /// 在跳转到目标块之前，检查目标块是否有PHI节点，如果有则设置PHI结果
    fn generatePhiAssignments(self: *Self, writer: anytype, func: *const IR.Function, target_block: *const IR.BasicBlock, source_block_idx: usize) !void {
        // 获取源块指针
        const source_block = func.blocks.items[source_block_idx];

        // 遍历目标块的指令，查找PHI节点
        for (target_block.instructions.items) |inst| {
            if (inst.op == .phi) {
                const phi_op = inst.op.phi;
                const result_reg = inst.result orelse continue;

                // 查找来自当前块的incoming值
                for (phi_op.incoming) |incoming| {
                    if (incoming.block == source_block) {
                        const value_str = try self.formatRegister(incoming.value);
                        defer self.allocator.free(value_str);
                        const result_str = try self.formatRegister(result_reg);
                        defer self.allocator.free(result_str);

                        try writer.print("            {s} = {s};\n", .{ result_str, value_str });
                        break;
                    }
                }
            }
        }
    }

    /// 查找基本块在函数中的索引
    fn findBlockIndex(self: *const Self, func: *const IR.Function, target: *const IR.BasicBlock) u32 {
        for (func.blocks.items, 0..) |block, i| {
            if (block == target) {
                return @intCast(i);
            }
        }
        // 如果找不到，返回0（不应该发生）
        _ = self.config.verbose;
        return 0;
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

        // 生成结果寄存器声明（如果有）
        const result_reg = if (inst.result) |r| try std.fmt.allocPrint(
            self.allocator,
            "reg_{d}",
            .{r.id},
        ) else null;
        defer if (result_reg) |r| self.allocator.free(r);

        switch (inst.op) {
            // ========================================================================
            // 常量指令
            // ========================================================================
            // 常量指令
            // ========================================================================
            .const_int => |val| {
                // 根据结果寄存器类型生成不同的代码
                if (inst.result) |reg| {
                    if (reg.type_ == .i64) {
                        try writer.print("        {s} = {d};\n", .{ result_reg.?, val });
                    } else {
                        try writer.print("        {s} = runtime.Value.initInt({d});\n", .{ result_reg.?, val });
                    }
                }
            },
            .const_float => |val| {
                if (inst.result) |reg| {
                    if (reg.type_ == .f64) {
                        try writer.print("        {s} = {d};\n", .{ result_reg.?, val });
                    } else {
                        try writer.print("        {s} = runtime.Value.initFloat({d});\n", .{ result_reg.?, val });
                    }
                }
            },
            .const_bool => |val| {
                if (inst.result) |reg| {
                    if (reg.type_ == .bool) {
                        try writer.print("        {s} = {};\n", .{ result_reg.?, val });
                    } else {
                        try writer.print("        {s} = runtime.Value.initBool({});\n", .{ result_reg.?, val });
                    }
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
                        try writer.print("        {s} = if (args.len > {d}) args[{d}] else runtime.Value.initNull();\n", .{ result_reg.?, arg_idx, arg_idx });
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
                const ptr = try self.formatRegister(op.ptr);
                defer self.allocator.free(ptr);

                // 智能处理类型转换
                // 检查结果寄存器的类型和加载的类型
                if (inst.result) |reg| {
                    const result_type = reg.type_;
                    const load_type = op.type_;

                    // 使用标签比较类型
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
            },
            .store => |op| {
                const ptr = try self.formatRegister(op.ptr);
                defer self.allocator.free(ptr);
                const value = try self.formatRegister(op.value);
                defer self.allocator.free(value);

                // 获取指针指向的类型
                const ptr_inner_type = switch (op.ptr.type_) {
                    .ptr => |inner| inner.*,
                    else => .php_value,
                };

                // 在存储新值之前，释放旧值（如果是引用类型）
                // 这对于字符串和数组特别重要，防止内存泄漏
                if (ptr_inner_type == .php_value) {
                    try writer.print("        {s}.*.release(runtime.runtime_allocator);\n", .{ptr});
                }

                // 存储新值 - 需要类型转换
                const ptr_tag = @as(std.meta.Tag(IR.Type), ptr_inner_type);
                const value_tag = @as(std.meta.Tag(IR.Type), op.value.type_);

                if (ptr_tag == value_tag) {
                    // 类型匹配，直接赋值
                    try writer.print("        {s}.* = {s};\n", .{ ptr, value });
                } else {
                    // 类型不匹配，需要转换
                    if (ptr_tag == .php_value) {
                        // 存储到php_value指针，需要从基本类型转换
                        switch (value_tag) {
                            .i64 => try writer.print("        {s}.* = runtime.Value.initInt({s});\n", .{ ptr, value }),
                            .f64 => try writer.print("        {s}.* = runtime.Value.initFloat({s});\n", .{ ptr, value }),
                            .bool => try writer.print("        {s}.* = runtime.Value.initBool({s});\n", .{ ptr, value }),
                            else => try writer.print("        {s}.* = {s};\n", .{ ptr, value }),
                        }
                    } else if (value_tag == .php_value) {
                        // 从php_value存储到基本类型指针，需要提取
                        switch (ptr_tag) {
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
            },

            // ========================================================================
            // 算术运算指令
            // ========================================================================
            .add => |op| {
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);
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
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);
                try writer.print("        {s} = try runtime.php_sub({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .mul => |op| {
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);
                try writer.print("        {s} = try runtime.php_mul({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .div => |op| {
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);
                try writer.print("        {s} = try runtime.php_div({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .mod => |op| {
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);
                try writer.print("        {s} = try runtime.php_mod({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .pow => |op| {
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);
                try writer.print("        {s} = try runtime.php_pow({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .neg => |op| {
                const operand = try self.formatRegister(op.operand);
                defer self.allocator.free(operand);
                try writer.print("        {s} = try runtime.php_sub(runtime.Value.initInt(0), {s});\n", .{ result_reg.?, operand });
            },

            // ========================================================================
            // 比较运算指令
            // ========================================================================
            .eq => |op| {
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);

                // 根据操作数类型和结果类型生成不同的代码
                if (op.lhs.type_ == .i64 and op.rhs.type_ == .i64) {
                    // 两个i64直接比较
                    try writer.print("        {s} = {s} == {s};\n", .{ result_reg.?, lhs, rhs });
                } else if (inst.result) |reg| {
                    // 涉及Value类型的比较
                    var lhs_val: []const u8 = undefined;
                    var rhs_val: []const u8 = undefined;
                    var need_free_lhs = false;
                    var need_free_rhs = false;

                    if (op.lhs.type_ == .php_value) {
                        lhs_val = lhs;
                    } else if (op.lhs.type_ == .i64) {
                        lhs_val = try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt({s})", .{lhs});
                        need_free_lhs = true;
                    } else {
                        lhs_val = lhs;
                    }

                    if (op.rhs.type_ == .php_value) {
                        rhs_val = rhs;
                    } else if (op.rhs.type_ == .i64) {
                        rhs_val = try std.fmt.allocPrint(self.allocator, "runtime.Value.initInt({s})", .{rhs});
                        need_free_rhs = true;
                    } else {
                        rhs_val = rhs;
                    }

                    if (reg.type_ == .bool) {
                        // 结果是bool，需要调用toBool()
                        try writer.print("        {s} = (try runtime.php_eq({s}, {s})).toBool();\n", .{ result_reg.?, lhs_val, rhs_val });
                    } else {
                        // 结果是Value
                        try writer.print("        {s} = try runtime.php_eq({s}, {s});\n", .{ result_reg.?, lhs_val, rhs_val });
                    }

                    if (need_free_lhs) self.allocator.free(lhs_val);
                    if (need_free_rhs) self.allocator.free(rhs_val);
                }
            },
            .ne => |op| {
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);
                try writer.print("        {s} = try runtime.php_ne({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .lt => |op| {
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);
                // 根据结果寄存器类型和操作数类型生成不同的代码
                if (inst.result) |reg| {
                    if (reg.type_ == .bool and op.lhs.type_ == .i64 and op.rhs.type_ == .i64) {
                        // 直接i64比较，返回bool（内部计算用）
                        try writer.print("        {s} = {s} < {s};\n", .{ result_reg.?, lhs, rhs });
                    } else {
                        // 使用运行时函数（运行时边界）
                        try writer.print("        {s} = try runtime.php_lt({s}, {s});\n", .{ result_reg.?, lhs, rhs });
                    }
                }
            },
            .le => |op| {
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);
                try writer.print("        {s} = try runtime.php_le({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .gt => |op| {
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);
                try writer.print("        {s} = try runtime.php_gt({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .ge => |op| {
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);
                try writer.print("        {s} = try runtime.php_ge({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .identical => |op| {
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);
                try writer.print("        {s} = try runtime.php_identical({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .not_identical => |op| {
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);
                try writer.print("        {s} = try runtime.php_not_identical({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },

            // ========================================================================
            // 逻辑运算指令
            // ========================================================================
            .and_ => |op| {
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);
                try writer.print("        {s} = try runtime.php_and({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .or_ => |op| {
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);
                try writer.print("        {s} = try runtime.php_or({s}, {s});\n", .{ result_reg.?, lhs, rhs });
            },
            .not => |op| {
                const operand = try self.formatRegister(op.operand);
                defer self.allocator.free(operand);
                try writer.print("        {s} = try runtime.php_not({s});\n", .{ result_reg.?, operand });
            },

            // ========================================================================
            // 字符串运算指令
            // ========================================================================
            .concat => |op| {
                const lhs = try self.formatRegister(op.lhs);
                defer self.allocator.free(lhs);
                const rhs = try self.formatRegister(op.rhs);
                defer self.allocator.free(rhs);
                try writer.print("        {s} = try runtime.php_concat({s}, {s}, runtime.runtime_allocator);\n", .{ result_reg.?, lhs, rhs });
            },

            // ========================================================================
            // 函数调用指令
            // ========================================================================
            .call => |op| {
                // 格式化参数列表
                var args_list = std.ArrayList(u8){};
                defer args_list.deinit(self.allocator);
                const args_writer = args_list.writer(self.allocator);

                for (op.args, 0..) |arg, i| {
                    if (i > 0) try args_writer.writeAll(", ");
                    const arg_str = try self.formatRegister(arg);
                    defer self.allocator.free(arg_str);
                    try args_writer.writeAll(arg_str);
                }

                // 检查是否是内置函数（runtime函数）
                const is_builtin = self.isBuiltinFunction(op.func_name);

                // 生成函数调用
                if (result_reg) |r| {
                    if (is_builtin) {
                        const runtime_name = self.mapToRuntimeFunction(op.func_name);
                        try writer.print("        {s} = try runtime.{s}({s});\n", .{ r, runtime_name, args_list.items });
                    } else {
                        // 用户定义函数：使用@"函数名"语法
                        try writer.print("        {s} = try @\"{s}\"({s});\n", .{ r, op.func_name, args_list.items });
                    }
                } else {
                    if (is_builtin) {
                        const runtime_name = self.mapToRuntimeFunction(op.func_name);
                        try writer.print("        _ = try runtime.{s}({s});\n", .{ runtime_name, args_list.items });
                    } else {
                        // 用户定义函数：使用@"函数名"语法
                        try writer.print("        _ = try @\"{s}\"({s});\n", .{ op.func_name, args_list.items });
                    }
                }
            },

            // ========================================================================
            // 数组操作指令
            // ========================================================================
            .array_new => |op| {
                _ = op; // 暂时忽略容量
                try writer.print("        {s} = runtime.Value.initArray(try runtime.PHPArray.init(runtime.runtime_allocator));\n", .{result_reg.?});
            },
            .array_get => |op| {
                const array = try self.formatRegister(op.array);
                defer self.allocator.free(array);
                const key = try self.formatRegister(op.key);
                defer self.allocator.free(key);

                // 智能处理键的类型
                if (op.key.type_ == .i64) {
                    // 键是i64类型，直接使用
                    try writer.print("        {s} = {s}.asArray().get(runtime.ArrayKey{{ .integer = {s} }}) orelse runtime.Value.initNull();\n", .{ result_reg.?, array, key });
                } else if (op.key.type_ == .php_value) {
                    // 键是Value类型，需要转换
                    try writer.print("        {s} = {s}.asArray().get(runtime.ArrayKey{{ .integer = {s}.toInt() }}) orelse runtime.Value.initNull();\n", .{ result_reg.?, array, key });
                } else {
                    // 其他类型，默认转换为整数
                    try writer.print("        {s} = {s}.asArray().get(runtime.ArrayKey{{ .integer = @intCast({s}) }}) orelse runtime.Value.initNull();\n", .{ result_reg.?, array, key });
                }
            },
            .array_set => |op| {
                const array = try self.formatRegister(op.array);
                defer self.allocator.free(array);
                const key = try self.formatRegister(op.key);
                defer self.allocator.free(key);
                const value = try self.formatRegister(op.value);
                defer self.allocator.free(value);
                try writer.print("        try {s}.asArray().set(runtime.runtime_allocator, runtime.ArrayKey{{ .integer = {s}.toInt() }}, {s});\n", .{ array, key, value });
            },
            .array_push => |op| {
                const array = try self.formatRegister(op.array);
                defer self.allocator.free(array);
                const value = try self.formatRegister(op.value);
                defer self.allocator.free(value);

                // 智能处理值的类型
                if (op.value.type_ == .php_value) {
                    // 值已经是Value类型，直接使用
                    try writer.print("        try {s}.asArray().push(runtime.runtime_allocator, {s});\n", .{ array, value });
                } else if (op.value.type_ == .i64) {
                    // 值是i64类型，需要转换
                    try writer.print("        try {s}.asArray().push(runtime.runtime_allocator, runtime.Value.initInt({s}));\n", .{ array, value });
                } else if (op.value.type_ == .f64) {
                    // 值是f64类型，需要转换
                    try writer.print("        try {s}.asArray().push(runtime.runtime_allocator, runtime.Value.initFloat({s}));\n", .{ array, value });
                } else if (op.value.type_ == .bool) {
                    // 值是bool类型，需要转换
                    try writer.print("        try {s}.asArray().push(runtime.runtime_allocator, runtime.Value.initBool({s}));\n", .{ array, value });
                } else {
                    // 其他类型，默认直接使用
                    try writer.print("        try {s}.asArray().push(runtime.runtime_allocator, {s});\n", .{ array, value });
                }
            },
            .array_count => |op| {
                const array = try self.formatRegister(op.operand);
                defer self.allocator.free(array);
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
                const value = try self.formatRegister(op.value);
                defer self.allocator.free(value);
                // 根据目标类型生成不同的转换代码
                if (op.to_type == .php_value) {
                    // 从基本类型转换到php_value
                    if (op.from_type == .i64) {
                        try writer.print("        {s} = runtime.Value.initInt({s});\n", .{ result_reg.?, value });
                    } else if (op.from_type == .f64) {
                        try writer.print("        {s} = runtime.Value.initFloat({s});\n", .{ result_reg.?, value });
                    } else if (op.from_type == .bool) {
                        try writer.print("        {s} = runtime.Value.initBool({s});\n", .{ result_reg.?, value });
                    } else {
                        try writer.print("        {s} = {s}; // cast from {any} to {any}\n", .{ result_reg.?, value, op.from_type, op.to_type });
                    }
                } else if (op.to_type == .i64) {
                    // 转换到i64
                    try writer.print("        {s} = {s}.toInt();\n", .{ result_reg.?, value });
                } else if (op.to_type == .f64) {
                    // 转换到f64
                    try writer.print("        {s} = {s}.toFloat();\n", .{ result_reg.?, value });
                } else if (op.to_type == .bool) {
                    // 转换到bool
                    try writer.print("        {s} = {s}.toBool();\n", .{ result_reg.?, value });
                } else {
                    // 默认：直接赋值
                    try writer.print("        {s} = {s}; // cast\n", .{ result_reg.?, value });
                }
            },

            // ========================================================================
            // 异常处理指令
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
                // catch块的开始已经在BasicBlock处理中隐含了（通过switch状态机跳转）
                // 这里我们可能需要从runtime获取当前的exception
                // 注意：在NativeLinker中，我们实际上通过switch状态机来模拟控制流
                // 当发生异常时，throw指令会设置状态并break
                try writer.print("        // catch clause\n", .{});
            },
            .throw => |ex_reg| {
                const ex = try self.formatRegister(ex_reg);
                defer self.allocator.free(ex);
                // 设置异常并返回错误
                try writer.print("        // throw {s}\n", .{ex});
                try writer.print("        runtime.setException({s});\n", .{ex});
                
                if (self.current_exception_handler) |handler_idx| {
                    try writer.print("        current_block = {d};\n", .{handler_idx});
                    try writer.print("        continue;\n", .{});
                } else {
                    try writer.print("        return error.RuntimeError;\n", .{});
                }
            },
            .get_exception => {
                // 获取当前捕获的异常
                if (inst.result) |_| {
                    try writer.print("        {s} = runtime.getException();\n", .{result_reg.?});
                }
            },

            // ========================================================================
            // PHI指令（用于三元运算符等控制流合并）
            // ========================================================================
            .phi => |op| {
                // PHI指令的处理：
                // 在状态机模式中，每个前驱块在跳转到merge块之前会设置PHI结果
                // 这里我们只需要声明，实际的赋值在前驱块的跳转代码中完成
                // 但为了代码完整性，我们生成一个默认赋值
                if (op.incoming.len > 0) {
                    // 注释说明这是PHI节点
                    try writer.writeAll("        // PHI node: value set by predecessor blocks\n");
                }
            },

            // ========================================================================
            // 其他指令（暂时生成注释）
            // ========================================================================
            else => {
                try writer.print("        // TODO: {s}\n", .{@tagName(inst.op)});
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

    /// 格式化寄存器名称
    fn formatRegister(self: *Self, reg: IR.Register) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "reg_{d}", .{reg.id});
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
        
        // Debug: Write to local file for inspection
        const debug_path = "debug_aot.zig";
        const debug_file = try std.fs.cwd().createFile(debug_path, .{});
        try debug_file.writeAll(zig_code);
        debug_file.close();

        {
            const file = try std.fs.cwd().createFile(zig_file_path, .{});
            defer file.close();
            try file.writeAll(zig_code);
        }

        // 复制运行时库
        try self.copyRuntimeLib(temp_dir);

        // 调用 Zig 编译器
        try self.invokeZigCompiler(zig_file_path, output_path);

        if (self.config.verbose) {
            std.debug.print("  Compilation successful: {s}\n", .{output_path});
        }
    }

    /// 复制运行时库到临时目录
    fn copyRuntimeLib(self: *Self, temp_dir: []const u8) !void {
        // 复制runtime_lib_template.zig
        const template_path = "src/aot/runtime_lib_template.zig";
        const template_content = try std.fs.cwd().readFileAlloc(
            self.allocator,
            template_path,
            10 * 1024 * 1024,
        );
        defer self.allocator.free(template_content);

        const runtime_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ temp_dir, "runtime_lib.zig" },
        );
        defer self.allocator.free(runtime_path);

        const file = try std.fs.cwd().createFile(runtime_path, .{});
        defer file.close();
        try file.writeAll(template_content);

        // 复制concurrency_runtime.zig
        const concurrency_path = "src/aot/concurrency_runtime.zig";
        const concurrency_content = try std.fs.cwd().readFileAlloc(
            self.allocator,
            concurrency_path,
            10 * 1024 * 1024,
        );
        defer self.allocator.free(concurrency_content);

        const concurrency_dest = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ temp_dir, "concurrency_runtime.zig" },
        );
        defer self.allocator.free(concurrency_dest);

        const concurrency_file = try std.fs.cwd().createFile(concurrency_dest, .{});
        defer concurrency_file.close();
        try concurrency_file.writeAll(concurrency_content);

        if (self.config.verbose) {
            std.debug.print("  Copied runtime libraries to {s}\n", .{temp_dir});
        }
    }

    /// 调用 Zig 编译器
    fn invokeZigCompiler(self: *Self, source_path: []const u8, output_path: []const u8) !void {
        var args = std.ArrayList([]const u8){};
        defer args.deinit(self.allocator);

        // 基本命令
        try args.append(self.allocator, "zig");
        try args.append(self.allocator, "build-exe");
        try args.append(self.allocator, source_path);

        // 输出路径（使用 -femit-bin=path 格式）
        const output_arg = try std.fmt.allocPrint(
            self.allocator,
            "-femit-bin={s}",
            .{output_path},
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

        // 目标平台
        const target_str = try self.getTargetString();
        defer self.allocator.free(target_str);
        try args.append(self.allocator, "-target");
        try args.append(self.allocator, target_str);

        // 静态链接（macOS 不支持）
        if (self.config.static_link and self.config.target.os != .macos) {
            try args.append(self.allocator, "-static");
        }

        // 剥离符号
        if (self.config.strip_symbols) {
            try args.append(self.allocator, "-fstrip");
        }

        if (self.config.verbose) {
            std.debug.print("  Invoking Zig compiler: ", .{});
            for (args.items) |arg| {
                std.debug.print("{s} ", .{arg});
            }
            std.debug.print("\n", .{});
        }

        // 执行编译命令
        var child = std.process.Child.init(args.items, self.allocator);
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

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
