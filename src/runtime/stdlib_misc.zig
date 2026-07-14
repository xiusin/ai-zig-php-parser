//! 杂项内置函数实现模块
//! 从 stdlib.zig 拆分而来 — 包含调试输出、HTTP、exit 函数

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const exceptions = @import("exceptions.zig");
const ExceptionFactory = exceptions.ExceptionFactory;
const VM = @import("vm.zig").VM;

// String functions implementations
// Debug functions
pub fn varDumpFn(_: *VM, args: []const Value) !Value {
    for (args) |arg| {
        dumpValueDebug(arg, 0);
        std.debug.print("\n", .{});
    }
    return Value.initNull();
}

pub fn dumpValueDebug(value: Value, indent: usize) void {
    const ind: [20]u8 = @splat(' ');
    switch (value.getTag()) {
        .null => std.debug.print("NULL", .{}),
        .boolean => std.debug.print("bool({s})", .{if (value.asBool()) "true" else "false"}),
        .integer => std.debug.print("int({d})", .{value.asInt()}),
        .float => std.debug.print("float({d})", .{value.asFloat()}),
        .string => std.debug.print("string({d}) \"{s}\"", .{ value.getAsString().data.length, value.getAsString().data.data }),
        .array => {
            const arr = value.getAsArray().data;
            std.debug.print("array({d}) {{\n", .{arr.count()});
            var iter = arr.getElements().iterator();
            while (iter.next()) |entry| {
                std.debug.print("{s}", .{ind[0..@min((indent + 1) * 2, ind.len)]});
                switch (entry.key_ptr.*) {
                    .integer => |i| std.debug.print("[{d}]=>\n", .{i}),
                    .string => |s| std.debug.print("[\"{s}\"]=>\n", .{s.data}),
                }
                std.debug.print("{s}", .{ind[0..@min((indent + 1) * 2, ind.len)]});
                dumpValueDebug(entry.value_ptr.*, indent + 1);
                std.debug.print("\n", .{});
            }
            std.debug.print("{s}}}", .{ind[0..@min(indent * 2, ind.len)]});
        },
        .object => std.debug.print("object({s})", .{value.getAsObject().data.class.name.data}),
        else => std.debug.print("unknown", .{}),
    }
}

pub fn printRFn(_: *VM, args: []const Value) !Value {
    printValueDebug(args[0], 0);
    return Value.initBool(true);
}

pub fn printValueDebug(value: Value, indent: usize) void {
    const ind: [40]u8 = @splat(' ');
    switch (value.getTag()) {
        .null => {},
        .boolean => std.debug.print("{s}", .{if (value.asBool()) "1" else ""}),
        .integer => std.debug.print("{d}", .{value.asInt()}),
        .float => std.debug.print("{d}", .{value.asFloat()}),
        .string => std.debug.print("{s}", .{value.getAsString().data.data}),
        .array => {
            std.debug.print("Array\n{s}(\n", .{ind[0..@min(indent * 4, ind.len)]});
            var iter = value.getAsArray().data.getElements().iterator();
            while (iter.next()) |entry| {
                std.debug.print("{s}", .{ind[0..@min((indent + 1) * 4, ind.len)]});
                switch (entry.key_ptr.*) {
                    .integer => |i| std.debug.print("[{d}] => ", .{i}),
                    .string => |s| std.debug.print("[{s}] => ", .{s.data}),
                }
                printValueDebug(entry.value_ptr.*, indent + 1);
                std.debug.print("\n", .{});
            }
            std.debug.print("{s})", .{ind[0..@min(indent * 4, ind.len)]});
        },
        else => {},
    }
}

pub fn varExportFn(vm: *VM, args: []const Value) !Value {
    if (args.len == 0) return Value.initNull();
    const return_output = args.len > 1 and args[1].toBool();
    if (return_output) {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(vm.allocator);
        exportValueToBuf(vm.allocator, args[0], &buf, 0) catch return Value.initNull();
        const str = buf.toOwnedSlice(vm.allocator) catch return Value.initNull();
        return Value.initString(vm.allocator, str) catch Value.initNull();
    } else {
        const stdout = std.posix.STDOUT_FILENO;
        exportValueToStdout(args[0], stdout, 0);
        return Value.initNull();
    }
}

fn writeStdout(fd: std.posix.fd_t, msg: []const u8) void {
    _ = std.posix.system.write(fd, msg.ptr, msg.len);
}

