const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const runtime = @import("runtime_lib.zig");

// ============================================================================
// 文件I/O函数
// ============================================================================

pub fn php_file_put_contents(filename: Value, data: Value, allocator: Allocator) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;

    const content_str = if (data.isString())
        data.asString().data
    else blk: {
        const temp = try data.toString(allocator);
        defer temp.release(allocator);
        break :blk temp.data;
    };

    const file = std.Io.Dir.cwd().createFile(getIo(), fname, .{}) catch return Value.initBool(false);
    defer file.close(getIo());
    fileWriteAll(file.handle, content_str);
    return Value.initInt(@intCast(content_str.len));
}

pub fn php_file_get_contents(filename: Value, allocator: Allocator) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;

    const content = std.Io.Dir.cwd().readFileAlloc(getIo(), fname, allocator, 10 * 1024 * 1024) catch return Value.initBool(false);
    const output = try PHPString.init(allocator, content);
    return Value.initString(output);
}

pub fn php_fopen(filename: Value, mode: Value, allocator: Allocator) !Value {
    if (!filename.isString() or !mode.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    const fmode = mode.asString().data;

    // 特殊处理php://流
    if (std.mem.startsWith(u8, fname, "php://")) {
        return Value.initInt(1);
    }

    const file = if (std.mem.eql(u8, fmode, "r"))
        std.Io.Dir.cwd().openFile(getIo(), fname, .{}) catch return Value.initBool(false)
    else if (std.mem.eql(u8, fmode, "w"))
        std.Io.Dir.cwd().createFile(getIo(), fname, .{}) catch return Value.initBool(false)
    else if (std.mem.eql(u8, fmode, "a"))
        std.Io.Dir.cwd().createFile(getIo(), fname, .{ .truncate = false }) catch return Value.initBool(false)
    else
        return Value.initBool(false);

    const handle = allocator.create(std.Io.File) catch return Value.initBool(false);
    handle.* = file;
    return Value.initInt(@intCast(@intFromPtr(handle)));
}

pub fn php_fwrite(handle: Value, data: Value, allocator: Allocator) !Value {
    if (!handle.isInt()) return Value.initBool(false);
    const handle_ptr = handle.asInt();
    if (handle_ptr <= 1) return Value.initInt(0); // 虚拟句柄

    const file_handle: *std.Io.File = @ptrFromInt(@as(usize, @intCast(handle_ptr)));
    const content = if (data.isString()) data.asString().data else blk: {
        const temp = try data.toString(allocator);
        defer temp.release(allocator);
        break :blk temp.data;
    };

    fileWriteAll(file_handle.handle, content);
    return Value.initInt(@intCast(content.len));
}

pub fn php_fread(handle: Value, length: Value, allocator: Allocator) !Value {
    if (!handle.isInt() or !length.isInt()) return Value.initBool(false);
    const handle_ptr = handle.asInt();
    if (handle_ptr <= 1) return Value.initString(try PHPString.init(allocator, try allocator.dupe(u8, ""))); // 虚拟句柄

    const file_handle: *std.Io.File = @ptrFromInt(@as(usize, @intCast(handle_ptr)));
    const len = length.asInt();

    const buffer = allocator.alloc(u8, @intCast(len)) catch return Value.initBool(false);
    const bytes_read = file_handle.read(buffer) catch {
        allocator.free(buffer);
        return Value.initBool(false);
    };

    const content = allocator.realloc(buffer, bytes_read) catch {
        allocator.free(buffer);
        return Value.initBool(false);
    };
    const output = try PHPString.init(allocator, content);
    return Value.initString(output);
}

pub fn php_fclose(handle: Value) !Value {
    if (!handle.isInt()) return Value.initBool(false);
    const handle_ptr = handle.asInt();
    if (handle_ptr <= 1) return Value.initBool(true); // 虚拟句柄

    const file_handle: *std.Io.File = @ptrFromInt(@as(usize, @intCast(handle_ptr)));
    file_handle.close(getIo());
    return Value.initBool(true);
}

pub fn php_is_resource(val: Value) !Value {
    if (val.isInt()) {
        const i = val.asInt();
        return Value.initBool(i > 0);
    }
    return Value.initBool(false);
}

pub fn php_fgets(handle: Value) !Value {
    if (!handle.isInt()) return Value.initBool(false);
    const handle_ptr = handle.asInt();
    if (handle_ptr <= 1) return Value.initBool(false);

    const file_handle: *std.Io.File = @ptrFromInt(@as(usize, @intCast(handle_ptr)));
    var buf: [4096]u8 = undefined;
    var pos: usize = 0;

    while (pos < buf.len) {
        const n = file_handle.read(buf[pos .. pos + 1]) catch break;
        if (n == 0) break;
        pos += 1;
        if (buf[pos - 1] == '\n') break;
    }

    if (pos == 0) return Value.initBool(false);

    // 需要allocator但函数签名没有，使用全局allocator
    const global_alloc = std.heap.page_allocator;
    const output = try PHPString.init(global_alloc, try global_alloc.dupe(u8, buf[0..pos]));
    return Value.initString(output);
}

pub fn php_fseek(handle: Value, offset: Value) !Value {
    if (!handle.isInt() or !offset.isInt()) return Value.initInt(-1);
    const handle_ptr = handle.asInt();
    if (handle_ptr <= 1) return Value.initInt(-1);

    const file_handle: *std.Io.File = @ptrFromInt(@as(usize, @intCast(handle_ptr)));
    const off = offset.asInt();
    file_handle.seekTo(@intCast(off)) catch return Value.initInt(-1);
    return Value.initInt(0);
}

pub fn php_scandir(dir: Value, allocator: Allocator) !Value {
    if (!dir.isString()) return Value.initBool(false);
    const dirname = dir.asString().data;

    var dir_handle = std.Io.Dir.cwd().openDir(getIo(), dirname, .{ .iterate = true }) catch return Value.initBool(false);
    defer dir_handle.close(getIo());

    var arr = try PHPArray.init(allocator);
    var iter = dir_handle.iterate();
    while (iter.next() catch null) |entry| {
        const name = try allocator.dupe(u8, entry.name);
        const str = try PHPString.init(allocator, name);
        try arr.push(allocator, Value.initString(str));
    }
    return Value.initArray(arr);
}

// ============================================================================
// 系统信息函数
// ============================================================================

pub fn php_getcwd(allocator: Allocator) !Value {
    const cwd = std.Io.Dir.cwd().realpathAlloc(allocator, ".") catch return Value.initBool(false);
    const output = try PHPString.init(allocator, cwd);
    return Value.initString(output);
}

pub fn php_sapi_name(allocator: Allocator) !Value {
    const output = try PHPString.init(allocator, try allocator.dupe(u8, "cli"));
    return Value.initString(output);
}

pub fn php_uname(allocator: Allocator) !Value {
    const uname_info = if (builtin.os.tag == .macos)
        "Darwin"
    else if (builtin.os.tag == .linux)
        "Linux"
    else if (builtin.os.tag == .windows)
        "Windows"
    else
        "Unknown";

    const output = try PHPString.init(allocator, try allocator.dupe(u8, uname_info));
    return Value.initString(output);
}

pub fn php_unlink(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    std.Io.Dir.cwd().deleteFile(fname) catch return Value.initBool(false);
    return Value.initBool(true);
}

pub fn php_filesize(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    const file = std.Io.Dir.cwd().openFile(getIo(), fname, .{}) catch return Value.initBool(false);
    defer file.close(getIo());
    const stat = file.stat(getIo()) catch return Value.initBool(false);
    return Value.initInt(@intCast(stat.size));
}

pub fn php_is_file(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    const stat = std.Io.Dir.cwd().statFile(getIo(), fname, .{}) catch return Value.initBool(false);
    return Value.initBool(stat.kind == .file);
}

pub fn php_is_dir(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    var dir = std.Io.Dir.cwd().openDir(getIo(), fname, .{}) catch return Value.initBool(false);
    dir.close(getIo());
    return Value.initBool(true);
}

pub fn php_is_readable(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    const file = std.Io.Dir.cwd().openFile(getIo(), fname, .{}) catch return Value.initBool(false);
    file.close(getIo());
    return Value.initBool(true);
}

pub fn php_is_writable(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    const file = std.Io.Dir.cwd().createFile(getIo(), fname, .{ .truncate = false }) catch return Value.initBool(false);
    file.close(getIo());
    return Value.initBool(true);
}

/// filemtime - 获取文件修改时间
pub fn php_filemtime(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    const file = std.Io.Dir.cwd().openFile(getIo(), fname, .{}) catch return Value.initBool(false);
    defer file.close(getIo());
    const stat = file.stat(getIo()) catch return Value.initBool(false);
    // 返回Unix时间戳
    return Value.initInt(@intCast(std.Io.Timestamp.toSeconds(stat.mtime)));
}

/// fileatime - 获取文件访问时间
pub fn php_fileatime(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    const file = std.Io.Dir.cwd().openFile(getIo(), fname, .{}) catch return Value.initBool(false);
    defer file.close(getIo());
    const stat = file.stat(getIo()) catch return Value.initBool(false);
    return Value.initInt(@intCast(if (stat.atime) |a| std.Io.Timestamp.toSeconds(a) else 0));
}

/// filectime - 获取文件创建时间（Unix下为inode修改时间）
pub fn php_filectime(filename: Value) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;
    const file = std.Io.Dir.cwd().openFile(getIo(), fname, .{}) catch return Value.initBool(false);
    defer file.close(getIo());
    const stat = file.stat(getIo()) catch return Value.initBool(false);
    return Value.initInt(@intCast(std.Io.Timestamp.toSeconds(stat.ctime)));
}

