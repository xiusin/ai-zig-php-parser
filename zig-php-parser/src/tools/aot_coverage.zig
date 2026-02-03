const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ir_ops = try extractIrOps(allocator);
    const supported_ops = try extractSupportedOps(allocator);
    const interpreter_builtins = try extractInterpreterBuiltins(allocator);
    const aot_builtins = try extractAotBuiltins(allocator);

    try generateReport(allocator, ir_ops, supported_ops, interpreter_builtins, aot_builtins);
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 1024 * 1024 * 5);
}

fn extractIrOps(allocator: std.mem.Allocator) !std.StringHashMap(void) {
    var ops = std.StringHashMap(void).init(allocator);
    const content = try readFile(allocator, "src/aot/ir.zig");
    
    // Find Op union definition
    const start_marker = "pub const Op = union(enum) {";
    const start_idx = std.mem.indexOf(u8, content, start_marker) orelse return error.OpDefinitionNotFound;
    
    var iter = std.mem.tokenizeAny(u8, content[start_idx + start_marker.len ..], "\n");
    var brace_count: usize = 1;

    while (iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "//")) continue;

        if (std.mem.indexOf(u8, trimmed, "{") != null) brace_count += 1;
        if (std.mem.indexOf(u8, trimmed, "}") != null) {
            brace_count -= 1;
            if (brace_count == 0) break;
        }

        // Extract op name (e.g., "add: BinaryOp," -> "add")
        if (std.mem.indexOf(u8, trimmed, ":")) |colon_idx| {
            try ops.put(try allocator.dupe(u8, trimmed[0..colon_idx]), {});
        } else if (std.mem.endsWith(u8, trimmed, ",")) {
             try ops.put(try allocator.dupe(u8, trimmed[0..trimmed.len-1]), {});
        }
    }
    return ops;
}

fn extractSupportedOps(allocator: std.mem.Allocator) !std.StringHashMap(void) {
    var ops = std.StringHashMap(void).init(allocator);
    const content = try readFile(allocator, "src/aot/native_linker.zig");

    // Find generateInstructionSimple function
    const func_marker = "fn generateInstructionSimple";
    const func_idx = std.mem.indexOf(u8, content, func_marker) orelse return error.FuncNotFound;
    
    // Find switch statement inside
    const switch_marker = "switch (inst.op) {";
    const switch_idx = std.mem.indexOf(u8, content[func_idx..], switch_marker) orelse return error.SwitchNotFound;
    const real_switch_idx = func_idx + switch_idx;

    var iter = std.mem.tokenizeAny(u8, content[real_switch_idx + switch_marker.len ..], "\n");
    var brace_count: usize = 1;

    while (iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "//")) continue;

        if (std.mem.indexOf(u8, trimmed, "{") != null) brace_count += 1;
        if (std.mem.indexOf(u8, trimmed, "}") != null) {
            brace_count -= 1;
            if (brace_count == 0) break;
        }

        // Extract case (e.g., ".add => |op| {" -> "add")
        if (std.mem.startsWith(u8, trimmed, ".")) {
            if (std.mem.indexOf(u8, trimmed, "=>")) |arrow_idx| {
                const op_name = std.mem.trim(u8, trimmed[1..arrow_idx], " ");
                try ops.put(try allocator.dupe(u8, op_name), {});
            }
        }
    }
    return ops;
}

fn extractInterpreterBuiltins(allocator: std.mem.Allocator) !std.StringHashMap(void) {
    var builtins = std.StringHashMap(void).init(allocator);
    const content = try readFile(allocator, "src/runtime/builtin_dispatch.zig");

    const start_marker = "pub const BuiltinId = enum(u16) {";
    const start_idx = std.mem.indexOf(u8, content, start_marker) orelse return error.BuiltinEnumNotFound;

    var iter = std.mem.tokenizeAny(u8, content[start_idx + start_marker.len ..], "\n");
    
    while (iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "//")) continue;
        if (std.mem.startsWith(u8, trimmed, "}")) break;

        // Extract builtin name (e.g., "array_map = 0," -> "array_map")
        if (std.mem.indexOf(u8, trimmed, "=")) |eq_idx| {
            const name = std.mem.trim(u8, trimmed[0..eq_idx], " ");
            try builtins.put(try allocator.dupe(u8, name), {});
        }
    }
    return builtins;
}