pub fn exportValueToStdout(value: Value, fd: std.posix.fd_t, indent: usize) void {
    const ind: [40]u8 = @splat(' ');
    switch (value.getTag()) {
        .null => writeStdout(fd, "NULL"),
        .boolean => writeStdout(fd, if (value.asBool()) "true" else "false"),
        .integer => {
            var buf: [32]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{d}", .{value.asInt()}) catch return;
            writeStdout(fd, slice);
        },
        .float => {
            const f = value.asFloat();
            var buf: [64]u8 = undefined;
            const slice = if (@floor(f) == f and !std.math.isInf(f) and !std.math.isNan(f))
                std.fmt.bufPrint(&buf, "{d:.1}", .{f}) catch return
            else
                std.fmt.bufPrint(&buf, "{d}", .{f}) catch return;
            writeStdout(fd, slice);
        },
        .string => {
            writeStdout(fd, "'");
            writeStdout(fd, value.getAsString().data.data);
            writeStdout(fd, "'");
        },
        .array => {
            writeStdout(fd, "array (\n");
            var iter = value.getAsArray().data.getElements().iterator();
            while (iter.next()) |entry| {
                writeStdout(fd, ind[0..@min((indent + 1) * 2, ind.len)]);
                switch (entry.key_ptr.*) {
                    .integer => |i| {
                        var buf: [32]u8 = undefined;
                        const slice = std.fmt.bufPrint(&buf, "{d} => ", .{i}) catch return;
                        writeStdout(fd, slice);
                    },
                    .string => |s| {
                        writeStdout(fd, "'");
                        writeStdout(fd, s.data);
                        writeStdout(fd, "' => ");
                    },
                }
                exportValueToStdout(entry.value_ptr.*, fd, indent + 1);
                writeStdout(fd, ",\n");
            }
            writeStdout(fd, ind[0..@min(indent * 2, ind.len)]);
            writeStdout(fd, ")");
        },
        .object => {
            const obj = value.getAsObject().data;
            var buf: [128]u8 = undefined;
            const header = std.fmt.bufPrint(&buf, "{s}::__set_state(array(\n", .{obj.class.name.data}) catch return;
            writeStdout(fd, header);
            var prop_iter = obj.shape.property_map.iterator();
            while (prop_iter.next()) |entry| {
                writeStdout(fd, ind[0..@min((indent + 2) * 2, ind.len)]);
                writeStdout(fd, "'");
                writeStdout(fd, entry.key_ptr.*);
                writeStdout(fd, "' => ");
                exportValueToStdout(obj.property_values.items[entry.value_ptr.*], fd, indent + 2);
                writeStdout(fd, ",\n");
            }
            writeStdout(fd, ind[0..@min((indent + 1) * 2, ind.len)]);
            writeStdout(fd, "))");
        },
        else => writeStdout(fd, "NULL"),
    }
}

pub fn exportValueToBuf(allocator: std.mem.Allocator, value: Value, buf: *std.ArrayList(u8), indent: usize) !void {
    const ind: [40]u8 = @splat(' ');
    switch (value.getTag()) {
        .null => try buf.appendSlice(allocator, "NULL"),
        .boolean => try buf.appendSlice(allocator, if (value.asBool()) "true" else "false"),
        .integer => {
            var tmp: [32]u8 = undefined;
            const slice = std.fmt.bufPrint(&tmp, "{d}", .{value.asInt()}) catch return;
            try buf.appendSlice(allocator, slice);
        },
        .float => {
            const f = value.asFloat();
            var tmp: [64]u8 = undefined;
            const slice = if (@floor(f) == f and !std.math.isInf(f) and !std.math.isNan(f))
                std.fmt.bufPrint(&tmp, "{d:.1}", .{f}) catch return
            else
                std.fmt.bufPrint(&tmp, "{d}", .{f}) catch return;
            try buf.appendSlice(allocator, slice);
        },
        .string => {
            try buf.append(allocator, '\'');
            try buf.appendSlice(allocator, value.getAsString().data.data);
            try buf.append(allocator, '\'');
        },
        .array => {
            try buf.appendSlice(allocator, "array (\n");
            var iter = value.getAsArray().data.getElements().iterator();
            while (iter.next()) |entry| {
                try buf.appendSlice(allocator, ind[0..@min((indent + 1) * 2, ind.len)]);
                switch (entry.key_ptr.*) {
                    .integer => |i| {
                        var tmp: [32]u8 = undefined;
                        const slice = std.fmt.bufPrint(&tmp, "{d} => ", .{i}) catch return;
                        try buf.appendSlice(allocator, slice);
                    },
                    .string => |s| {
                        try buf.append(allocator, '\'');
                        try buf.appendSlice(allocator, s.data);
                        try buf.appendSlice(allocator, "' => ");
                    },
                }
                try exportValueToBuf(allocator, entry.value_ptr.*, buf, indent + 1);
                try buf.appendSlice(allocator, ",\n");
            }
            try buf.appendSlice(allocator, ind[0..@min(indent * 2, ind.len)]);
            try buf.appendSlice(allocator, ")");
        },
        else => try buf.appendSlice(allocator, "NULL"),
    }
}

pub fn headerFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    // In a real implementation, this would set HTTP headers
    // For now, we just ignore it (common in CLI mode)
    _ = args;
    return Value.initNull();
}

pub fn httpResponseCodeFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    if (args.len > 0) {
        // Set response code - ignore in CLI mode
        return args[0];
    }
    return Value.initInt(200); // Default response code
}