// ============================================================================
// 错误处理函数
// ============================================================================

// 全局错误处理器存储
threadlocal var global_error_handler: ?Value = null;
threadlocal var global_error_types: i64 = E_ALL;
threadlocal var global_exception_handler: ?Value = null;

// 错误级别常量
pub const E_ERROR: i64 = 1;
pub const E_WARNING: i64 = 2;
pub const E_PARSE: i64 = 4;
pub const E_NOTICE: i64 = 8;
pub const E_CORE_ERROR: i64 = 16;
pub const E_CORE_WARNING: i64 = 32;
pub const E_COMPILE_ERROR: i64 = 64;
pub const E_COMPILE_WARNING: i64 = 128;
pub const E_USER_ERROR: i64 = 256;
pub const E_USER_WARNING: i64 = 512;
pub const E_USER_NOTICE: i64 = 1024;
pub const E_STRICT: i64 = 2048;
pub const E_RECOVERABLE_ERROR: i64 = 4096;
pub const E_DEPRECATED: i64 = 8192;
pub const E_USER_DEPRECATED: i64 = 16384;
pub const E_ALL: i64 = 32767;

/// set_error_handler - 设置用户自定义错误处理函数
pub fn php_set_error_handler(handler: Value, error_types: Value, allocator: Allocator) !Value {
    _ = allocator;
    // 返回之前设置的错误处理器
    const prev_handler = if (global_error_handler) |h| h else Value.initNull();

    // 设置新的错误处理器
    if (handler.isNull()) {
        global_error_handler = null;
    } else {
        _ = handler.retain();
        global_error_handler = handler;
    }

    // 设置错误类型掩码
    if (!error_types.isNull()) {
        global_error_types = error_types.toInt();
    }

    return prev_handler;
}

/// restore_error_handler - 恢复之前的错误处理函数
pub fn php_restore_error_handler() !Value {
    const prev_handler = if (global_error_handler) |h| h else Value.initNull();
    global_error_handler = null;
    return prev_handler;
}

/// set_exception_handler - 设置用户自定义异常处理函数
pub fn php_set_exception_handler(handler: Value, allocator: Allocator) !Value {
    _ = allocator;
    const prev = if (global_exception_handler) |h| h else Value.initNull();
    if (handler.isNull()) {
        global_exception_handler = null;
    } else {
        _ = handler.retain();
        global_exception_handler = handler;
    }
    return prev;
}

/// restore_exception_handler - 恢复之前的异常处理函数
pub fn php_restore_exception_handler() !Value {
    const prev = if (global_exception_handler) |h| h else Value.initNull();
    global_exception_handler = null;
    return prev;
}

/// trigger_error - 触发用户错误
pub fn php_trigger_error(message: Value, error_type: Value, allocator: Allocator) !Value {
    if (!message.isString()) return Value.initBool(false);

    const err_type = if (error_type.isNull()) E_USER_NOTICE else error_type.toInt();

    // 如果设置了自定义错误处理器
    if (global_error_handler) |handler| {
        // 检查是否在错误类型掩码内
        if ((err_type & global_error_types) != 0) {
            // 调用用户错误处理器
            if (handler.isFunction()) {
                const closure = handler.asFunction();
                var args = [_]Value{
                    message,
                    Value.initInt(err_type),
                    Value.initString(try PHPString.init(allocator, "")), // errfile
                    Value.initInt(0), // errline
                };
                _ = closure.func(Value.initNull(), args[0..], allocator) catch {};
            }
        }
    } else {
        // 没有自定义处理器，直接输出错误
        const err_type_str = switch (err_type) {
            E_USER_ERROR => "Fatal error",
            E_USER_WARNING => "Warning",
            E_USER_NOTICE => "Notice",
            E_USER_DEPRECATED => "Deprecated",
            else => "Error",
        };
        std.debug.print("{s}: {s}\n", .{ err_type_str, message.asString().data });
    }

    return Value.initBool(true);
}

/// error_reporting - 设置或获取错误报告级别
pub fn php_error_reporting(level: Value) !Value {
    const prev_level = global_error_types;
    if (!level.isNull()) {
        global_error_types = level.toInt();
    }
    return Value.initInt(prev_level);
}

pub fn php_sys_get_temp_dir(allocator: Allocator) !Value {
    const tmp_dir = if (builtin.os.tag == .windows) "C:\\Windows\\Temp" else "/tmp";
    const output = try PHPString.init(allocator, try allocator.dupe(u8, tmp_dir));
    return Value.initString(output);
}

pub fn php_file(filename: Value, allocator: Allocator) !Value {
    if (!filename.isString()) return Value.initBool(false);
    const fname = filename.asString().data;

    const content = std.Io.Dir.cwd().readFileAlloc(getIo(), fname, allocator, 10 * 1024 * 1024) catch return Value.initBool(false);
    defer allocator.free(content);

    const arr = try PHPArray.init(allocator);
    var lines = std.mem.splitScalar(u8, content, '\n');
    var idx: i64 = 0;
    while (lines.next()) |line| {
        if (line.len == 0 and lines.rest().len == 0) break; // 最后的空行
        const line_with_newline = try std.fmt.allocPrint(allocator, "{s}\n", .{line});
        const line_str = try PHPString.init(allocator, line_with_newline);
        try arr.set(allocator, ArrayKey{ .integer = idx }, Value.initString(line_str));
        idx += 1;
    }
    return Value.initArray(arr);
}

