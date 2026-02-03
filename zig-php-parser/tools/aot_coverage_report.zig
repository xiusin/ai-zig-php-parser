const std = @import("std");

fn parseEnumMembers(allocator: std.mem.Allocator, source: []const u8, enum_header: []const u8) !std.StringHashMapUnmanaged(void) {
    var out: std.StringHashMapUnmanaged(void) = .{};
    errdefer out.deinit(allocator);

    const start = std.mem.indexOf(u8, source, enum_header) orelse return out;
    const brace_start = std.mem.indexOfPos(u8, source, start, "{") orelse return out;

    var depth: usize = 0;
    var i: usize = brace_start;
    var line_start: usize = brace_start;
    while (i < source.len) : (i += 1) {
        const c = source[i];
        if (c == '{') depth += 1;
        if (c == '}') {
            if (depth == 0) break;
            depth -= 1;
            if (depth == 0) break;
        }
        if (c == '\n') {
            const line = std.mem.trim(u8, source[line_start..i], " \t\r");
            line_start = i + 1;
            if (line.len == 0) continue;
            if (std.mem.startsWith(u8, line, "//")) continue;
            if (std.mem.startsWith(u8, line, "pub")) continue;
            if (std.mem.startsWith(u8, line, "const")) continue;
            if (std.mem.startsWith(u8, line, "};")) continue;
            if (std.mem.indexOfScalar(u8, line, '=') == null) continue;
            const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const lhs = std.mem.trim(u8, line[0..eq_idx], " \t,");
            if (lhs.len == 0) continue;
            const comma_idx = std.mem.indexOfScalar(u8, lhs, ',') orelse lhs.len;
            const name = std.mem.trim(u8, lhs[0..comma_idx], " \t");
            if (name.len == 0) continue;
            try out.put(allocator, try allocator.dupe(u8, name), {});
        }
    }
    return out;
}

fn parseIrOpMembers(allocator: std.mem.Allocator, source: []const u8) !std.StringHashMapUnmanaged(void) {
    var out: std.StringHashMapUnmanaged(void) = .{};
    errdefer out.deinit(allocator);

    const header = "pub const Op = union(enum)";
    const start = std.mem.indexOf(u8, source, header) orelse return out;
    const brace_start = std.mem.indexOfPos(u8, source, start, "{") orelse return out;

    var depth: usize = 0;
    var i: usize = brace_start;
    var line_start: usize = brace_start;
    while (i < source.len) : (i += 1) {
        const c = source[i];
        if (c == '{') depth += 1;
        if (c == '}') {
            if (depth == 0) break;
            depth -= 1;
            if (depth == 0) break;
        }
        if (c == '\n') {
            const line = std.mem.trim(u8, source[line_start..i], " \t\r");
            line_start = i + 1;
            if (line.len == 0) continue;
            if (std.mem.startsWith(u8, line, "//")) continue;
            if (std.mem.startsWith(u8, line, "pub")) continue;
            if (std.mem.startsWith(u8, line, "const")) continue;
            const colon_idx = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const lhs = std.mem.trim(u8, line[0..colon_idx], " \t,");
            if (lhs.len == 0) continue;
            if (!std.ascii.isAlphabetic(lhs[0]) and lhs[0] != '_') continue;
            var ok = true;
            for (lhs) |ch| {
                if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '@' or ch == '"')) {
                    ok = false;
                    break;
                }
            }
            if (!ok) continue;
            try out.put(allocator, try allocator.dupe(u8, lhs), {});
        }
    }
    return out;
}

