const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const ArrayKey = types.ArrayKey;
const gc = @import("gc.zig");
const exceptions = @import("exceptions.zig");
const ExceptionFactory = exceptions.ExceptionFactory;
// VM 前向声明
const VM = @import("vm.zig").VM;

// PCRE2 C 声明 (使用 8 位版本)
const pcre2_code = opaque {};
const pcre2_match_data = opaque {};

extern fn pcre2_compile_8(
    pattern: [*]const u8,
    pattern_length: usize,
    options: c_uint,
    *c_int,
    [*c]usize,
    ?*anyopaque,
) ?*pcre2_code;

extern fn pcre2_code_free_8(?*pcre2_code) void;
extern fn pcre2_match_data_create_from_pattern_8(?*const pcre2_code, ?*anyopaque) ?*pcre2_match_data;
extern fn pcre2_match_data_free_8(?*pcre2_match_data) void;
extern fn pcre2_match_8(
    ?*const pcre2_code,
    [*]const u8,
    usize,
    c_int,
    c_uint,
    ?*pcre2_match_data,
    ?*anyopaque,
) c_int;
extern fn pcre2_pattern_info_8(?*const pcre2_code, c_int, ?*c_int) c_int;
extern fn pcre2_get_ovector_pointer_8(?*pcre2_match_data) [*]usize;

// PCRE2 常量
const PCRE2_ANCHORED = 0x00000010;
const PCRE2_SUBSTITUTE_OVERFLOW_LENGTH = 0x00000020;
const PCRE2_SUBSTITUTE_EXTENDED = 0x00000040;
const PCRE2_INFO_CAPTURECOUNT = 0x20000000;
const PCRE2_ERROR_NOMATCH = -1;
const PCRE2_UNSET: usize = std.math.maxInt(usize);
const PCRE2_CASELESS = 0x00000008;
const PCRE2_MULTILINE = 0x00000002;
const PCRE2_DOTALL = 0x00000004;
const PCRE2_EXTENDED = 0x00000008;
const PCRE2_UTF = 0x00000000;

/// 解析结果结构
const ParsedPattern = struct {
    pattern: []const u8,
    options: c_uint,
};

/// 辅助函数：解析 PHP 风格的正则表达式模式（去除分隔符并提取修饰符）
/// PHP preg_* 函数接受的模式格式为: /pattern/modifiers
fn parsePHPRegexPattern(pattern: []const u8) ParsedPattern {
    var result = ParsedPattern{
        .pattern = pattern,
        .options = PCRE2_UTF | PCRE2_DOTALL,
    };

    if (pattern.len == 0) return result;

    // 找到第一个非空白字符作为分隔符
    var start: usize = 0;
    while (start < pattern.len and pattern[start] == ' ') : (start += 1) {}

    if (start >= pattern.len) return result;

    const delimiter = pattern[start];

    // 查找结束分隔符（跳过转义的相同字符和括号等）
    var end: usize = start + 1;
    var paren_depth: i32 = 0;
    var in_escape = false;

    while (end < pattern.len) : (end += 1) {
        const ch = pattern[end];

        if (in_escape) {
            in_escape = false;
            continue;
        }

        if (ch == '\\') {
            in_escape = true;
            continue;
        }

        if (ch == '(' or ch == '[' or ch == '{') {
            paren_depth += 1;
        } else if (ch == ')' or ch == ']' or ch == '}') {
            paren_depth -= 1;
        } else if (ch == delimiter and paren_depth == 0) {
            // 找到结束分隔符
            break;
        }
    }

    // 提取模式部分（不包括分隔符）
    // 如果没有找到结束分隔符，返回原始模式（PCRE2 会处理错误）
    if (end >= pattern.len) {
        result.pattern = pattern[start + 1 ..];
        return result;
    }
    result.pattern = pattern[start + 1 .. end];

    // 解析修饰符
    const modifiers = pattern[end + 1 ..];
    for (modifiers) |ch| {
        switch (ch) {
            'i' => result.options |= PCRE2_CASELESS,
            'm' => result.options |= PCRE2_MULTILINE,
            's' => result.options |= PCRE2_DOTALL,
            'x' => result.options |= PCRE2_EXTENDED,
            ' ' => break, // 修饰符后的空格表示结束
            else => {},
        }
    }

    return result;
}