pub fn php_function_exists(args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len != 1) return error.InvalidArgumentCount;
    if (!args[0].isString()) return Value.initBool(false);
    return Value.initBool(lookupBuiltinFunction(args[0].asString().data) != null);
}

pub fn php_gc_enable(args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len != 0) return error.InvalidArgumentCount;
    gc_enabled = true;
    return Value.initNull();
}

pub fn php_gc_collect_cycles(args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len != 0) return error.InvalidArgumentCount;
    return Value.initInt(@intCast(php_collect_cycles()));
}

pub fn php_ini_get(args: []const Value, allocator: Allocator) !Value {
    if (args.len != 1) return error.InvalidArgumentCount;
    if (!args[0].isString()) return Value.initBool(false);

    const option = args[0].asString().data;
    const value: ?[]const u8 = if (std.mem.eql(u8, option, "display_errors"))
        "1"
    else if (std.mem.eql(u8, option, "error_reporting"))
        "32767"
    else if (std.mem.eql(u8, option, "max_execution_time"))
        "0"
    else if (std.mem.eql(u8, option, "memory_limit"))
        "128M"
    else if (std.mem.eql(u8, option, "post_max_size"))
        "8M"
    else if (std.mem.eql(u8, option, "upload_max_filesize"))
        "2M"
    else
        null;

    if (value) |s| return Value.initString(try PHPString.init(allocator, s));
    return Value.initBool(false);
}

pub fn php_getrusage(args: []const Value, allocator: Allocator) !Value {
    if (args.len > 1) return error.InvalidArgumentCount;

    const arr = try PHPArray.init(allocator);
    const key = try PHPString.init(allocator, "ru_utime.tv_sec");
    defer key.release(allocator);
    try arr.set(allocator, ArrayKey{ .string = key }, Value.initInt(0));
    return Value.initArray(arr);
}

fn wrapBuiltin_trim(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const mask = if (args.len >= 2) args[1] else Value.initNull();
    return php_trim(args[0], mask, allocator);
}

fn wrapBuiltin_count(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    const mode = if (args.len >= 2) args[1] else Value.initInt(0);
    return php_count(args[0], mode);
}

fn wrapBuiltin_sqrt(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_sqrt(args[0]);
}

fn wrapBuiltin_strval(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_strval(args[0], allocator);
}

fn wrapBuiltin_array_map(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_array_map(args, allocator);
}

fn wrapBuiltin_array_filter(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const callback = if (args.len >= 2) args[1] else Value.initNull();
    const mode = if (args.len >= 3) args[2] else Value.initInt(0);
    return php_array_filter(args[0], callback, mode, allocator);
}

fn wrapBuiltin_array_reduce(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const initial = if (args.len >= 3) args[2] else Value.initNull();
    return php_array_reduce(args[0], args[1], initial, allocator);
}

fn wrapBuiltin_json_decode(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_json_decode(args, allocator);
}

fn wrapBuiltin_json_last_error_msg(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len != 0) return error.InvalidArgumentCount;
    return php_json_last_error_msg(allocator);
}

fn wrapBuiltin_array_walk(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const userdata = if (args.len >= 3) args[2] else Value.initNull();
    return php_array_walk(args[0], args[1], userdata, allocator);
}

fn wrapBuiltin_array_walk_recursive(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const userdata = if (args.len >= 3) args[2] else Value.initNull();
    return php_array_walk_recursive(args[0], args[1], userdata, allocator);
}

fn wrapBuiltin_select(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_select(args, allocator);
}

fn wrapBuiltin_get_class_methods(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_get_class_methods(args[0], allocator);
}

fn wrapBuiltin_get_class_vars(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_get_class_vars(args[0], allocator);
}

fn wrapBuiltin_get_object_vars(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_get_object_vars(args[0], allocator);
}

fn wrapBuiltin_get_called_class(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len != 0) return error.InvalidArgumentCount;
    const called = getCurrentCalledClass() orelse return error.ClassNotFound;
    const s = try PHPString.init(allocator, called.name);
    return Value.initString(s);
}

/// static::class → 运行时获取调用类名（LSB）
pub fn php_get_called_class_name() !Value {
    const called = getCurrentCalledClass() orelse return error.ClassNotFound;
    const s = try PHPString.init(runtime_allocator, called.name);
    return Value.initString(s);
}

fn php_forward_static_call(callback: Value, args: []const Value, allocator: Allocator) !Value {
    if (!callback.isString()) return error.InvalidCallback;
    const cb = callback.asString().data;

    const sep = std.mem.indexOf(u8, cb, "::") orelse return error.InvalidCallback;
    if (sep == 0 or sep + 2 >= cb.len) return error.InvalidCallback;

    const class_part = cb[0..sep];
    const method_part = cb[sep + 2 ..];

    const lookup_meta = blk: {
        if (std.mem.eql(u8, class_part, "self")) {
            break :blk getCurrentScopeClass() orelse return error.ClassNotFound;
        }
        if (std.mem.eql(u8, class_part, "parent")) {
            const scope = getCurrentScopeClass() orelse return error.ClassNotFound;
            break :blk scope.parent orelse return error.ClassNotFound;
        }
        if (std.mem.eql(u8, class_part, "static")) {
            break :blk getCurrentCalledClass() orelse return error.ClassNotFound;
        }
        break :blk findClass(class_part) orelse return error.ClassNotFound;
    };

    const called_meta = getCurrentCalledClass() orelse lookup_meta;

    if (lookup_meta.findMethodLookup(method_part)) |lookup| {
        const guard = ClassContext.init(called_meta, lookup.owner);
        defer guard.deinit();
        return lookup.method.func(Value.initNull(), args, allocator);
    }

    if (lookup_meta.findMethodLookup("__callStatic")) |lookup| {
        const name_str = try PHPString.init(allocator, method_part);
        const name_val = Value.initString(name_str);
        defer name_val.release(allocator);

        const args_arr = try PHPArray.init(allocator);
        for (args) |arg| {
            try args_arr.push(allocator, arg);
        }
        const call_args = [_]Value{ name_val, Value.initArray(args_arr) };
        const guard = ClassContext.init(called_meta, lookup.owner);
        defer guard.deinit();
        return lookup.method.func(Value.initNull(), &call_args, allocator);
    }

    return error.MethodNotFound;
}

fn wrapBuiltin_forward_static_call(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_forward_static_call(args[0], args[1..], allocator);
}

fn wrapBuiltin_forward_static_call_array(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len != 2) return error.InvalidArgumentCount;
    if (!args[1].isArray()) return error.InvalidArgument;

    const arr = args[1].asArray();
    var list = std.ArrayListUnmanaged(Value){ .items = &.{}, .capacity = 0 };
    defer list.deinit(allocator);

    var iter = arr.elements.iterator();
    while (iter.next()) |entry| {
        try list.append(allocator, entry.value_ptr.*);
    }

    return php_forward_static_call(args[0], list.items, allocator);
}

// ============================================================================
// 文件系统函数包装器
// ============================================================================

fn wrapBuiltin_filemtime(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_filemtime(args[0]);
}

fn wrapBuiltin_fileatime(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_fileatime(args[0]);
}

fn wrapBuiltin_filectime(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_filectime(args[0]);
}

// ============================================================================
// 网络函数包装器
// ============================================================================

fn wrapBuiltin_getenv(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_getenv(args[0], allocator);
}

fn wrapBuiltin_gethostbyname(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_gethostbyname(args[0], allocator);
}

fn wrapBuiltin_gethostname(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = args;
    return php_gethostname(allocator);
}

