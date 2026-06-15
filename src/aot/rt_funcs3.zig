const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const runtime = @import("runtime_lib.zig");

// ============================================================================
// Generator Runtime Implementation
// ============================================================================

const GeneratorState = enum(u8) {
    created,
    running,
    suspended,
    completed,
};

pub const GeneratorContext = struct {
    mutex: std.Io.Mutex = .init,
    caller_cond: std.Io.Condition = .init,
    gen_cond: std.Io.Condition = .init,
    state: GeneratorState = .created,
    current_key: Value = Value.initNull(),
    current_value: Value = Value.initNull(),
    sent_value: Value = Value.initNull(),
    return_value: Value = Value.initNull(),
    caller_ctx: Value = Value.initNull(),
    caller_args_storage: []Value = &.{},
    body_fn: ?*const fn (Value, []const Value, Allocator) anyerror!Value = null,
    thread: ?std.Thread = null,
    auto_key: i64 = 0,
    has_error: bool = false,
    throw_value: Value = Value.initNull(),
    has_throw: bool = false,
};

threadlocal var tl_generator_ctx: ?*GeneratorContext = null;

pub fn php_generator_get_context() *GeneratorContext {
    return tl_generator_ctx.?;
}

fn generatorThreadRunner(gen_ctx: *GeneratorContext) void {
    tl_generator_ctx = gen_ctx;
    const body = gen_ctx.body_fn orelse {
        while (!gen_ctx.mutex.tryLock()) std.atomic.spinLoopHint();
        gen_ctx.state = .completed;
        gen_ctx.caller_cond.signal(getIo());
        gen_ctx.mutex.unlock();
        return;
    };
    const result = body(
        gen_ctx.caller_ctx,
        gen_ctx.caller_args_storage,
        runtime_allocator,
    ) catch {
        while (!gen_ctx.mutex.tryLock()) std.atomic.spinLoopHint();
        gen_ctx.has_error = true;
        gen_ctx.state = .completed;
        gen_ctx.caller_cond.signal(getIo());
        gen_ctx.mutex.unlock();
        return;
    };
    while (!gen_ctx.mutex.tryLock()) std.atomic.spinLoopHint();
    gen_ctx.return_value = result;
    gen_ctx.state = .completed;
    gen_ctx.caller_cond.signal(getIo());
    gen_ctx.mutex.unlock();
}

pub fn php_create_generator(
    body_fn: *const fn (Value, []const Value, Allocator) anyerror!Value,
    ctx: Value,
    args: []const Value,
    allocator: Allocator,
) !Value {
    const gen_ctx = try allocator.create(GeneratorContext);
    gen_ctx.* = GeneratorContext{};
    gen_ctx.body_fn = body_fn;
    gen_ctx.caller_ctx = ctx;
    if (args.len > 0) {
        gen_ctx.caller_args_storage = try allocator.alloc(Value, args.len);
        @memcpy(gen_ctx.caller_args_storage, args);
    }
    const meta = findClass("Generator");
    const obj = if (meta) |m|
        try PHPObject.initWithMeta(allocator, m)
    else
        try PHPObject.init(allocator, "Generator");
    try obj.setProperty("__gen_ctx", Value.initInt(
        @as(i64, @intCast(@intFromPtr(gen_ctx))),
    ));
    return Value_initObject(obj);
}

fn getGenCtx(ctx: Value) ?*GeneratorContext {
    if (!Value_isObject(ctx)) return null;
    const obj = Value_asObject(ctx);
    const ptr_val = obj.getPropertyDirect("__gen_ctx") orelse return null;
    if (!ptr_val.isInt()) return null;
    const addr = ptr_val.toInt();
    if (addr <= 0) return null;
    return @ptrFromInt(@as(usize, @intCast(addr)));
}

fn generatorEnsureStarted(gen_ctx: *GeneratorContext) void {
    while (!gen_ctx.mutex.tryLock()) std.atomic.spinLoopHint();
    if (gen_ctx.state == .created) {
        gen_ctx.state = .running;
        gen_ctx.mutex.unlock();
        gen_ctx.thread = std.Thread.spawn(
            .{},
            generatorThreadRunner,
            .{gen_ctx},
        ) catch {
            while (!gen_ctx.mutex.tryLock()) std.atomic.spinLoopHint();
            gen_ctx.state = .completed;
            gen_ctx.mutex.unlock();
            return;
        };
        while (!gen_ctx.mutex.tryLock()) std.atomic.spinLoopHint();
        while (gen_ctx.state == .running) {
            gen_ctx.caller_cond.wait(getIo(), &gen_ctx.mutex) catch {};
        }
        gen_ctx.mutex.unlock();
    } else {
        gen_ctx.mutex.unlock();
    }
}