// PCRE2 模式封装
const PCRE2Pattern = struct {
    re: *pcre2_code,
    match_data: *pcre2_match_data,
    allocator: std.mem.Allocator,

    /// 编译正则表达式
    pub fn compile(allocator: std.mem.Allocator, pattern: []const u8, options: c_uint) !PCRE2Pattern {
        var errcode: c_int = 0;
        var erroffset: usize = 0;

        const re_ptr = pcre2_compile_8(
            pattern.ptr,
            pattern.len,
            options,
            &errcode,
            &erroffset,
            null,
        );

        if (re_ptr == null) {
            return error.CompileFailed;
        }
        const re = re_ptr.?;

        const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
            pcre2_code_free_8(re);
            return error.MatchDataCreateFailed;
        };

        return PCRE2Pattern{
            .re = re,
            .match_data = match_data,
            .allocator = allocator,
        };
    }

    /// 释放资源
    pub fn deinit(self: *PCRE2Pattern) void {
        pcre2_match_data_free_8(self.match_data);
        pcre2_code_free_8(self.re);
    }

    /// 执行匹配
    pub fn match(self: *PCRE2Pattern, subject: []const u8, start_offset: usize, options: c_uint) c_int {
        const rc = pcre2_match_8(
            self.re,
            subject.ptr,
            subject.len,
            @as(c_int, @intCast(start_offset)),
            options | PCRE2_SUBSTITUTE_OVERFLOW_LENGTH,
            self.match_data,
            null,
        );
        return rc;
    }

    /// 获取 ovector 指针
    fn getOvector(self: *PCRE2Pattern) [*]usize {
        return pcre2_get_ovector_pointer_8(self.match_data);
    }

    /// 获取匹配组数量
    pub fn getGroupCount(self: *PCRE2Pattern) usize {
        var capturecount: c_int = 0;
        _ = pcre2_pattern_info_8(self.re, PCRE2_INFO_CAPTURECOUNT, &capturecount);
        return @intCast(capturecount);
    }

    /// 获取所有匹配组
    pub fn getMatches(self: *PCRE2Pattern, allocator: std.mem.Allocator, subject: []const u8, ovector: []usize) !*PHPArray {
        const result = try allocator.create(PHPArray);
        errdefer {
            result.deinit(allocator);
            allocator.destroy(result);
        }
        result.* = PHPArray.init(allocator);

        const group_count = self.getGroupCount();
        var i: usize = 0;
        while (i <= group_count and i * 2 + 1 < ovector.len) : (i += 1) {
            const start = ovector[i * 2];
            const end = ovector[i * 2 + 1];

            // PCRE2_UNSET: 捕获组未参与匹配时 start/end 均为 maxInt(usize)
            if (start == PCRE2_UNSET or end == PCRE2_UNSET) continue;
            // 边界检查
            if (start > end or end > subject.len) continue;

            const matched_str = subject[start..end];
            const match_value = try createStringValue(allocator, matched_str);
            try result.set(allocator, ArrayKey{ .integer = @as(i64, @intCast(i)) }, match_value);
        }

        return result;
    }

    /// 获取所有匹配（全局）
    pub fn getAllMatches(self: *PCRE2Pattern, allocator: std.mem.Allocator, subject: []const u8, options: c_uint) !*PHPArray {
        const result = try allocator.create(PHPArray);
        errdefer {
            result.deinit(allocator);
            allocator.destroy(result);
        }
        result.* = PHPArray.init(allocator);

        var offset: usize = 0;

        while (offset < subject.len) {
            const rc = pcre2_match_8(
                self.re,
                subject.ptr,
                subject.len,
                @as(c_int, @intCast(offset)),
                options,
                self.match_data,
                null,
            );

            if (rc == PCRE2_ERROR_NOMATCH) break;
            if (rc < 0) return error.MatchFailed;

            const ovec = self.getOvector();
            const match_array = try self.getMatches(allocator, subject, ovec[0 .. @as(usize, @intCast(rc)) * 2]);
            const box = try allocator.create(types.gc.Box(*PHPArray));
            box.* = .{
                .ref_count = 1,
                .gc_info = .{},
                .data = match_array,
            };
            try result.push(allocator, Value.fromBox(box, Value.TYPE_ARRAY));

            const match_end = ovec[1];
            if (match_end == PCRE2_UNSET or match_end == offset) {
                break;
            }
            offset = match_end;
        }

        return result;
    }
};