fn wrapBuiltin_ip2long(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ip2long(args[0]);
}

fn wrapBuiltin_long2ip(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_long2ip(args[0], allocator);
}

fn wrapBuiltin_parse_url(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_parse_url(args[0], allocator);
}

// ============================================================================
// 错误处理函数包装器
// ============================================================================

fn wrapBuiltin_set_error_handler(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    const handler = if (args.len > 0) args[0] else Value.initNull();
    const error_types = if (args.len > 1) args[1] else Value.initNull();
    return php_set_error_handler(handler, error_types, allocator);
}

fn wrapBuiltin_restore_error_handler(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = args;
    _ = allocator;
    return php_restore_error_handler();
}

fn wrapBuiltin_trigger_error(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    const message = if (args.len > 0) args[0] else Value.initString(try PHPString.init(allocator, ""));
    const error_type = if (args.len > 1) args[1] else Value.initNull();
    return php_trigger_error(message, error_type, allocator);
}

fn wrapBuiltin_error_reporting(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    const level = if (args.len > 0) args[0] else Value.initNull();
    return php_error_reporting(level);
}

pub fn php_select_builtin(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    return php_select(args, allocator);
}

pub fn php_get_class_methods_builtin(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_get_class_methods(args[0], allocator);
}

pub fn php_get_class_vars_builtin(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_get_class_vars(args[0], allocator);
}

pub fn php_get_object_vars_builtin(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_get_object_vars(args[0], allocator);
}

pub fn php_get_called_class_builtin(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    return wrapBuiltin_get_called_class(ctx, args, allocator);
}

pub fn php_forward_static_call_builtin(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    return wrapBuiltin_forward_static_call(ctx, args, allocator);
}

pub fn php_forward_static_call_array_builtin(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    return wrapBuiltin_forward_static_call_array(ctx, args, allocator);
}

/// Convert PHPValue to ArrayKey
fn valueToArrayKey(val: Value, allocator: Allocator) !ArrayKey {
    _ = allocator;
    if (val.isInt()) {
        return ArrayKey{ .integer = val.asInt() };
    } else if (val.isString()) {
        const str = val.asString();
        // Try to parse as integer
        const int_val = std.fmt.parseInt(i64, str.data, 10) catch {
            return ArrayKey{ .string = str };
        };
        return ArrayKey{ .integer = int_val };
    } else if (val.isNull()) {
        return ArrayKey{ .integer = 0 };
    } else if (val.isBool()) {
        return ArrayKey{ .integer = if (val.asBool()) 1 else 0 };
    } else if (val.isFloat()) {
        return ArrayKey{ .integer = @intFromFloat(val.asFloat()) };
    }
    return ArrayKey{ .integer = 0 };
}

pub fn php_array_get(arr_val_in: Value, key_val: Value, allocator: Allocator) !Value {
    // Dereference references to access the underlying value
    var arr_val = arr_val_in;
    while (arr_val.isRef()) {
        arr_val = arr_val.asRef().*;
    }

    if (Value_isObject(arr_val)) {
        return php_object_call(arr_val, "offsetGet", &[_]Value{key_val});
    }

    if (arr_val.isString()) {
        const str = arr_val.asString();
        const idx_i64 = key_val.toInt();
        if (idx_i64 < 0 or idx_i64 >= str.length) return Value.initNull();
        const idx = @as(usize, @intCast(idx_i64));
        const ch_slice = str.data[idx..@min(idx + 1, str.data.len)];
        return Value.initString(try PHPString.init(allocator, ch_slice));
    }

    if (arr_val.isArray()) {
        const result = arr_val.asArray().getByValue(key_val) orelse Value.initNull();
        _ = result.retain();
        return result;
    }

    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(
        &buf,
        "Trying to access array offset on {s}",
        .{valueTypeName(arr_val)},
    ) catch "Trying to access array offset";
    emitWarning(msg);

    return Value.initNull();
}

/// 获取数组元素的引用（用于引用返回）
/// 参数：array, key
/// 返回：Value.initRef(指向数组元素的指针)
pub fn php_array_get_ref(arr_val_in: Value, key_val: Value, allocator: Allocator) !Value {
    // Dereference references to access the underlying array
    var arr_val = arr_val_in;
    while (arr_val.isRef()) {
        arr_val = arr_val.asRef().*;
    }

    if (!arr_val.isArray()) return error.InvalidArgument;
    const arr = arr_val.asArray();

    const key = normalizeArrayKeyFromValue(key_val);

    // 获取或创建数组元素
    const entry_ptr = arr.data.getPtr(key) orelse blk: {
        // 元素不存在，创建一个 null 值
        try arr.data.put(allocator, key, Value.initNull());
        break :blk arr.data.getPtr(key).?;
    };

    // 返回指向数组元素的引用
    return Value.initRef(entry_ptr);
}

fn php_get_class_methods(class_name_val: Value, allocator: Allocator) !Value {
    var meta_opt: ?*const ClassMeta = null;
    if (class_name_val.isString()) {
        meta_opt = findClass(class_name_val.asString().data);
    } else if (Value_isObject(class_name_val)) {
        const obj = Value_asObject(class_name_val);
        meta_opt = obj.class_meta orelse findClass(obj.class_name);
    } else {
        return error.InvalidArgument;
    }

    const meta = meta_opt orelse return Value.initNull();

    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    const res_arr = try PHPArray.init(allocator);

    var cur: ?*const ClassMeta = meta;
    while (cur) |m| : (cur = m.parent) {
        var iter = m.methods.iterator();
        while (iter.next()) |entry| {
            const method = entry.value_ptr.*;
            if (!method.is_public) continue;
            if (seen.contains(entry.key_ptr.*)) continue;
            try seen.put(entry.key_ptr.*, {});

            const s = try PHPString.init(allocator, entry.key_ptr.*);
            const v = Value.initString(s);
            try res_arr.push(allocator, v);
            v.release(allocator);
        }
    }

    return Value.initArray(res_arr);
}

fn php_get_class_vars(class_name_val: Value, allocator: Allocator) !Value {
    var meta_opt: ?*const ClassMeta = null;
    if (class_name_val.isString()) {
        meta_opt = findClass(class_name_val.asString().data);
    } else if (Value_isObject(class_name_val)) {
        const obj = Value_asObject(class_name_val);
        meta_opt = obj.class_meta orelse findClass(obj.class_name);
    } else {
        return error.InvalidArgument;
    }

    const meta = meta_opt orelse return Value.initNull();
    const res_arr = try PHPArray.init(allocator);

    var iter = meta.properties.iterator();
    while (iter.next()) |entry| {
        const prop = entry.value_ptr.*;
        if (prop.is_static) continue;
        if (!prop.is_public) continue;
        const key_str = try PHPString.init(allocator, entry.key_ptr.*);
        try res_arr.set(allocator, ArrayKey{ .string = key_str }, prop.default_value orelse Value.initNull());
        key_str.release(allocator);
    }

    return Value.initArray(res_arr);
}

fn php_get_object_vars(obj_val: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) return error.InvalidArgument;
    const obj = Value_asObject(obj_val);

    const res_arr = try PHPArray.init(allocator);
    var iter = obj.properties.iterator();
    while (iter.next()) |entry| {
        const key_str = try PHPString.init(allocator, entry.key_ptr.*);
        try res_arr.set(allocator, ArrayKey{ .string = key_str }, entry.value_ptr.*);
        key_str.release(allocator);
    }
    return Value.initArray(res_arr);
}