fn parseNativeLinkerHandledOps(allocator: std.mem.Allocator, source: []const u8) !std.StringHashMapUnmanaged(void) {
    var out: std.StringHashMapUnmanaged(void) = .{};
    errdefer out.deinit(allocator);

    const header = "switch (inst.op)";
    var search_pos: usize = 0;
    while (true) {
        const start = std.mem.indexOfPos(u8, source, search_pos, header) orelse break;
        search_pos = start + header.len;
        const brace_start = std.mem.indexOfPos(u8, source, start, "{") orelse continue;

        var depth: usize = 0;
        var i: usize = brace_start;
        var line_start: usize = brace_start;
        while (i < source.len) : (i += 1) {
            const c = source[i];
            if (c == '{') depth += 1;
            if (c == '}') {
                if (depth == 0) break;
                depth -= 1;
                if (depth == 0) break;
            }
            if (c == '\n') {
                const raw_line = source[line_start..i];
                line_start = i + 1;
                const line = std.mem.trim(u8, raw_line, " \t\r");
                if (line.len == 0) continue;
                if (!std.mem.startsWith(u8, line, ".")) continue;
                if (std.mem.indexOf(u8, line, "=>") == null) continue;
                var name_end: usize = 1;
                while (name_end < line.len) : (name_end += 1) {
                    const ch = line[name_end];
                    if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '@' or ch == '"')) break;
                }
                if (name_end <= 1) continue;
                const name = line[1..name_end];
                if (!out.contains(name)) {
                    try out.put(allocator, try allocator.dupe(u8, name), {});
                }
            }
        }
    }
    return out;
}

fn parseStringLiteralsInArray(allocator: std.mem.Allocator, source: []const u8, anchor: []const u8) !std.StringHashMapUnmanaged(void) {
    var out: std.StringHashMapUnmanaged(void) = .{};
    errdefer out.deinit(allocator);

    const start = std.mem.indexOf(u8, source, anchor) orelse return out;
    const brace_start = std.mem.indexOfPos(u8, source, start, "{") orelse return out;

    var depth: usize = 0;
    var i: usize = brace_start;
    while (i < source.len) : (i += 1) {
        const c = source[i];
        if (c == '{') depth += 1;
        if (c == '}') {
            if (depth == 0) break;
            depth -= 1;
            if (depth == 0) break;
        }
        if (c == '"') {
            const j = std.mem.indexOfScalarPos(u8, source, i + 1, '"') orelse continue;
            const lit = source[i + 1 .. j];
            if (lit.len > 0) {
                try out.put(allocator, try allocator.dupe(u8, lit), {});
            }
            i = j;
        }
    }

    return out;
}

fn parseTemplateCallableBuiltins(allocator: std.mem.Allocator, source: []const u8) !std.StringHashMapUnmanaged(void) {
    var out: std.StringHashMapUnmanaged(void) = .{};
    errdefer out.deinit(allocator);

    const header = "fn lookupBuiltinFunction";
    const start = std.mem.indexOf(u8, source, header) orelse return out;
    const brace_start = std.mem.indexOfPos(u8, source, start, "{") orelse return out;

    var depth: usize = 0;
    var i: usize = brace_start;
    while (i < source.len) : (i += 1) {
        const c = source[i];
        if (c == '{') depth += 1;
        if (c == '}') {
            if (depth == 0) break;
            depth -= 1;
            if (depth == 0) break;
        }
        if (std.mem.startsWith(u8, source[i..], ".name = \"")) {
            const lit_start = i + ".name = \"".len;
            const lit_end = std.mem.indexOfScalarPos(u8, source, lit_start, '"') orelse continue;
            const name = source[lit_start..lit_end];
            if (!out.contains(name)) {
                try out.put(allocator, try allocator.dupe(u8, name), {});
            }
            i = lit_end;
        }
    }

    return out;
}