fn generatorAdvance(gen_ctx: *GeneratorContext) void {
    while (!gen_ctx.mutex.tryLock()) std.atomic.spinLoopHint();
    if (gen_ctx.state != .suspended) {
        gen_ctx.mutex.unlock();
        return;
    }
    gen_ctx.state = .running;
    gen_ctx.gen_cond.signal(getIo());
    while (gen_ctx.state == .running) {
        gen_ctx.caller_cond.wait(getIo(), &gen_ctx.mutex) catch {};
    }
    gen_ctx.mutex.unlock();
}

pub fn php_generator_yield(
    gen_ctx: *GeneratorContext,
    key: Value,
    value: Value,
) !Value {
    while (!gen_ctx.mutex.tryLock()) std.atomic.spinLoopHint();
    if (key.isNull()) {
        gen_ctx.current_key = Value.initInt(gen_ctx.auto_key);
        gen_ctx.auto_key += 1;
    } else {
        gen_ctx.current_key = key;
    }
    gen_ctx.current_value = value;
    gen_ctx.state = .suspended;
    gen_ctx.caller_cond.signal(getIo());
    while (gen_ctx.state == .suspended) {
        gen_ctx.gen_cond.wait(getIo(), &gen_ctx.mutex);
    }
    if (gen_ctx.state == .completed) {
        gen_ctx.mutex.unlock();
        return error.GeneratorClosed;
    }
    if (gen_ctx.has_throw) {
        const throw_val = gen_ctx.throw_value;
        gen_ctx.throw_value = Value.initNull();
        gen_ctx.has_throw = false;
        gen_ctx.mutex.unlock();
        setException(throw_val);
        return Value.initNull();
    }
    const sent = gen_ctx.sent_value;
    gen_ctx.sent_value = Value.initNull();
    gen_ctx.mutex.unlock();
    return sent;
}

pub fn php_generator_yield_from(
    gen_ctx: *GeneratorContext,
    iterable: Value,
) !Value {
    if (Value_isObject(iterable)) {
        const obj = Value_asObject(iterable);
        if (std.mem.eql(u8, obj.class_name, "Generator")) {
            if (getGenCtx(iterable)) |inner| {
                generatorEnsureStarted(inner);
                while (inner.state != .completed) {
                    _ = try php_generator_yield(
                        gen_ctx,
                        inner.current_key,
                        inner.current_value,
                    );
                    generatorAdvance(inner);
                }
                return inner.return_value;
            }
        }
    }
    if (iterable.isArray()) {
        const arr = iterable.asArray();
        var iter = arr.elements.iterator();
        while (iter.next()) |entry| {
            const k = entry.key_ptr.*;
            const v = entry.value_ptr.*;
            const key_val = switch (k) {
                .integer => |i| Value.initInt(i),
                .string => |s| Value.initString(s),
            };
            _ = try php_generator_yield(gen_ctx, key_val, v);
        }
    }
    return Value.initNull();
}