fn php_get_public_object_vars_snapshot(obj_val: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) return error.InvalidArgument;
    const obj = Value_asObject(obj_val);

    const res_arr = try PHPArray.init(allocator);
    var iter = obj.properties.iterator();
    while (iter.next()) |entry| {
        if (obj.class_meta) |meta| {
            if (meta.properties.get(entry.key_ptr.*)) |prop| {
                if (prop.is_static or !prop.is_public) continue;
            }
        }

        const key_str = try PHPString.init(allocator, entry.key_ptr.*);
        try res_arr.set(allocator, ArrayKey{ .string = key_str }, entry.value_ptr.*);
        key_str.release(allocator);
    }
    return Value.initArray(res_arr);
}

fn php_select(args: []const Value, allocator: Allocator) !Value {
    const cases_arg = args[0];
    if (!cases_arg.isArray()) return error.InvalidArgument;

    var timeout: ?i64 = null;
    if (args.len > 1 and !args[1].isNull()) {
        timeout = args[1].toInt();
    }

    const array = cases_arg.asArray();
    const start_time = milliTimestamp();

    while (true) {
        var iter = array.elements.iterator();
        var index: usize = 0;
        while (iter.next()) |entry| : (index += 1) {
            const case_val = entry.value_ptr.*;
            if (!case_val.isArray()) continue;

            const case_arr = case_val.asArray();
            const ch_val = case_arr.get(ArrayKey{ .integer = 0 }) orelse continue;
            const op_val = case_arr.get(ArrayKey{ .integer = 1 }) orelse continue;

            if (!Value_isObject(ch_val)) continue;
            const ch_obj = Value_asObject(ch_val);
            if (ch_obj.getProperty("_ptr")) |ptr_val| {
                const channel = @as(*concurrency.Channel(Value), @ptrFromInt(@as(usize, @intCast(ptr_val.asInt()))));
                const op = op_val.toInt();

                if (op == 0) {
                    if (channel.tryRecv()) |val| {
                        const res_arr = try PHPArray.init(allocator);
                        try res_arr.push(allocator, Value.initInt(@intCast(index)));
                        try res_arr.push(allocator, val);
                        return Value.initArray(res_arr);
                    }
                } else if (op == 1) {
                    const send_val = case_arr.get(ArrayKey{ .integer = 2 }) orelse Value.initNull();
                    _ = send_val.retain();
                    const ok = channel.trySend(send_val) catch {
                        send_val.release(allocator);
                        continue;
                    };
                    if (ok) {
                        return Value.initInt(@intCast(index));
                    }
                    send_val.release(allocator);
                }
            }
        }

        if (timeout) |t| {
            if (milliTimestamp() - start_time >= t) {
                return Value.initNull();
            }
        }
        std.Thread.yield() catch {};
    }
}

// Closure::bind/bindTo 绑定的 $this 栈（支持嵌套调用）
threadlocal var closure_bound_this_stack: Value = Value.initNull();

/// 获取当前 Closure::bind 绑定的 $this（供 getGlobalVar("$this") 使用）
pub fn getClosureBoundThis() Value {
    return closure_bound_this_stack;
}

pub fn php_invoke_callable(callback: Value, args: []const Value, allocator: Allocator) !Value {
    // 引用透明：闭包自引用场景中 callback 可能是 Ref(cell)
    var actual_cb = if (callback.isRef()) callback.asRef().* else callback;

    // 多层Ref解引用：捕获的闭包可能被多次包装
    while (actual_cb.isRef()) {
        actual_cb = actual_cb.asRef().*;
    }

    if (actual_cb.isFunction()) {
        const closure = actual_cb.asFunction();
        // Closure::bind/bindTo: 如果有 bound_this，临时设置全局 $this
        if (!closure.bound_this.isNull()) {
            const prev_this = closure_bound_this_stack;
            closure_bound_this_stack = closure.bound_this;
            defer closure_bound_this_stack = prev_this;
            return closure.func(actual_cb, args, allocator);
        }
        return closure.func(actual_cb, args, allocator);
    }
    if (Value_isObject(actual_cb)) {
        const obj_ptr = Value_asObject(actual_cb);
        return obj_ptr.callMethod("__invoke", args) catch |err| switch (err) {
            error.MethodNotFound => return Value.initBool(false),
            else => return Value.initBool(false),
        };
    }
    if (actual_cb.isString()) {
        const func_name = actual_cb.asString().data;
        // AOT hook 优先：支持所有 AOT 注册的函数（包括内置函数分发）
        if (aot_callable_hook) |hook| {
            if (hook(func_name, args, allocator)) |result| {
                return result;
            } else |err| {
                // AOT hook 返回错误则尝试其他路径
                if (err != error.UnknownFunction) return err;
            }
        }
        if (lookupBuiltinFunction(func_name)) |func| {
            return func(Value.initNull(), args, allocator);
        }
        if (user_function_registry) |registry| {
            if (registry.get(func_name)) |func| {
                return func(Value.initNull(), args, allocator);
            }
        }
        // PHP: 对不存在的函数发出 warning 并返回 false
        return Value.initBool(false);
    }
    if (actual_cb.isArray()) {
        const arr = actual_cb.asArray();
        if (arr.elements.count() != 2) return Value.initBool(false);

        const key0 = ArrayKey{ .integer = 0 };
        const key1 = ArrayKey{ .integer = 1 };

        const val0 = arr.elements.get(key0) orelse return Value.initBool(false);
        const val1 = arr.elements.get(key1) orelse return Value.initBool(false);

        if (!val1.isString()) return Value.initBool(false);
        const method_name = val1.asString().data;

        if (Value_isObject(val0)) {
            const obj_ptr = Value_asObject(val0);
            return obj_ptr.callMethod(method_name, args) catch Value.initBool(false);
        }
        if (val0.isString()) {
            return php_call_static(val0.asString().data, method_name, args, allocator) catch Value.initBool(false);
        }
        return Value.initBool(false);
    }
    return Value.initBool(false);
}

pub fn php_args_append_spread(dest: Value, src: Value, allocator: Allocator) !Value {
    if (!dest.isArray()) {
        return throwException("Only arrays can be unpacked", allocator);
    }

    const dest_arr = dest.asArray();
    const iter_val = try php_array_iter_init(src, allocator);
    defer _ = php_array_iter_free(iter_val, allocator) catch {};

    while ((try php_array_iter_valid(iter_val)).toBool()) {
        const value = try php_array_iter_value(iter_val);
        defer value.release(allocator);
        try dest_arr.push(allocator, value);

        const next_iter = try php_array_iter_next(iter_val);
        next_iter.release(allocator);
    }
    return dest;
}

pub fn php_invoke_callable_args_array(callback: Value, args_array: Value, allocator: Allocator) !Value {
    if (!args_array.isArray()) {
        return throwException("Only arrays can be unpacked", allocator);
    }

    const arr = args_array.asArray();
    const max_count: usize = @intCast(arr.next_index);
    const tmp_args = try allocator.alloc(Value, max_count);
    defer allocator.free(tmp_args);

    var used: usize = 0;
    var i: usize = 0;
    while (i < max_count) : (i += 1) {
        const key = ArrayKey{ .integer = @intCast(i) };
        if (arr.get(key)) |v| {
            tmp_args[used] = v;
            used += 1;
        }
    }
    return php_invoke_callable(callback, tmp_args[0..used], allocator);
}