/// 辅助函数：创建字符串 Value
fn createStringValue(allocator: std.mem.Allocator, str: []const u8) !Value {
    const php_string = try PHPString.init(allocator, str);
    errdefer php_string.deinit(allocator);

    const box = try allocator.create(types.gc.Box(*PHPString));
    errdefer allocator.destroy(box);

    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = php_string,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

/// preg_match 实现
pub fn pregMatchFn(vm: *VM, args: []const Value) !Value {
    const min_args: usize = 2;
    if (args.len < min_args) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, min_args, @as(u32, @intCast(args.len)), "preg_match", "builtin", 0);
        _ = try vm.throwException(exception);
        vm.preg_last_error = -1; // Set error code for argument count
        return error.ArgumentCountMismatch;
    }

    const pattern_val = args[0];
    const subject_val = args[1];
    const matches_ref = if (args.len > 2) args[2] else null;
    _ = if (args.len > 3) args[3] else null;
    const offset_val = if (args.len > 4) args[4] else null;

    if (pattern_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "preg_match() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        vm.preg_last_error = -2; // Set error code for type error
        return error.InvalidArgumentType;
    }

    if (subject_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "preg_match() expects parameter 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        vm.preg_last_error = -2; // Set error code for type error
        return error.InvalidArgumentType;
    }

    const pattern = pattern_val.getAsString().data.data;
    const subject = subject_val.getAsString().data.data;
    const offset: usize = if (offset_val != null and offset_val.?.getTag() == .integer) @as(usize, @intCast(offset_val.?.asInt())) else 0;

    const clean_pattern = parsePHPRegexPattern(pattern);

    var pcre_pattern = PCRE2Pattern.compile(vm.allocator, clean_pattern.pattern, clean_pattern.options) catch {
        vm.preg_last_error = -256; // PCRE2_ERROR_NOSUBSTRING or similar for compilation failure
        return Value.initInt(0); // Return 0 for compilation failure
    };
    defer pcre_pattern.deinit();

    const rc = pcre2_match_8(
        pcre_pattern.re,
        subject.ptr,
        subject.len,
        @as(c_int, @intCast(offset)),
        0,
        pcre_pattern.match_data,
        null,
    );

    if (rc == PCRE2_ERROR_NOMATCH) {
        vm.preg_last_error = 0; // No error
        return Value.initInt(0);
    }

    if (rc < 0) {
        vm.preg_last_error = rc; // Set PCRE2 error code
        return Value.initInt(0);
    }

    // 填充matches数组
    if (matches_ref) |ref| {
        if (ref.getTag() == .array) {
            const matches_box = ref.getAsArray();
            const matches_arr = matches_box.data;

            matches_arr.deinit(vm.allocator);
            matches_arr.* = PHPArray.init(vm.allocator);

            const ovec = pcre_pattern.getOvector();
            var i: usize = 0;
            while (i < @as(usize, @intCast(rc))) : (i += 1) {
                const start = ovec[i * 2];
                const end = ovec[i * 2 + 1];
                if (start == PCRE2_UNSET or end == PCRE2_UNSET) continue;
                if (start < subject.len and end <= subject.len and start <= end) {
                    const capture = subject[start..end];
                    const capture_val = try createStringValue(vm.allocator, capture);
                    try matches_arr.push(vm.allocator, capture_val);
                }
            }
        }
    }

    vm.preg_last_error = 0; // No error
    return Value.initInt(1);
}

