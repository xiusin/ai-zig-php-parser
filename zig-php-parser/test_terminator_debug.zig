const std = @import("std");
const Compiler = @import("src/compiler/mod.zig");
const AOT = @import("src/aot/root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 读取测试文件
    const source = try std.fs.cwd().readFileAlloc(allocator, "test_simple_var.php", 1024 * 1024);
    defer allocator.free(source);

    std.debug.print("=== 开始编译测试 ===\n", .{});
    std.debug.print("源代码:\n{s}\n", .{source});
    std.debug.print("===================\n\n", .{});

    // 创建诊断引擎
    var diagnostics = AOT.Diagnostics.DiagnosticEngine.init(allocator);
    defer diagnostics.deinit();

    // 创建解析器
    var parser = try Compiler.Parser.init(allocator, source, "test_simple_var.php");
    defer parser.deinit();

    // 解析AST
    const ast = try parser.parse();
    std.debug.print("AST解析完成，节点数: {d}\n", .{ast.nodes.len});

    // 创建符号表
    var symbol_table = AOT.SymbolTable.init(allocator);
    defer symbol_table.deinit();

    // 创建类型推断器
    var type_inferencer = try AOT.TypeInferencer.init(allocator, &symbol_table, &diagnostics);
    defer type_inferencer.deinit();

    // 执行类型推断
    try type_inferencer.inferTypes(ast.nodes, ast.string_table);
    std.debug.print("类型推断完成\n", .{});

    // 创建IR生成器
    var ir_generator = AOT.IRGenerator.init(allocator, &symbol_table, &type_inferencer, &diagnostics);
    defer ir_generator.deinit();

    // 生成IR
    std.debug.print("\n=== 开始生成IR ===\n", .{});
    const ir_module = try ir_generator.generate(ast.nodes, ast.string_table, "test_simple_var", "test_simple_var.php");
    defer {
        ir_module.deinit();
        allocator.destroy(ir_module);
    }

    std.debug.print("IR生成完成\n", .{});
    std.debug.print("函数数量: {d}\n", .{ir_module.functions.items.len});

    // 打印每个函数的基本块信息
    for (ir_module.functions.items, 0..) |func, func_idx| {
        std.debug.print("\n函数 {d}: {s}\n", .{ func_idx, func.name });
        std.debug.print("  基本块数量: {d}\n", .{func.blocks.items.len});
        
        for (func.blocks.items, 0..) |block, block_idx| {
            std.debug.print("  块 {d}: {s}\n", .{ block_idx, block.label });
            std.debug.print("    指令数: {d}\n", .{block.instructions.items.len});
            std.debug.print("    terminator: {any}\n", .{block.terminator});
            
            // 检查terminator是否有效
            if (block.terminator) |term| {
                const tag_name = @tagName(term);
                std.debug.print("    terminator tag: {s}\n", .{tag_name});
            } else {
                std.debug.print("    WARNING: 块没有terminator!\n", .{});
            }
        }
    }

    // 创建原生链接器配置
    const linker_config = AOT.NativeLinkerConfig{
        .target = .{
            .arch = .x86_64,
            .os = .macos,
            .abi = .none,
        },
        .optimize_level = .debug,
        .verbose = true,
    };

    // 创建原生链接器
    var native_linker = try AOT.NativeLinker.init(allocator, linker_config, &diagnostics);
    defer native_linker.deinit();

    std.debug.print("\n=== 开始生成Zig代码 ===\n", .{});
    
    // 生成Zig代码（这里会触发错误）
    const zig_code = try native_linker.generateZigCode(ir_module);
    defer allocator.free(zig_code);

    std.debug.print("Zig代码生成完成\n", .{});
    std.debug.print("生成的代码:\n{s}\n", .{zig_code});
}