fn extractAotBuiltins(allocator: std.mem.Allocator) !std.StringHashMap(void) {
    var builtins = std.StringHashMap(void).init(allocator);
    const content = try readFile(allocator, "src/aot/native_linker.zig");

    // Look for isBuiltinFunction and then the builtins array
    const marker = "const builtins = [_][]const u8{";
    const idx = std.mem.indexOf(u8, content, marker) orelse return error.AotBuiltinsNotFound;

    var iter = std.mem.tokenizeAny(u8, content[idx + marker.len ..], "\n");

    while (iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "//")) continue;
        if (std.mem.startsWith(u8, trimmed, "};")) break;

        // Extract strings like "strlen",
        var line_iter = std.mem.tokenizeAny(u8, trimmed, ",");
        while (line_iter.next()) |part| {
            const part_trimmed = std.mem.trim(u8, part, " \t\"");
            if (part_trimmed.len > 0) {
                try builtins.put(try allocator.dupe(u8, part_trimmed), {});
            }
        }
    }
    
    // Add builtins from runtime_lib_template.zig manually or by reading the file
    // For now, let's hardcode the ones we saw in lookupBuiltinFunction as a fallback
    // But better to read the file.
    const template_content = try readFile(allocator, "src/aot/runtime_lib_template.zig");
    const lookup_marker = "BuiltinFunctionEntry{";
    if (std.mem.indexOf(u8, template_content, lookup_marker)) |lookup_idx| {
        var t_iter = std.mem.tokenizeAny(u8, template_content[lookup_idx + lookup_marker.len ..], "\n");
         while (t_iter.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
             if (std.mem.startsWith(u8, trimmed, "};")) break;
             // .{ .name = "strlen", .func = wrapBuiltin_strlen },
             if (std.mem.indexOf(u8, trimmed, ".name = \"")) |name_start| {
                 const rest = trimmed[name_start + 9 ..];
                 if (std.mem.indexOf(u8, rest, "\"")) |quote_end| {
                     try builtins.put(try allocator.dupe(u8, rest[0..quote_end]), {});
                 }
             }
         }
    }

    return builtins;
}

fn generateReport(
    allocator: std.mem.Allocator,
    ir_ops: std.StringHashMap(void),
    supported_ops: std.StringHashMap(void),
    interpreter_builtins: std.StringHashMap(void),
    aot_builtins: std.StringHashMap(void),
) !void {
    // Buffer the output
    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);
    const writer = buffer.writer(allocator);

    try writer.print("# AOT Coverage Report\n\n", .{});
    try writer.print("Generated on: {s}\n\n", .{"2026-02-03"}); // Use actual date if possible

    // 1. IR Op Coverage
    try writer.print("## 1. IR Op Coverage\n\n", .{});
    try writer.print("| IR Op | Supported | Status |\n", .{});
    try writer.print("|---|---|---|\n", .{});

    var ir_keys = std.ArrayListUnmanaged([]const u8){};
    defer ir_keys.deinit(allocator);
    var ir_iter = ir_ops.keyIterator();
    while (ir_iter.next()) |key| {
        try ir_keys.append(allocator, key.*);
    }
    std.mem.sort([]const u8, ir_keys.items, {}, struct{
        fn less(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.less);

    var supported_count: usize = 0;
    for (ir_keys.items) |op| {
        const is_supported = supported_ops.contains(op);
        if (is_supported) supported_count += 1;
        try writer.print("| `{s}` | {s} | {s} |\n", .{
            op,
            if (is_supported) "✅" else "❌",
            if (is_supported) "Implemented" else "Missing",
        });
    }
    
    const ir_coverage = if (ir_keys.items.len > 0) @as(f64, @floatFromInt(supported_count)) / @as(f64, @floatFromInt(ir_keys.items.len)) * 100.0 else 0.0;
    try writer.print("\n**Coverage: {d:.2}% ({d}/{d})**\n\n", .{ir_coverage, supported_count, ir_keys.items.len});

    // 2. Builtin Coverage
    try writer.print("## 2. Builtin Coverage\n\n", .{});
    try writer.print("| Builtin Function | Supported | Status |\n", .{});
    try writer.print("|---|---|---|\n", .{});

    var builtin_keys = std.ArrayListUnmanaged([]const u8){};
    defer builtin_keys.deinit(allocator);
    var b_iter = interpreter_builtins.keyIterator();
    while (b_iter.next()) |key| {
        try builtin_keys.append(allocator, key.*);
    }
    std.mem.sort([]const u8, builtin_keys.items, {}, struct{
        fn less(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.less);

    var builtin_supported_count: usize = 0;
    for (builtin_keys.items) |name| {
        const is_supported = aot_builtins.contains(name);
        if (is_supported) builtin_supported_count += 1;
        try writer.print("| `{s}` | {s} | {s} |\n", .{
            name,
            if (is_supported) "✅" else "❌",
            if (is_supported) "Implemented" else "Missing",
        });
    }

    const builtin_coverage = if (builtin_keys.items.len > 0) @as(f64, @floatFromInt(builtin_supported_count)) / @as(f64, @floatFromInt(builtin_keys.items.len)) * 100.0 else 0.0;
    try writer.print("\n**Coverage: {d:.2}% ({d}/{d})**\n\n", .{builtin_coverage, builtin_supported_count, builtin_keys.items.len});

    // 3. Summary
    try writer.print("## 3. Action Items\n\n", .{});
    try writer.print("### Missing High Priority Builtins (P0)\n\n", .{});
    
    // Define P0 builtins manually for checking
    const p0_builtins = [_][]const u8{
        "echo", "print", "strlen", "count", "array_map", "array_filter", 
        "file_get_contents", "json_encode", "json_decode", "date", "time"
    };

    for (p0_builtins) |p0| {
        if (!aot_builtins.contains(p0) and interpreter_builtins.contains(p0)) {
            try writer.print("- [ ] Implement `{s}`\n", .{p0});
        }
    }

    // Write to file
    const file = try std.fs.cwd().createFile(".trae/documents/AOT_Coverage_Report.md", .{});
    defer file.close();
    try file.writeAll(buffer.items);
}