/// preg_match_all 实现
pub fn pregMatchAllFn(vm: *VM, args: []const Value) !Value {
    const min_args: usize = 3;
    if (args.len < min_args) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, min_args, @as(u32, @intCast(args.len)), "preg_match_all", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const pattern_val = args[0];
    const subject_val = args[1];
    const matches_ref = if (args.len > 2) args[2] else null;

    if (pattern_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "preg_match_all() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (subject_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "preg_match_all() expects parameter 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const pattern = pattern_val.getAsString().data.data;
    const subject = subject_val.getAsString().data.data;

    const parsed = parsePHPRegexPattern(pattern);
    var pcre_pattern = try PCRE2Pattern.compile(vm.allocator, parsed.pattern, parsed.options);
    defer pcre_pattern.deinit();

    // 临时存储所有匹配
    var all_matches = std.ArrayListUnmanaged(std.ArrayListUnmanaged([]const u8)).empty;
    defer {
        for (all_matches.items) |*match_groups| {
            match_groups.deinit(vm.allocator);
        }
        all_matches.deinit(vm.allocator);
    }

    var match_count: i64 = 0;
    var offset: usize = 0;

    while (offset <= subject.len) {
        const rc = pcre2_match_8(
            pcre_pattern.re,
            subject.ptr,
            subject.len,
            @as(c_int, @intCast(offset)),
            0,
            pcre_pattern.match_data,
            null,
        );

        if (rc == PCRE2_ERROR_NOMATCH or rc < 0) break;

        match_count += 1;
        const ovec = pcre_pattern.getOvector();

        var match_groups = std.ArrayListUnmanaged([]const u8){ .items = &.{}, .capacity = 0 };
        var i: usize = 0;
        while (i < @as(usize, @intCast(rc))) : (i += 1) {
            const start = ovec[i * 2];
            const end = ovec[i * 2 + 1];
            if (start == PCRE2_UNSET or end == PCRE2_UNSET) continue;
            if (start < subject.len and end <= subject.len and start <= end) {
                const capture = subject[start..end];
                try match_groups.append(vm.allocator, capture);
            }
        }
        try all_matches.append(vm.allocator, match_groups);

        const match_end = ovec[1];
        if (match_end == PCRE2_UNSET or match_end == offset) {
            offset += 1;
        } else {
            offset = match_end;
        }
    }

    // 填充matches数组（PREG_PATTERN_ORDER格式）
    if (matches_ref) |ref| {
        if (ref.getTag() == .array) {
            const matches_box = ref.getAsArray();
            const matches_arr = matches_box.data;

            // 重新初始化数组
            matches_arr.deinit(vm.allocator);
            matches_arr.* = PHPArray.init(vm.allocator);

            if (all_matches.items.len > 0) {
                const num_groups = all_matches.items[0].items.len;
                var group_idx: usize = 0;
                while (group_idx < num_groups) : (group_idx += 1) {
                    // 创建组数组
                    const group_box = try vm.allocator.create(gc.Box(*PHPArray));
                    const group_arr = try vm.allocator.create(PHPArray);
                    group_arr.* = PHPArray.init(vm.allocator);
                    group_box.* = .{
                        .ref_count = 1,
                        .gc_info = .{},
                        .data = group_arr,
                    };

                    for (all_matches.items) |match_groups| {
                        if (group_idx < match_groups.items.len) {
                            const capture_val = try createStringValue(vm.allocator, match_groups.items[group_idx]);
                            try group_arr.push(vm.allocator, capture_val);
                        }
                    }
                    try matches_arr.push(vm.allocator, Value.fromBox(group_box, Value.TYPE_ARRAY));
                }
            }
        }
    }

    return Value.initInt(match_count);
}

/// preg_replace 实现
pub fn pregReplaceFn(vm: *VM, args: []const Value) !Value {
    const min_args: usize = 3;
    if (args.len < min_args) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, min_args, @as(u32, @intCast(args.len)), "preg_replace", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const pattern_val = args[0];
    const replacement_val = args[1];
    const subject_val = args[2];
    const limit_val = if (args.len > 3) args[3] else null;

    const limit: usize = if (limit_val != null and limit_val.?.getTag() == .integer) @as(usize, @intCast(limit_val.?.asInt())) else std.math.maxInt(usize);

    if (pattern_val.getTag() == .string and replacement_val.getTag() == .string and subject_val.getTag() == .string) {
        const pattern = pattern_val.getAsString().data.data;
        const replacement = replacement_val.getAsString().data.data;
        const subject = subject_val.getAsString().data.data;

        const parsed = parsePHPRegexPattern(pattern);
        var pcre_pattern = try PCRE2Pattern.compile(vm.allocator, parsed.pattern, parsed.options);
        defer pcre_pattern.deinit();

        const output_len: usize = subject.len * 2;
        var buffer = try vm.allocator.alloc(u8, output_len);
        errdefer vm.allocator.free(buffer);

        var subject_offset: usize = 0;
        var output_offset: usize = 0;
        var replace_count: usize = 0;

        while (subject_offset < subject.len and replace_count < limit) {
            const rc = pcre2_match_8(
                pcre_pattern.re,
                subject.ptr,
                subject.len,
                @as(c_int, @intCast(subject_offset)),
                PCRE2_SUBSTITUTE_OVERFLOW_LENGTH,
                pcre_pattern.match_data,
                null,
            );

            if (rc == PCRE2_ERROR_NOMATCH) break;
            if (rc < 0) return error.MatchFailed;

            const ovec = pcre_pattern.getOvector();
            const match_start = ovec[0];
            const match_end = ovec[1];

            // PCRE2_UNSET 检查
            if (match_start == PCRE2_UNSET or match_end == PCRE2_UNSET) break;
            if (match_start > subject.len or match_end > subject.len or match_start > match_end) break;

            const before_len = match_start;
            if (before_len > subject_offset) {
                const copy_len = before_len - subject_offset;
                if (output_offset + copy_len > buffer.len) {
                    buffer = try vm.allocator.realloc(buffer, buffer.len * 2);
                }
                @memcpy(buffer[output_offset..][0..copy_len], subject[subject_offset..before_len]);
                output_offset += copy_len;
            }

            if (output_offset + replacement.len > buffer.len) {
                buffer = try vm.allocator.realloc(buffer, buffer.len * 2);
            }
            @memcpy(buffer[output_offset..][0..replacement.len], replacement);
            output_offset += replacement.len;

            subject_offset = match_end;
            replace_count += 1;
        }

        if (subject_offset < subject.len) {
            const remaining = subject.len - subject_offset;
            if (output_offset + remaining > buffer.len) {
                buffer = try vm.allocator.realloc(buffer, buffer.len + remaining);
            }
            @memcpy(buffer[output_offset .. output_offset + remaining], subject[subject_offset..]);
            output_offset += remaining;
        }

        const result = try vm.allocator.realloc(buffer, output_offset);
        return try createStringValue(vm.allocator, result);
    }

    return Value.initNull();
}

/// preg_replace_callback 实现
pub fn pregReplaceCallbackFn(vm: *VM, args: []const Value) !Value {
    const min_args: usize = 3;
    if (args.len < min_args) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, min_args, @as(u32, @intCast(args.len)), "preg_replace_callback", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const pattern_val = args[0];
    const callback_val = args[1];
    const subject_val = args[2];
    const limit_val = if (args.len > 3) args[3] else null;

    if (pattern_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "preg_replace_callback() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (subject_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "preg_replace_callback() expects parameter 3 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const pattern = pattern_val.getAsString().data.data;
    const subject = subject_val.getAsString().data.data;
    const limit: usize = if (limit_val != null and limit_val.?.getTag() == .integer) @as(usize, @intCast(limit_val.?.asInt())) else std.math.maxInt(usize);

    const parsed = parsePHPRegexPattern(pattern);
    var pcre_pattern = try PCRE2Pattern.compile(vm.allocator, parsed.pattern, parsed.options);
    defer pcre_pattern.deinit();

    const output_len: usize = subject.len * 2;
    var buffer = try vm.allocator.alloc(u8, output_len);
    errdefer vm.allocator.free(buffer);

    var subject_offset: usize = 0;
    var output_offset: usize = 0;
    var replace_count: usize = 0;

    while (subject_offset < subject.len and replace_count < limit) {
        const rc = pcre2_match_8(
            pcre_pattern.re,
            subject.ptr,
            subject.len,
            @as(c_int, @intCast(subject_offset)),
            0,
            pcre_pattern.match_data,
            null,
        );

        if (rc == PCRE2_ERROR_NOMATCH) break;
        if (rc < 0) return error.MatchFailed;

        const ovec = pcre_pattern.getOvector();
        const match_start = ovec[0];
        const match_end = ovec[1];

        // PCRE2_UNSET 检查：未匹配时跳过
        if (match_start == PCRE2_UNSET or match_end == PCRE2_UNSET) break;
        // 边界检查
        if (match_start > subject.len or match_end > subject.len or match_start > match_end) break;

        const before_len = match_start;
        if (before_len > subject_offset) {
            const copy_len = before_len - subject_offset;
            if (output_offset + copy_len > buffer.len) {
                buffer = try vm.allocator.realloc(buffer, buffer.len * 2);
            }
            @memcpy(buffer[output_offset..][0..copy_len], subject[subject_offset..before_len]);
            output_offset += copy_len;
        }

        const match_str = subject[match_start..match_end];

        const match_array = try pcre_pattern.getMatches(vm.allocator, match_str, ovec[0 .. @as(usize, @intCast(rc)) * 2]);

        const box = try vm.allocator.create(types.gc.Box(*PHPArray));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = match_array,
        };
        const match_value = Value.fromBox(box, Value.TYPE_ARRAY);

        const callback_result = switch (callback_val.getTag()) {
            .native_function => blk: {
                const function: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(callback_val.getAsNativeFunc()));
                break :blk try function(vm, &[_]Value{match_value});
            },
            .user_function => try vm.callUserFunction(callback_val.getAsUserFunc().data, &[_]Value{match_value}),
            .closure => try vm.callClosure(callback_val.getAsClosure().data, &[_]Value{match_value}),
            .arrow_function => try vm.callArrowFunction(callback_val.getAsArrowFunc().data, &[_]Value{match_value}),
            else => {
                const exception = try ExceptionFactory.createTypeError(vm.allocator, "preg_replace_callback() expects parameter 2 to be a valid callback", "builtin", 0);
                _ = try vm.throwException(exception);
                return error.InvalidArgumentType;
            },
        };

        const replacement = switch (callback_result.getTag()) {
            .string => callback_result.getAsString().data.data,
            else => "",
        };

        if (output_offset + replacement.len > buffer.len) {
            buffer = try vm.allocator.realloc(buffer, buffer.len * 2);
        }
        @memcpy(buffer[output_offset..][0..replacement.len], replacement);
        output_offset += replacement.len;

        vm.releaseValue(callback_result);

        subject_offset = match_end;
        replace_count += 1;
    }

    if (subject_offset < subject.len) {
        const remaining = subject.len - subject_offset;
        if (output_offset + remaining > buffer.len) {
            buffer = try vm.allocator.realloc(buffer, buffer.len + remaining);
        }
        @memcpy(buffer[output_offset .. output_offset + remaining], subject[subject_offset..]);
        output_offset += remaining;
    }

    const result = try vm.allocator.realloc(buffer, output_offset);
    return try createStringValue(vm.allocator, result);
}