pub fn php_object_call_safe_args_array(obj_val: Value, method_name_val: Value, args_array: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) {
        return Value.initNull();
    }
    if (!method_name_val.isString()) {
        return Value.initNull();
    }
    if (!args_array.isArray()) {
        return throwException("Only arrays can be unpacked", allocator);
    }

    const arr = args_array.asArray();
    const max_count: usize = @intCast(arr.next_index);
    const tmp_args = try allocator.alloc(Value, max_count);
    defer allocator.free(tmp_args);

    var used: usize = 0;
    var i: usize = 0;
    while (i < max_count) : (i += 1) {
        const key = ArrayKey{ .integer = @intCast(i) };
        if (arr.get(key)) |v| {
            tmp_args[used] = v;
            used += 1;
        }
    }

    return php_object_call(obj_val, method_name_val.asString().data, tmp_args[0..used]);
}

pub fn php_object_call_args_array(obj_val: Value, method_name_val: Value, args_array: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) {
        return throwException("Call to a member function on null", allocator);
    }
    if (!method_name_val.isString()) {
        return throwException("Method name must be a string", allocator);
    }
    if (!args_array.isArray()) {
        return throwException("Only arrays can be unpacked", allocator);
    }

    const arr = args_array.asArray();
    const max_count: usize = @intCast(arr.next_index);
    const tmp_args = try allocator.alloc(Value, max_count);
    defer allocator.free(tmp_args);

    var used: usize = 0;
    var i: usize = 0;
    while (i < max_count) : (i += 1) {
        const key = ArrayKey{ .integer = @intCast(i) };
        if (arr.get(key)) |v| {
            tmp_args[used] = v;
            used += 1;
        }
    }

    return php_object_call(obj_val, method_name_val.asString().data, tmp_args[0..used]);
}

/// 使用命名参数调用对象方法
/// args_array 包含位置参数（整数键）和命名参数（字符串键）
pub fn php_object_call_named_args(obj_val: Value, method_name_val: Value, args_array: Value, allocator: Allocator) !Value {
    if (!Value_isObject(obj_val)) {
        return throwException("Call to a member function on null", allocator);
    }
    if (!method_name_val.isString()) {
        return throwException("Method name must be a string", allocator);
    }
    if (!args_array.isArray()) {
        return throwException("Arguments must be an array", allocator);
    }

    const obj = Value_asObject(obj_val);
    const method_name = method_name_val.asString().data;
    const arr = args_array.asArray();

    // 获取方法的参数信息
    const meta = obj.class_meta orelse return throwException("Cannot find class metadata", allocator);
    _ = meta.findMethod(method_name) orelse return throwException("Call to undefined method", allocator);

    // 收集位置参数（整数键，按顺序）
    var positional = std.ArrayListUnmanaged(Value){ .items = &.{}, .capacity = 0 };
    defer positional.deinit(allocator);
    var pos_idx: usize = 0;
    while (true) : (pos_idx += 1) {
        const key = ArrayKey{ .integer = @intCast(pos_idx) };
        if (arr.get(key)) |v| {
            try positional.append(allocator, v);
        } else {
            break;
        }
    }

    // 收集命名参数（字符串键）
    var named = std.StringHashMap(Value).init(allocator);
    defer {
        var it = named.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.release(allocator);
        }
        named.deinit();
    }
    var iter = arr.elements.iterator();
    while (iter.next()) |entry| {
        switch (entry.key_ptr.*) {
            .string => |s| {
                const val = entry.value_ptr.*;
                _ = val.retain();
                try named.put(s.data, val);
            },
            else => {},
        }
    }

    // 获取方法参数名（从函数元数据）
    const full_method_name = try std.fmt.allocPrint(allocator, "{s}::{s}", .{ meta.name, method_name });
    defer allocator.free(full_method_name);

    // 尝试获取参数信息
    const param_count: u16 = if (function_meta_registry) |meta_reg|
        (if (meta_reg.get(full_method_name)) |m| m.param_count else 0)
    else
        0;

    // 构建最终参数列表
    const final_args = try allocator.alloc(Value, @max(param_count, positional.items.len));
    defer allocator.free(final_args);
    var final_count: usize = 0;

    // 首先填充位置参数
    for (positional.items) |arg| {
        if (final_count < final_args.len) {
            final_args[final_count] = arg;
            final_count += 1;
        }
    }

    // 然后用命名参数覆盖/填充
    // 我们需要从类方法中获取参数名
    // 这是一个简化实现：假设参数顺序正确
    // 完整实现需要在编译时记录参数名

    return php_object_call(obj_val, method_name, final_args[0..final_count]);
}

// ============================================================================
// 算术运算符
// ============================================================================

/// 加法运算（PHP语义）
pub fn php_add(lhs: Value, rhs: Value) !Value {
    // 数组联合运算：$a + $b（保留左侧值，右侧不存在的键才加入）
    if (lhs.isArray() and rhs.isArray()) {
        return php_array_union(lhs, rhs, runtime_allocator);
    }
    if (!checkArithmeticOperand(lhs) or !checkArithmeticOperand(rhs)) {
        emitUnsupportedOperandError(lhs, rhs, "+");
    }
    emitArithmeticStringWarningIfNeeded(lhs);
    emitArithmeticStringWarningIfNeeded(rhs);
    // 整数 + 整数 = 整数（可能溢出为浮点）
    if (lhs.isInt() and rhs.isInt()) {
        const a = lhs.asInt();
        const b = rhs.asInt();
        const result = @addWithOverflow(a, b);
        if (result[1] != 0 or result[0] < Value.INT48_MIN or result[0] > Value.INT48_MAX) {
            // 溢出：转为浮点数
            return Value.initFloat(@as(f64, @floatFromInt(a)) + @as(f64, @floatFromInt(b)));
        }
        return Value.initInt(result[0]);
    }

    // 其他情况：转为浮点数
    const a = lhs.toFloat();
    const b = rhs.toFloat();
    return Value.initFloat(a + b);
}

/// 减法运算（PHP语义）
pub fn php_sub(lhs: Value, rhs: Value) !Value {
    if (!checkArithmeticOperand(lhs) or !checkArithmeticOperand(rhs)) {
        emitUnsupportedOperandError(lhs, rhs, "-");
    }
    emitArithmeticStringWarningIfNeeded(lhs);
    emitArithmeticStringWarningIfNeeded(rhs);
    if (lhs.isInt() and rhs.isInt()) {
        const a = lhs.asInt();
        const b = rhs.asInt();
        const result = @subWithOverflow(a, b);
        if (result[1] != 0 or result[0] < Value.INT48_MIN or result[0] > Value.INT48_MAX) {
            return Value.initFloat(@as(f64, @floatFromInt(a)) - @as(f64, @floatFromInt(b)));
        }
        return Value.initInt(result[0]);
    }

    const a = lhs.toFloat();
    const b = rhs.toFloat();
    return Value.initFloat(a - b);
}

/// Negate a value (unary minus)
pub fn php_neg(val: Value) !Value {
    if (val.isInt()) {
        const a = val.asInt();
        if (a == Value.INT48_MIN) {
            return Value.initFloat(-@as(f64, @floatFromInt(a)));
        }
        return Value.initInt(-a);
    }
    return Value.initFloat(-val.toFloat());
}

/// 乘法运算（PHP语义）
pub fn php_mul(lhs: Value, rhs: Value) !Value {
    if (!checkArithmeticOperand(lhs) or !checkArithmeticOperand(rhs)) {
        emitUnsupportedOperandError(lhs, rhs, "*");
    }
    emitArithmeticStringWarningIfNeeded(lhs);
    emitArithmeticStringWarningIfNeeded(rhs);
    if (lhs.isInt() and rhs.isInt()) {
        const a = lhs.asInt();
        const b = rhs.asInt();
        const result = @mulWithOverflow(a, b);
        if (result[1] != 0 or result[0] < Value.INT48_MIN or result[0] > Value.INT48_MAX) {
            return Value.initFloat(@as(f64, @floatFromInt(a)) * @as(f64, @floatFromInt(b)));
        }
        return Value.initInt(result[0]);
    }

    const a = lhs.toFloat();
    const b = rhs.toFloat();
    return Value.initFloat(a * b);
}