fn registerGeneratorClass(allocator: Allocator) !void {
    const meta = try ClassMeta.init(allocator, "Generator");

    try meta.addMethod(.{
        .name = "rewind",
        .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                if (getGenCtx(ctx)) |gc| {
                    generatorEnsureStarted(gc);
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "valid",
        .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                if (getGenCtx(ctx)) |gc| {
                    generatorEnsureStarted(gc);
                    return Value.initBool(gc.state != .completed);
                }
                return Value.initBool(false);
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "current",
        .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                if (getGenCtx(ctx)) |gc| {
                    generatorEnsureStarted(gc);
                    if (gc.state == .completed) return Value.initNull();
                    _ = gc.current_value.retain();
                    return gc.current_value;
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "key",
        .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                if (getGenCtx(ctx)) |gc| {
                    generatorEnsureStarted(gc);
                    if (gc.state == .completed) return Value.initNull();
                    _ = gc.current_key.retain();
                    return gc.current_key;
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "next",
        .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                if (getGenCtx(ctx)) |gc| {
                    generatorEnsureStarted(gc);
                    generatorAdvance(gc);
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "send",
        .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                if (getGenCtx(ctx)) |gc| {
                    generatorEnsureStarted(gc);
                    if (args.len > 0) {
                        while (!gc.mutex.tryLock()) std.atomic.spinLoopHint();
                        gc.sent_value = args[0];
                        gc.mutex.unlock();
                    }
                    generatorAdvance(gc);
                    if (gc.state == .completed) return Value.initNull();
                    _ = gc.current_value.retain();
                    return gc.current_value;
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "throw",
        .func = struct {
            fn call(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
                if (getGenCtx(ctx)) |gc| {
                    generatorEnsureStarted(gc);
                    if (gc.state == .completed) return Value.initNull();
                    while (!gc.mutex.tryLock()) std.atomic.spinLoopHint();
                    if (args.len > 0) {
                        gc.throw_value = args[0];
                        gc.has_throw = true;
                    }
                    gc.state = .running;
                    gc.gen_cond.signal(getIo());
                    while (gc.state == .running) {
                        gc.caller_cond.wait(getIo(), &gc.mutex) catch {};
                    }
                    gc.mutex.unlock();
                    if (gc.state == .completed) return Value.initNull();
                    _ = gc.current_value.retain();
                    return gc.current_value;
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try meta.addMethod(.{
        .name = "getReturn",
        .func = struct {
            fn call(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
                if (getGenCtx(ctx)) |gc| {
                    if (gc.state != .completed) {
                        return error.GeneratorNotCompleted;
                    }
                    _ = gc.return_value.retain();
                    return gc.return_value;
                }
                return Value.initNull();
            }
        }.call,
        .is_static = false,
    });

    try registerClass(meta);
}

// ============================================================================
// Ctype 系列函数 - 字符类型检测
// ============================================================================

/// ctype_alnum - 检查是否为字母数字字符
pub fn php_ctype_alnum(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isAlphanumeric(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isAlphanumeric(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_alpha - 检查是否为字母字符
pub fn php_ctype_alpha(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isAlphabetic(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isAlphabetic(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_cntrl - 检查是否为控制字符
pub fn php_ctype_cntrl(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isControl(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isControl(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_digit - 检查是否为数字字符
pub fn php_ctype_digit(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isDigit(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isDigit(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_graph - 检查是否为可打印字符（不包括空格）
pub fn php_ctype_graph(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isPrint(c) and c != ' ');
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isPrint(c) or c == ' ') return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_lower - 检查是否为小写字母
pub fn php_ctype_lower(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isLower(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isLower(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_print - 检查是否为可打印字符（包括空格）
pub fn php_ctype_print(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isPrint(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isPrint(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_punct - 检查是否为标点符号
pub fn php_ctype_punct(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(isPunct(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!isPunct(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// 标点符号判断：可打印的非字母数字非空格字符
fn isPunct(c: u8) bool {
    return std.ascii.isPrint(c) and !std.ascii.isAlphanumeric(c) and c != ' ';
}

/// ctype_space - 检查是否为空白字符
pub fn php_ctype_space(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isWhitespace(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isWhitespace(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_upper - 检查是否为大写字母
pub fn php_ctype_upper(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(std.ascii.isUpper(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!std.ascii.isUpper(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// ctype_xdigit - 检查是否为十六进制数字
pub fn php_ctype_xdigit(text: Value) Value {
    if (text.isInt()) {
        const c = @as(u8, @intCast(text.toInt() & 0xFF));
        return Value.initBool(isXDigit(c));
    }
    if (!text.isString()) return Value.initBool(false);
    
    const str = text.asString();
    if (str.length == 0) return Value.initBool(false);
    
    for (str.data) |c| {
        if (!isXDigit(c)) return Value.initBool(false);
    }
    return Value.initBool(true);
}

/// 十六进制数字判断
fn isXDigit(c: u8) bool {
    return std.ascii.isDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

// Ctype 函数包装器
fn wrapBuiltin_ctype_alnum(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_alnum(args[0]);
}

fn wrapBuiltin_ctype_alpha(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_alpha(args[0]);
}

fn wrapBuiltin_ctype_cntrl(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_cntrl(args[0]);
}

fn wrapBuiltin_ctype_digit(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_digit(args[0]);
}

fn wrapBuiltin_ctype_graph(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_graph(args[0]);
}

fn wrapBuiltin_ctype_lower(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_lower(args[0]);
}

fn wrapBuiltin_ctype_print(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_print(args[0]);
}

fn wrapBuiltin_ctype_punct(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_punct(args[0]);
}

fn wrapBuiltin_ctype_space(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_space(args[0]);
}

fn wrapBuiltin_ctype_upper(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_upper(args[0]);
}

fn wrapBuiltin_ctype_xdigit(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ctype_xdigit(args[0]);
}

// ============================================================================
// Mbstring 扩展函数
// ============================================================================

/// mb_strlen - 获取字符串长度（支持多字节字符）
/// 对于ASCII字符串，行为与strlen相同
/// 对于UTF-8字符串，返回字符数而非字节数
pub fn php_mb_strlen(str: Value, encoding: Value) !Value {
    _ = encoding; // 简化实现：忽略encoding参数，默认使用UTF-8
    if (!str.isString()) return Value.initInt(0);

    const php_str = str.asString();
    const data = php_str.data;

    // UTF-8字符计数
    var char_count: usize = 0;
    var i: usize = 0;
    while (i < data.len) {
        const byte = data[i];
        // UTF-8连续字节以10开头，跳过这些
        if ((byte & 0xC0) != 0x80) {
            char_count += 1;
        }
        i += 1;
    }

    return Value.initInt(@intCast(char_count));
}

/// mb_substr - 获取子字符串（支持多字节字符）
/// 对于UTF-8字符串，按字符位置操作而非字节位置
pub fn php_mb_substr(str: Value, start: Value, length: Value, encoding: Value, allocator: Allocator) !Value {
    _ = encoding; // 简化实现：忽略encoding参数，默认使用UTF-8
    if (!str.isString()) return Value.initNull();

    const php_str = str.asString();
    const data = php_str.data;

    // 将字节位置映射到字符位置
    const CharPos = struct {
        byte_idx: usize,
        char_idx: usize,
    };

    // 构建字符位置映射表
    var char_positions = try std.ArrayList(CharPos).initCapacity(allocator, 0);
    defer char_positions.deinit(allocator);

    var char_idx: usize = 0;
    var byte_idx: usize = 0;
    while (byte_idx < data.len) {
        const byte = data[byte_idx];
        if ((byte & 0xC0) != 0x80) {
            try char_positions.append(allocator, .{ .byte_idx = byte_idx, .char_idx = char_idx });
            char_idx += 1;
        }
        byte_idx += 1;
    }
    // 添加结束位置
    try char_positions.append(allocator, .{ .byte_idx = data.len, .char_idx = char_idx });

    const total_chars = char_idx;

    // 处理start参数
    const start_int = start.toInt();
    const start_char: usize = blk: {
        if (start_int >= 0) {
            const s: usize = @intCast(@min(start_int, @as(i64, @intCast(total_chars))));
            break :blk s;
        } else {
            // 负数从末尾开始计数
            const abs_start: usize = @intCast(@min(-start_int, @as(i64, @intCast(total_chars))));
            break :blk if (abs_start > total_chars) @as(usize, 0) else total_chars - abs_start;
        }
    };

    // 处理length参数
    const end_char: usize = blk: {
        if (length.isNull()) {
            break :blk total_chars;
        }
        const len_int = length.toInt();
        if (len_int < 0) {
            // 负数长度从末尾截断
            const abs_len: usize = @intCast(@min(-len_int, @as(i64, @intCast(total_chars))));
            const end = total_chars - abs_len;
            break :blk @min(end, total_chars);
        }
        const end = start_char + @as(usize, @intCast(len_int));
        break :blk @min(end, total_chars);
    };

    if (start_char >= end_char or start_char >= total_chars) {
        const empty_str = try PHPString.init(allocator, "");
        return Value.initString(empty_str);
    }

    // 获取字节范围
    const start_byte = char_positions.items[start_char].byte_idx;
    const end_byte = char_positions.items[end_char].byte_idx;

    const result = try PHPString.init(allocator, data[start_byte..end_byte]);
    return Value.initString(result);
}

/// mb_strtoupper - 转换为大写（支持多字节字符）
/// 注意：简化实现仅处理ASCII字符，完整实现需要Unicode大小写映射表
pub fn php_mb_strtoupper(str: Value, encoding: Value, allocator: Allocator) !Value {
    _ = encoding;
    if (!str.isString()) return str;

    const php_str = str.asString();
    const data = php_str.data;

    var result_data = try std.ArrayList(u8).initCapacity(allocator, data.len + 4);
    defer result_data.deinit(allocator);

    var i: usize = 0;
    while (i < data.len) {
        if (i + 1 < data.len and data[i] == 0xC3 and data[i + 1] == 0x9F) {
            try result_data.appendSlice(allocator, "SS");
            i += 2;
            continue;
        }

        const byte = data[i];
        if (byte >= 'a' and byte <= 'z') {
            try result_data.append(allocator, byte - 32);
        } else {
            try result_data.append(allocator, byte);
        }
        i += 1;
    }

    const result = try PHPString.init(allocator, result_data.items);
    return Value.initString(result);
}

/// mb_strtolower - 转换为小写（支持多字节字符）
/// 注意：简化实现仅处理ASCII字符
pub fn php_mb_strtolower(str: Value, encoding: Value, allocator: Allocator) !Value {
    _ = encoding;
    if (!str.isString()) return str;

    const php_str = str.asString();
    const data = php_str.data;

    const result_data = try allocator.alloc(u8, data.len);
    errdefer allocator.free(result_data);

    var i: usize = 0;
    while (i < data.len) {
        const byte = data[i];
        // 只转换ASCII字母
        if (byte >= 'A' and byte <= 'Z') {
            result_data[i] = byte + 32;
        } else {
            result_data[i] = byte;
        }
        i += 1;
    }

    const result = try PHPString.init(allocator, result_data);
    allocator.free(result_data);
    return Value.initString(result);
}

/// mb_detect_encoding - 简化实现：检测字符串编码
/// 规则：
///   - 空/纯 ASCII -> "ASCII"
///   - 合法 UTF-8 -> "UTF-8"
///   - 其他 -> false
pub fn php_mb_detect_encoding(str_val: Value, encodings: Value, strict: Value, allocator: Allocator) !Value {
    _ = encodings;
    _ = strict;
    if (!str_val.isString()) return Value.initBool(false);
    const data = str_val.asString().data;
    // 检查是否全部 ASCII
    var is_ascii = true;
    for (data) |b| {
        if (b >= 0x80) { is_ascii = false; break; }
    }
    if (is_ascii) {
        const s = try PHPString.init(allocator, "ASCII");
        return Value.initString(s);
    }
    // 验证 UTF-8
    if (std.unicode.utf8ValidateSlice(data)) {
        const s = try PHPString.init(allocator, "UTF-8");
        return Value.initString(s);
    }
    return Value.initBool(false);
}

/// substr_count - 计算子字符串出现次数
pub fn php_substr_count(haystack: Value, needle: Value, offset: Value, length: Value) !Value {
    _ = offset;
    _ = length;
    if (!haystack.isString() or !needle.isString()) return Value.initInt(0);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0) return Value.initInt(0);
    if (need.length > hay.length) return Value.initInt(0);

    var count: i64 = 0;
    var pos: usize = 0;

    while (pos <= hay.length - need.length) {
        if (std.mem.eql(u8, hay.data[pos .. pos + need.length], need.data)) {
            count += 1;
            pos += need.length;
        } else {
            pos += 1;
        }
    }

    return Value.initInt(count);
}

// Mbstring 和字符串函数包装器
fn wrapBuiltin_mb_strlen(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const encoding = if (args.len >= 2) args[1] else Value.initNull();
    return php_mb_strlen(args[0], encoding);
}

fn wrapBuiltin_mb_substr(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const length = if (args.len >= 3) args[2] else Value.initNull();
    const encoding = if (args.len >= 4) args[3] else Value.initNull();
    return php_mb_substr(args[0], args[1], length, encoding, allocator);
}

fn wrapBuiltin_mb_strtoupper(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const encoding = if (args.len >= 2) args[1] else Value.initNull();
    return php_mb_strtoupper(args[0], encoding, allocator);
}

fn wrapBuiltin_mb_strtolower(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const encoding = if (args.len >= 2) args[1] else Value.initNull();
    return php_mb_strtolower(args[0], encoding, allocator);
}

fn wrapBuiltin_substr_count(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const offset = if (args.len >= 3) args[2] else Value.initNull();
    const length = if (args.len >= 4) args[3] else Value.initNull();
    return php_substr_count(args[0], args[1], offset, length);
}

fn wrapBuiltin_ucfirst(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ucfirst(args[0], allocator);
}

fn wrapBuiltin_lcfirst(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_lcfirst(args[0], allocator);
}

fn wrapBuiltin_ucwords(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const delimiters = if (args.len >= 2) args[1] else Value.initNull();
    return php_ucwords(args[0], delimiters, allocator);
}

fn wrapBuiltin_strrpos(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const offset = if (args.len >= 3) args[2] else Value.initInt(0);
    return php_strrpos(args[0], args[1], offset);
}

fn wrapBuiltin_strripos(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const offset = if (args.len >= 3) args[2] else Value.initInt(0);
    return php_strripos(args[0], args[1], offset);
}

fn wrapBuiltin_str_word_count(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const format = if (args.len >= 2) args[1] else Value.initInt(0);
    const charlist = if (args.len >= 3) args[2] else Value.initNull();
    return php_str_word_count(args[0], format, charlist);
}

fn wrapBuiltin_substr(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const length = if (args.len >= 3) args[2] else Value.initNull();
    return php_substr(args[0], args[1], length, allocator);
}

fn wrapBuiltin_strpos(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const offset = if (args.len >= 3) args[2] else Value.initInt(0);
    return php_strpos(args[0], args[1], offset);
}

// 数学函数包装器
fn wrapBuiltin_floor(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_floor(args[0]);
}

fn wrapBuiltin_ceil(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ceil(args[0]);
}

fn wrapBuiltin_sin(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_sin(args[0]);
}

fn wrapBuiltin_cos(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_cos(args[0]);
}

fn wrapBuiltin_tan(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_tan(args[0]);
}

fn wrapBuiltin_log(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_log(args[0]);
}

fn wrapBuiltin_exp(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_exp(args[0]);
}

fn wrapBuiltin_hypot(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    return php_hypot(args[0], args[1]);
}

fn wrapBuiltin_pow(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    return php_pow(args[0], args[1]);
}

fn wrapBuiltin_min(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_min(args);
}

fn wrapBuiltin_max(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_max(args);
}

// 字符串函数包装器
fn wrapBuiltin_stripos(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const offset = if (args.len >= 3) args[2] else Value.initInt(0);
    return php_stripos(args[0], args[1], offset);
}

fn wrapBuiltin_strstr(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    return php_strstr(args[0], args[1], allocator);
}

fn wrapBuiltin_str_split(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const length = if (args.len >= 2) args[1] else Value.initInt(1);
    return php_str_split(args[0], length, allocator);
}

fn wrapBuiltin_implode(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const glue = if (args.len >= 1) args[0] else Value.initNull();
    const pieces = if (args.len >= 2) args[1] else Value.initNull();
    return php_implode(glue, pieces, allocator);
}

fn wrapBuiltin_explode(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    const limit = if (args.len >= 3) args[2] else Value.initNull();
    return php_explode(args[0], args[1], limit, allocator);
}

/// get_debug_type - 获取变量的调试类型（PHP 8+）
pub fn php_get_debug_type(val: Value, allocator: Allocator) !Value {
    if (val.isNull()) {
        return Value.initString(try PHPString.init(allocator, "null"));
    }
    if (val.isBool()) {
        return Value.initString(try PHPString.init(allocator, "bool"));
    }
    if (val.isInt()) {
        return Value.initString(try PHPString.init(allocator, "int"));
    }
    if (val.isFloat()) {
        return Value.initString(try PHPString.init(allocator, "float"));
    }
    if (val.isString()) {
        return Value.initString(try PHPString.init(allocator, "string"));
    }
    if (val.isArray()) {
        return Value.initString(try PHPString.init(allocator, "array"));
    }
    if (Value_isObject(val)) {
        const obj = Value_asObject(val);
        if (obj.class_meta) |meta| {
            return Value.initString(try PHPString.init(allocator, meta.name));
        }
        return Value.initString(try PHPString.init(allocator, "object"));
    }
    if (val.isFunction()) {
        return Value.initString(try PHPString.init(allocator, "Closure"));
    }
    return Value.initString(try PHPString.init(allocator, "unknown"));
}

/// call_user_func - 调用回调函数
pub fn php_call_user_func(args: []const Value, allocator: Allocator) !Value {
    if (args.len < 1) return error.InvalidArgumentCount;

    const callback = args[0];
    const call_args = args[1..];
    return php_invoke_callable(callback, call_args, allocator);
}

/// call_user_func_array - 使用数组参数调用回调函数
pub fn php_call_user_func_array(callback: Value, args_arr: Value, allocator: Allocator) !Value {
    return php_invoke_callable_args_array(callback, args_arr, allocator);
}

// 更多函数包装器
fn wrapBuiltin_is_callable(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_is_callable(args[0]);
}

fn wrapBuiltin_get_debug_type(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_get_debug_type(args[0], allocator);
}

fn wrapBuiltin_call_user_func(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_call_user_func(args, allocator);
}

fn wrapBuiltin_call_user_func_array(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 2) return error.InvalidArgumentCount;
    return php_call_user_func_array(args[0], args[1], allocator);
}

fn wrapBuiltin_ob_gzhandler(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const phase = if (args.len >= 2) args[1] else Value.initInt(0);
    return php_ob_gzhandler(args[0], phase, allocator);
}

fn wrapBuiltin_ob_start(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    const callback = if (args.len >= 1) args[0] else Value.initNull();
    return php_ob_start(callback, allocator);
}

fn wrapBuiltin_mysqli_connect(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    const host = if (args.len >= 1) args[0] else Value.initNull();
    const user = if (args.len >= 2) args[1] else Value.initNull();
    const password = if (args.len >= 3) args[2] else Value.initNull();
    const db = if (args.len >= 4) args[3] else Value.initNull();
    const port = if (args.len >= 5) args[4] else Value.initNull();
    const socket = if (args.len >= 6) args[5] else Value.initNull();
    return php_mysqli_connect(host, user, password, db, port, socket, allocator);
}

fn wrapBuiltin_token_get_all(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const flags = if (args.len >= 2) args[1] else Value.initInt(0);
    return php_token_get_all(args[0], flags, allocator);
}

fn wrapBuiltin_ob_get_contents(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len != 0) return error.InvalidArgumentCount;
    return php_ob_get_contents(allocator);
}

fn wrapBuiltin_ob_end_clean(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len != 0) return error.InvalidArgumentCount;
    return php_ob_end_clean();
}

fn wrapBuiltin_ob_get_clean(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len != 0) return error.InvalidArgumentCount;
    return php_ob_get_clean(allocator);
}

fn wrapBuiltin_ob_get_level(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len != 0) return error.InvalidArgumentCount;
    return php_ob_get_level();
}

fn wrapBuiltin_ob_flush(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len != 0) return error.InvalidArgumentCount;
    return php_ob_flush();
}

fn wrapBuiltin_ob_end_flush(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len != 0) return error.InvalidArgumentCount;
    return php_ob_end_flush();
}

fn wrapBuiltin_ob_get_length(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len != 0) return error.InvalidArgumentCount;
    return php_ob_get_length();
}

fn wrapBuiltin_ob_get_status(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    const full_status = if (args.len >= 1) args[0] else Value.initBool(false);
    return php_ob_get_status(full_status, allocator);
}

fn wrapBuiltin_ob_implicit_flush(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    const flag = if (args.len >= 1) args[0] else Value.initBool(true);
    return php_ob_implicit_flush(flag);
}

fn wrapBuiltin_get_resource_id(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_get_resource_id(args[0]);
}

fn wrapBuiltin_compact(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    return php_compact(args, allocator);
}

fn wrapBuiltin_extract(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const flags = if (args.len >= 2) args[1] else Value.initInt(0);
    const prefix = if (args.len >= 3) args[2] else Value.initNull();
    return php_extract(args[0], flags, prefix, allocator);
}

// 字符操作函数包装器
fn wrapBuiltin_ord(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_ord(args[0]);
}

fn wrapBuiltin_chr(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_chr(args[0], allocator);
}

fn wrapBuiltin_md5(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const raw = if (args.len >= 2) args[1] else Value.initBool(false);
    return php_md5(args[0], raw, allocator);
}

fn wrapBuiltin_sha1(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const raw = if (args.len >= 2) args[1] else Value.initBool(false);
    return php_sha1(args[0], raw, allocator);
}

fn wrapBuiltin_crc32(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_crc32(args[0]);
}

fn wrapBuiltin_strrev(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_strrev(args[0], allocator);
}

fn wrapBuiltin_ltrim(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const mask = if (args.len >= 2) args[1] else Value.initNull();
    return php_ltrim(args[0], mask, allocator);
}

fn wrapBuiltin_rtrim(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    const mask = if (args.len >= 2) args[1] else Value.initNull();
    return php_rtrim(args[0], mask, allocator);
}

/// addslashes - 使用反斜线引用字符串
pub fn php_addslashes(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const data = php_str.data;

    // 计算结果长度
    var result_len: usize = 0;
    for (data) |c| {
        // 需要转义的字符: ', ", \, NUL
        if (c == '\'' or c == '"' or c == '\\' or c == 0) {
            result_len += 2;
        } else {
            result_len += 1;
        }
    }

    const result = try allocator.alloc(u8, result_len);
    errdefer allocator.free(result);

    var pos: usize = 0;
    for (data) |c| {
        if (c == '\'' or c == '"' or c == '\\' or c == 0) {
            result[pos] = '\\';
            result[pos + 1] = if (c == 0) '0' else c;
            pos += 2;
        } else {
            result[pos] = c;
            pos += 1;
        }
    }

    const php_result = try PHPString.init(allocator, result);
    allocator.free(result);
    return Value.initString(php_result);
}

/// stripslashes - 反引用一个引用字符串
pub fn php_stripslashes(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const data = php_str.data;

    // 计算结果长度（最多等于原长度）
    const result = try allocator.alloc(u8, data.len);
    errdefer allocator.free(result);

    var pos: usize = 0;
    var i: usize = 0;
    while (i < data.len) {
        if (data[i] == '\\' and i + 1 < data.len) {
            const next = data[i + 1];
            if (next == '0') {
                result[pos] = 0;
                pos += 1;
                i += 2;
            } else if (next == '\'' or next == '"' or next == '\\') {
                result[pos] = next;
                pos += 1;
                i += 2;
            } else {
                result[pos] = data[i];
                pos += 1;
                i += 1;
            }
        } else {
            result[pos] = data[i];
            pos += 1;
            i += 1;
        }
    }

    const php_result = try PHPString.init(allocator, result[0..pos]);
    allocator.free(result);
    return Value.initString(php_result);
}

fn wrapBuiltin_addslashes(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_addslashes(args[0], allocator);
}

fn wrapBuiltin_stripslashes(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    if (args.len < 1) return error.InvalidArgumentCount;
    return php_stripslashes(args[0], allocator);
}

// ============================================================================
// 新增缺失的内置函数
// ============================================================================

/// error_get_last - 获取最后发生的错误
pub fn php_error_get_last(allocator: Allocator) !Value {
    // 简化实现：返回 null（表示没有错误）
    // PHP CLI 中如果没有发生错误也返回 null
    _ = allocator;
    return Value.initNull();
}

/// rewind - 倒回文件指针的位置
pub fn php_rewind(handle: Value) !Value {
    if (!handle.isInt()) return Value.initBool(false);
    const handle_ptr = handle.asInt();
    if (handle_ptr <= 1) return Value.initBool(false);

    const file_handle: *std.Io.File = @ptrFromInt(@as(usize, @intCast(handle_ptr)));
    file_handle.seekTo(0) catch return Value.initBool(false);
    return Value.initBool(true);
}

/// gethostbyaddr - 获取指定IP地址对应的主机名
pub fn php_gethostbyaddr(ip: Value, allocator: Allocator) !Value {
    if (!ip.isString()) return Value.initBool(false);
    const ip_str = ip.asString().data;
    // 简化实现：对于本地地址直接返回
    if (std.mem.eql(u8, ip_str, "127.0.0.1")) {
        return Value.initString(try PHPString.init(allocator, "localhost"));
    }
    // 其他地址返回原 IP（模拟 PHP 在无法反解时的行为）
    return Value.initString(try PHPString.init(allocator, ip_str));
}

/// hash_file - 使用给定文件的内容生成哈希值
pub fn php_hash_file(algo: Value, filename: Value, allocator: Allocator) !Value {
    if (!algo.isString() or !filename.isString()) return Value.initBool(false);

    const algo_str = algo.asString().data;
    const fname = filename.asString().data;

    // 读取文件内容
    const file = std.Io.Dir.cwd().openFile(getIo(), fname, .{}) catch return Value.initBool(false);
    defer file.close(getIo());

    const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch return Value.initBool(false);
    defer allocator.free(content);

    // 复用已有的 php_hash 逻辑
    const content_val = Value.initString(try PHPString.init(allocator, content));
    return php_hash(
        Value.initString(try PHPString.init(allocator, algo_str)),
        content_val,
        allocator,
    );
}

/// get_resource_type - 返回资源类型
pub fn php_get_resource_type(res: Value, allocator: Allocator) !Value {
    _ = res;
    return Value.initString(try PHPString.init(allocator, "Unknown"));
}

/// stream_register_wrapper - 注册一个用 PHP 类实现的 URL 封装协议
pub fn php_stream_register_wrapper(protocol: Value, classname: Value, allocator: Allocator) !Value {
    _ = protocol;
    _ = classname;
    _ = allocator;
    return Value.initBool(true);
}