/// preg_split 实现
pub fn pregSplitFn(vm: *VM, args: []const Value) !Value {
    const min_args: usize = 2;
    if (args.len < min_args) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, min_args, @as(u32, @intCast(args.len)), "preg_split", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const pattern_val = args[0];
    const subject_val = args[1];
    const limit_val = if (args.len > 2) args[2] else null;
    const flags_val = if (args.len > 3) args[3] else null;

    if (pattern_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "preg_split() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (subject_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "preg_split() expects parameter 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const pattern = pattern_val.getAsString().data.data;
    const subject = subject_val.getAsString().data.data;
    const limit: usize = if (limit_val != null and limit_val.?.getTag() == .integer) @as(usize, @intCast(limit_val.?.asInt())) else std.math.maxInt(usize);
    const delim_capture = flags_val != null and flags_val.?.getTag() == .integer and (flags_val.?.asInt() & PREG_SPLIT_DELIM_CAPTURE) != 0;

    const parsed = parsePHPRegexPattern(pattern);
    var pcre_pattern = try PCRE2Pattern.compile(vm.allocator, parsed.pattern, parsed.options);
    defer pcre_pattern.deinit();

    const result_array = try vm.allocator.create(PHPArray);
    errdefer {
        result_array.deinit(vm.allocator);
        vm.allocator.destroy(result_array);
    }
    result_array.* = PHPArray.init(vm.allocator);

    var offset: usize = 0;
    var split_count: usize = 0;

    while (offset < subject.len and split_count < limit) {
        const rc = pcre2_match_8(
            pcre_pattern.re,
            subject.ptr,
            subject.len,
            @as(c_int, @intCast(offset)),
            0,
            pcre_pattern.match_data,
            null,
        );

        if (rc == PCRE2_ERROR_NOMATCH) break;
        if (rc < 0) return error.MatchFailed;

        const ovec = pcre_pattern.getOvector();
        const match_start = ovec[0];
        const match_end = ovec[1];

        // PCRE2_UNSET 检查
        if (match_start == PCRE2_UNSET or match_end == PCRE2_UNSET) break;
        if (match_start > subject.len or match_end > subject.len or match_start > match_end) break;

        const before_len = match_start;
        if (before_len > offset) {
            const part = subject[offset..match_start];
            const part_value = try createStringValue(vm.allocator, part);
            try result_array.push(vm.allocator, part_value);
            vm.releaseValue(part_value);
            split_count += 1;
        }

        if (delim_capture) {
            const delim = subject[match_start..match_end];
            const delim_value = try createStringValue(vm.allocator, delim);
            try result_array.push(vm.allocator, delim_value);
            vm.releaseValue(delim_value);
            split_count += 1;
        }

        offset = match_end;
    }

    if (offset < subject.len and split_count < limit) {
        const part = subject[offset..];
        const part_value = try createStringValue(vm.allocator, part);
        try result_array.push(vm.allocator, part_value);
        vm.releaseValue(part_value);
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_array,
    };

    return Value.fromBox(box, Value.TYPE_ARRAY);
}

/// preg_grep 实现
pub fn pregGrepFn(vm: *VM, args: []const Value) !Value {
    const min_args: usize = 2;
    if (args.len < min_args) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, min_args, @as(u32, @intCast(args.len)), "preg_grep", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const pattern_val = args[0];
    const input_val = args[1];
    const flags_val = if (args.len > 2) args[2] else null;

    if (pattern_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "preg_grep() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (input_val.getTag() != .array) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "preg_grep() expects parameter 2 to be array", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const pattern = pattern_val.getAsString().data.data;
    const input_arr = input_val.getAsArray().data;
    const flags: i64 = if (flags_val != null and flags_val.?.getTag() == .integer) flags_val.?.asInt() else 0;
    const invert = (flags & 1) != 0;

    const parsed = parsePHPRegexPattern(pattern);
    var pcre_pattern = try PCRE2Pattern.compile(vm.allocator, parsed.pattern, parsed.options);
    defer pcre_pattern.deinit();

    const result_box = try vm.allocator.create(gc.Box(*PHPArray));
    const result_arr = try vm.allocator.create(PHPArray);
    result_arr.* = PHPArray.init(vm.allocator);
    result_box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_arr,
    };

    var iter = input_arr.*.getElements().iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        const str_val = if (value.getTag() == .string)
            value.getAsString().data.data
        else
            "";

        const rc = pcre2_match_8(pcre_pattern.re, str_val.ptr, str_val.len, 0, 0, pcre_pattern.match_data, null);
        const matched = (rc >= 0);
        const should_include = if (invert) !matched else matched;

        if (should_include) {
            try result_arr.*.set(vm.allocator, key, value);
        }
    }

    return Value.fromBox(result_box, Value.TYPE_ARRAY);
}