/// 除法运算（PHP语义）
pub fn php_div(lhs: Value, rhs: Value) !Value {
    if (!checkArithmeticOperand(lhs) or !checkArithmeticOperand(rhs)) {
        emitUnsupportedOperandError(lhs, rhs, "/");
    }
    emitArithmeticStringWarningIfNeeded(lhs);
    emitArithmeticStringWarningIfNeeded(rhs);
    // PHP 将 null/bool 视为整数参与整除判断
    const lhs_is_int = lhs.isInt() or lhs.isNull() or lhs.isBool();
    const rhs_is_int = rhs.isInt() or rhs.isNull() or rhs.isBool();
    if (lhs_is_int and rhs_is_int) {
        const a = lhs.toInt();
        const b = rhs.toInt();
        if (b == 0) {
            _ = try throwThrowable("DivisionByZeroError", "Division by zero", runtime_allocator);
            return Value.initNull();
        }
        if (@mod(a, b) == 0) {
            const result = @divTrunc(a, b);
            if (result >= Value.INT48_MIN and result <= Value.INT48_MAX) {
                return Value.initInt(result);
            }
        }
    }

    const a = lhs.toFloat();
    const b = rhs.toFloat();
    if (b == 0.0) {
        _ = try throwThrowable("DivisionByZeroError", "Division by zero", runtime_allocator);
        return Value.initNull();
    }
    return Value.initFloat(a / b);
}

/// 取模运算（PHP语义）
pub fn php_mod(lhs: Value, rhs: Value) !Value {
    if (!checkArithmeticOperand(lhs) or !checkArithmeticOperand(rhs)) {
        emitUnsupportedOperandError(lhs, rhs, "%");
    }
    emitArithmeticStringWarningIfNeeded(lhs);
    emitArithmeticStringWarningIfNeeded(rhs);
    // PHP 8.1+: float→int 隐式转换精度丢失时输出 Deprecated
    if (lhs.isFloat()) {
        const f = lhs.asFloat();
        const i: f64 = @floatFromInt(lhs.toInt());
        if (f != i) emitDeprecatedFloatToInt(f);
    }
    if (rhs.isFloat()) {
        const f = rhs.asFloat();
        const i: f64 = @floatFromInt(rhs.toInt());
        if (f != i) emitDeprecatedFloatToInt(f);
    }
    const a = lhs.toInt();
    const b = rhs.toInt();
    if (b == 0) {
        _ = try throwThrowable("DivisionByZeroError", "Modulo by zero", runtime_allocator);
        return Value.initNull();
    }
    return Value.initInt(@rem(a, b));
}

/// 检查字符串是否为 PHP 数字字符串
fn isNumericString(data: []const u8) bool {
    if (data.len == 0) return false;
    var i: usize = 0;
    while (i < data.len and std.ascii.isWhitespace(data[i])) : (i += 1) {}
    if (i < data.len and (data[i] == '+' or data[i] == '-')) i += 1;
    if (i >= data.len) return false;
    var has_digits = false;
    while (i < data.len and std.ascii.isDigit(data[i])) : (i += 1) {
        has_digits = true;
    }
    if (i < data.len and data[i] == '.') {
        i += 1;
        while (i < data.len and std.ascii.isDigit(data[i])) : (i += 1) {
            has_digits = true;
        }
    }
    if (!has_digits) return false;
    if (i < data.len and (data[i] == 'e' or data[i] == 'E')) {
        i += 1;
        if (i < data.len and (data[i] == '+' or data[i] == '-')) i += 1;
        if (i >= data.len or !std.ascii.isDigit(data[i])) return false;
        while (i < data.len and std.ascii.isDigit(data[i])) : (i += 1) {}
    }
    while (i < data.len and std.ascii.isWhitespace(data[i])) : (i += 1) {}
    return i >= data.len;
}

fn numericPrefixLength(data: []const u8) usize {
    if (data.len == 0) return 0;
    var i: usize = 0;
    while (i < data.len and std.ascii.isWhitespace(data[i])) : (i += 1) {}
    if (i < data.len and (data[i] == '+' or data[i] == '-')) i += 1;
    const start_digits = i;
    while (i < data.len and std.ascii.isDigit(data[i])) : (i += 1) {}
    var has_digits = i > start_digits;
    if (i < data.len and data[i] == '.') {
        i += 1;
        const frac_start = i;
        while (i < data.len and std.ascii.isDigit(data[i])) : (i += 1) {}
        if (i > frac_start) has_digits = true;
    }
    if (!has_digits) return 0;
    if (i < data.len and (data[i] == 'e' or data[i] == 'E')) {
        var j = i + 1;
        if (j < data.len and (data[j] == '+' or data[j] == '-')) j += 1;
        const exp_start = j;
        while (j < data.len and std.ascii.isDigit(data[j])) : (j += 1) {}
        if (j > exp_start) i = j;
    }
    return i;
}

fn hasNumericPrefix(data: []const u8) bool {
    return numericPrefixLength(data) > 0;
}

fn emitArithmeticStringWarningIfNeeded(v: Value) void {
    if (!v.isString()) return;
    const str = v.asString().data[0..v.asString().length];
    if (hasNumericPrefix(str) and !isNumericString(str)) {
        emitWarning("A non-numeric value encountered");
    }
}

/// 检查 Value 是否可参与算术运算（PHP 8.x）
fn checkArithmeticOperand(v: Value) bool {
    if (v.isString()) {
        const str = v.asString();
        return hasNumericPrefix(str.data[0..str.length]);
    }
    return !v.isArray();
}

/// 输出 PHP Warning 到 stdout 和 stderr
pub fn emitWarning(msg: []const u8) void {
    // @操作符：错误抑制时不输出警告
    if (isErrorSuppressed()) return;

    // PHP 输出顺序：先 stderr（PHP Warning:），再 stdout（Warning:）
    var ebuf: [1024]u8 = undefined;
    const emsg = std.fmt.bufPrint(
        &ebuf,
        "PHP Warning:  {s} in {s} on line {d}\n",
        .{ msg, src_file, src_line },
    ) catch "";
    fileWriteAll(2, emsg);
    var buf: [1024]u8 = undefined;
    const wmsg = std.fmt.bufPrint(
        &buf,
        "\nWarning: {s} in {s} on line {d}\n",
        .{ msg, src_file, src_line },
    ) catch "";
    fileWriteAll(1, wmsg);
}

pub fn emitDeprecatedStrGetcsvEscape() void {
    // PHP 输出顺序：先 stderr，再 stdout
    var ebuf: [1024]u8 = undefined;
    const emsg = std.fmt.bufPrint(
        &ebuf,
        "PHP Deprecated:  str_getcsv(): the $escape parameter must be provided as its default value will change in {s} on line {d}\n",
        .{ src_file, src_line },
    ) catch "";
    fileWriteAll(2, emsg);
    var buf: [1024]u8 = undefined;
    const wmsg = std.fmt.bufPrint(
        &buf,
        "\nDeprecated: str_getcsv(): the $escape parameter must be provided as its default value will change in {s} on line {d}\n",
        .{ src_file, src_line },
    ) catch "";
    fileWriteAll(1, wmsg);
}