pub fn exitFn(vm: *VM, args: []const Value) !Value {
    _ = vm;
    if (args.len > 0) {
        const arg = args[0];
        if (arg.getTag() == .string) {
            arg.print();
        }
    }
    return error.Exit;
}

// ============================================================================
// 单元测试
// ============================================================================

test "stdlib_misc: handler functions exist" {
    _ = &varDumpFn;
    _ = &printRFn;
    _ = &varExportFn;
    _ = &headerFn;
    _ = &httpResponseCodeFn;
    _ = &exitFn;
}

test "stdlib_misc: dumpValueDebug function exists" {
    _ = &dumpValueDebug;
}

test "stdlib_misc: printValueDebug function exists" {
    _ = &printValueDebug;
}

test "stdlib_misc: exportValueToStdout function exists" {
    _ = &exportValueToStdout;
}

pub fn mbStrlenFn(vm: *VM, args: []const Value) anyerror!Value {
    _ = vm;
    if (args.len == 0) return Value.initInt(0);
    const data = args[0].getAsString().data.data;
    var count: usize = 0;
    for (data) |byte| {
        if ((byte & 0xC0) != 0x80) count += 1;
    }
    return Value.initInt(@intCast(count));
}

pub fn mbSubstrFn(vm: *VM, args: []const Value) anyerror!Value {
    if (args.len < 2) return Value.initNull();
    const data = args[0].getAsString().data.data;
    const total_chars = blk: {
        var c: usize = 0;
        for (data) |byte| {
            if ((byte & 0xC0) != 0x80) c += 1;
        }
        break :blk c;
    };
    var start: i64 = args[1].asInt();
    if (start < 0) start = @max(@as(i64, @intCast(total_chars)) + start, 0);
    if (start >= @as(i64, @intCast(total_chars))) return Value.initString(vm.allocator, "") catch Value.initNull();
    var length: ?i64 = null;
    if (args.len >= 3 and !args[2].isNull()) {
        length = args[2].asInt();
    }
    var byte_start: usize = 0;
    var chars: usize = 0;
    for (data, 0..) |byte, idx| {
        if ((byte & 0xC0) != 0x80) {
            if (chars == @as(usize, @intCast(start))) {
                byte_start = idx;
                break;
            }
            chars += 1;
        }
    }
    var byte_end: usize = data.len;
    if (length) |len| {
        if (len < 0) {
            const end_char: i64 = @as(i64, @intCast(total_chars)) + len;
            if (end_char <= start) return Value.initString(vm.allocator, "") catch Value.initNull();
            var ec: usize = 0;
            chars = 0;
            for (data, 0..) |byte, idx| {
                if ((byte & 0xC0) != 0x80) {
                    if (chars == @as(usize, @intCast(end_char))) {
                        ec = idx;
                        break;
                    }
                    chars += 1;
                }
            }
            byte_end = ec;
        } else {
            const end_char: usize = @as(usize, @intCast(start)) + @as(usize, @intCast(len));
            var ec: usize = data.len;
            chars = 0;
            for (data, 0..) |byte, idx| {
                if ((byte & 0xC0) != 0x80) {
                    if (chars == @min(end_char, total_chars)) {
                        ec = idx;
                        break;
                    }
                    chars += 1;
                }
            }
            byte_end = ec;
        }
    }
    if (byte_end <= byte_start) return Value.initString(vm.allocator, "") catch Value.initNull();
    return Value.initString(vm.allocator, data[byte_start..byte_end]) catch Value.initNull();
}

pub fn mbStrtolowerFn(vm: *VM, args: []const Value) anyerror!Value {
    if (args.len == 0) return Value.initNull();
    const data = args[0].getAsString().data.data;
    var buf = std.ArrayList(u8).initCapacity(vm.allocator, data.len) catch return Value.initNull();
    defer buf.deinit(vm.allocator);
    for (data) |byte| {
        if (byte >= 'A' and byte <= 'Z') {
            buf.append(vm.allocator, byte + 32) catch return Value.initNull();
        } else {
            buf.append(vm.allocator, byte) catch return Value.initNull();
        }
    }
    return Value.initString(vm.allocator, buf.items) catch Value.initNull();
}

pub fn mbStrtoupperFn(vm: *VM, args: []const Value) anyerror!Value {
    if (args.len == 0) return Value.initNull();
    const data = args[0].getAsString().data.data;
    var buf = std.ArrayList(u8).initCapacity(vm.allocator, data.len) catch return Value.initNull();
    defer buf.deinit(vm.allocator);
    for (data) |byte| {
        if (byte >= 'a' and byte <= 'z') {
            buf.append(vm.allocator, byte - 32) catch return Value.initNull();
        } else {
            buf.append(vm.allocator, byte) catch return Value.initNull();
        }
    }
    return Value.initString(vm.allocator, buf.items) catch Value.initNull();
}

pub fn mbDetectEncodingFn(vm: *VM, args: []const Value) anyerror!Value {
    _ = args;
    return Value.initString(vm.allocator, "UTF-8") catch Value.initNull();
}