/// preg_quote 实现
pub fn pregQuoteFn(vm: *VM, args: []const Value) !Value {
    const min_args: usize = 1;
    if (args.len < min_args) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, min_args, @as(u32, @intCast(args.len)), "preg_quote", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const str_val = args[0];
    const delimiter_val = if (args.len > 1) args[1] else null;

    if (str_val.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "preg_quote() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const str = str_val.getAsString().data.data;
    const delimiter = if (delimiter_val != null and delimiter_val.?.getTag() == .string) delimiter_val.?.getAsString().data.data[0] else 0;

    const specials = ".\\+*?[^]$(){}=!<>|:";
    var escape_table: [256]u8 = undefined;
    @memset(escape_table[0..], 0);
    for (specials) |ch| {
        escape_table[@as(usize, @intCast(ch))] = 1;
    }

    var result_len: usize = str.len;
    for (str) |ch| {
        const needs_escape = ch == '\\' or ch == delimiter or escape_table[@as(usize, @intCast(ch))] == 1;
        if (needs_escape) {
            result_len += 1;
        }
    }

    const result = try vm.allocator.alloc(u8, result_len);
    errdefer vm.allocator.free(result);

    var j: usize = 0;
    for (str) |ch| {
        const needs_escape = ch == '\\' or ch == delimiter or escape_table[@as(usize, @intCast(ch))] == 1;
        if (needs_escape) {
            result[j] = '\\';
            j += 1;
        }
        result[j] = ch;
        j += 1;
    }

    return try createStringValue(vm.allocator, result);
}

/// preg_filter 实现 - 类似 preg_replace，但只返回匹配的元素
/// 对于数组输入，只返回发生替换的元素
pub fn pregFilterFn(vm: *VM, args: []const Value) !Value {
    const min_args: usize = 3;
    if (args.len < min_args) {
        const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, min_args, @as(u32, @intCast(args.len)), "preg_filter", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.ArgumentCountMismatch;
    }

    const pattern_val = args[0];
    const replacement_val = args[1];
    const subject_val = args[2];
    const limit_val = if (args.len > 3) args[3] else null;

    const limit: usize = if (limit_val != null and limit_val.?.getTag() == .integer) @as(usize, @intCast(limit_val.?.asInt())) else std.math.maxInt(usize);

    // 处理数组输入
    if (subject_val.getTag() == .array) {
        const subject_box = subject_val.getAsArray();
        const subject_arr = subject_box.data;

        const result_box = try vm.allocator.create(gc.Box(*PHPArray));
        const result_arr = try vm.allocator.create(PHPArray);
        result_arr.* = PHPArray.init(vm.allocator);
        result_box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = result_arr,
        };

        // 遍历数组，只保留匹配的元素
        var iter = subject_arr.iterator();
        while (iter.next()) |entry| {
            if (entry.value.getTag() == .string) {
                const subject = entry.value.getAsString().data.data;

                if (pattern_val.getTag() == .string and replacement_val.getTag() == .string) {
                    const pattern = pattern_val.getAsString().data.data;
                    const replacement = replacement_val.getAsString().data.data;

                    const parsed = parsePHPRegexPattern(pattern);
                    var pcre_pattern = PCRE2Pattern.compile(vm.allocator, parsed.pattern, parsed.options) catch continue;
                    defer pcre_pattern.deinit();

                    // 检查是否有匹配
                    const rc = pcre2_match_8(
                        pcre_pattern.re,
                        subject.ptr,
                        subject.len,
                        0,
                        0,
                        pcre_pattern.match_data,
                        null,
                    );

                    // 只有匹配时才进行替换并添加到结果
                    if (rc >= 0) {
                        // 执行替换（复用 preg_replace 逻辑）
                        const output_len: usize = subject.len * 2;
                        var buffer = try vm.allocator.alloc(u8, output_len);
                        errdefer vm.allocator.free(buffer);

                        var subject_offset: usize = 0;
                        var output_offset: usize = 0;
                        var replace_count: usize = 0;

                        while (subject_offset < subject.len and replace_count < limit) {
                            const rc2 = pcre2_match_8(
                                pcre_pattern.re,
                                subject.ptr,
                                subject.len,
                                @as(c_int, @intCast(subject_offset)),
                                PCRE2_SUBSTITUTE_OVERFLOW_LENGTH,
                                pcre_pattern.match_data,
                                null,
                            );

                            if (rc2 == PCRE2_ERROR_NOMATCH) break;
                            if (rc2 < 0) break;

                            const ovec = pcre_pattern.getOvector();
                            const match_start = ovec[0];
                            const match_end = ovec[1];

                            // PCRE2_UNSET 检查：未匹配时跳过
                            if (match_start == PCRE2_UNSET or match_end == PCRE2_UNSET) break;
                            // 边界检查
                            if (match_start > subject.len or match_end > subject.len or match_start > match_end) break;

                            const before_len = match_start;
                            if (before_len > subject_offset) {
                                const copy_len = before_len - subject_offset;
                                if (output_offset + copy_len > buffer.len) {
                                    buffer = try vm.allocator.realloc(buffer, buffer.len * 2);
                                }
                                @memcpy(buffer[output_offset..][0..copy_len], subject[subject_offset..before_len]);
                                output_offset += copy_len;
                            }

                            if (output_offset + replacement.len > buffer.len) {
                                buffer = try vm.allocator.realloc(buffer, buffer.len * 2);
                            }
                            @memcpy(buffer[output_offset..][0..replacement.len], replacement);
                            output_offset += replacement.len;

                            subject_offset = match_end;
                            replace_count += 1;
                        }

                        if (subject_offset < subject.len) {
                            const remaining = subject.len - subject_offset;
                            if (output_offset + remaining > buffer.len) {
                                buffer = try vm.allocator.realloc(buffer, buffer.len + remaining);
                            }
                            @memcpy(buffer[output_offset .. output_offset + remaining], subject[subject_offset..]);
                            output_offset += remaining;
                        }

                        const result = try vm.allocator.realloc(buffer, output_offset);
                        const result_val = try createStringValue(vm.allocator, result);

                        // 保持原始键
                        switch (entry.key) {
                            .integer => try result_arr.set(vm.allocator, entry.key, result_val),
                            .string => try result_arr.push(vm.allocator, result_val),
                        }
                    }
                }
            }
        }

        return Value.fromBox(result_box, Value.TYPE_ARRAY);
    }

    // 处理字符串输入（与 preg_replace 相同）
    if (pattern_val.getTag() == .string and replacement_val.getTag() == .string and subject_val.getTag() == .string) {
        const pattern = pattern_val.getAsString().data.data;
        const replacement = replacement_val.getAsString().data.data;
        const subject = subject_val.getAsString().data.data;

        const parsed = parsePHPRegexPattern(pattern);
        var pcre_pattern = try PCRE2Pattern.compile(vm.allocator, parsed.pattern, parsed.options);
        defer pcre_pattern.deinit();

        // 检查是否有匹配
        const rc_check = pcre2_match_8(
            pcre_pattern.re,
            subject.ptr,
            subject.len,
            0,
            0,
            pcre_pattern.match_data,
            null,
        );

        // 如果没有匹配，返回 null（preg_filter 的特性）
        if (rc_check == PCRE2_ERROR_NOMATCH or rc_check < 0) {
            return Value.initNull();
        }

        // 有匹配，执行替换
        const output_len: usize = subject.len * 2;
        var buffer = try vm.allocator.alloc(u8, output_len);
        errdefer vm.allocator.free(buffer);

        var subject_offset: usize = 0;
        var output_offset: usize = 0;
        var replace_count: usize = 0;

        while (subject_offset < subject.len and replace_count < limit) {
            const rc = pcre2_match_8(
                pcre_pattern.re,
                subject.ptr,
                subject.len,
                @as(c_int, @intCast(subject_offset)),
                PCRE2_SUBSTITUTE_OVERFLOW_LENGTH,
                pcre_pattern.match_data,
                null,
            );

            if (rc == PCRE2_ERROR_NOMATCH) break;
            if (rc < 0) return error.MatchFailed;

            const ovec = pcre_pattern.getOvector();
            const match_start = ovec[0];
            const match_end = ovec[1];

            // PCRE2_UNSET 检查
            if (match_start == PCRE2_UNSET or match_end == PCRE2_UNSET) break;
            if (match_start > subject.len or match_end > subject.len or match_start > match_end) break;

            const before_len = match_start;
            if (before_len > subject_offset) {
                const copy_len = before_len - subject_offset;
                if (output_offset + copy_len > buffer.len) {
                    buffer = try vm.allocator.realloc(buffer, buffer.len * 2);
                }
                @memcpy(buffer[output_offset..][0..copy_len], subject[subject_offset..before_len]);
                output_offset += copy_len;
            }

            if (output_offset + replacement.len > buffer.len) {
                buffer = try vm.allocator.realloc(buffer, buffer.len * 2);
            }
            @memcpy(buffer[output_offset..][0..replacement.len], replacement);
            output_offset += replacement.len;

            subject_offset = match_end;
            replace_count += 1;
        }

        if (subject_offset < subject.len) {
            const remaining = subject.len - subject_offset;
            if (output_offset + remaining > buffer.len) {
                buffer = try vm.allocator.realloc(buffer, buffer.len + remaining);
            }
            @memcpy(buffer[output_offset .. output_offset + remaining], subject[subject_offset..]);
            output_offset += remaining;
        }

        const result = try vm.allocator.realloc(buffer, output_offset);
        return try createStringValue(vm.allocator, result);
    }

    return Value.initNull();
}

/// preg_last_error 实现 - 返回当前协程的错误状态
pub fn pregLastErrorFn(vm: *VM, _: []const Value) !Value {
    return Value.initInt(vm.preg_last_error);
}

// 标志常量
pub const PREG_OFFSET_CAPTURE = 256;
pub const PREG_SPLIT_DELIM_CAPTURE = 2;