pub fn emitUndefinedVariableWarning(name: []const u8) void {
    // PHP 输出顺序：先 stderr，再 stdout
    var ebuf: [1024]u8 = undefined;
    const emsg = std.fmt.bufPrint(
        &ebuf,
        "PHP Warning:  Undefined variable {s} in {s} on line {d}\n",
        .{ name, src_file, src_line },
    ) catch "";
    fileWriteAll(2, emsg);
    var buf: [1024]u8 = undefined;
    const wmsg = std.fmt.bufPrint(
        &buf,
        "\nWarning: Undefined variable {s} in {s} on line {d}\n",
        .{ name, src_file, src_line },
    ) catch "";
    fileWriteAll(1, wmsg);
}

/// 输出 Unsupported operand types TypeError 并终止
fn emitUnsupportedOperandError(
    lhs: Value,
    rhs: Value,
    op: []const u8,
) noreturn {
    const ltype = valueTypeName(lhs);
    const rtype = valueTypeName(rhs);
    // PHP 输出顺序：先 stderr，再 stdout
    var ebuf: [1024]u8 = undefined;
    const emsg = std.fmt.bufPrint(
        &ebuf,
        "PHP Fatal error:  Uncaught TypeError: Unsupported" ++
            " operand types: {s} {s} {s} in {s}:{d}\n" ++
            "Stack trace:\n#0 {{main}}\n" ++
            "  thrown in {s} on line {d}\n",
        .{
            ltype,    op,       rtype,
            src_file, src_line, src_file,
            src_line,
        },
    ) catch {
        std.process.exit(255);
    };
    fileWriteAll(2, emsg);
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(
        &buf,
        "\nFatal error: Uncaught TypeError: Unsupported" ++
            " operand types: {s} {s} {s} in {s}:{d}\n" ++
            "Stack trace:\n#0 {{main}}\n" ++
            "  thrown in {s} on line {d}\n",
        .{
            ltype,    op,       rtype,
            src_file, src_line, src_file,
            src_line,
        },
    ) catch {
        fileWriteAll(1, "\nFatal error: TypeError\n");
        std.process.exit(255);
    };
    fileWriteAll(1, msg);
    std.process.exit(255);
}

/// 获取 Value 的 PHP 类型名称
fn valueTypeName(v: Value) []const u8 {
    if (v.isNull()) return "null";
    if (v.isBool()) return "bool";
    if (v.isInt()) return "int";
    if (v.isFloat()) return "float";
    if (v.isString()) return "string";
    if (v.isArray()) return "array";
    if (Value_isObject(v)) return "object";
    return "unknown";
}

/// 输出 PHP Fatal TypeError 并终止执行
fn emitTypeFatalError(func_name: []const u8, arg_num: u32, expected: []const u8, got: []const u8) noreturn {
    // PHP 输出顺序：先 stderr，再 stdout
    var ebuf: [1024]u8 = undefined;
    const stderr_msg = std.fmt.bufPrint(
        &ebuf,
        "PHP Fatal error:  Uncaught TypeError: {s}(): Argument" ++
            " #{d} ($array) must be of type {s}, {s} given" ++
            " in {s}:{d}\nStack trace:\n#0 {{main}}\n" ++
            "  thrown in {s} on line {d}\n",
        .{
            func_name, arg_num,  expected, got,
            src_file,  src_line, src_file, src_line,
        },
    ) catch {
        std.process.exit(255);
    };
    fileWriteAll(2, stderr_msg);
    var buf: [1024]u8 = undefined;
    const stdout_msg = std.fmt.bufPrint(
        &buf,
        "\nFatal error: Uncaught TypeError: {s}(): Argument" ++
            " #{d} ($array) must be of type {s}, {s} given" ++
            " in {s}:{d}\nStack trace:\n#0 {{main}}\n" ++
            "  thrown in {s} on line {d}\n",
        .{
            func_name, arg_num,  expected, got,
            src_file,  src_line, src_file, src_line,
        },
    ) catch {
        fileWriteAll(1, "\nFatal error: TypeError\n");
        std.process.exit(255);
    };
    fileWriteAll(1, stdout_msg);
    std.process.exit(255);
}

/// 调用未定义函数时输出 PHP Fatal error 并终止执行
pub fn php_call_undefined_function(name: []const u8) noreturn {
    // PHP 输出顺序：先 stderr，再 stdout
    var ebuf: [1024]u8 = undefined;
    const stderr_msg = std.fmt.bufPrint(
        &ebuf,
        "PHP Fatal error:  Uncaught Error: Call to undefined" ++
            " function {s}() in {s}:{d}\nStack trace:\n" ++
            "#0 {{main}}\n  thrown in {s} on line {d}\n",
        .{ name, src_file, src_line, src_file, src_line },
    ) catch {
        std.process.exit(255);
    };
    fileWriteAll(2, stderr_msg);
    var buf: [1024]u8 = undefined;
    const stdout_msg = std.fmt.bufPrint(
        &buf,
        "\nFatal error: Uncaught Error: Call to undefined" ++
            " function {s}() in {s}:{d}\nStack trace:\n" ++
            "#0 {{main}}\n  thrown in {s} on line {d}\n",
        .{ name, src_file, src_line, src_file, src_line },
    ) catch {
        fileWriteAll(1, "\nFatal error: Call to undefined function\n");
        std.process.exit(255);
    };
    fileWriteAll(1, stdout_msg);
    std.process.exit(255);
}

/// 输出 PHP 8.1+ Deprecated 警告到 stdout（匹配 display_errors=On）
fn emitDeprecatedFloatToInt(f: f64) void {
    // 警告信息中使用完整精度（PHP serialize_precision），不是 echo 的 precision=14
    var fbuf: [64]u8 = undefined;
    const fstr = std.fmt.bufPrint(&fbuf, "{d}", .{f}) catch "?";
    // PHP 输出顺序：先 stderr，再 stdout
    var err_buf: [512]u8 = undefined;
    const stderr_msg = std.fmt.bufPrint(
        &err_buf,
        "PHP Deprecated:  Implicit conversion from" ++
            " float {s} to int loses precision in {s}" ++
            " on line {d}\n",
        .{ fstr, src_file, src_line },
    ) catch return;
    fileWriteAll(2, stderr_msg);
    var msg_buf: [512]u8 = undefined;
    const stdout_msg = std.fmt.bufPrint(
        &msg_buf,
        "\nDeprecated: Implicit conversion from float" ++
            " {s} to int loses precision in {s} on line" ++
            " {d}\n",
        .{ fstr, src_file, src_line },
    ) catch return;
    fileWriteAll(1, stdout_msg);
}

/// 幂运算（PHP语义）
/// PHP 的 pow() 在底数和指数都是整数时返回整数，否则返回浮点数
pub fn php_pow(base: Value, exp: Value) !Value {
    // PHP 语义：两个整数输入且指数非负 → 返回整数
    if (base.isInt() and exp.isInt()) {
        const b = base.asInt();
        const e = exp.asInt();
        if (e >= 0) {
            // 直接整数幂运算，避免浮点误差
            var result: i64 = 1;
            var i: i64 = 0;
            while (i < e) : (i += 1) {
                result = std.math.mul(i64, result, b) catch {
                    // 溢出时回退到浮点
                    return Value.initFloat(std.math.pow(f64, @as(f64, @floatFromInt(b)), @as(f64, @floatFromInt(e))));
                };
            }
            return Value.initInt(result);
        }
    }
    const b = base.toFloat();
    const e = exp.toFloat();
    return Value.initFloat(std.math.pow(f64, b, e));
}