fn dumpSortedList(allocator: std.mem.Allocator, writer: anytype, title: []const u8, set: *const std.StringHashMapUnmanaged(void)) !void {
    var names = try allocator.alloc([]const u8, set.count());
    defer allocator.free(names);

    var it = set.iterator();
    var idx: usize = 0;
    while (it.next()) |e| : (idx += 1) {
        names[idx] = e.key_ptr.*;
    }
    std.mem.sort([]const u8, names, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    try writer.print("### {s}\n\n", .{title});
    for (names) |n| {
        try writer.print("- {s}\n", .{n});
    }
    try writer.writeAll("\n");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cwd = std.fs.cwd();

    const ir_text = try cwd.readFileAlloc(allocator, "src/aot/ir.zig", 2 * 1024 * 1024);
    defer allocator.free(ir_text);
    const native_linker_text = try cwd.readFileAlloc(allocator, "src/aot/native_linker.zig", 4 * 1024 * 1024);
    defer allocator.free(native_linker_text);
    const builtin_dispatch_text = try cwd.readFileAlloc(allocator, "src/runtime/builtin_dispatch.zig", 4 * 1024 * 1024);
    defer allocator.free(builtin_dispatch_text);
    const runtime_template_text = try cwd.readFileAlloc(allocator, "src/aot/runtime_lib_template.zig", 4 * 1024 * 1024);
    defer allocator.free(runtime_template_text);

    var ir_ops = try parseIrOpMembers(allocator, ir_text);
    defer {
        var it = ir_ops.iterator();
        while (it.next()) |e| allocator.free(e.key_ptr.*);
        ir_ops.deinit(allocator);
    }

    var handled_ops = try parseNativeLinkerHandledOps(allocator, native_linker_text);
    defer {
        var it = handled_ops.iterator();
        while (it.next()) |e| allocator.free(e.key_ptr.*);
        handled_ops.deinit(allocator);
    }

    var interp_builtins = try parseEnumMembers(allocator, builtin_dispatch_text, "pub const BuiltinId = enum");
    defer {
        var it = interp_builtins.iterator();
        while (it.next()) |e| allocator.free(e.key_ptr.*);
        interp_builtins.deinit(allocator);
    }

    var aot_builtin_names = try parseStringLiteralsInArray(allocator, native_linker_text, "const builtins = [_][]const u8{");
    defer {
        var it = aot_builtin_names.iterator();
        while (it.next()) |e| allocator.free(e.key_ptr.*);
        aot_builtin_names.deinit(allocator);
    }

    var aot_callable_builtins = try parseTemplateCallableBuiltins(allocator, runtime_template_text);
    defer {
        var it = aot_callable_builtins.iterator();
        while (it.next()) |e| allocator.free(e.key_ptr.*);
        aot_callable_builtins.deinit(allocator);
    }

    var missing_ops: std.StringHashMapUnmanaged(void) = .{};
    defer missing_ops.deinit(allocator);
    {
        var it = ir_ops.iterator();
        while (it.next()) |e| {
            const name = e.key_ptr.*;
            if (handled_ops.contains(name)) continue;
            try missing_ops.put(allocator, name, {});
        }
    }

    var missing_builtins: std.StringHashMapUnmanaged(void) = .{};
    defer missing_builtins.deinit(allocator);
    {
        var it = interp_builtins.iterator();
        while (it.next()) |e| {
            const name = e.key_ptr.*;
            if (aot_builtin_names.contains(name)) continue;
            try missing_builtins.put(allocator, name, {});
        }
    }

    try std.fs.cwd().makePath("docs");
    var list = std.ArrayList(u8){};
    defer list.deinit(allocator);

    const w = list.writer(allocator);

    try w.writeAll("# AOT 与解释器覆盖矩阵（自动生成）\n\n");
    try w.print("- IR op 总数：{d}\n", .{ir_ops.count()});
    try w.print("- native_linker 处理到的 op（静态抽取）：{d}\n", .{handled_ops.count()});
    try w.print("- native_linker 缺失 op（静态抽取）：{d}\n", .{missing_ops.count()});
    try w.print("- 解释器 builtin（BuiltinId）数量：{d}\n", .{interp_builtins.count()});
    try w.print("- AOT builtin 白名单数量（isBuiltinFunction 数组）：{d}\n", .{aot_builtin_names.count()});
    try w.print("- AOT callable 白名单数量（runtime_lib_template lookup）：{d}\n\n", .{aot_callable_builtins.count()});

    try w.writeAll("## IR op 差异\n\n");
    try dumpSortedList(allocator, w, "AOT 缺失的 IR op（相对 IR 定义）", &missing_ops);

    try w.writeAll("## builtin 差异\n\n");
    try dumpSortedList(allocator, w, "解释器 builtin 中 AOT 白名单缺失项", &missing_builtins);
    try dumpSortedList(allocator, w, "AOT runtime callable 白名单", &aot_callable_builtins);

    {
        const out_file = try std.fs.cwd().createFile("docs/aot_coverage_report.md", .{ .truncate = true });
        defer out_file.close();
        try out_file.writeAll(list.items);
    }
}
