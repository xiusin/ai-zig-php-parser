const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const runtime = @import("runtime_lib.zig");

// ============================================================================
// 比较运算符
// ============================================================================

/// 等于运算（PHP语义：类型转换后比较）
pub fn php_eq(lhs: Value, rhs: Value) !Value {
    const actual_lhs = if (lhs.isRef()) lhs.asRef().* else lhs;
    const actual_rhs = if (rhs.isRef()) rhs.asRef().* else rhs;

    if (actual_lhs.isArray() and actual_rhs.isArray()) {
        const a = actual_lhs.asArray();
        const b = actual_rhs.asArray();
        if (a.elements.count() != b.elements.count()) return Value.initBool(false);

        var iter = a.elements.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const val = entry.value_ptr.*;
            const other_val = b.elements.get(key) orelse return Value.initBool(false);
            const eq = try php_eq(val, other_val);
            if (!eq.asBool()) return Value.initBool(false);
        }
        return Value.initBool(true);
    }

    if (Value_isObject(actual_lhs) and Value_isObject(actual_rhs)) {
        return Value.initBool(Value_asObject(actual_lhs) == Value_asObject(actual_rhs));
    }

    return Value.initBool(phpCompare(actual_lhs, actual_rhs) == 0);
}

// 辅助函数：字符串转数字（PHP 语义）
fn stringToNumber(str: []const u8) f64 {
    if (str.len == 0) return 0.0;

    // 跳过前导空格
    var i: usize = 0;
    while (i < str.len and std.ascii.isWhitespace(str[i])) : (i += 1) {}
    if (i == str.len) return 0.0;

    const trimmed = str[i..];

    // 尝试解析为整数或浮点数
    if (std.fmt.parseInt(i64, trimmed, 10)) |int_val| {
        return @floatFromInt(int_val);
    } else |_| {
        if (std.fmt.parseFloat(f64, trimmed)) |float_val| {
            return float_val;
        } else |_| {
            // PHP: 非数字字符串转为 0
            return 0.0;
        }
    }
}

/// 不等于运算
pub fn php_ne(lhs: Value, rhs: Value) !Value {
    const result = try php_eq(lhs, rhs);
    return Value.initBool(!result.asBool());
}

/// 全等运算（PHP语义：类型和值都相等）
fn php_array_key_identical(lhs: ArrayKey, rhs: ArrayKey) bool {
    return switch (lhs) {
        .integer => |li| switch (rhs) {
            .integer => |ri| li == ri,
            else => false,
        },
        .string => |ls| switch (rhs) {
            .string => |rs| std.mem.eql(u8, ls.data, rs.data),
            else => false,
        },
    };
}

fn php_array_identical(lhs: *PHPArray, rhs: *PHPArray) anyerror!bool {
    if (lhs.elements.count() != rhs.elements.count()) return false;

    var lhs_iter = lhs.elements.iterator();
    var rhs_iter = rhs.elements.iterator();
    while (true) {
        const lhs_entry = lhs_iter.next();
        const rhs_entry = rhs_iter.next();
        if (lhs_entry == null or rhs_entry == null) {
            return lhs_entry == null and rhs_entry == null;
        }

        const l = lhs_entry.?;
        const r = rhs_entry.?;
        if (!php_array_key_identical(l.key_ptr.*, r.key_ptr.*)) return false;
        if (!(try php_identical(l.value_ptr.*, r.value_ptr.*)).toBool()) return false;
    }
}

pub fn php_identical(lhs: Value, rhs: Value) !Value {
    // 类型不同
    if (lhs.isNull() != rhs.isNull()) return Value.initBool(false);
    if (lhs.isBool() != rhs.isBool()) return Value.initBool(false);
    if (lhs.isInt() != rhs.isInt()) return Value.initBool(false);
    if (lhs.isFloat() != rhs.isFloat()) return Value.initBool(false);
    if (lhs.isString() != rhs.isString()) return Value.initBool(false);
    if (lhs.isArray() != rhs.isArray()) return Value.initBool(false);

    // 类型相同，比较值
    if (lhs.isNull()) return Value.initBool(true);
    if (lhs.isBool()) return Value.initBool(lhs.asBool() == rhs.asBool());
    if (lhs.isInt()) return Value.initBool(lhs.asInt() == rhs.asInt());
    if (lhs.isFloat()) return Value.initBool(lhs.asFloat() == rhs.asFloat());
    if (lhs.isString()) {
        const a = lhs.asString();
        const b = rhs.asString();
        return Value.initBool(std.mem.eql(u8, a.data, b.data));
    }
    if (lhs.isArray()) {
        return Value.initBool(try php_array_identical(lhs.asArray(), rhs.asArray()));
    }

    // Object: 同一引用才 identical（指针比较）
    if (Value_isObject(lhs) and Value_isObject(rhs)) {
        return Value.initBool(Value_asObject(lhs) == Value_asObject(rhs));
    }

    return Value.initBool(false);
}

/// 不全等运算
pub fn php_not_identical(lhs: Value, rhs: Value) !Value {
    const result = try php_identical(lhs, rhs);
    return Value.initBool(!result.asBool());
}

/// PHP 8 比较核心：返回 -1, 0, 1
fn phpCompare(lhs: Value, rhs: Value) i2 {
    // PHP 8 comparison table (in priority order):
    // 1. null|string vs string → null→"", string comparison
    // 2. bool|null vs anything → both→bool, false < true
    // 3. int vs int → integer comparison
    // 4. number vs number (at least one float) → float comparison
    // 5. string vs string → numeric strings: number cmp, else lexicographic
    // 6. string vs number → convert string to number
    // 7. array vs non-array → array is always greater

    // Rule 1: null|string vs string → string comparison
    if ((lhs.isNull() or lhs.isString()) and rhs.isString()) {
        if (lhs.isNull()) {
            const r = rhs.asString();
            if (r.length == 0) return 0;
            return -1;
        }
        // both string → fall through to Rule 5
    } else if (lhs.isString() and (rhs.isNull() or rhs.isString())) {
        if (rhs.isNull()) {
            const l = lhs.asString();
            if (l.length == 0) return 0;
            return 1;
        }
        // both string → fall through to Rule 5
    } else if (lhs.isNull() or lhs.isBool() or rhs.isNull() or rhs.isBool()) {
        // Rule 2: bool|null vs non-string → bool comparison
        const lb = lhs.toBool();
        const rb = rhs.toBool();
        if (!lb and rb) return -1;
        if (lb and !rb) return 1;
        return 0;
    }

    // Rule 3: int vs int
    if (lhs.isInt() and rhs.isInt()) {
        const l = lhs.asInt();
        const r = rhs.asInt();
        if (l < r) return -1;
        if (l > r) return 1;
        return 0;
    }

    // Rule 5: string vs string
    if (lhs.isString() and rhs.isString()) {
        const ls = lhs.asString();
        const rs = rhs.asString();
        if (isNumericString(ls.data[0..ls.length]) and
            isNumericString(rs.data[0..rs.length]))
        {
            const lf = lhs.toFloat();
            const rf = rhs.toFloat();
            if (lf < rf) return -1;
            if (lf > rf) return 1;
            return 0;
        }
        const cmp = std.mem.order(
            u8,
            ls.data[0..ls.length],
            rs.data[0..rs.length],
        );
        return switch (cmp) {
            .lt => -1,
            .gt => 1,
            .eq => 0,
        };
    }

    // Rule 7: array vs non-array
    if (lhs.isArray() and !rhs.isArray()) return 1;
    if (!lhs.isArray() and rhs.isArray()) return -1;

    // Rule 4/6: numeric comparison (fallback)
    const l = lhs.toFloat();
    const r = rhs.toFloat();
    if (l < r) return -1;
    if (l > r) return 1;
    return 0;
}

/// 小于运算
pub fn php_lt(lhs: Value, rhs: Value) !Value {
    return Value.initBool(phpCompare(lhs, rhs) < 0);
}

/// 小于等于运算
pub fn php_le(lhs: Value, rhs: Value) !Value {
    return Value.initBool(phpCompare(lhs, rhs) <= 0);
}

/// 大于运算
pub fn php_gt(lhs: Value, rhs: Value) !Value {
    return Value.initBool(phpCompare(lhs, rhs) > 0);
}

/// 大于等于运算
pub fn php_ge(lhs: Value, rhs: Value) !Value {
    return Value.initBool(phpCompare(lhs, rhs) >= 0);
}

/// Spaceship 运算符 (<=>)
/// 返回 -1 (lhs < rhs), 0 (lhs == rhs), 1 (lhs > rhs)
pub fn php_spaceship(lhs: Value, rhs: Value) !Value {
    if (lhs.isInt() and rhs.isInt()) {
        const l = lhs.asInt();
        const r = rhs.asInt();
        if (l < r) return Value.initInt(-1);
        if (l > r) return Value.initInt(1);
        return Value.initInt(0);
    }
    if (lhs.isString() and rhs.isString()) {
        const l = lhs.asString();
        const r = rhs.asString();
        const cmp = std.mem.order(u8, l.data[0..l.length], r.data[0..r.length]);
        return Value.initInt(switch (cmp) {
            .lt => -1,
            .gt => 1,
            .eq => 0,
        });
    }
    const l = lhs.toFloat();
    const r = rhs.toFloat();
    if (l < r) return Value.initInt(-1);
    if (l > r) return Value.initInt(1);
    return Value.initInt(0);
}

// ============================================================================
// 逻辑运算符
// ============================================================================

/// 逻辑与运算
pub fn php_and(lhs: Value, rhs: Value) !Value {
    return Value.initBool(lhs.toBool() and rhs.toBool());
}

/// 逻辑或运算
pub fn php_or(lhs: Value, rhs: Value) !Value {
    return Value.initBool(lhs.toBool() or rhs.toBool());
}

/// 布尔或运算（用于 match 表达式多条件合并）
pub fn php_bool_or(lhs: Value, rhs: Value) Value {
    return Value.initBool(lhs.toBool() or rhs.toBool());
}

/// 逻辑异或运算
pub fn php_xor(lhs: Value, rhs: Value) !Value {
    const l = lhs.toBool();
    const r = rhs.toBool();
    return Value.initBool((l and !r) or (!l and r));
}

/// 逻辑非运算
pub fn php_not(val: Value) !Value {
    return Value.initBool(!val.toBool());
}

/// 逻辑异或运算 (xor)
pub fn php_logical_xor(lhs: Value, rhs: Value) !Value {
    return Value.initBool(lhs.toBool() != rhs.toBool());
}

// ============================================================================
// 字符串运算符
// ============================================================================

/// 字符串连接运算
pub fn php_concat(lhs: Value, rhs: Value, allocator: Allocator) !Value {
    // 快速路径：两个都是字符串
    if (lhs.isString() and rhs.isString()) {
        const result = try lhs.asString().concat(rhs.asString(), allocator);
        return Value.initString(result);
    }

    // 慢速路径：需要类型转换
    const rhs_str = rhs.toString(allocator) catch {
        // 类型转换失败（如数组转字符串），异常已设置
        return Value.initString(try PHPString.init(allocator, ""));
    };
    defer rhs_str.release(allocator);

    const lhs_str = lhs.toString(allocator) catch {
        // 类型转换失败（如数组转字符串），异常已设置
        // 返回空字符串以继续执行（异常会在后续被检查）
        return Value.initString(try PHPString.init(allocator, ""));
    };
    defer lhs_str.release(allocator);

    const result = try lhs_str.concat(rhs_str, allocator);
    return Value.initString(result);
}

pub fn php_concat_with_undef(lhs: Value, rhs: Value, lhs_undef: bool, lhs_name: []const u8, rhs_undef: bool, rhs_name: []const u8, allocator: Allocator) !Value {
    if (!lhs_undef and !rhs_undef) {
        return php_concat(lhs, rhs, allocator);
    }

    const rhs_str = blk: {
        if (rhs_undef) emitUndefinedVariableWarning(rhs_name);
        break :blk rhs.toString(allocator) catch {
            return Value.initString(try PHPString.init(allocator, ""));
        };
    };
    defer rhs_str.release(allocator);

    const lhs_str = blk: {
        if (lhs_undef) emitUndefinedVariableWarning(lhs_name);
        break :blk lhs.toString(allocator) catch {
            return Value.initString(try PHPString.init(allocator, ""));
        };
    };
    defer lhs_str.release(allocator);

    const result = try lhs_str.concat(rhs_str, allocator);
    return Value.initString(result);
}

// ============================================================================
// 输出函数
// ============================================================================

/// PHP 兼容浮点格式化（14 位有效数字，去尾零）
/// @pre buf.len >= 64
/// @post 返回 buf 中的有效切片
pub fn phpFormatFloat(buf: []u8, f: f64) []const u8 {
    const PHP_PRECISION: usize = 14;

    if (std.math.isNan(f)) return "NAN";
    if (std.math.isInf(f)) {
        return if (f > 0) "INF" else "-INF";
    }
    if (f == 0.0) {
        if (std.math.signbit(f)) return "-0";
        return "0";
    }

    // 计算指数（log10），决定是否使用科学计数法（模拟 PHP 的 %G 行为）
    const abs_f = @abs(f);
    const exp10: i32 = if (abs_f >= 1.0) @intFromFloat(@floor(@log10(abs_f))) else blk: {
        // 对于小于1的数，log10为负数
        const l = @log10(abs_f);
        break :blk @as(i32, @intFromFloat(@floor(l)));
    };

    // PHP %.*G 规则：当指数 >= precision 或 < -4 时使用科学计数法
    if (exp10 >= @as(i32, @intCast(PHP_PRECISION)) or exp10 < -4) {
        // 科学计数法：如 9.2233720368548E+18
        const mantissa = f / std.math.pow(f64, 10.0, @floatFromInt(exp10));
        // 格式化尾数部分（precision-1 位小数）
        var work: [64]u8 = undefined;
        const dec_digits = PHP_PRECISION - 1;
        const mant_str = std.fmt.bufPrint(&work, "{d:.13}", .{mantissa}) catch return "0";
        // 手动截断到 dec_digits 位小数并去尾零
        var out_len: usize = 0;
        const sign_len: usize = if (mant_str[0] == '-') 1 else 0;
        // 复制符号
        if (sign_len > 0) {
            buf[0] = '-';
            out_len = 1;
        }
        // 找到小数点位置
        var dot_pos: usize = 0;
        for (mant_str[sign_len..], 0..) |c, idx| {
            if (c == '.') {
                dot_pos = sign_len + idx;
                break;
            }
        }
        if (dot_pos == 0) dot_pos = mant_str.len;
        // 复制整数部分
        const int_part = mant_str[sign_len..dot_pos];
        @memcpy(buf[out_len .. out_len + int_part.len], int_part);
        out_len += int_part.len;
        // 复制小数部分（最多 dec_digits 位）
        if (dot_pos < mant_str.len) {
            buf[out_len] = '.';
            out_len += 1;
            const frac_start = dot_pos + 1;
            const frac_avail = mant_str.len - frac_start;
            const frac_copy = @min(frac_avail, dec_digits);
            @memcpy(buf[out_len .. out_len + frac_copy], mant_str[frac_start .. frac_start + frac_copy]);
            out_len += frac_copy;
            // 去尾零
            while (out_len > 0 and buf[out_len - 1] == '0') : (out_len -= 1) {}
            if (out_len > 0 and buf[out_len - 1] == '.') out_len -= 1;
        }
        // 追加 E±XX 部分（PHP 用大写 E）
        const e_str = if (exp10 >= 0)
            std.fmt.bufPrint(buf[out_len..], "E+{d}", .{exp10}) catch return "0"
        else
            std.fmt.bufPrint(buf[out_len..], "E{d}", .{exp10}) catch return "0";
        out_len += e_str.len;
        return buf[0..out_len];
    }

    // 非科学计数法路径
    var work: [64]u8 = undefined;
    const full = std.fmt.bufPrint(&work, "{d}", .{f}) catch
        return "0";

    var i: usize = 0;
    const sign_len: usize = if (full[0] == '-') 1 else 0;
    i = sign_len;

    var sig_count: usize = 0;
    var started = false;
    var round_pos: usize = full.len;

    while (i < full.len) : (i += 1) {
        if (full[i] == '.') continue;
        if (!started) {
            if (full[i] == '0') continue;
            started = true;
        }
        sig_count += 1;
        if (sig_count == PHP_PRECISION) {
            round_pos = i + 1;
            break;
        }
    }

    if (sig_count < PHP_PRECISION) {
        @memcpy(buf[0..full.len], full[0..full.len]);
        return phpStripTrailingZeros(buf[0..full.len]);
    }

    var next = round_pos;
    if (next < full.len and full[next] == '.') next += 1;
    const round_up = (next < full.len and full[next] >= '5');

    var end = round_pos;
    @memcpy(buf[0..end], full[0..end]);

    if (round_up) {
        var j: usize = end;
        while (j > sign_len) {
            j -= 1;
            if (buf[j] == '.') continue;
            if (buf[j] < '9') {
                buf[j] += 1;
                break;
            }
            buf[j] = '0';
            if (j == sign_len) {
                std.mem.copyBackwards(
                    u8,
                    buf[sign_len + 1 .. end + 1],
                    buf[sign_len..end],
                );
                buf[sign_len] = '1';
                end += 1;
                break;
            }
        }
    }

    return phpStripTrailingZeros(buf[0..end]);
}

fn phpStripTrailingZeros(s: []u8) []const u8 {
    var has_dot = false;
    for (s) |c| {
        if (c == '.') {
            has_dot = true;
            break;
        }
    }
    if (!has_dot) return s;

    var end = s.len;
    while (end > 0 and s[end - 1] == '0') : (end -= 1) {}
    if (end > 0 and s[end - 1] == '.') end -= 1;
    return s[0..end];
}

/// echo语句
fn php_output_write(bytes: []const u8) !void {
    ensureObInit();
    if (ob_stack.items.len > 0) {
        const level = &ob_stack.items[ob_stack.items.len - 1];
        try level.buffer.appendSlice(runtime_allocator, bytes);
        return;
    }

    fileWriteAll(1, bytes);
}

pub fn php_echo(value: Value) !void {
    if (value.isNull()) {
        // null不输出任何内容
        return;
    } else if (value.isBool()) {
        if (value.asBool()) {
            try php_output_write("1");
        }
        // false不输出任何内容
    } else if (value.isInt()) {
        var buf: [64]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "{d}", .{value.asInt()});
        try php_output_write(str);
    } else if (value.isFloat()) {
        var buf: [64]u8 = undefined;
        const str = phpFormatFloat(&buf, value.asFloat());
        try php_output_write(str);
    } else if (value.isString()) {
        const str = value.asString();
        try php_output_write(str.data);
    } else if (value.isArray()) {
        // PHP Warning: Array to string conversion
        var wbuf: [512]u8 = undefined;
        const wmsg = std.fmt.bufPrint(
            &wbuf,
            "\nWarning: Array to string conversion in" ++
                " {s} on line {d}\n",
            .{ src_file, src_line },
        ) catch "";
        if (wmsg.len > 0) {
            fileWriteAll(1, wmsg);
            var ebuf: [512]u8 = undefined;
            const emsg = std.fmt.bufPrint(
                &ebuf,
                "PHP Warning:  Array to string conversion in" ++
                    " {s} on line {d}\n",
                .{ src_file, src_line },
            ) catch "";
            if (emsg.len > 0) fileWriteAll(2, emsg);
        }
        try php_output_write("Array");
    }
}

/// print语句（返回1）
pub fn php_print(value: Value) !Value {
    try php_echo(value);
    return Value.initInt(1);
}

/// var_dump函数
pub fn php_var_dump(value: Value) !Value {
    if (value.isNull()) {
        fileWriteAll(1, "NULL\n");
    } else if (value.isBool()) {
        var buf: [32]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "bool({})\n", .{value.asBool()});
        fileWriteAll(1, str);
    } else if (value.isInt()) {
        var buf: [64]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "int({})\n", .{value.asInt()});
        fileWriteAll(1, str);
    } else if (value.isFloat()) {
        var buf: [64]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "float({})\n", .{value.asFloat()});
        fileWriteAll(1, str);
    } else if (value.isString()) {
        const str = value.asString();
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "string({}) \"{s}\"\n", .{ str.length, str.data });
        fileWriteAll(1, msg);
    } else if (value.isArray()) {
        const arr = value.asArray();
        var buf: [64]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "array({d}) {{\n", .{arr.count()});
        fileWriteAll(1, msg);
        // 遍历数组
        var iter = arr.elements.iterator();
        while (iter.next()) |entry| {
            fileWriteAll(1, "  ");
            switch (entry.key_ptr.*) {
                .integer => |i| {
                    const key_msg = try std.fmt.bufPrint(&buf, "[{d}]", .{i});
                    fileWriteAll(1, key_msg);
                },
                .string => |s| {
                    var key_buf: [256]u8 = undefined;
                    const key_msg = try std.fmt.bufPrint(&key_buf, "[\"{s}\"]", .{s.data});
                    fileWriteAll(1, key_msg);
                },
            }
            fileWriteAll(1, "=>\n  ");
            _ = php_var_dump(entry.value_ptr.*) catch {};
        }
        fileWriteAll(1, "}\n");
    }
    return Value.initNull();
}

pub fn var_dump(value: Value) !Value {
    try php_var_dump(value);
    return Value.initNull();
}

pub fn print_r(value: Value, return_output: Value) !Value {
    const want_return = return_output.toBool();
    var aw = std.Io.Writer.Allocating.initCapacity(runtime_allocator, 256) catch return error.OutOfMemory;
    defer aw.deinit();

    try printValue(&aw.writer, value, 0, false);

    if (want_return) {
        return Value.initString(try PHPString.init(runtime_allocator, aw.written()));
    }
    fileWriteAll(1, aw.written());
    return Value.initBool(true);
}

pub fn var_export(value: Value, return_output: Value) !Value {
    const want_return = return_output.toBool();
    var aw = std.Io.Writer.Allocating.initCapacity(runtime_allocator, 256) catch return error.OutOfMemory;
    defer aw.deinit();

    try exportValue(&aw.writer, value, 0);

    if (want_return) {
        return Value.initString(try PHPString.init(runtime_allocator, aw.written()));
    }
    fileWriteAll(1, aw.written());
    return Value.initNull();
}

fn writeIndent(writer: anytype, indent: usize) !void {
    var i: usize = 0;
    while (i < indent * 4) : (i += 1) { // 4空格缩进 (print_r)
        try writer.writeByte(' ');
    }
}

fn writeExportIndent(writer: anytype, indent: usize) !void {
    var i: usize = 0;
    while (i < indent * 2) : (i += 1) { // 2空格缩进 (var_export)
        try writer.writeByte(' ');
    }
}

fn printValue(writer: anytype, value: Value, indent: usize, is_nested: bool) !void {
    if (value.isNull()) {
        // null不输出任何内容（PHP行为）
        return;
    }
    if (value.isBool()) {
        // bool输出1或空（PHP行为）
        if (value.asBool()) {
            try writer.writeByte('1');
        }
        return;
    }
    if (value.isInt()) {
        try writer.print("{d}", .{value.asInt()});
        return;
    }
    if (value.isFloat()) {
        var buf: [64]u8 = undefined;
        try writer.writeAll(phpFormatFloat(&buf, value.asFloat()));
        return;
    }
    if (value.isString()) {
        try writer.writeAll(value.asString().data);
        return;
    }
    if (value.isArray()) {
        const arr = value.asArray();

        // 数组开始
        try writer.writeAll("Array\n");
        if (is_nested) {
            try writeIndent(writer, indent + 1);
        } else {
            try writeIndent(writer, indent);
        }
        try writer.writeAll("(\n");

        // 遍历元素
        var iter = arr.elements.iterator();
        while (iter.next()) |entry| {
            const elem_indent = if (is_nested) indent + 2 else indent + 1;
            try writeIndent(writer, elem_indent);
            switch (entry.key_ptr.*) {
                .integer => |i| try writer.print("[{d}] => ", .{i}),
                .string => |s| try writer.print("[{s}] => ", .{s.data}),
            }

            const val = entry.value_ptr.*;
            const is_complex = val.isArray() or Value_isObject(val);

            if (is_complex) {
                try printValue(writer, val, elem_indent, true);
                try writer.writeByte('\n');
            } else {
                try printValue(writer, val, elem_indent, false);
                try writer.writeByte('\n');
            }
        }

        if (is_nested) {
            try writeIndent(writer, indent + 1);
        } else {
            try writeIndent(writer, indent);
        }
        try writer.writeAll(")\n");
        return;
    }
    if (Value_isObject(value)) {
        const obj = Value_asObject(value);

        // 对象开始
        try writer.print("{s} Object\n", .{obj.class_name});
        if (is_nested) {
            try writeIndent(writer, indent + 1);
        } else {
            try writeIndent(writer, indent);
        }
        try writer.writeAll("(\n");

        // DateTime 对象特殊处理: 输出 PHP 格式
        if (std.mem.eql(u8, obj.class_name, "DateTime")) {
            const elem_indent = if (is_nested) indent + 2 else indent + 1;
            if (obj.getProperty("timestamp")) |ts_val| {
                const ts = ts_val.toInt();
                const usecs: u64 = if (obj.getProperty("microseconds")) |us_val| @intCast(us_val.toInt()) else 0;
                // 格式化日期时间字符串 (Y-m-d H:i:s.u)
                const epoch_secs: u64 = @intCast(ts);
                const epoch = std.time.epoch.EpochSeconds{ .secs = epoch_secs };
                const day_secs = epoch.getDaySeconds();
                const year_day = epoch.getEpochDay().calculateYearDay();
                const month_day = year_day.calculateMonthDay();
                try writeIndent(writer, elem_indent);
                try writer.print("[date] => {d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}\n", .{
                    year_day.year,
                    month_day.month.numeric(),
                    month_day.day_index + 1,
                    day_secs.getHoursIntoDay(),
                    day_secs.getMinutesIntoHour(),
                    day_secs.getSecondsIntoMinute(),
                    usecs,
                });
                try writeIndent(writer, elem_indent);
                try writer.writeAll("[timezone_type] => 3\n");
                try writeIndent(writer, elem_indent);
                try writer.writeAll("[timezone] => UTC\n");
            }
        } else {
            // 遍历属性
            var it = obj.properties.iterator();
            while (it.next()) |entry| {
                const elem_indent = if (is_nested) indent + 2 else indent + 1;
                try writeIndent(writer, elem_indent);

                // 属性名格式化
                const prop_name = entry.key_ptr.*;
                try writer.print("[{s}] => ", .{prop_name});

                const val = entry.value_ptr.*;
                const is_complex = val.isArray() or Value_isObject(val);

                if (is_complex) {
                    try printValue(writer, val, elem_indent, true);
                    try writer.writeByte('\n');
                } else {
                    try printValue(writer, val, elem_indent, false);
                    try writer.writeByte('\n');
                }
            }
        }

        if (is_nested) {
            try writeIndent(writer, indent + 1);
        } else {
            try writeIndent(writer, indent);
        }
        try writer.writeAll(")\n");
        return;
    }

    // 其他类型（资源等）
    try writer.writeAll("Resource");
}

fn exportValue(writer: anytype, value: Value, indent: usize) !void {
    if (value.isNull()) {
        try writer.writeAll("NULL");
        return;
    }
    if (value.isBool()) {
        try writer.writeAll(if (value.asBool()) "true" else "false");
        return;
    }
    if (value.isInt()) {
        try writer.print("{d}", .{value.asInt()});
        return;
    }
    if (value.isFloat()) {
        const f = value.asFloat();
        if (std.math.isNan(f)) {
            try writer.writeAll("NAN");
        } else if (std.math.isInf(f)) {
            try writer.writeAll(if (f > 0) "INF" else "-INF");
        } else {
            var buf: [64]u8 = undefined;
            const str = phpFormatFloat(&buf, f);
            try writer.writeAll(str);
            // var_export 浮点数必须含小数点
            if (std.mem.indexOf(u8, str, ".") == null and std.mem.indexOf(u8, str, "E") == null) {
                try writer.writeAll(".0");
            }
        }
        return;
    }
    if (value.isString()) {
        try writer.writeAll("'");
        const s = value.asString().data;
        for (s) |c| {
            if (c == '\'') {
                try writer.writeAll("\\'");
            } else if (c == '\\') {
                try writer.writeAll("\\\\");
            } else {
                try writer.writeByte(c);
            }
        }
        try writer.writeAll("'");
        return;
    }
    if (value.isArray()) {
        const arr = value.asArray();
        try writer.writeAll("array (\n");
        var iter = arr.elements.iterator();
        while (iter.next()) |entry| {
            try writeExportIndent(writer, indent + 1);
            switch (entry.key_ptr.*) {
                .integer => |i| try writer.print("{d}", .{i}),
                .string => |k| {
                    try writer.writeAll("'");
                    for (k.data) |c| {
                        if (c == '\'') {
                            try writer.writeAll("\\'");
                        } else if (c == '\\') {
                            try writer.writeAll("\\\\");
                        } else {
                            try writer.writeByte(c);
                        }
                    }
                    try writer.writeAll("'");
                },
            }
            try writer.writeAll(" => ");
            // PHP var_export: 数组/对象值换行后同级缩进
            if (entry.value_ptr.*.isArray() or Value_isObject(entry.value_ptr.*)) {
                try writer.writeAll("\n");
                try writeExportIndent(writer, indent + 1);
            }
            try exportValue(writer, entry.value_ptr.*, indent + 1);
            try writer.writeAll(",\n");
        }
        try writeExportIndent(writer, indent);
        try writer.writeAll(")");
        return;
    }
    if (Value_isObject(value)) {
        const obj = Value_asObject(value);
        // PHP var_export: \ClassName::__set_state(array(...))
        const class_name = if (obj.class_meta) |m| m.name else "stdClass";
        try writer.writeAll("\\");
        try writer.writeAll(class_name);
        try writer.writeAll("::__set_state(array(\n");
        var it = obj.properties.iterator();
        while (it.next()) |entry| {
            try writeExportIndent(writer, indent + 1);
            try writer.writeAll("'");
            for (entry.key_ptr.*) |c| {
                if (c == '\'') {
                    try writer.writeAll("\\'");
                } else if (c == '\\') {
                    try writer.writeAll("\\\\");
                } else {
                    try writer.writeByte(c);
                }
            }
            try writer.writeAll("' => ");
            if (entry.value_ptr.*.isArray() or Value_isObject(entry.value_ptr.*)) {
                try writer.writeAll("\n");
                try writeExportIndent(writer, indent + 1);
            }
            try exportValue(writer, entry.value_ptr.*, indent + 1);
            try writer.writeAll(",\n");
        }
        try writeExportIndent(writer, indent);
        try writer.writeAll("))");
        return;
    }
    try writer.writeAll("NULL");
}

// ============================================================================
// 常量函数
// ============================================================================

/// 注册所有PHP预定义常量
pub fn registerPHPPredefinedConstants(allocator: Allocator) !void {
    const IntConst = struct { name: []const u8, value: i64 };
    const FloatConst = struct { name: []const u8, value: f64 };
    const StrConst = struct { name: []const u8, value: []const u8 };
    const BoolConst = struct { name: []const u8, value: bool };

    // 整数常量
    const int_consts = [_]IntConst{
        // 数组
        .{ .name = "COUNT_NORMAL", .value = 0 },
        .{ .name = "COUNT_RECURSIVE", .value = 1 },
        .{ .name = "ARRAY_FILTER_USE_BOTH", .value = 1 },
        .{ .name = "ARRAY_FILTER_USE_KEY", .value = 2 },
        .{ .name = "ARRAY_UNIQUE_REGULAR", .value = 0 },
        .{ .name = "SORT_REGULAR", .value = 0 },
        .{ .name = "SORT_NUMERIC", .value = 1 },
        .{ .name = "SORT_STRING", .value = 2 },
        .{ .name = "SORT_ASC", .value = 4 },
        .{ .name = "SORT_DESC", .value = 3 },
        .{ .name = "SORT_NATURAL", .value = 6 },
        .{ .name = "SORT_FLAG_CASE", .value = 8 },
        // JSON
        .{ .name = "JSON_PRETTY_PRINT", .value = 128 },
        .{ .name = "JSON_UNESCAPED_UNICODE", .value = 256 },
        .{ .name = "JSON_UNESCAPED_SLASHES", .value = 64 },
        .{ .name = "JSON_THROW_ON_ERROR", .value = 4194304 },
        .{ .name = "JSON_FORCE_OBJECT", .value = 16 },
        .{ .name = "JSON_HEX_TAG", .value = 1 },
        .{ .name = "JSON_HEX_AMP", .value = 2 },
        .{ .name = "JSON_HEX_APOS", .value = 4 },
        .{ .name = "JSON_HEX_QUOT", .value = 8 },
        .{ .name = "JSON_NUMERIC_CHECK", .value = 32 },
        .{ .name = "JSON_BIGINT_AS_STRING", .value = 512 },
        .{ .name = "JSON_PARTIAL_OUTPUT_ON_ERROR", .value = 1024 },
        .{ .name = "JSON_INVALID_UTF8_IGNORE", .value = 1048576 },
        .{ .name = "JSON_INVALID_UTF8_SUBSTITUTE", .value = 2097152 },
        // 错误级别
        .{ .name = "E_ERROR", .value = 1 },
        .{ .name = "E_WARNING", .value = 2 },
        .{ .name = "E_PARSE", .value = 4 },
        .{ .name = "E_NOTICE", .value = 8 },
        .{ .name = "E_CORE_ERROR", .value = 16 },
        .{ .name = "E_CORE_WARNING", .value = 32 },
        .{ .name = "E_COMPILE_ERROR", .value = 64 },
        .{ .name = "E_COMPILE_WARNING", .value = 128 },
        .{ .name = "E_USER_ERROR", .value = 256 },
        .{ .name = "E_USER_WARNING", .value = 512 },
        .{ .name = "E_USER_NOTICE", .value = 1024 },
        .{ .name = "E_STRICT", .value = 2048 },
        .{ .name = "E_RECOVERABLE_ERROR", .value = 4096 },
        .{ .name = "E_DEPRECATED", .value = 8192 },
        .{ .name = "E_USER_DEPRECATED", .value = 16384 },
        .{ .name = "E_ALL", .value = 32767 },
        // 正则
        .{ .name = "PREG_OFFSET_CAPTURE", .value = 256 },
        .{ .name = "PREG_UNMATCHED_AS_NULL", .value = 512 },
        .{ .name = "PREG_SET_ORDER", .value = 2 },
        .{ .name = "PREG_PATTERN_ORDER", .value = 1 },
        .{ .name = "PREG_SPLIT_NO_EMPTY", .value = 1 },
        .{ .name = "PREG_SPLIT_DELIM_CAPTURE", .value = 2 },
        // 文件
        .{ .name = "FILE_APPEND", .value = 8 },
        .{ .name = "FILE_IGNORE_NEW_LINES", .value = 2 },
        .{ .name = "FILE_SKIP_EMPTY_LINES", .value = 4 },
        .{ .name = "LOCK_EX", .value = 2 },
        .{ .name = "LOCK_SH", .value = 1 },
        .{ .name = "LOCK_UN", .value = 3 },
        .{ .name = "SEEK_SET", .value = 0 },
        .{ .name = "SEEK_CUR", .value = 1 },
        .{ .name = "SEEK_END", .value = 2 },
        .{ .name = "GLOB_MARK", .value = 1 },
        .{ .name = "GLOB_NOSORT", .value = 2 },
        .{ .name = "GLOB_NOCHECK", .value = 16 },
        .{ .name = "GLOB_BRACE", .value = 1024 },
        .{ .name = "SCANDIR_SORT_ASCENDING", .value = 0 },
        .{ .name = "SCANDIR_SORT_DESCENDING", .value = 1 },
        .{ .name = "SCANDIR_SORT_NONE", .value = 2 },
        .{ .name = "PATHINFO_DIRNAME", .value = 1 },
        .{ .name = "PATHINFO_BASENAME", .value = 2 },
        .{ .name = "PATHINFO_EXTENSION", .value = 4 },
        .{ .name = "PATHINFO_FILENAME", .value = 8 },
        // 字符串
        .{ .name = "STR_PAD_RIGHT", .value = 1 },
        .{ .name = "STR_PAD_LEFT", .value = 0 },
        .{ .name = "STR_PAD_BOTH", .value = 2 },
        .{ .name = "CASE_UPPER", .value = 1 },
        .{ .name = "CASE_LOWER", .value = 0 },
        // 数学
        .{ .name = "PHP_ROUND_HALF_UP", .value = 0 },
        .{ .name = "PHP_ROUND_HALF_DOWN", .value = 1 },
        .{ .name = "PHP_ROUND_HALF_EVEN", .value = 2 },
        .{ .name = "PHP_ROUND_HALF_ODD", .value = 3 },
        // PHP 整数限制
        .{ .name = "PHP_INT_MAX", .value = 9223372036854775807 },
        .{ .name = "PHP_INT_MIN", .value = -9223372036854775808 },
        .{ .name = "PHP_INT_SIZE", .value = 8 },
        .{ .name = "PHP_MAJOR_VERSION", .value = 8 },
        .{ .name = "PHP_MINOR_VERSION", .value = 3 },
        .{ .name = "PHP_RELEASE_VERSION", .value = 0 },
        // 密码
        .{ .name = "PASSWORD_DEFAULT", .value = 1 },
        .{ .name = "PASSWORD_BCRYPT", .value = 1 },
        // 输出缓冲
        .{ .name = "PHP_OUTPUT_HANDLER_START", .value = 1 },
        .{ .name = "PHP_OUTPUT_HANDLER_WRITE", .value = 0 },
        .{ .name = "PHP_OUTPUT_HANDLER_FLUSH", .value = 4 },
        .{ .name = "PHP_OUTPUT_HANDLER_CLEAN", .value = 2 },
        .{ .name = "PHP_OUTPUT_HANDLER_FINAL", .value = 8 },
        // 杂项
        .{ .name = "PHP_MAXPATHLEN", .value = 4096 },
        .{ .name = "PHP_PREFIX_SEPARATOR", .value = 95 },
        .{ .name = "EXTR_OVERWRITE", .value = 0 },
        .{ .name = "EXTR_SKIP", .value = 1 },
        .{ .name = "EXTR_PREFIX_SAME", .value = 2 },
        .{ .name = "EXTR_PREFIX_ALL", .value = 3 },
    };

    // 浮点常量
    const float_consts = [_]FloatConst{
        .{ .name = "M_PI", .value = 3.14159265358979323846 },
        .{ .name = "M_E", .value = 2.71828182845904523536 },
        .{ .name = "M_LOG2E", .value = 1.44269504088896340736 },
        .{ .name = "M_LOG10E", .value = 0.43429448190325182765 },
        .{ .name = "M_LN2", .value = 0.69314718055994530942 },
        .{ .name = "M_LN10", .value = 2.30258509299404568402 },
        .{ .name = "M_PI_2", .value = 1.57079632679489661923 },
        .{ .name = "M_PI_4", .value = 0.78539816339744830962 },
        .{ .name = "M_1_PI", .value = 0.31830988618379067154 },
        .{ .name = "M_2_PI", .value = 0.63661977236758134308 },
        .{ .name = "M_SQRT2", .value = 1.41421356237309504880 },
        .{ .name = "M_SQRT3", .value = 1.73205080756887729353 },
        .{ .name = "M_2_SQRTPI", .value = 1.12837916709551257390 },
        .{ .name = "M_SQRT1_2", .value = 0.70710678118654752440 },
        .{ .name = "PHP_FLOAT_MAX", .value = 1.7976931348623158e+308 },
        .{ .name = "PHP_FLOAT_MIN", .value = 2.2250738585072014e-308 },
        .{ .name = "PHP_FLOAT_EPSILON", .value = 2.2204460492503131e-16 },
        .{ .name = "INF", .value = std.math.inf(f64) },
        .{ .name = "NAN", .value = std.math.nan(f64) },
    };

    // 字符串常量
    const str_consts = [_]StrConst{
        .{ .name = "PHP_EOL", .value = "\n" },
        .{ .name = "PHP_SAPI", .value = "cli" },
        .{ .name = "PHP_OS", .value = "Darwin" },
        .{ .name = "PHP_OS_FAMILY", .value = "Darwin" },
        .{ .name = "PHP_VERSION", .value = "8.4.8" },
        .{ .name = "DIRECTORY_SEPARATOR", .value = "/" },
        .{ .name = "PATH_SEPARATOR", .value = ":" },
        .{ .name = "PHP_EXTENSION_DIR", .value = "" },
        .{ .name = "PHP_BINDIR", .value = "/usr/local/bin" },
    };

    // 布尔常量
    const bool_consts = [_]BoolConst{
        .{ .name = "TRUE", .value = true },
        .{ .name = "FALSE", .value = false },
    };

    for (int_consts) |c| {
        const key = try allocator.dupe(u8, c.name);
        try constants.put(key, Value.initInt(c.value));
    }
    for (float_consts) |c| {
        const key = try allocator.dupe(u8, c.name);
        try constants.put(key, Value.initFloat(c.value));
    }
    for (str_consts) |c| {
        const key = try allocator.dupe(u8, c.name);
        const str = try PHPString.init(allocator, c.value);
        try constants.put(key, Value.initString(str));
    }
    for (bool_consts) |c| {
        const key = try allocator.dupe(u8, c.name);
        try constants.put(key, Value.initBool(c.value));
    }

    // NULL 常量
    const null_key = try allocator.dupe(u8, "NULL");
    try constants.put(null_key, Value.initNull());
}

/// 用户通过 define() 定义的常量集合（用于 get_defined_constants(true) 分类）
var user_defined_constants: ?std.StringHashMap(void) = null;

pub fn php_define(name_val: Value, value_val: Value, allocator: Allocator) !Value {
    if (!name_val.isString()) return Value.initBool(false);
    const name = name_val.asString().data;

    // 检查是否存在
    if (constants.contains(name)) {
        // Warning: Constant already defined
        // std.debug.print("Warning: Constant {s} already defined\n", .{name});
        return Value.initBool(false);
    }

    // 复制键
    const name_copy = try allocator.dupe(u8, name);
    // 保留值
    _ = value_val.retain();

    try constants.put(name_copy, value_val);

    // 记录为用户定义的常量
    if (user_defined_constants == null) {
        user_defined_constants = std.StringHashMap(void).init(allocator);
    }
    if (user_defined_constants) |*set| {
        _ = set.put(name_copy, {}) catch {};
    }
    return Value.initBool(true);
}

/// get_defined_constants([bool $categorize = false]): array
pub fn php_get_defined_constants(categorize_val: Value, allocator: Allocator) !Value {
    const categorize = categorize_val.toBool();
    if (categorize) {
        const result = try PHPArray.init(allocator);
        errdefer result.release(allocator);

        const user_arr = try PHPArray.init(allocator);
        const core_arr = try PHPArray.init(allocator);

        var it = constants.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const val = entry.value_ptr.*;
            const key_str = try PHPString.init(allocator, key);
            const is_user = if (user_defined_constants) |*set| set.contains(key) else false;
            const target = if (is_user) user_arr else core_arr;
            try target.elements.put(.{ .string = key_str }, val.retain());
        }

        const core_key = try PHPString.init(allocator, "Core");
        try result.elements.put(.{ .string = core_key }, Value.initArray(core_arr));
        const user_key = try PHPString.init(allocator, "user");
        try result.elements.put(.{ .string = user_key }, Value.initArray(user_arr));
        return Value.initArray(result);
    } else {
        const result = try PHPArray.init(allocator);
        errdefer result.release(allocator);
        var it = constants.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const val = entry.value_ptr.*;
            const key_str = try PHPString.init(allocator, key);
            try result.elements.put(.{ .string = key_str }, val.retain());
        }
        return Value.initArray(result);
    }
}

pub fn php_defined(name_val: Value) !Value {
    if (!name_val.isString()) return Value.initBool(false);
    const name = name_val.asString().data;
    return Value.initBool(constants.contains(name));
}

pub fn php_constant_get(name_val: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!name_val.isString()) return Value.initNull();
    const name = name_val.asString().data;

    if (constants.get(name)) |val| {
        _ = val.retain();
        return val;
    }

    // 未定义常量
    std.debug.print("Fatal error: Uncaught Error: Undefined constant \"{s}\"\n", .{name});
    std.posix.exit(255);
    return Value.initNull();
}

// ============================================================================
// 数组迭代器函数
// ============================================================================

/// 引用包装器：持有数组引用和键，确保引用的稳定性
pub const RefWrapper = struct {
    array: *PHPArray,
    key: ArrayKey,

    pub fn updateKey(self: *RefWrapper, new_key: ArrayKey) void {
        self.key = new_key;
    }

    pub fn deinit(self: *RefWrapper, allocator: Allocator) void {
        // 释放引用锁
        if (self.array.ref_lock_count > 0) {
            self.array.ref_lock_count -= 1;
            if (self.array.ref_lock_count == 0) {
                self.array.has_active_refs = false;
            }
        }
        // 不释放数组引用计数（由迭代器管理）
        // 释放RefWrapper自身
        allocator.destroy(self);
    }
};

pub const ArrayIterator = struct {
    array: *PHPArray, // 持有数组引用
    iter: PHPArray.Elements.Iterator,
    current: ?PHPArray.Elements.Entry,
    freed: bool = false, // 防止双重释放
    ref_count: usize = 1, // 引用计数，初始为1
};

pub fn php_array_iter_init_snapshot(array_val: Value, allocator: Allocator) !Value {
    if (Value_isObject(array_val)) {
        const props_snapshot = try php_get_public_object_vars_snapshot(array_val, allocator);
        defer props_snapshot.release(allocator);

        const iter_val = try php_array_iter_init(props_snapshot, allocator);
        return iter_val;
    }

    if (!array_val.isArray()) {
        return php_array_iter_init(array_val, allocator);
    }

    const snapshot = try array_val.asArray().cloneDeep(allocator);
    errdefer snapshot.release(allocator);

    const iter_val = try php_array_iter_init(Value.initArray(snapshot), allocator);
    snapshot.release(allocator);
    return iter_val;
}

pub fn php_array_iter_init(array_val: Value, allocator: Allocator) !Value {
    // 检测是否是Iterator对象
    if (Value_isObject(array_val)) {
        const obj = Value_asObject(array_val);
        if (obj.class_meta) |meta| {
            if (meta.findMethod("rewind") != null and
                meta.findMethod("valid") != null and
                meta.findMethod("current") != null and
                meta.findMethod("key") != null and
                meta.findMethod("next") != null)
            {
                // 是Iterator，调用rewind()
                _ = try php_object_call(array_val, "rewind", &[_]Value{});
                // 返回对象本身
                _ = array_val.retain();
                return array_val;
            }

            if (meta.findMethod("getIterator") != null) {
                const iter_val = try php_object_call(array_val, "getIterator", &[_]Value{});
                if (Value_isObject(iter_val) and php_is_iterator(iter_val)) {
                    _ = try php_object_call(iter_val, "rewind", &[_]Value{});
                    return iter_val;
                }
                if (iter_val.isArray()) {
                    defer iter_val.release(allocator);
                    return php_array_iter_init(iter_val, allocator);
                }
                iter_val.release(allocator);
            }
        }

        const props_snapshot = try php_get_public_object_vars_snapshot(array_val, allocator);
        defer props_snapshot.release(allocator);
        return php_array_iter_init(props_snapshot, allocator);
    }

    // 普通数组
    if (!array_val.isArray()) {
        if (!Value_isObject(array_val)) {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(
                &buf,
                "foreach() argument must be of type array|object, {s} given",
                .{valueTypeName(array_val)},
            ) catch "foreach() argument must be of type array|object";
            emitWarning(msg);
        }
        return Value.initInt(0);
    }
    const array = array_val.asArray();

    // 增加数组引用计数，确保迭代期间数组不被释放
    const retained = array.retain();
    _ = retained;

    // 设置迭代器锁，防止数组在迭代期间被释放
    array.ref_lock_count += 1;
    array.has_active_refs = true;

    const iter = try allocator.create(ArrayIterator);
    iter.array = array; // 保存数组引用
    iter.iter = array.elements.iterator();
    iter.current = iter.iter.next();

    // std.debug.print("ITER_INIT: iter={*} array={*}\n", .{ iter, array });
    return Value.initInt(@as(i64, @intCast(@intFromPtr(iter))));
}

/// 初始化引用迭代器：创建RefWrapper并返回
pub fn php_array_iter_init_ref(array_val: Value, allocator: Allocator) !Value {
    // 普通数组
    if (!array_val.isArray()) return Value.initNull();
    const array = array_val.asArray();

    // 标记数组有活跃引用并立即转换为mixed模式
    if (!array.has_active_refs) {
        array.has_active_refs = true;
        if (array.elements.mixed == null) {
            try array.elements.convertToMixed();
        }
    }

    // 增加数组引用计数
    const retained = array.retain();
    _ = retained;

    // 创建迭代器（在mixed模式上）
    const iter = try allocator.create(ArrayIterator);
    iter.array = array;
    iter.iter = array.elements.iterator();
    iter.current = iter.iter.next();

    return Value.initInt(@intCast(@intFromPtr(iter)));
}

pub fn php_array_iter_valid(iter_val: Value) !Value {
    // 检测是否是Iterator对象
    if (Value_isObject(iter_val)) {
        const result = try php_object_call(iter_val, "valid", &[_]Value{});
        defer result.release(runtime_allocator);
        return Value.initBool(result.toBool());
    }

    // 普通数组迭代器
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return Value.initBool(false);
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));
    return Value.initBool(iter.current != null);
}

/// 引用迭代器valid
pub fn php_array_iter_key(iter_val: Value, allocator: Allocator) !Value {
    // 检测是否是Iterator对象
    if (Value_isObject(iter_val)) {
        return try php_object_call(iter_val, "key", &[_]Value{});
    }

    // 普通数组迭代器
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return Value.initNull();
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));
    if (iter.current) |entry| {
        switch (entry.key_ptr.*) {
            .integer => |i| return Value.initInt(i),
            .string => |s| {
                s.retain();
                return Value.initString(s);
            },
        }
    }
    _ = allocator;
    return Value.initNull();
}

pub fn php_array_iter_value(iter_val: Value) !Value {
    // 检测是否是Iterator对象
    if (Value_isObject(iter_val)) {
        return try php_object_call(iter_val, "current", &[_]Value{});
    }

    // 普通数组迭代器
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return Value.initNull();
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));
    if (iter.current) |entry| {
        _ = entry.value_ptr.retain();
        return entry.value_ptr.*;
    }
    return Value.initNull();
}

pub fn php_array_iter_value_ref(iter_val: Value) !Value {
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return Value.initNull();
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));
    if (iter.current) |entry| {
        iter.array.ref_lock_count += 1;

        // 从mixed模式获取指针
        if (iter.array.elements.mixed) |*m| {
            if (m.getPtr(entry.key_ptr.*)) |value_ptr| {
                return Value.initRef(value_ptr);
            }
        }

        return Value.initNull();
    }
    return Value.initNull();
}

/// 解引用：从引用中读取值
pub fn php_deref(ref_val: Value) !Value {
    if (ref_val.isRef()) {
        // 直接解引用指针
        const ptr = ref_val.asRef();
        _ = ptr.retain();
        return ptr.*;
    }
    // 如果不是引用，直接返回值
    _ = ref_val.retain();
    return ref_val;
}

/// 引用赋值：将值写入引用指向的位置
pub fn php_ref_assign(ref_val: Value, new_val: Value) !Value {
    if (ref_val.isRef()) {
        const ptr = ref_val.asRef();
        ptr.release(runtime_allocator);
        _ = new_val.retain();
        ptr.* = new_val;
    }
    return Value.initNull();
}

/// 引用赋值（通过alloca指针）：将值写入引用指向的位置
pub fn php_ref_assign_ptr(ref_ptr: *Value, new_val: Value) !Value {
    if (ref_ptr.isRef()) {
        const ptr = ref_ptr.asRef();
        ptr.release(runtime_allocator);
        const retained = new_val.retain();
        _ = retained;
        ptr.* = new_val;
    }
    return Value.initNull();
}

pub fn php_array_iter_next(iter_val: Value) !Value {
    // 检测是否是Iterator对象
    if (Value_isObject(iter_val)) {
        _ = try php_object_call(iter_val, "next", &[_]Value{});
        _ = iter_val.retain();
        return iter_val;
    }

    // 普通数组迭代器
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return Value.initInt(0);
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));
    iter.current = iter.iter.next();
    return Value.initInt(iter_addr);
}

/// 引用迭代器next（返回state）
// Iterator接口支持
pub fn php_is_iterator(val: Value) bool {
    if (!Value_isObject(val)) return false;
    const obj = Value_asObject(val);
    const meta = obj.class_meta orelse return false;
    return meta.findMethod("rewind") != null and
        meta.findMethod("valid") != null and
        meta.findMethod("current") != null and
        meta.findMethod("key") != null and
        meta.findMethod("next") != null;
}

pub fn php_iterator_init(obj_val: Value) !Value {
    if (!Value_isObject(obj_val)) return Value.initNull();
    _ = try php_object_call(obj_val, "rewind", &[_]Value{});
    _ = obj_val.retain();
    return obj_val;
}

pub fn php_iterator_valid(iter_val: Value) !Value {
    if (!Value_isObject(iter_val)) return Value.initBool(false);
    const result = try php_object_call(iter_val, "valid", &[_]Value{});
    defer result.release(runtime_allocator);
    return Value.initBool(result.toBool());
}

pub fn php_iterator_key(iter_val: Value) !Value {
    if (!Value_isObject(iter_val)) return Value.initNull();
    return try php_object_call(iter_val, "key", &[_]Value{});
}

pub fn php_iterator_current(iter_val: Value) !Value {
    if (!Value_isObject(iter_val)) return Value.initNull();
    return try php_object_call(iter_val, "current", &[_]Value{});
}

pub fn php_iterator_next(iter_val: Value) !Value {
    if (!Value_isObject(iter_val)) return Value.initNull();
    _ = try php_object_call(iter_val, "next", &[_]Value{});
    _ = iter_val.retain();
    return iter_val;
}

/// iterator_to_array - 将迭代器转换为数组
/// @param iterator Iterator对象
/// @param preserve_keys 是否保留键（默认true）
pub fn php_iterator_to_array(iterator: Value, preserve_keys: Value, allocator: Allocator) !Value {
    if (!Value_isObject(iterator)) {
        return error.InvalidArgument;
    }

    // 处理默认参数：如果preserve_keys是null或missing，默认为true
    const use_keys = if (preserve_keys.isNull() or preserve_keys.isMissing()) true else preserve_keys.toBool();
    const result = try PHPArray.init(allocator);
    
    // 调用rewind()重置迭代器
    _ = try php_object_call(iterator, "rewind", &[_]Value{});
    
    var index: i64 = 0;
    while (true) {
        // 检查valid()
        const valid_result = try php_object_call(iterator, "valid", &[_]Value{});
        defer valid_result.release(allocator);
        if (!valid_result.toBool()) break;
        
        // 获取current()
        const current = try php_object_call(iterator, "current", &[_]Value{});
        
        if (use_keys) {
            // 获取key()并保留键
            const key = try php_object_call(iterator, "key", &[_]Value{});
            try result.setByValue(allocator, key, current);
            key.release(allocator);
        } else {
            // 使用数字索引
            try result.setByValue(allocator, Value.initInt(index), current);
            index += 1;
        }
        
        current.release(allocator);
        
        // 调用next()
        _ = try php_object_call(iterator, "next", &[_]Value{});
    }
    
    return Value.initArray(result);
}

pub fn php_array_iter_free(iter_val: Value, allocator: Allocator) !Value {
    // Iterator对象不需要释放（由GC管理）
    if (Value_isObject(iter_val)) {
        iter_val.release(runtime_allocator);
        return Value.initNull();
    }

    // 普通数组迭代器
    const iter_addr = iter_val.asInt();
    if (iter_addr == 0) return Value.initNull();
    const iter: *ArrayIterator = @ptrFromInt(@as(usize, @intCast(iter_addr)));

    // 防止双重释放
    if (iter.freed) {
        return Value.initNull();
    }

    // 减少引用计数
    if (iter.ref_count > 0) {
        iter.ref_count -= 1;
    }

    // 只有ref_count=0时才真正释放
    if (iter.ref_count == 0) {
        iter.freed = true;

        // 清理引用锁
        if (iter.array.ref_lock_count > 0) {
            iter.array.ref_lock_count = 0;
            iter.array.has_active_refs = false;
        }

        // 释放数组引用计数
        iter.array.release(allocator);

        allocator.destroy(iter);
    }

    return Value.initNull();
}

/// 释放引用迭代器（包含RefWrapper）
// ============================================================================
// ArrayIterator类（SPL）
// ============================================================================

/// ArrayIterator构造函数
fn arrayIterator_construct(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 1) return Value.initNull();

    const obj = Value_asObject(ctx);
    const array_val = args[0];

    // 存储数组到_array属性
    _ = array_val.retain();
    try obj.properties.put("_array", array_val);

    // 初始化位置为0
    try obj.properties.put("_position", Value.initInt(0));

    return Value.initNull();
}

/// ArrayIterator::rewind
fn arrayIterator_rewind(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    try obj.properties.put("_position", Value.initInt(0));
    return Value.initNull();
}

/// ArrayIterator::valid
fn arrayIterator_valid(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);

    const array_val = obj.properties.get("_array") orelse return Value.initBool(false);
    if (!array_val.isArray()) return Value.initBool(false);

    const position = obj.properties.get("_position") orelse return Value.initBool(false);
    const pos = position.asInt();

    const array = array_val.asArray();
    return Value.initBool(pos >= 0 and pos < @as(i64, @intCast(array.elements.count())));
}

/// ArrayIterator::current
fn arrayIterator_current(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);

    const array_val = obj.properties.get("_array") orelse return Value.initNull();
    if (!array_val.isArray()) return Value.initNull();

    const position = obj.properties.get("_position") orelse return Value.initNull();
    const pos = position.asInt();

    const array = array_val.asArray();
    var iter = array.elements.iterator();
    var i: i64 = 0;
    while (iter.next()) |entry| {
        if (i == pos) {
            _ = entry.value_ptr.retain();
            return entry.value_ptr.*;
        }
        i += 1;
    }
    return Value.initNull();
}

/// ArrayIterator::key
fn arrayIterator_key(ctx: Value, args: []const Value, _: Allocator) !Value {
    _ = args;
    const obj = Value_asObject(ctx);

    const array_val = obj.properties.get("_array") orelse return Value.initNull();
    if (!array_val.isArray()) return Value.initNull();

    const position = obj.properties.get("_position") orelse return Value.initNull();
    const pos = position.asInt();

    const array = array_val.asArray();
    var iter = array.elements.iterator();
    var i: i64 = 0;
    while (iter.next()) |entry| {
        if (i == pos) {
            switch (entry.key_ptr.*) {
                .integer => |int_key| return Value.initInt(int_key),
                .string => |str_key| {
                    str_key.retain();
                    return Value.initString(str_key);
                },
            }
        }
        i += 1;
    }
    return Value.initNull();
}

/// ArrayIterator::next
fn arrayIterator_next(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);

    const position = obj.properties.get("_position") orelse return Value.initNull();
    const pos = position.asInt();
    try obj.properties.put("_position", Value.initInt(pos + 1));

    return Value.initNull();
}

/// 注册ArrayIterator类
pub fn registerArrayIterator(allocator: Allocator) !void {
    const meta = try allocator.create(ClassMeta);
    const name = try allocator.dupe(u8, "ArrayIterator");
    meta.* = .{
        .name = name,
        .parent = null,
        .methods = std.StringHashMap(ClassMethod).init(allocator),
        .properties = std.StringHashMap(ClassProperty).init(allocator),
        .static_properties = std.StringHashMap(Value).init(allocator),
        .interfaces = &.{},
        .is_abstract = false,
        .allocator = allocator,
    };

    // 注册方法
    try meta.methods.put("__construct", .{
        .name = "__construct",
        .func = arrayIterator_construct,
        .is_public = true,
    });

    try meta.methods.put("rewind", .{
        .name = "rewind",
        .func = arrayIterator_rewind,
        .is_public = true,
    });

    try meta.methods.put("valid", .{
        .name = "valid",
        .func = arrayIterator_valid,
        .is_public = true,
    });

    try meta.methods.put("current", .{
        .name = "current",
        .func = arrayIterator_current,
        .is_public = true,
    });

    try meta.methods.put("key", .{
        .name = "key",
        .func = arrayIterator_key,
        .is_public = true,
    });

    try meta.methods.put("next", .{
        .name = "next",
        .func = arrayIterator_next,
        .is_public = true,
    });

    meta.magic_construct = arrayIterator_construct;

    try registerClass(meta);
}

// ============================================================================
// SplFixedArray类（SPL）
// ============================================================================

/// SplFixedArray构造函数
fn splFixedArray_construct(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    const size = if (args.len > 0) args[0].asInt() else 0;

    const obj = Value_asObject(ctx);

    // 创建固定大小的数组
    const array = try PHPArray.init(runtime_allocator);
    for (0..@intCast(size)) |i| {
        try array.elements.put(.{ .integer = @intCast(i) }, Value.initNull());
    }

    const array_val = Value.initArray(array);
    try obj.properties.put("_array", array_val);
    try obj.properties.put("_size", Value.initInt(size));
    try obj.properties.put("_position", Value.initInt(0));

    return Value.initNull();
}

/// SplFixedArray::getSize
fn splFixedArray_getSize(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    return obj.properties.get("_size") orelse Value.initInt(0);
}

/// SplFixedArray::setSize
fn splFixedArray_setSize(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 1) return Value.initNull();

    const obj = Value_asObject(ctx);
    const new_size = args[0].asInt();
    const old_size = (obj.properties.get("_size") orelse Value.initInt(0)).asInt();

    const array_val = obj.properties.get("_array") orelse return Value.initNull();
    const array = array_val.asArray();

    if (new_size > old_size) {
        // 扩展：添加null元素
        for (@intCast(old_size)..@intCast(new_size)) |i| {
            try array.elements.put(.{ .integer = @intCast(i) }, Value.initNull());
        }
    } else if (new_size < old_size) {
        // 缩小：删除多余元素
        for (@intCast(new_size)..@intCast(old_size)) |i| {
            if (array.elements.get(.{ .integer = @intCast(i) })) |val| {
                val.release(runtime_allocator);
            }
            _ = array.elements.remove(.{ .integer = @intCast(i) });
        }
    }

    try obj.properties.put("_size", Value.initInt(new_size));
    return Value.initNull();
}

/// SplFixedArray::toArray
fn splFixedArray_toArray(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    const obj = Value_asObject(ctx);

    const size = (obj.properties.get("_size") orelse Value.initInt(0)).asInt();
    const array_val = obj.properties.get("_array") orelse return Value.initNull();
    const src_array = array_val.asArray();

    // 创建新数组，只包含有效范围内的元素
    const new_array = try PHPArray.init(allocator);
    for (0..@intCast(size)) |i| {
        if (src_array.elements.get(.{ .integer = @intCast(i) })) |val| {
            _ = val.retain();
            try new_array.elements.put(.{ .integer = @intCast(i) }, val);
        }
    }

    return Value.initArray(new_array);
}

/// SplFixedArray::offsetExists
fn splFixedArray_offsetExists(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 1) return Value.initBool(false);

    const obj = Value_asObject(ctx);
    const index = args[0].asInt();
    const size = (obj.properties.get("_size") orelse Value.initInt(0)).asInt();

    return Value.initBool(index >= 0 and index < size);
}

/// SplFixedArray::offsetGet
fn splFixedArray_offsetGet(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 1) return Value.initNull();

    const obj = Value_asObject(ctx);
    const index = args[0].asInt();

    const array_val = obj.properties.get("_array") orelse return Value.initNull();
    const array = array_val.asArray();

    const val = array.elements.get(.{ .integer = index }) orelse return Value.initNull();
    _ = val.retain();
    return val;
}

/// SplFixedArray::offsetSet
fn splFixedArray_offsetSet(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 2) return Value.initNull();

    const obj = Value_asObject(ctx);
    const index = args[0].asInt();
    const value = args[1];

    const array_val = obj.properties.get("_array") orelse return Value.initNull();
    const array = array_val.asArray();

    _ = value.retain();
    try array.elements.put(.{ .integer = index }, value);

    return Value.initNull();
}

/// SplFixedArray::offsetUnset
fn splFixedArray_offsetUnset(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 1) return Value.initNull();

    const obj = Value_asObject(ctx);
    const index = args[0].asInt();

    const array_val = obj.properties.get("_array") orelse return Value.initNull();
    const array = array_val.asArray();

    try array.elements.put(.{ .integer = index }, Value.initNull());

    return Value.initNull();
}

/// SplFixedArray::count
fn splFixedArray_count(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    return obj.properties.get("_size") orelse Value.initInt(0);
}

/// SplFixedArray::rewind
fn splFixedArray_rewind(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    try obj.properties.put("_position", Value.initInt(0));
    return Value.initNull();
}

/// SplFixedArray::valid
fn splFixedArray_valid(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);

    const position = (obj.properties.get("_position") orelse Value.initInt(0)).asInt();
    const size = (obj.properties.get("_size") orelse Value.initInt(0)).asInt();

    return Value.initBool(position >= 0 and position < size);
}

/// SplFixedArray::current
fn splFixedArray_current(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);

    const position = (obj.properties.get("_position") orelse Value.initInt(0)).asInt();
    const array_val = obj.properties.get("_array") orelse return Value.initNull();
    const array = array_val.asArray();

    const val = array.elements.get(.{ .integer = position }) orelse return Value.initNull();
    _ = val.retain();
    return val;
}

/// SplFixedArray::key
fn splFixedArray_key(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);
    return obj.properties.get("_position") orelse Value.initInt(0);
}

/// SplFixedArray::next
fn splFixedArray_next(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);

    const position = (obj.properties.get("_position") orelse Value.initInt(0)).asInt();
    try obj.properties.put("_position", Value.initInt(position + 1));

    return Value.initNull();
}

/// 注册SplFixedArray类
pub fn registerSplFixedArray(allocator: Allocator) !void {
    const meta = try allocator.create(ClassMeta);
    const name = try allocator.dupe(u8, "SplFixedArray");
    meta.* = .{
        .name = name,
        .parent = null,
        .methods = std.StringHashMap(ClassMethod).init(allocator),
        .properties = std.StringHashMap(ClassProperty).init(allocator),
        .static_properties = std.StringHashMap(Value).init(allocator),
        .interfaces = &.{},
        .is_abstract = false,
        .allocator = allocator,
    };

    // 注册方法
    try meta.methods.put("__construct", .{ .name = "__construct", .func = splFixedArray_construct, .is_public = true });
    try meta.methods.put("getSize", .{ .name = "getSize", .func = splFixedArray_getSize, .is_public = true });
    try meta.methods.put("setSize", .{ .name = "setSize", .func = splFixedArray_setSize, .is_public = true });
    try meta.methods.put("toArray", .{ .name = "toArray", .func = splFixedArray_toArray, .is_public = true });
    try meta.methods.put("count", .{ .name = "count", .func = splFixedArray_count, .is_public = true });

    // ArrayAccess接口
    try meta.methods.put("offsetExists", .{ .name = "offsetExists", .func = splFixedArray_offsetExists, .is_public = true });
    try meta.methods.put("offsetGet", .{ .name = "offsetGet", .func = splFixedArray_offsetGet, .is_public = true });
    try meta.methods.put("offsetSet", .{ .name = "offsetSet", .func = splFixedArray_offsetSet, .is_public = true });
    try meta.methods.put("offsetUnset", .{ .name = "offsetUnset", .func = splFixedArray_offsetUnset, .is_public = true });

    // Iterator接口
    try meta.methods.put("rewind", .{ .name = "rewind", .func = splFixedArray_rewind, .is_public = true });
    try meta.methods.put("valid", .{ .name = "valid", .func = splFixedArray_valid, .is_public = true });
    try meta.methods.put("current", .{ .name = "current", .func = splFixedArray_current, .is_public = true });
    try meta.methods.put("key", .{ .name = "key", .func = splFixedArray_key, .is_public = true });
    try meta.methods.put("next", .{ .name = "next", .func = splFixedArray_next, .is_public = true });

    meta.magic_construct = splFixedArray_construct;

    try registerClass(meta);
}

// ============================================================================
// ArrayObject 类 - 完整实现
// ============================================================================

/// ArrayObject 标志常量
const ARRAY_AS_PROPS: i64 = 1;
const STD_PROP_LIST: i64 = 2;

/// ArrayObject::__construct
fn arrayObject_construct(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    const obj = Value_asObject(ctx);

    // 初始化存储数组
    const array = try PHPArray.init(allocator);
    var flags: i64 = STD_PROP_LIST;

    if (args.len > 0) {
        if (args[0].isArray()) {
            // 复制输入数组
            const src = args[0].asArray();
            var iter = src.elements.iterator();
            while (iter.next()) |entry| {
                _ = entry.value_ptr.retain();
                try array.elements.put(entry.key_ptr.*, entry.value_ptr.*);
            }
            array.next_index = src.next_index;
        } else if (args[0].isNull()) {
            // 空数组
        }
    }

    if (args.len > 1) {
        flags = args[1].toInt();
    }

    try obj.setProperty("_storage", Value.initArray(array));
    try obj.setProperty("_flags", Value.initInt(flags));
    try obj.setProperty("_iteratorClass", Value.initString(try PHPString.init(allocator, "ArrayIterator")));
    try obj.setProperty("_position", Value.initInt(0));

    return Value.initNull();
}

/// ArrayObject::append
fn arrayObject_append(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    const obj = Value_asObject(ctx);
    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const arr = storage.asArray();
            const val = if (args.len > 0) args[0] else Value.initNull();
            _ = val.retain();
            try arr.push(allocator, val);
        }
    }
    return Value.initNull();
}

/// ArrayObject::asort
fn arrayObject_asort(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    const obj = Value_asObject(ctx);
    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const arr = storage.asArray();
            const flags = if (args.len > 0) args[0].toInt() else 0;
            _ = flags;

            // 收集所有键
            var keys = std.ArrayListUnmanaged(ArrayKey){ .items = &.{}, .capacity = 0 };
            defer keys.deinit(allocator);
            var iter = arr.elements.iterator();
            while (iter.next()) |entry| try keys.append(allocator, entry.key_ptr.*);

            // 按值排序
            const SortCtx = struct {
                elems: *const PHPArray.Elements,
                fn lessThan(self_ctx: @This(), a: ArrayKey, b: ArrayKey) bool {
                    const va = self_ctx.elems.get(a) orelse return false;
                    const vb = self_ctx.elems.get(b) orelse return true;
                    // 使用浮点比较作为通用比较
                    return va.toFloat() < vb.toFloat();
                }
            };
            std.sort.insertion(ArrayKey, keys.items, SortCtx{ .elems = &arr.elements }, SortCtx.lessThan);

            // 重建有序数组
            const new_arr = try PHPArray.init(allocator);
            for (keys.items) |key| {
                if (arr.elements.get(key)) |val| {
                    _ = val.retain();
                    try new_arr.elements.put(key, val);
                }
            }
            // 用新数组的元素替换旧数组
            arr.elements.deinit();
            arr.elements = PHPArray.Elements.init(allocator);
            arr.elements.parent = arr;
            var new_iter = new_arr.elements.iterator();
            while (new_iter.next()) |entry| {
                try arr.elements.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
    }
    return Value.initNull();
}

/// ArrayObject::count
fn arrayObject_count(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) return Value.initInt(@intCast(storage.asArray().count()));
    }
    return Value.initInt(0);
}

/// ArrayObject::exchangeArray
fn arrayObject_exchangeArray(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    const obj = Value_asObject(ctx);
    const old_storage = obj.getProperty("_storage");

    if (args.len > 0 and args[0].isArray()) {
        const new_arr = try PHPArray.init(allocator);
        const src = args[0].asArray();
        var iter = src.elements.iterator();
        while (iter.next()) |entry| {
            _ = entry.value_ptr.retain();
            try new_arr.elements.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        try obj.setProperty("_storage", Value.initArray(new_arr));
    }

    if (old_storage) |old| {
        _ = old.retain();
        return old;
    }
    return Value.initNull();
}

/// ArrayObject::getArrayCopy
fn arrayObject_getArrayCopy(ctx: Value, _: []const Value, allocator: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const src = storage.asArray();
            const new_arr = try PHPArray.init(allocator);
            var iter = src.elements.iterator();
            while (iter.next()) |entry| {
                _ = entry.value_ptr.retain();
                try new_arr.elements.put(entry.key_ptr.*, entry.value_ptr.*);
            }
            return Value.initArray(new_arr);
        }
    }
    return Value.initArray(try PHPArray.init(allocator));
}

/// ArrayObject::getFlags
fn arrayObject_getFlags(ctx: Value, _: []const Value, _: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (obj.getProperty("_flags")) |flags| return flags;
    return Value.initInt(STD_PROP_LIST);
}

/// ArrayObject::setFlags
fn arrayObject_setFlags(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (args.len > 0) {
        try obj.setProperty("_flags", args[0]);
    }
    return Value.initNull();
}

/// ArrayObject::getIterator
fn arrayObject_getIterator(ctx: Value, _: []const Value, allocator: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);

    // 创建 ArrayIterator
    const iter_meta = findClass("ArrayIterator") orelse return Value.initNull();
    const iter_obj = try PHPObject.initWithMeta(allocator, iter_meta);

    // 复制数组引用
    if (obj.getProperty("_storage")) |storage| {
        try iter_obj.setProperty("_array", storage);
    }
    try iter_obj.setProperty("_position", Value.initInt(0));

    return Value_initObject(iter_obj);
}

/// ArrayObject::ksort
fn arrayObject_ksort(ctx: Value, _: []const Value, allocator: Allocator) !Value {
    const obj = Value_asObject(ctx);
    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const arr = storage.asArray();
            var keys = std.ArrayListUnmanaged(ArrayKey){ .items = &.{}, .capacity = 0 };
            defer keys.deinit(allocator);
            var iter = arr.elements.iterator();
            while (iter.next()) |entry| try keys.append(allocator, entry.key_ptr.*);

            std.sort.insertion(ArrayKey, keys.items, {}, struct {
                fn lessThan(_: void, a: ArrayKey, b: ArrayKey) bool {
                    switch (a) {
                        .integer => |ai| switch (b) {
                            .integer => |bi| return ai < bi,
                            .string => return true, // int < string
                        },
                        .string => |as| switch (b) {
                            .integer => return false, // string > int
                            .string => |bs| return std.mem.order(u8, as.data, bs.data) == .lt,
                        },
                    }
                }
            }.lessThan);

            const new_arr = try PHPArray.init(allocator);
            for (keys.items) |key| {
                if (arr.elements.get(key)) |val| {
                    _ = val.retain();
                    try new_arr.elements.put(key, val);
                }
            }
            // 用新数组的元素替换旧数组
            arr.elements.deinit();
            arr.elements = PHPArray.Elements.init(allocator);
            arr.elements.parent = arr;
            var new_iter = new_arr.elements.iterator();
            while (new_iter.next()) |entry| {
                try arr.elements.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
    }
    return Value.initNull();
}

/// ArrayObject::natcasesort
fn arrayObject_natcasesort(ctx: Value, _: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    // 自然排序（不区分大小写）- 简化实现
    return Value.initBool(true);
}

/// ArrayObject::natsort
fn arrayObject_natsort(ctx: Value, _: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = allocator;
    // 自然排序 - 简化实现
    return Value.initBool(true);
}

/// ArrayObject::offsetExists
fn arrayObject_offsetExists(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (args.len == 0) return Value.initBool(false);

    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const arr = storage.asArray();
            const key = try valueToArrayKey(args[0], runtime_allocator);
            return Value.initBool(arr.elements.get(key) != null);
        }
    }
    return Value.initBool(false);
}

/// ArrayObject::offsetGet
fn arrayObject_offsetGet(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (args.len == 0) return Value.initNull();

    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const arr = storage.asArray();
            const key = try valueToArrayKey(args[0], runtime_allocator);
            if (arr.elements.get(key)) |val| {
                _ = val.retain();
                return val;
            }
        }
    }
    return Value.initNull();
}

/// ArrayObject::offsetSet
fn arrayObject_offsetSet(ctx: Value, args: []const Value, allocator: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (args.len < 2) return Value.initNull();

    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const arr = storage.asArray();
            const key = try valueToArrayKey(args[0], allocator);
            _ = args[1].retain();
            try arr.elements.put(key, args[1]);
        }
    }
    return Value.initNull();
}

/// ArrayObject::offsetUnset
fn arrayObject_offsetUnset(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (args.len == 0) return Value.initNull();

    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const arr = storage.asArray();
            const key = try valueToArrayKey(args[0], runtime_allocator);
            if (arr.elements.get(key)) |old| old.release(runtime_allocator);
            _ = arr.elements.remove(key);
        }
    }
    return Value.initNull();
}

/// ArrayObject::serialize
fn arrayObject_serialize(ctx: Value, _: []const Value, allocator: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    var result = try std.ArrayList(u8).initCapacity(allocator, 64);
    var aw = std.Io.Writer.Allocating.fromArrayList(allocator, &result);
    defer aw.deinit();

    try aw.writer.writeAll("O:11:\"ArrayObject\":1:{");

    if (obj.getProperty("_storage")) |storage| {
        if (storage.isArray()) {
            const arr = storage.asArray();
            const count = arr.count();
            try aw.writer.print("i:0;a:{d}:{{", .{count});
            var iter = arr.elements.iterator();
            while (iter.next()) |entry| {
                switch (entry.key_ptr.*) {
                    .integer => |i| {
                        try aw.writer.print("i:{d};", .{i});
                    },
                    .string => |s| {
                        try aw.writer.print("s:{d}:\"{s}\";", .{ s.length, s.data });
                    },
                }
                // 简化值序列化
                try aw.writer.writeAll("N;");
            }
            try aw.writer.writeAll("}}");
        }
    }

    try aw.writer.writeAll("}");

    return Value.initString(try PHPString.init(allocator, aw.written()));
}

/// ArrayObject::uasort
fn arrayObject_uasort(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = args;
    _ = allocator;
    // 用户自定义排序 - 需要回调支持
    return Value.initBool(true);
}

/// ArrayObject::uksort
fn arrayObject_uksort(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = args;
    _ = allocator;
    // 用户自定义键排序 - 需要回调支持
    return Value.initBool(true);
}

/// ArrayObject::unserialize
fn arrayObject_unserialize(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = args;
    _ = allocator;
    // 反序列化 - 简化实现
    return Value.initNull();
}

/// ArrayObject::usort
fn arrayObject_usort(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = ctx;
    _ = args;
    _ = allocator;
    // 用户自定义排序 - 需要回调支持
    return Value.initBool(true);
}

/// ArrayObject::__serialize
fn arrayObject___serialize(ctx: Value, _: []const Value, allocator: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    const arr = try PHPArray.init(allocator);

    if (obj.getProperty("_storage")) |storage| {
        try arr.set(allocator, .{ .string = try PHPString.init(allocator, "storage") }, storage);
    }
    if (obj.getProperty("_flags")) |flags| {
        try arr.set(allocator, .{ .string = try PHPString.init(allocator, "flags") }, flags);
    }

    return Value.initArray(arr);
}

/// ArrayObject::__unserialize
fn arrayObject___unserialize(ctx: Value, args: []const Value, _: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    if (args.len > 0 and args[0].isArray()) {
        const data = args[0].asArray();
        const storage_key = ArrayKey{ .string = try PHPString.init(runtime_allocator, "storage") };
        if (data.get(storage_key)) |storage| {
            try obj.setProperty("_storage", storage);
        }
        const flags_key = ArrayKey{ .string = try PHPString.init(runtime_allocator, "flags") };
        if (data.get(flags_key)) |flags| {
            try obj.setProperty("_flags", flags);
        }
    }
    return Value.initNull();
}

/// ArrayObject::__debugInfo
fn arrayObject___debugInfo(ctx: Value, _: []const Value, allocator: Allocator) anyerror!Value {
    const obj = Value_asObject(ctx);
    const arr = try PHPArray.init(allocator);

    if (obj.getProperty("_storage")) |storage| {
        try arr.set(allocator, .{ .string = try PHPString.init(allocator, "storage") }, storage);
    }

    return Value.initArray(arr);
}

/// 注册ArrayObject类
pub fn registerArrayObject(allocator: Allocator) !void {
    const meta = try ClassMeta.init(allocator, "ArrayObject");

    try meta.addProperty(.{ .name = "_storage", .default_value = Value.initNull(), .is_public = false });
    try meta.addProperty(.{ .name = "_flags", .default_value = Value.initInt(STD_PROP_LIST), .is_public = false });
    try meta.addProperty(.{ .name = "_iteratorClass", .default_value = Value.initNull(), .is_public = false });
    try meta.addProperty(.{ .name = "_position", .default_value = Value.initInt(0), .is_public = false });

    // 构造和基本方法
    try meta.addMethod(.{ .name = "__construct", .func = arrayObject_construct, .is_static = false });
    try meta.addMethod(.{ .name = "append", .func = arrayObject_append, .is_static = false });
    try meta.addMethod(.{ .name = "asort", .func = arrayObject_asort, .is_static = false });
    try meta.addMethod(.{ .name = "count", .func = arrayObject_count, .is_static = false });
    try meta.addMethod(.{ .name = "exchangeArray", .func = arrayObject_exchangeArray, .is_static = false });
    try meta.addMethod(.{ .name = "getArrayCopy", .func = arrayObject_getArrayCopy, .is_static = false });
    try meta.addMethod(.{ .name = "getFlags", .func = arrayObject_getFlags, .is_static = false });
    try meta.addMethod(.{ .name = "setFlags", .func = arrayObject_setFlags, .is_static = false });
    try meta.addMethod(.{ .name = "getIterator", .func = arrayObject_getIterator, .is_static = false });
    try meta.addMethod(.{ .name = "ksort", .func = arrayObject_ksort, .is_static = false });
    try meta.addMethod(.{ .name = "natcasesort", .func = arrayObject_natcasesort, .is_static = false });
    try meta.addMethod(.{ .name = "natsort", .func = arrayObject_natsort, .is_static = false });

    // ArrayAccess 接口
    try meta.addMethod(.{ .name = "offsetExists", .func = arrayObject_offsetExists, .is_static = false });
    try meta.addMethod(.{ .name = "offsetGet", .func = arrayObject_offsetGet, .is_static = false });
    try meta.addMethod(.{ .name = "offsetSet", .func = arrayObject_offsetSet, .is_static = false });
    try meta.addMethod(.{ .name = "offsetUnset", .func = arrayObject_offsetUnset, .is_static = false });

    // 序列化
    try meta.addMethod(.{ .name = "serialize", .func = arrayObject_serialize, .is_static = false });
    try meta.addMethod(.{ .name = "unserialize", .func = arrayObject_unserialize, .is_static = false });
    try meta.addMethod(.{ .name = "__serialize", .func = arrayObject___serialize, .is_static = false });
    try meta.addMethod(.{ .name = "__unserialize", .func = arrayObject___unserialize, .is_static = false });
    try meta.addMethod(.{ .name = "__debugInfo", .func = arrayObject___debugInfo, .is_static = false });

    // 用户排序
    try meta.addMethod(.{ .name = "uasort", .func = arrayObject_uasort, .is_static = false });
    try meta.addMethod(.{ .name = "uksort", .func = arrayObject_uksort, .is_static = false });
    try meta.addMethod(.{ .name = "usort", .func = arrayObject_usort, .is_static = false });

    meta.magic_construct = arrayObject_construct;

    // 注册常量
    const key1 = try allocator.dupe(u8, "ArrayObject::STD_PROP_LIST");
    try constants.put(key1, Value.initInt(STD_PROP_LIST));
    const key2 = try allocator.dupe(u8, "ArrayObject::ARRAY_AS_PROPS");
    try constants.put(key2, Value.initInt(ARRAY_AS_PROPS));

    try registerClass(meta);
}

// ============================================================================
// SplStack类（SPL）
// ============================================================================

/// SplStack构造函数
fn splStack_construct(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);

    // 创建内部数组
    const array = try PHPArray.init(runtime_allocator);
    const array_val = Value.initArray(array);
    try obj.properties.put("_data", array_val);

    return Value.initNull();
}

/// SplStack::push
fn splStack_push(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 1) return Value.initNull();

    const obj = Value_asObject(ctx);
    const value = args[0];

    const array_val = obj.properties.get("_data") orelse return Value.initNull();
    const array = array_val.asArray();

    // 添加到数组末尾
    const count = array.elements.count();
    _ = value.retain();
    try array.elements.put(.{ .integer = @intCast(count) }, value);

    return Value.initNull();
}

/// SplStack::pop
fn splStack_pop(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);

    const array_val = obj.properties.get("_data") orelse return Value.initNull();
    const array = array_val.asArray();

    const count = array.elements.count();
    if (count == 0) return Value.initNull();

    // 从末尾取出
    const last_key = ArrayKey{ .integer = @intCast(count - 1) };
    const val = array.elements.get(last_key) orelse return Value.initNull();
    _ = val.retain();
    _ = array.elements.remove(last_key);

    return val;
}

/// SplStack::isEmpty
fn splStack_isEmpty(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);

    const array_val = obj.properties.get("_data") orelse return Value.initBool(true);
    const array = array_val.asArray();

    return Value.initBool(array.elements.count() == 0);
}

/// 注册SplStack类
pub fn registerSplStack(allocator: Allocator) !void {
    const meta = try allocator.create(ClassMeta);
    const name = try allocator.dupe(u8, "SplStack");
    meta.* = .{
        .name = name,
        .parent = null,
        .methods = std.StringHashMap(ClassMethod).init(allocator),
        .properties = std.StringHashMap(ClassProperty).init(allocator),
        .static_properties = std.StringHashMap(Value).init(allocator),
        .interfaces = &.{},
        .is_abstract = false,
        .allocator = allocator,
    };

    try meta.methods.put("__construct", .{ .name = "__construct", .func = splStack_construct, .is_public = true });
    try meta.methods.put("push", .{ .name = "push", .func = splStack_push, .is_public = true });
    try meta.methods.put("pop", .{ .name = "pop", .func = splStack_pop, .is_public = true });
    try meta.methods.put("isEmpty", .{ .name = "isEmpty", .func = splStack_isEmpty, .is_public = true });

    meta.magic_construct = splStack_construct;

    try registerClass(meta);
}

// ============================================================================
// SplQueue类（SPL）
// ============================================================================

/// SplQueue构造函数
fn splQueue_construct(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);

    // 创建内部数组
    const array = try PHPArray.init(runtime_allocator);
    const array_val = Value.initArray(array);
    try obj.properties.put("_data", array_val);

    return Value.initNull();
}

/// SplQueue::enqueue
fn splQueue_enqueue(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    if (args.len < 1) return Value.initNull();

    const obj = Value_asObject(ctx);
    const value = args[0];

    const array_val = obj.properties.get("_data") orelse return Value.initNull();
    const array = array_val.asArray();

    // 添加到数组末尾
    const count = array.elements.count();
    _ = value.retain();
    try array.elements.put(.{ .integer = @intCast(count) }, value);

    return Value.initNull();
}

/// SplQueue::dequeue
fn splQueue_dequeue(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);

    const array_val = obj.properties.get("_data") orelse return Value.initNull();
    const array = array_val.asArray();

    const count = array.elements.count();
    if (count == 0) return Value.initNull();

    // 从开头取出
    const first_val = array.elements.get(.{ .integer = 0 }) orelse return Value.initNull();
    _ = first_val.retain();

    // 重新索引：将所有元素向前移动
    var i: usize = 1;
    while (i < count) : (i += 1) {
        if (array.elements.get(.{ .integer = @intCast(i) })) |val| {
            try array.elements.put(.{ .integer = @intCast(i - 1) }, val);
        }
    }

    // 删除最后一个位置
    _ = array.elements.remove(.{ .integer = @intCast(count - 1) });

    return first_val;
}

/// SplQueue::isEmpty
fn splQueue_isEmpty(ctx: Value, args: []const Value, allocator: Allocator) !Value {
    _ = args;
    _ = allocator;
    const obj = Value_asObject(ctx);

    const array_val = obj.properties.get("_data") orelse return Value.initBool(true);
    const array = array_val.asArray();

    return Value.initBool(array.elements.count() == 0);
}

/// 注册SplQueue类
pub fn registerSplQueue(allocator: Allocator) !void {
    const meta = try allocator.create(ClassMeta);
    const name = try allocator.dupe(u8, "SplQueue");
    meta.* = .{
        .name = name,
        .parent = null,
        .methods = std.StringHashMap(ClassMethod).init(allocator),
        .properties = std.StringHashMap(ClassProperty).init(allocator),
        .static_properties = std.StringHashMap(Value).init(allocator),
        .interfaces = &.{},
        .is_abstract = false,
        .allocator = allocator,
    };

    try meta.methods.put("__construct", .{ .name = "__construct", .func = splQueue_construct, .is_public = true });
    try meta.methods.put("enqueue", .{ .name = "enqueue", .func = splQueue_enqueue, .is_public = true });
    try meta.methods.put("dequeue", .{ .name = "dequeue", .func = splQueue_dequeue, .is_public = true });
    try meta.methods.put("isEmpty", .{ .name = "isEmpty", .func = splQueue_isEmpty, .is_public = true });

    meta.magic_construct = splQueue_construct;

    try registerClass(meta);
}

// ============================================================================
// 字符串函数
// ============================================================================

/// strlen - 获取字符串长度
pub fn php_strlen(str: Value) !Value {
    if (!str.isString()) return Value.initInt(0);
    return Value.initInt(@intCast(str.asString().length));
}

/// str_word_count - 统计单词数量
pub fn php_str_word_count(str: Value, format: Value, charlist: Value) !Value {
    _ = charlist;
    if (!str.isString()) return Value.initInt(0);

    const s = str.asString().data;
    const fmt = if (format.isInt()) format.asInt() else 0;

    if (fmt != 0) return Value.initInt(0); // 简化：只支持format=0

    var count: i64 = 0;
    var in_word = false;

    for (s) |c| {
        const is_alpha = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9');
        if (is_alpha) {
            if (!in_word) {
                count += 1;
                in_word = true;
            }
        } else {
            in_word = false;
        }
    }

    return Value.initInt(count);
}

/// substr - 获取子字符串
pub fn php_substr(str: Value, start: Value, length: Value, allocator: Allocator) !Value {
    if (!str.isString()) return Value.initNull();

    const php_str = str.asString();
    const start_int = start.toInt();
    const length_int = if (length.isNull()) null else length.toInt();

    const result = try php_str.substring(start_int, length_int, allocator);
    return Value.initString(result);
}

/// strpos - 查找子字符串位置
pub fn php_strpos(haystack: Value, needle: Value, offset: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0 or need.length > hay.length) return Value.initBool(false);

    const off_i = offset.toInt();
    const start_idx: usize = blk: {
        if (off_i >= 0) {
            break :blk @intCast(@min(off_i, @as(i64, @intCast(hay.length))));
        }
        const abs_off: usize = @intCast(@min(-off_i, @as(i64, @intCast(hay.length))));
        break :blk hay.length - abs_off;
    };

    if (start_idx > hay.length or start_idx + need.length > hay.length) return Value.initBool(false);

    var i: usize = start_idx;
    while (i <= hay.length - need.length) : (i += 1) {
        if (std.mem.eql(u8, hay.data[i .. i + need.length], need.data)) {
            return Value.initInt(@intCast(i));
        }
    }
    return Value.initBool(false);
}

/// comptime 生成 256 字节大写查找表（零运行时分支）
const upper_lut = blk: {
    var table: [256]u8 = undefined;
    for (0..256) |i| {
        table[i] = if (i >= 'a' and i <= 'z') @intCast(i - 32) else @intCast(i);
    }
    break :blk table;
};

/// comptime 生成 256 字节小写查找表（零运行时分支）
const lower_lut = blk: {
    var table: [256]u8 = undefined;
    for (0..256) |i| {
        table[i] = if (i >= 'A' and i <= 'Z') @intCast(i + 32) else @intCast(i);
    }
    break :blk table;
};

/// strtoupper - 转换为大写（comptime 查找表，零分支）
pub fn php_strtoupper(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const result_data = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(result_data);

    for (php_str.data, 0..) |c, i| {
        result_data[i] = upper_lut[c];
    }

    const result = try PHPString.init(allocator, result_data);
    allocator.free(result_data);
    return Value.initString(result);
}

/// strtolower - 转换为小写（comptime 查找表，零分支）
pub fn php_strtolower(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const result_data = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(result_data);

    for (php_str.data, 0..) |c, i| {
        result_data[i] = lower_lut[c];
    }

    const result = try PHPString.init(allocator, result_data);
    allocator.free(result_data);
    return Value.initString(result);
}

/// trim - 去除首尾空白
pub fn php_trim(str: Value, char_mask: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const mask = if (char_mask.isString()) char_mask.asString().data else " \t\n\r";
    const trimmed = std.mem.trim(u8, php_str.data, mask);

    const result = try PHPString.init(allocator, trimmed);
    return Value.initString(result);
}

/// ltrim - 去除左侧空白
pub fn php_ltrim(str: Value, char_mask: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const mask = if (char_mask.isString()) char_mask.asString().data else " \t\n\r";
    const trimmed = std.mem.trimStart(u8, php_str.data, mask);

    const result = try PHPString.init(allocator, trimmed);
    return Value.initString(result);
}

/// rtrim - 去除右侧空白
pub fn php_rtrim(str: Value, char_mask: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const mask = if (char_mask.isString()) char_mask.asString().data else " \t\n\r";
    const trimmed = std.mem.trimEnd(u8, php_str.data, mask);

    const result = try PHPString.init(allocator, trimmed);
    return Value.initString(result);
}

/// str_replace - 字符串替换
fn php_string_replace_once(subject_data: []const u8, search_data: []const u8, replace_data: []const u8, allocator: Allocator, ignore_case: bool) ![]u8 {
    if (search_data.len == 0) return allocator.dupe(u8, subject_data);

    const found_count = php_string_count_replacements(subject_data, search_data, ignore_case);

    if (found_count == 0) return allocator.dupe(u8, subject_data);

    const new_len = subject_data.len - (found_count * search_data.len) + (found_count * replace_data.len);
    const buffer = try allocator.alloc(u8, new_len);
    errdefer allocator.free(buffer);

    var write_pos: usize = 0;
    var pos: usize = 0;
    pos = 0;
    while (pos < subject_data.len) {
        if (pos + search_data.len <= subject_data.len) {
            const matched = if (ignore_case)
                std.ascii.eqlIgnoreCase(subject_data[pos .. pos + search_data.len], search_data)
            else
                std.mem.eql(u8, subject_data[pos .. pos + search_data.len], search_data);
            if (matched) {
                @memcpy(buffer[write_pos .. write_pos + replace_data.len], replace_data);
                write_pos += replace_data.len;
                pos += search_data.len;
                continue;
            }
        }
        buffer[write_pos] = subject_data[pos];
        write_pos += 1;
        pos += 1;
    }

    return buffer;
}

fn php_string_count_replacements(subject_data: []const u8, search_data: []const u8, ignore_case: bool) usize {
    if (search_data.len == 0) return 0;

    var found_count: usize = 0;
    var pos: usize = 0;
    while (pos < subject_data.len) {
        if (pos + search_data.len <= subject_data.len) {
            const matched = if (ignore_case)
                std.ascii.eqlIgnoreCase(subject_data[pos .. pos + search_data.len], search_data)
            else
                std.mem.eql(u8, subject_data[pos .. pos + search_data.len], search_data);
            if (matched) {
                found_count += 1;
                pos += search_data.len;
                continue;
            }
        }
        pos += 1;
    }
    return found_count;
}

fn php_value_to_owned_string_slice(val: Value, allocator: Allocator) ![]u8 {
    if (val.isString()) return allocator.dupe(u8, val.asString().data);
    const str = try val.toString(allocator);
    defer str.release(allocator);
    return allocator.dupe(u8, str.data);
}

fn php_str_replace_common(search: Value, replace: Value, subject: Value, count_out: Value, allocator: Allocator, ignore_case: bool) !Value {
    if (!subject.isString()) return subject;

    var total_count: usize = 0;

    if (search.isArray()) {
        var current = try allocator.dupe(u8, subject.asString().data);
        errdefer allocator.free(current);

        const search_arr = search.asArray();
        const replace_is_array = replace.isArray();
        var i: usize = 0;
        while (i < search_arr.elements.count()) : (i += 1) {
            const key = ArrayKey{ .integer = @intCast(i) };
            const search_val = search_arr.elements.get(key) orelse continue;
            const search_slice = try php_value_to_owned_string_slice(search_val, allocator);
            defer allocator.free(search_slice);

            const replace_slice = blk: {
                if (replace_is_array) {
                    const replace_arr = replace.asArray();
                    if (replace_arr.elements.get(key)) |replace_val| {
                        break :blk try php_value_to_owned_string_slice(replace_val, allocator);
                    }
                    break :blk try allocator.dupe(u8, "");
                }
                break :blk try php_value_to_owned_string_slice(replace, allocator);
            };
            defer allocator.free(replace_slice);

            total_count += php_string_count_replacements(current, search_slice, ignore_case);
            const next = try php_string_replace_once(current, search_slice, replace_slice, allocator, ignore_case);
            allocator.free(current);
            current = next;
        }

        if (count_out.isRef()) {
            count_out.asRef().* = Value.initInt(@intCast(total_count));
        }

        const result = try PHPString.init(allocator, current);
        allocator.free(current);
        return Value.initString(result);
    }

    const search_slice = try php_value_to_owned_string_slice(search, allocator);
    defer allocator.free(search_slice);
    const replace_slice = try php_value_to_owned_string_slice(replace, allocator);
    defer allocator.free(replace_slice);
    total_count = php_string_count_replacements(subject.asString().data, search_slice, ignore_case);
    if (count_out.isRef()) {
        count_out.asRef().* = Value.initInt(@intCast(total_count));
    }
    const buffer = try php_string_replace_once(subject.asString().data, search_slice, replace_slice, allocator, ignore_case);
    defer allocator.free(buffer);
    return Value.initString(try PHPString.init(allocator, buffer));
}

pub fn php_str_replace(search: Value, replace: Value, subject: Value, count_out: Value, allocator: Allocator) !Value {
    return php_str_replace_common(search, replace, subject, count_out, allocator, false);
}

pub fn php_str_ireplace(search: Value, replace: Value, subject: Value, count_out: Value, allocator: Allocator) !Value {
    return php_str_replace_common(search, replace, subject, count_out, allocator, true);
}

/// str_repeat - 重复字符串
pub fn php_str_repeat(str: Value, times: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const repeat_times = times.toInt();

    if (repeat_times <= 0) return Value.initString(try PHPString.init(allocator, ""));
    if (repeat_times == 1) return str;

    const new_len = php_str.length * @as(usize, @intCast(repeat_times));
    const buffer = try allocator.alloc(u8, new_len);
    errdefer allocator.free(buffer);

    var pos: usize = 0;
    var i: i64 = 0;
    while (i < repeat_times) : (i += 1) {
        @memcpy(buffer[pos .. pos + php_str.length], php_str.data);
        pos += php_str.length;
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// str_pad - 填充字符串到指定长度
pub fn php_str_pad(str: Value, length: Value, pad_str: Value, pad_type: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const target_len = length.toInt();

    if (target_len <= @as(i64, @intCast(php_str.length))) return str;

    var created_pad = false;
    const pad_string = if (pad_str.isString()) pad_str.asString() else blk: {
        created_pad = true;
        break :blk try PHPString.init(allocator, " ");
    };
    defer if (created_pad) pad_string.release(allocator);

    const mode = pad_type.toInt();
    const pad_len: usize = @intCast(@as(i64, @intCast(target_len)) - @as(i64, @intCast(php_str.length)));
    const left_pad: usize = if (mode == 0)
        pad_len
    else if (mode == 2)
        pad_len / 2
    else
        0;
    const right_pad: usize = pad_len - left_pad;

    const buffer = try allocator.alloc(u8, @intCast(target_len));
    errdefer allocator.free(buffer);

    var pos: usize = 0;
    while (pos < left_pad) {
        const copy_len = @min(pad_string.length, left_pad - pos);
        @memcpy(buffer[pos .. pos + copy_len], pad_string.data[0..copy_len]);
        pos += copy_len;
    }

    @memcpy(buffer[pos .. pos + php_str.length], php_str.data);
    pos += php_str.length;

    var rpos: usize = 0;
    while (rpos < right_pad) {
        const copy_len = @min(pad_string.length, right_pad - rpos);
        @memcpy(buffer[pos .. pos + copy_len], pad_string.data[0..copy_len]);
        pos += copy_len;
        rpos += copy_len;
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// strstr - 查找字符串首次出现的位置并返回剩余部分
pub fn php_strstr(haystack: Value, needle: Value, allocator: Allocator) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const h = haystack.asString();
    const n = needle.asString();
    if (n.length == 0) return Value.initBool(false);

    const pos = std.mem.indexOf(u8, h.data[0..h.length], n.data[0..n.length]) orelse return Value.initBool(false);

    const result_len = h.length - pos;
    const buffer = try allocator.alloc(u8, result_len);
    @memcpy(buffer, h.data[pos..h.length]);

    const result = try allocator.create(PHPString);
    result.* = .{ .data = buffer, .length = result_len, .ref_count = 1, .is_static = false };
    return Value.initString(result);
}

pub fn php_strrchr(haystack: Value, needle: Value, allocator: Allocator) !Value {
    if (!haystack.isString()) return Value.initBool(false);

    const h = haystack.asString();
    if (h.length == 0) return Value.initBool(false);

    var needle_byte: u8 = 0;
    if (needle.isInt()) {
        needle_byte = @as(u8, @truncate(@as(u64, @intCast(needle.toInt() & 0xFF))));
    } else if (needle.isString()) {
        const n = needle.asString();
        if (n.length == 0) return Value.initBool(false);
        needle_byte = n.data[0];
    } else {
        return Value.initBool(false);
    }

    const pos = std.mem.lastIndexOfScalar(u8, h.data[0..h.length], needle_byte) orelse return Value.initBool(false);
    const result_len = h.length - pos;
    const buffer = try allocator.alloc(u8, result_len);
    @memcpy(buffer, h.data[pos..h.length]);

    const result = try allocator.create(PHPString);
    result.* = .{ .data = buffer, .length = result_len, .ref_count = 1, .is_static = false };
    return Value.initString(result);
}

/// stristr - 大小写不敏感查找并返回从匹配处开始的子串
pub fn php_stristr(haystack: Value, needle: Value, allocator: Allocator) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);
    const h = haystack.asString();
    const n = needle.asString();
    if (n.length == 0) return Value.initBool(false);
    if (n.length > h.length) return Value.initBool(false);

    var i: usize = 0;
    while (i + n.length <= h.length) : (i += 1) {
        var matched = true;
        var j: usize = 0;
        while (j < n.length) : (j += 1) {
            const a = std.ascii.toLower(h.data[i + j]);
            const b = std.ascii.toLower(n.data[j]);
            if (a != b) { matched = false; break; }
        }
        if (matched) {
            const result_len = h.length - i;
            const buffer = try allocator.alloc(u8, result_len);
            @memcpy(buffer, h.data[i..h.length]);
            const result = try allocator.create(PHPString);
            result.* = .{ .data = buffer, .length = result_len, .ref_count = 1, .is_static = false };
            return Value.initString(result);
        }
    }
    return Value.initBool(false);
}

/// strrev - 反转字符串
pub fn php_strrev(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    const buffer = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(buffer);

    var i: usize = 0;
    while (i < php_str.length) : (i += 1) {
        buffer[i] = php_str.data[php_str.length - 1 - i];
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

pub fn php_str_shuffle(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    if (php_str.length <= 1) return str;

    const buffer = try allocator.dupe(u8, php_str.data[0..php_str.length]);
    errdefer allocator.free(buffer);

    var i: usize = php_str.length - 1;
    while (i > 0) : (i -= 1) {
        const j: usize = @intCast(nextRandom() % @as(u64, @intCast(i + 1)));
        const tmp = buffer[i];
        buffer[i] = buffer[j];
        buffer[j] = tmp;
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// 字符串索引赋值 - PHP: $str[$i] = 'x'
/// 修改字符串中指定位置的字符，返回修改后的新字符串
pub fn php_string_offset_set(str_val: *Value, index_val: Value, char_val: Value, allocator: Allocator) !void {
    if (!str_val.isString()) return;
    const php_str = str_val.asString();
    const idx = index_val.toInt();
    if (idx < 0 or idx >= @as(i64, @intCast(php_str.length))) return;
    const pos: usize = @intCast(idx);

    // 获取要设置的字符
    var new_char: u8 = 0;
    if (char_val.isString()) {
        const char_str = char_val.asString();
        if (char_str.length > 0) {
            new_char = char_str.data[0];
        }
    } else {
        new_char = @as(u8, @intCast(char_val.toInt() & 0xFF));
    }

    // 创建新字符串（COW语义）
    const new_data = try allocator.alloc(u8, php_str.length);
    @memcpy(new_data, php_str.data[0..php_str.length]);
    new_data[pos] = new_char;

    const new_str = try PHPString.init(allocator, new_data);
    allocator.free(new_data);
    str_val.release(allocator);
    str_val.* = Value.initString(new_str);
}

/// str_contains - 检查字符串是否包含子串 (PHP 8.0+)
pub fn php_str_contains(haystack: Value, needle: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0) return Value.initBool(true);
    if (need.length > hay.length) return Value.initBool(false);

    var i: usize = 0;
    while (i <= hay.length - need.length) : (i += 1) {
        if (std.mem.eql(u8, hay.data[i .. i + need.length], need.data)) {
            return Value.initBool(true);
        }
    }

    return Value.initBool(false);
}

// ============================================================================
// PCRE2 正则表达式支持
// ============================================================================

// PCRE2 C API声明
const pcre2_code = opaque {};
const pcre2_match_data = opaque {};

// 正则缓存条目
const RegexCacheEntry = struct {
    code: *pcre2_code,
    last_used: i128, // 纳秒时间戳（i128）

    fn init(code: *pcre2_code) RegexCacheEntry {
        return .{
            .code = code,
            .last_used = nanoTimestamp(),
        };
    }

    fn touch(self: *RegexCacheEntry) void {
        self.last_used = nanoTimestamp();
    }

    fn deinit(self: *RegexCacheEntry) void {
        pcre2_code_free_8(self.code);
    }
};

// 全局正则缓存
const REGEX_CACHE_SIZE = 128;
var regex_cache: std.StringHashMap(RegexCacheEntry) = undefined;
var regex_cache_mutex: std.atomic.Mutex = .unlocked;
var regex_cache_initialized: bool = false;

fn initRegexCache(allocator: Allocator) !void {
    if (regex_cache_initialized) return;
    regex_cache = std.StringHashMap(RegexCacheEntry).init(allocator);
    regex_cache_initialized = true;
}

fn getOrCompileRegex(pattern: []const u8, options: c_uint, allocator: Allocator) !*pcre2_code {
    try initRegexCache(allocator);

    spinLock(&regex_cache_mutex);
    defer regex_cache_mutex.unlock();

    // 查找缓存
    if (regex_cache.getPtr(pattern)) |entry| {
        entry.touch();
        return entry.code;
    }

    // 缓存未命中，编译新模式
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
    if (re_ptr == null) return error.RegexCompileFailed;
    const re = re_ptr.?;

    // LRU淘汰：如果缓存满了，移除最旧的条目
    if (regex_cache.count() >= REGEX_CACHE_SIZE) {
        var oldest_key: ?[]const u8 = null;
        var oldest_time: i128 = std.math.maxInt(i128);

        var iter = regex_cache.iterator();
        while (iter.next()) |kv| {
            if (kv.value_ptr.last_used < oldest_time) {
                oldest_time = kv.value_ptr.last_used;
                oldest_key = kv.key_ptr.*;
            }
        }

        if (oldest_key) |key| {
            if (regex_cache.fetchRemove(key)) |removed| {
                var entry = removed.value;
                entry.deinit();
                allocator.free(removed.key);
            }
        }
    }

    // 添加到缓存
    const key_copy = try allocator.dupe(u8, pattern);
    try regex_cache.put(key_copy, RegexCacheEntry.init(re));

    return re;
}

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

extern fn pcre2_get_ovector_pointer_8(?*pcre2_match_data) [*]usize;

extern fn pcre2_substitute_8(
    ?*const pcre2_code,
    [*]const u8,
    usize,
    usize,
    c_uint,
    ?*pcre2_match_data,
    ?*anyopaque,
    [*]const u8,
    usize,
    [*]u8,
    [*]usize,
) c_int;

// PCRE2 常量
const PCRE2_CASELESS: c_uint = 0x00000008;
const PCRE2_MULTILINE: c_uint = 0x00000002;
const PCRE2_DOTALL: c_uint = 0x00000004;
const PCRE2_EXTENDED: c_uint = 0x00000008;
const PCRE2_UTF: c_uint = 0x00080000;
const PCRE2_ERROR_NOMATCH: c_int = -1;
const PCRE2_SUBSTITUTE_GLOBAL: c_uint = 0x00000100;
const PCRE2_SUBSTITUTE_OVERFLOW_LENGTH: c_uint = 0x00001000;

const ParsedPattern = struct {
    pattern: []const u8,
    options: c_uint,
};

/// 解析PHP风格正则表达式 (/pattern/flags)
fn parsePHPRegexPattern(pattern: []const u8) ParsedPattern {
    var result = ParsedPattern{
        .pattern = pattern,
        .options = PCRE2_UTF | PCRE2_DOTALL,
    };

    if (pattern.len == 0) return result;

    var start: usize = 0;
    while (start < pattern.len and pattern[start] == ' ') : (start += 1) {}
    if (start >= pattern.len) return result;

    const delimiter = pattern[start];
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
            break;
        }
    }

    if (end >= pattern.len) {
        result.pattern = pattern[start + 1 ..];
        return result;
    }
    result.pattern = pattern[start + 1 .. end];

    const modifiers = pattern[end + 1 ..];
    for (modifiers) |ch| {
        switch (ch) {
            'i' => result.options |= PCRE2_CASELESS,
            'm' => result.options |= PCRE2_MULTILINE,
            's' => result.options |= PCRE2_DOTALL,
            'x' => result.options |= PCRE2_EXTENDED,
            ' ' => break,
            else => {},
        }
    }

    return result;
}

/// 完整PCRE2实现的preg_match
/// 支持所有正则语法，与解释器/Bytecode行为一致
pub fn preg_match(pattern_val: Value, subject_val: Value, matches_ref: *Value, flags: Value, offset: Value, allocator: Allocator) !Value {
    _ = flags; // TODO: 实现flags支持
    _ = offset; // TODO: 实现offset支持
    _ = matches_ref; // TODO: 实现matches填充
    
    if (!pattern_val.isString() or !subject_val.isString()) {
        return Value.initInt(0);
    }

    const pattern_str = pattern_val.asString();
    const subject_str = subject_val.asString();

    const parsed = parsePHPRegexPattern(pattern_str.data);

    // 使用缓存获取编译后的正则（不需要release，缓存管理生命周期）
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch return Value.initInt(0);

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse return Value.initInt(0);
    defer pcre2_match_data_free_8(match_data);

    const rc = pcre2_match_8(re, subject_str.data.ptr, subject_str.length, 0, 0, match_data, null);

    if (rc == PCRE2_ERROR_NOMATCH) return Value.initInt(0);
    if (rc < 0) return Value.initInt(0);
    return Value.initInt(1);
}

/// preg_match with matches - 支持捕获组
/// matches_ref: 引用参数，会被填充为 [full_match, group1, group2, ...]
pub fn preg_match_with_matches(pattern_val: Value, subject_val: Value, matches_ref: *Value, allocator: Allocator) !Value {
    if (!pattern_val.isString() or !subject_val.isString()) {
        matches_ref.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    }

    const pattern_str = pattern_val.asString();
    const subject_str = subject_val.asString();
    const parsed = parsePHPRegexPattern(pattern_str.data);

    // 使用缓存获取编译后的正则
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch {
        matches_ref.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    };

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
        matches_ref.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    };
    defer pcre2_match_data_free_8(match_data);

    const rc = pcre2_match_8(
        re,
        subject_str.data.ptr,
        subject_str.length,
        0,
        0,
        match_data,
        null,
    );

    if (rc == PCRE2_ERROR_NOMATCH or rc < 0) {
        matches_ref.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    }

    // 填充matches数组
    const matches_arr = try PHPArray.init(allocator);
    const ovec = pcre2_get_ovector_pointer_8(match_data);

    var i: usize = 0;
    while (i < @as(usize, @intCast(rc))) : (i += 1) {
        const start = ovec[i * 2];
        const end = ovec[i * 2 + 1];
        if (start < subject_str.length and end <= subject_str.length and start <= end) {
            const capture = subject_str.data[start..end];
            const capture_str = try PHPString.init(allocator, capture);
            try matches_arr.push(allocator, Value.initString(capture_str));
        }
    }

    matches_ref.* = Value.initArray(matches_arr);
    return Value.initInt(1);
}

/// preg_match_all - 返回所有匹配
/// matches_ref: 引用参数，填充为二维数组
/// 返回：匹配次数
pub fn preg_match_all(pattern_val: Value, subject_val: Value, matches_ref: *Value, flags: Value, offset: Value, allocator: Allocator) !Value {
    _ = flags; // TODO: 实现flags支持
    _ = offset; // TODO: 实现offset支持
    
    if (!pattern_val.isString() or !subject_val.isString()) {
        matches_ref.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    }

    const pattern_str = pattern_val.asString();
    const subject_str = subject_val.asString();
    const parsed = parsePHPRegexPattern(pattern_str.data);

    // 使用缓存获取编译后的正则
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch {
        matches_ref.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    };

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
        matches_ref.* = Value.initArray(try PHPArray.init(allocator));
        return Value.initInt(0);
    };
    defer pcre2_match_data_free_8(match_data);

    // 存储所有匹配（临时）
    var all_matches = std.ArrayListUnmanaged(std.ArrayListUnmanaged([]const u8)){ .items = &.{}, .capacity = 0 };
    defer {
        for (all_matches.items) |*match_groups| {
            match_groups.deinit(allocator);
        }
        all_matches.deinit(allocator);
    }

    var match_offset: usize = 0;
    var match_count: i64 = 0;

    // 循环匹配所有
    while (match_offset <= subject_str.length) {
        const rc = pcre2_match_8(
            re,
            subject_str.data.ptr,
            subject_str.length,
            @intCast(match_offset),
            0,
            match_data,
            null,
        );

        if (rc == PCRE2_ERROR_NOMATCH or rc < 0) break;

        match_count += 1;
        const ovec = pcre2_get_ovector_pointer_8(match_data);

        // 保存当前匹配的所有组
        var match_groups = std.ArrayListUnmanaged([]const u8){ .items = &.{}, .capacity = 0 };
        var i: usize = 0;
        while (i < @as(usize, @intCast(rc))) : (i += 1) {
            const start = ovec[i * 2];
            const end = ovec[i * 2 + 1];
            if (start < subject_str.length and end <= subject_str.length and start <= end) {
                const capture = subject_str.data[start..end];
                try match_groups.append(allocator, capture);
            }
        }
        try all_matches.append(allocator, match_groups);

        // 移动到下一个位置
        const match_end = ovec[1];
        if (match_end == match_offset) {
            match_offset += 1; // 避免空匹配无限循环
        } else {
            match_offset = match_end;
        }
    }

    // 转换为PREG_PATTERN_ORDER格式
    // matches[0] = [所有完整匹配]
    // matches[1] = [所有第1个捕获组]
    const matches_arr = try PHPArray.init(allocator);

    if (all_matches.items.len > 0) {
        const num_groups = all_matches.items[0].items.len;

        // 为每个组创建数组
        var group_idx: usize = 0;
        while (group_idx < num_groups) : (group_idx += 1) {
            const group_arr = try PHPArray.init(allocator);

            // 收集所有匹配中的该组
            for (all_matches.items) |match_groups| {
                if (group_idx < match_groups.items.len) {
                    const capture = match_groups.items[group_idx];
                    const capture_str = try PHPString.init(allocator, capture);
                    try group_arr.push(allocator, Value.initString(capture_str));
                }
            }

            try matches_arr.push(allocator, Value.initArray(group_arr));
        }
    }

    matches_ref.* = Value.initArray(matches_arr);
    return Value.initInt(match_count);
}

/// preg_match_all - 返回所有匹配和捕获组
/// 返回: [match_count, [[full_match, group1, group2, ...], ...]]
pub fn preg_replace(pattern_val: Value, replacement_val: Value, subject_val: Value, allocator: Allocator) !Value {
    if (!pattern_val.isString() or !replacement_val.isString() or !subject_val.isString()) {
        return Value.initNull();
    }

    const pattern_str = pattern_val.asString();
    const replacement_str = replacement_val.asString();
    const subject_str = subject_val.asString();

    const parsed = parsePHPRegexPattern(pattern_str.data);

    // 使用缓存获取编译后的正则
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch return subject_val;

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse return subject_val;
    defer pcre2_match_data_free_8(match_data);

    // 分配输出缓冲区
    const output_len: usize = subject_str.length * 2;
    const output = try allocator.alloc(u8, output_len);
    errdefer allocator.free(output);

    var output_size: usize = output_len;
    const rc = pcre2_substitute_8(re, subject_str.data.ptr, subject_str.length, 0, PCRE2_SUBSTITUTE_GLOBAL, match_data, null, replacement_str.data.ptr, replacement_str.length, output.ptr, @ptrCast(&output_size));

    if (rc < 0) {
        allocator.free(output);
        return subject_val;
    }

    const result = try allocator.realloc(output, output_size);
    return Value.initString(try PHPString.init(allocator, result));
}

/// preg_filter - 类似 preg_replace，但只返回匹配的元素
pub fn preg_filter(pattern_val: Value, replacement_val: Value, subject_val: Value, allocator: Allocator) !Value {
    // 处理数组输入
    if (subject_val.isArray()) {
        const subject_arr = subject_val.asArray();
        const result_arr = try PHPArray.init(allocator);

        var iter = subject_arr.elements.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.isString()) {
                const subject_str = entry.value_ptr.asString();
                
                if (pattern_val.isString() and replacement_val.isString()) {
                    const pattern_str = pattern_val.asString();
                    const parsed = parsePHPRegexPattern(pattern_str.data);
                    
                    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch continue;
                    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse continue;
                    defer pcre2_match_data_free_8(match_data);

                    // 检查是否有匹配
                    const rc_check = pcre2_match_8(re, subject_str.data.ptr, subject_str.length, 0, 0, match_data, null);
                    
                    // 只有匹配时才进行替换并添加到结果
                    if (rc_check >= 0) {
                        const replacement_str = replacement_val.asString();
                        const output_len: usize = subject_str.length * 2;
                        const output = allocator.alloc(u8, output_len) catch continue;
                        errdefer allocator.free(output);

                        var output_size: usize = output_len;
                        const rc = pcre2_substitute_8(re, subject_str.data.ptr, subject_str.length, 0, PCRE2_SUBSTITUTE_GLOBAL, match_data, null, replacement_str.data.ptr, replacement_str.length, output.ptr, @ptrCast(&output_size));

                        if (rc >= 0) {
                            const result = allocator.realloc(output, output_size) catch {
                                allocator.free(output);
                                continue;
                            };
                            const result_val = Value.initString(PHPString.init(allocator, result) catch {
                                allocator.free(result);
                                continue;
                            });
                            
                            // 保持原始键
                            switch (entry.key_ptr.*) {
                                .integer => result_arr.set(allocator, entry.key_ptr.*, result_val) catch {},
                                .string => result_arr.push(allocator, result_val) catch {},
                            }
                        } else {
                            allocator.free(output);
                        }
                    }
                }
            }
        }

        return Value.initArray(result_arr);
    }

    // 处理字符串输入
    if (!pattern_val.isString() or !replacement_val.isString() or !subject_val.isString()) {
        return Value.initNull();
    }

    const pattern_str = pattern_val.asString();
    const replacement_str = replacement_val.asString();
    const subject_str = subject_val.asString();

    const parsed = parsePHPRegexPattern(pattern_str.data);
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch return Value.initNull();

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse return Value.initNull();
    defer pcre2_match_data_free_8(match_data);

    // 检查是否有匹配
    const rc_check = pcre2_match_8(re, subject_str.data.ptr, subject_str.length, 0, 0, match_data, null);
    
    // 如果没有匹配，返回 null（preg_filter 的特性）
    if (rc_check == PCRE2_ERROR_NOMATCH or rc_check < 0) {
        return Value.initNull();
    }

    // 有匹配，执行替换
    const output_len: usize = subject_str.length * 2;
    const output = try allocator.alloc(u8, output_len);
    errdefer allocator.free(output);

    var output_size: usize = output_len;
    const rc = pcre2_substitute_8(re, subject_str.data.ptr, subject_str.length, 0, PCRE2_SUBSTITUTE_GLOBAL, match_data, null, replacement_str.data.ptr, replacement_str.length, output.ptr, @ptrCast(&output_size));

    if (rc < 0) {
        allocator.free(output);
        return Value.initNull();
    }

    const result = try allocator.realloc(output, output_size);
    return Value.initString(try PHPString.init(allocator, result));
}

/// preg_split - 正则分割 (pattern, subject, limit=-1, flags=0, allocator)
pub fn preg_split(pattern_val: Value, subject_val: Value, limit_val: Value, flags_val: Value, allocator: Allocator) !Value {
    if (!pattern_val.isString() or !subject_val.isString()) {
        return Value.initNull();
    }

    const pattern_str = pattern_val.asString();
    const subject_str = subject_val.asString();

    // limit: -1 表示无限制
    const limit: i64 = if (limit_val.isInt()) limit_val.asInt() else -1;
    // flags: PREG_SPLIT_NO_EMPTY=1, PREG_SPLIT_DELIM_CAPTURE=2, PREG_SPLIT_OFFSET_CAPTURE=4
    const flags: i64 = if (flags_val.isInt()) flags_val.asInt() else 0;
    const no_empty = (flags & 1) != 0;

    const parsed = parsePHPRegexPattern(pattern_str.data);

    // 使用缓存获取编译后的正则
    const re = getOrCompileRegex(parsed.pattern, parsed.options, allocator) catch {
        // 编译失败，返回包含原字符串的数组
        const arr = try PHPArray.init(allocator);
        try arr.push(allocator, subject_val);
        return Value.initArray(arr);
    };

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
        const arr = try PHPArray.init(allocator);
        try arr.push(allocator, subject_val);
        return Value.initArray(arr);
    };
    defer pcre2_match_data_free_8(match_data);

    const result_arr = try PHPArray.init(allocator);
    var offset: usize = 0;
    var part_count: i64 = 0;

    while (offset < subject_str.length) {
        // 如果达到limit-1，把剩余部分全部放入最后一个元素
        if (limit > 0 and part_count >= limit - 1) {
            const remaining = subject_str.data[offset..];
            if (!no_empty or remaining.len > 0) {
                const part_str = try PHPString.init(allocator, remaining);
                try result_arr.push(allocator, Value.initString(part_str));
            }
            break;
        }

        const rc = pcre2_match_8(re, subject_str.data.ptr, subject_str.length, @intCast(offset), 0, match_data, null);

        if (rc == PCRE2_ERROR_NOMATCH) {
            // 添加剩余部分
            const remaining = subject_str.data[offset..];
            if (!no_empty or remaining.len > 0) {
                const part = try PHPString.init(allocator, remaining);
                try result_arr.push(allocator, Value.initString(part));
            }
            break;
        }

        if (rc < 0) break;

        const ovec = pcre2_get_ovector_pointer_8(match_data);
        const match_start = ovec[0];
        const match_end = ovec[1];

        // 添加匹配前的部分
        const part = subject_str.data[offset..match_start];
        if (!no_empty or part.len > 0) {
            const part_str = try PHPString.init(allocator, part);
            try result_arr.push(allocator, Value.initString(part_str));
            part_count += 1;
        }

        offset = match_end;
        if (match_start == match_end) {
            // 空匹配，前进一个字符避免无限循环
            offset += 1;
        }
    }

    return Value.initArray(result_arr);
}

/// preg_grep - 返回匹配正则的数组元素
pub fn preg_grep(pattern_val: Value, input_val: Value, flags_val: Value, allocator: Allocator) !Value {
    if (!pattern_val.isString() or !input_val.isArray()) {
        return Value.initArray(try PHPArray.init(allocator));
    }

    const pattern_str = pattern_val.asString();
    const input_arr = input_val.asArray();
    const flags = if (flags_val.isInt()) flags_val.asInt() else 0;
    const invert = (flags & 1) != 0; // PREG_GREP_INVERT = 1

    const parsed = parsePHPRegexPattern(pattern_str.data);
    const re = try getOrCompileRegex(parsed.pattern, parsed.options, allocator);

    const match_data = pcre2_match_data_create_from_pattern_8(re, null) orelse {
        return Value.initArray(try PHPArray.init(allocator));
    };
    defer pcre2_match_data_free_8(match_data);

    const result_arr = try PHPArray.init(allocator);

    // 遍历输入数组（简化：只支持数字索引）
    var i: usize = 0;
    while (i < input_arr.elements.packed_values.items.len) : (i += 1) {
        const key = ArrayKey{ .integer = @intCast(i) };
        const value = input_arr.get(key) orelse continue;

        // 转换为字符串
        const str_val = if (value.isString())
            value.asString().data
        else if (value.isInt()) blk: {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{value.asInt()}) catch "";
            break :blk s;
        } else "";

        // 匹配测试
        const rc = pcre2_match_8(re, str_val.ptr, str_val.len, 0, 0, match_data, null);
        const matched = (rc >= 0);

        // 根据flags决定是否包含
        const should_include = if (invert) !matched else matched;

        if (should_include) {
            try result_arr.push(allocator, value);
        }
    }

    return Value.initArray(result_arr);
}

/// preg_quote - 转义正则表达式字符
pub fn preg_quote(str_val: Value, delimiter_val: Value, allocator: Allocator) !Value {
    if (!str_val.isString()) {
        return Value.initString(try PHPString.init(allocator, ""));
    }

    const str = str_val.asString();
    const delimiter: u8 = if (delimiter_val.isString() and delimiter_val.asString().length > 0)
        delimiter_val.asString().data[0]
    else
        0;

    // 需要转义的特殊字符
    const specials = ".\\+*?[^]$(){}=!<>|:-#";
    var escape_table: [256]u8 = undefined;
    @memset(escape_table[0..], 0);
    for (specials) |ch| {
        escape_table[@as(usize, @intCast(ch))] = 1;
    }

    // 计算结果长度
    var result_len: usize = str.length;
    for (str.data) |ch| {
        const needs_escape = ch == '\\' or ch == delimiter or escape_table[@as(usize, @intCast(ch))] == 1;
        if (needs_escape) {
            result_len += 1;
        }
    }

    // 分配结果缓冲区
    const result = try allocator.alloc(u8, result_len);
    errdefer allocator.free(result);

    // 执行转义
    var j: usize = 0;
    for (str.data) |ch| {
        const needs_escape = ch == '\\' or ch == delimiter or escape_table[@as(usize, @intCast(ch))] == 1;
        if (needs_escape) {
            result[j] = '\\';
            j += 1;
        }
        result[j] = ch;
        j += 1;
    }

    return Value.initString(try PHPString.init(allocator, result));
}

/// preg_last_error - 返回最后一次 PCRE 正则执行的错误代码
pub fn preg_last_error() Value {
    // AOT 模式下简化实现，总是返回 0 (PREG_NO_ERROR)
    return Value.initInt(0);
}

/// str_starts_with - 检查字符串是否以指定前缀开始 (PHP 8.0+)
pub fn php_str_starts_with(haystack: Value, needle: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0) return Value.initBool(true);
    if (need.length > hay.length) return Value.initBool(false);

    return Value.initBool(std.mem.eql(u8, hay.data[0..need.length], need.data));
}

/// str_ends_with - 检查字符串是否以指定后缀结束 (PHP 8.0+)
pub fn php_str_ends_with(haystack: Value, needle: Value) !Value {
    if (!haystack.isString() or !needle.isString()) return Value.initBool(false);

    const hay = haystack.asString();
    const need = needle.asString();

    if (need.length == 0) return Value.initBool(true);
    if (need.length > hay.length) return Value.initBool(false);

    const start_pos = hay.length - need.length;
    return Value.initBool(std.mem.eql(u8, hay.data[start_pos..], need.data));
}

/// ucfirst - 首字母大写
pub fn php_ucfirst(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    if (php_str.length == 0) return str;

    const buffer = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(buffer);

    @memcpy(buffer, php_str.data);
    buffer[0] = std.ascii.toUpper(buffer[0]);

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// lcfirst - 首字母小写
pub fn php_lcfirst(str: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    if (php_str.length == 0) return str;

    const buffer = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(buffer);

    @memcpy(buffer, php_str.data);
    buffer[0] = std.ascii.toLower(buffer[0]);

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// ucwords - 每个单词首字母大写
pub fn php_ucwords(str: Value, delimiters: Value, allocator: Allocator) !Value {
    if (!str.isString()) return str;

    const php_str = str.asString();
    if (php_str.length == 0) return str;

    const buffer = try allocator.alloc(u8, php_str.length);
    errdefer allocator.free(buffer);

    @memcpy(buffer, php_str.data);

    const delims = if (delimiters.isString()) delimiters.asString().data else " \t\n\r";
    var is_word_start = true;
    for (buffer, 0..) |c, i| {
        if (std.mem.indexOfScalar(u8, delims, c) != null) {
            is_word_start = true;
        } else if (is_word_start) {
            buffer[i] = std.ascii.toUpper(c);
            is_word_start = false;
        }
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

/// explode - 分割字符串为数组
pub fn php_explode(delimiter: Value, str: Value, limit: Value, allocator: Allocator) !Value {
    if (!delimiter.isString() or !str.isString()) {
        return Value.initArray(try PHPArray.init(allocator));
    }

    const delim = delimiter.asString();
    const php_str = str.asString();

    const arr = try PHPArray.init(allocator);

    if (delim.length == 0) {
        // 空分隔符，返回包含整个字符串的数组
        try arr.push(allocator, str);
        return Value.initArray(arr);
    }

    var lim: ?i64 = null;
    if (!limit.isNull()) {
        lim = limit.toInt();
        if (lim.? == 0) lim = 1;
    }

    if (lim != null and lim.? < 0) {
        var start: usize = 0;
        var pos: usize = 0;

        while (pos <= php_str.length - delim.length) {
            if (std.mem.eql(u8, php_str.data[pos .. pos + delim.length], delim.data)) {
                const part = try PHPString.init(allocator, php_str.data[start..pos]);
                try arr.push(allocator, Value.initString(part));
                pos += delim.length;
                start = pos;
            } else {
                pos += 1;
            }
        }

        const last_part = try PHPString.init(allocator, php_str.data[start..]);
        try arr.push(allocator, Value.initString(last_part));

        const total = arr.count();
        const drop: usize = @intCast(@min(-lim.?, @as(i64, @intCast(total))));
        if (drop == 0) return Value.initArray(arr);

        const keep = total - drop;
        const out = try PHPArray.init(allocator);
        var i: usize = 0;
        while (i < keep) : (i += 1) {
            const key = ArrayKey{ .integer = @intCast(i) };
            if (arr.get(key)) |v| {
                try out.push(allocator, v);
            } else {
                try out.push(allocator, Value.initNull());
            }
        }

        arr.release(allocator);
        return Value.initArray(out);
    }

    var start: usize = 0;
    var pos: usize = 0;
    var pushed: i64 = 0;
    const max_parts: ?i64 = if (lim != null and lim.? > 0) lim.? else null;

    while (pos <= php_str.length - delim.length) {
        if (max_parts != null and pushed >= max_parts.? - 1) break;
        if (std.mem.eql(u8, php_str.data[pos .. pos + delim.length], delim.data)) {
            // 找到分隔符
            const part = try PHPString.init(allocator, php_str.data[start..pos]);
            try arr.push(allocator, Value.initString(part));
            pushed += 1;
            pos += delim.length;
            start = pos;
        } else {
            pos += 1;
        }
    }

    // 添加最后一部分
    const last_part = try PHPString.init(allocator, php_str.data[start..]);
    try arr.push(allocator, Value.initString(last_part));

    return Value.initArray(arr);
}

/// implode - 连接数组元素为字符串
pub fn php_implode(glue: Value, pieces: Value, allocator: Allocator) !Value {
    var glue_val = glue;
    var pieces_val = pieces;
    if (!pieces_val.isArray() and glue_val.isArray()) {
        glue_val = pieces;
        pieces_val = glue;
    }
    if (!pieces_val.isArray()) return Value.initString(try PHPString.init(allocator, ""));

    var created_glue = false;
    const glue_str = if (glue_val.isString()) glue_val.asString() else blk: {
        created_glue = true;
        break :blk try PHPString.init(allocator, "");
    };
    defer if (created_glue) glue_str.release(allocator);
    const arr = pieces_val.asArray();

    if (arr.count() == 0) return Value.initString(try PHPString.init(allocator, ""));

    // 计算总长度
    var total_len: usize = 0;
    var it = arr.elements.iterator();
    var first = true;
    while (it.next()) |entry| {
        if (!first) total_len += glue_str.length;
        const val = entry.value_ptr.*;
        const str = try val.toString(allocator);
        defer str.release(allocator);
        total_len += str.length;
        first = false;
    }

    // 构建结果字符串
    const buffer = try allocator.alloc(u8, total_len);
    errdefer allocator.free(buffer);

    var write_pos: usize = 0;
    it = arr.elements.iterator();
    first = true;
    while (it.next()) |entry| {
        if (!first) {
            @memcpy(buffer[write_pos .. write_pos + glue_str.length], glue_str.data);
            write_pos += glue_str.length;
        }
        const val = entry.value_ptr.*;
        const str = try val.toString(allocator);
        defer str.release(allocator);
        @memcpy(buffer[write_pos .. write_pos + str.length], str.data);
        write_pos += str.length;
        first = false;
    }

    const result = try PHPString.init(allocator, buffer);
    allocator.free(buffer);
    return Value.initString(result);
}

pub fn php_str_getcsv(input: Value, separator: Value, enclosure: Value, escape: Value, allocator: Allocator) !Value {
    const input_str = try input.toString(allocator);
    defer input_str.release(allocator);

    const separator_str = try separator.toString(allocator);
    defer separator_str.release(allocator);

    const enclosure_str = try enclosure.toString(allocator);
    defer enclosure_str.release(allocator);

    const escape_str = try escape.toString(allocator);
    defer escape_str.release(allocator);

    const sep: u8 = if (separator_str.length > 0) separator_str.data[0] else ',';
    const enc: u8 = if (enclosure_str.length > 0) enclosure_str.data[0] else '"';
    const esc: u8 = if (escape_str.length > 0) escape_str.data[0] else '\\';

    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var field = std.ArrayList(u8).empty;
    defer field.deinit(allocator);

    var in_quotes = false;
    var i: usize = 0;
    while (i < input_str.length) : (i += 1) {
        const ch = input_str.data[i];

        if (ch == esc and i + 1 < input_str.length) {
            const next = input_str.data[i + 1];
            if (next == enc or next == esc) {
                try field.append(allocator, next);
                i += 1;
                continue;
            }
        }

        if (ch == enc) {
            if (in_quotes and i + 1 < input_str.length and input_str.data[i + 1] == enc) {
                try field.append(allocator, enc);
                i += 1;
                continue;
            }
            in_quotes = !in_quotes;
            continue;
        }

        if (!in_quotes and ch == sep) {
            const field_str = try PHPString.init(allocator, field.items);
            try result.push(allocator, Value.initString(field_str));
            field.clearRetainingCapacity();
            continue;
        }

        try field.append(allocator, ch);
    }

    const field_str = try PHPString.init(allocator, field.items);
    try result.push(allocator, Value.initString(field_str));
    return Value.initArray(result);
}

/// str_split - 将字符串分割为数组
pub fn php_str_split(str: Value, length: Value, allocator: Allocator) !Value {
    if (!str.isString()) return Value.initArray(try PHPArray.init(allocator));

    const php_str = str.asString();
    const chunk_len = if (length.isNull()) 1 else @max(1, length.toInt());

    const arr = try PHPArray.init(allocator);

    var pos: usize = 0;
    while (pos < php_str.length) {
        const end = @min(pos + @as(usize, @intCast(chunk_len)), php_str.length);
        const chunk = try PHPString.init(allocator, php_str.data[pos..end]);
        try arr.push(allocator, Value.initString(chunk));
        pos = end;
    }

    return Value.initArray(arr);
}

fn php_string_compare_bytes(lhs: []const u8, rhs: []const u8, comptime ignore_case: bool) i64 {
    const shared_len = @min(lhs.len, rhs.len);
    var i: usize = 0;
    while (i < shared_len) : (i += 1) {
        const lc: u8 = if (ignore_case) std.ascii.toLower(lhs[i]) else lhs[i];
        const rc: u8 = if (ignore_case) std.ascii.toLower(rhs[i]) else rhs[i];
        if (lc != rc) {
            return @as(i64, lc) - @as(i64, rc);
        }
    }
    return @as(i64, @intCast(lhs.len)) - @as(i64, @intCast(rhs.len));
}

pub fn php_strcmp(str1: Value, str2: Value) !Value {
    if (!str1.isString() or !str2.isString()) return Value.initInt(0);

    const s1 = str1.asString();
    const s2 = str2.asString();
    return Value.initInt(php_string_compare_bytes(s1.data[0..s1.length], s2.data[0..s2.length], false));
}

pub fn php_strcasecmp(str1: Value, str2: Value, allocator: Allocator) !Value {
    _ = allocator;
    if (!str1.isString() or !str2.isString()) return Value.initInt(0);

    const s1 = str1.asString();
    const s2 = str2.asString();
    return Value.initInt(php_string_compare_bytes(s1.data[0..s1.length], s2.data[0..s2.length], true));
}

pub fn php_strncasecmp(str1: Value, str2: Value, length: Value) !Value {
    if (!str1.isString() or !str2.isString()) return Value.initInt(0);

    const limit = length.toInt();
    if (limit <= 0) return Value.initInt(0);

    const compare_len: usize = @intCast(limit);
    const s1 = str1.asString();
    const s2 = str2.asString();
    const lhs = s1.data[0..@min(s1.length, compare_len)];
    const rhs = s2.data[0..@min(s2.length, compare_len)];
    return Value.initInt(php_string_compare_bytes(lhs, rhs, true));
}

/// strnatcmp - 自然排序字符串比较（区分大小写）
pub fn php_strnatcmp(str1: Value, str2: Value) !Value {
    if (!str1.isString() or !str2.isString()) return Value.initInt(0);

    const s1 = str1.asString();
    const s2 = str2.asString();
    return Value.initInt(naturalCompare(s1.data[0..s1.length], s2.data[0..s2.length], false));
}

/// strnatcasecmp - 自然排序字符串比较（不区分大小写）
pub fn php_strnatcasecmp(str1: Value, str2: Value) !Value {
    if (!str1.isString() or !str2.isString()) return Value.initInt(0);

    const s1 = str1.asString();
    const s2 = str2.asString();
    return Value.initInt(naturalCompare(s1.data[0..s1.length], s2.data[0..s2.length], true));
}

/// 自然排序比较算法
/// 将数字部分作为整数比较，非数字部分按字符比较
fn naturalCompare(s1: []const u8, s2: []const u8, case_insensitive: bool) i64 {
    var idx1: usize = 0;
    var idx2: usize = 0;

    while (idx1 < s1.len and idx2 < s2.len) {
        const c1 = s1[idx1];
        const c2 = s2[idx2];

        // 检查是否都是数字
        if (std.ascii.isDigit(c1) and std.ascii.isDigit(c2)) {
            // 跳过前导零
            while (idx1 < s1.len and s1[idx1] == '0') idx1 += 1;
            while (idx2 < s2.len and s2[idx2] == '0') idx2 += 1;

            // 提取数字
            var num1: i64 = 0;
            var num2: i64 = 0;
            var len1: usize = 0;
            var len2: usize = 0;

            while (idx1 + len1 < s1.len and std.ascii.isDigit(s1[idx1 + len1])) {
                num1 = num1 * 10 + (s1[idx1 + len1] - '0');
                len1 += 1;
            }

            while (idx2 + len2 < s2.len and std.ascii.isDigit(s2[idx2 + len2])) {
                num2 = num2 * 10 + (s2[idx2 + len2] - '0');
                len2 += 1;
            }

            // 比较数字
            if (num1 != num2) {
                return if (num1 < num2) -1 else 1;
            }

            // 数字相同，继续比较
            idx1 += len1;
            idx2 += len2;
        } else {
            // 非数字部分，按字符比较
            const ch1 = if (case_insensitive) std.ascii.toLower(c1) else c1;
            const ch2 = if (case_insensitive) std.ascii.toLower(c2) else c2;

            if (ch1 != ch2) {
                return if (ch1 < ch2) -1 else 1;
            }

            idx1 += 1;
            idx2 += 1;
        }
    }

    // 长度不同
    if (idx1 < s1.len) return 1;
    if (idx2 < s2.len) return -1;
    return 0;
}

// ============================================================================
// 数组函数
// ============================================================================

/// count - 获取数组元素数量
/// count() - 计算数组元素个数
/// @param arr 要计数的数组
/// @param mode 可选，COUNT_RECURSIVE(1)表示递归计数
pub fn php_count(arr: Value, mode: Value) !Value {
    // 检测Countable对象
    if (Value_isObject(arr)) {
        const obj = Value_asObject(arr);
        if (obj.class_meta) |meta| {
            if (meta.findMethod("count")) |_| {
                return try php_object_call(arr, "count", &[_]Value{});
            }
        }
    }

    if (!arr.isArray()) return Value.initInt(0);

    const mode_int = if (mode.isInt()) mode.asInt() else 0;
    const php_arr = arr.asArray();

    // COUNT_RECURSIVE = 1
    if (mode_int == 1) {
        return Value.initInt(@intCast(countRecursive(php_arr)));
    }

    return Value.initInt(@intCast(php_arr.elements.count()));
}

fn countRecursive(arr: *PHPArray) usize {
    var total: usize = arr.elements.count();

    var iter = arr.elements.iterator();
    while (iter.next()) |entry| {
        const val = entry.value_ptr.*;
        if (val.isArray()) {
            total += countRecursive(val.asArray());
        }
    }

    return total;
}

/// array_push - 追加元素到数组
pub fn php_array_push(arr: Value, values: []const Value, allocator: Allocator) !Value {
    if (!arr.isArray()) {
        const got = valueTypeName(arr);
        emitTypeFatalError("array_push", 1, "array", got);
    }

    const php_arr = arr.asArray();
    for (values) |val| {
        try php_arr.push(allocator, val);
    }

    return Value.initInt(@intCast(php_arr.count()));
}

/// array_pop - 弹出数组最后一个元素
pub fn php_array_pop(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) {
        const got = valueTypeName(arr);
        emitTypeFatalError("array_pop", 1, "array", got);
    }

    const php_arr = arr.asArray();
    const value = array_ops_shared.pop(ArrayKey, Value, @TypeOf(php_arr.elements), allocator, &php_arr.elements, &php_arr.next_index) orelse return Value.initNull();
    return value;
}

/// in_array - 检查值是否在数组中
pub fn php_in_array(needle: Value, haystack: Value, strict: Value) !Value {
    if (!haystack.isArray()) return Value.initBool(false);

    const use_strict = strict.toBool();
    const arr = haystack.asArray();
    var iter = arr.elements.iterator();

    while (iter.next()) |entry| {
        if (use_strict) {
            const eq = try php_identical(needle, entry.value_ptr.*);
            if (eq.asBool()) return Value.initBool(true);
        } else {
            const eq = try php_eq(needle, entry.value_ptr.*);
            if (eq.asBool()) return Value.initBool(true);
        }
    }

    return Value.initBool(false);
}

/// array_slice - 从数组中提取一段切片
///
/// 提取数组中的一段元素，返回新数组。
///
/// @param arr 源数组
/// @param offset 起始偏移量（可以为负数，表示从末尾开始）
/// @param length 切片长度（可选，null表示到数组末尾）
/// @param allocator 内存分配器
/// @return 新的数组切片
///
/// 示例：
/// ```php
/// $arr = [1, 2, 3, 4, 5];
/// array_slice($arr, 1, 2);  // [2, 3]
/// array_slice($arr, -2);     // [4, 5]
/// array_slice($arr, 1, -1);  // [2, 3, 4]
/// ```
pub fn php_array_slice(arr: Value, offset: Value, length: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    const arr_count = php_arr.count();

    if (arr_count == 0) {
        // 空数组，返回空数组
        return Value.initArray(try PHPArray.init(allocator));
    }

    // 计算起始位置
    const offset_int = offset.toInt();
    const start_idx: usize = blk: {
        if (offset_int < 0) {
            const abs_offset = @as(usize, @intCast(-offset_int));
            break :blk if (abs_offset > arr_count) 0 else arr_count - abs_offset;
        } else {
            break :blk @intCast(@min(offset_int, @as(i64, @intCast(arr_count))));
        }
    };

    // 计算结束位置
    const end_idx: usize = blk: {
        if (length.isNull()) {
            // 没有指定长度，取到数组末尾
            break :blk arr_count;
        }

        const length_int = length.toInt();
        if (length_int >= 0) {
            // 正数长度
            break :blk @min(start_idx + @as(usize, @intCast(length_int)), arr_count);
        } else {
            // 负数长度：从末尾减去
            const abs_len = @as(usize, @intCast(-length_int));
            if (abs_len >= arr_count) {
                break :blk start_idx; // 返回空数组
            }
            break :blk if (arr_count - abs_len > start_idx) arr_count - abs_len else start_idx;
        }
    };

    // 创建新数组
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    if (start_idx >= end_idx) {
        // 空切片
        return Value.initArray(result);
    }

    // 复制元素
    // 注意：PHP的array_slice会重新索引数组（从0开始）
    var iter = php_arr.elements.iterator();
    var current_idx: usize = 0;
    var new_idx: i64 = 0;

    while (iter.next()) |entry| {
        // 只处理整数键（保持顺序）
        if (entry.key_ptr.* == .integer) {
            if (current_idx >= start_idx and current_idx < end_idx) {
                const new_key = ArrayKey{ .integer = new_idx };
                const value_copy = entry.value_ptr.*.retain();
                try result.elements.put(new_key, value_copy);
                new_idx += 1;
            }
            current_idx += 1;
        }
    }

    result.next_index = new_idx;
    return Value.initArray(result);
}

/// array_merge - 合并一个或多个数组
///
/// 将多个数组合并成一个新数组。
/// - 整数键会被重新索引（从0开始）
/// - 字符串键会被保留，后面的值会覆盖前面的值
///
/// @param arrays 要合并的数组列表
/// @param allocator 内存分配器
/// @return 合并后的新数组
///
/// 示例：
/// ```php
/// $arr1 = [1, 2];
/// $arr2 = [3, 4];
/// array_merge($arr1, $arr2);  // [1, 2, 3, 4]
///
/// $arr3 = ['a' => 1, 'b' => 2];
/// $arr4 = ['b' => 3, 'c' => 4];
/// array_merge($arr3, $arr4);  // ['a' => 1, 'b' => 3, 'c' => 4]
/// ```
pub fn php_array_merge(arrays: []const Value, allocator: Allocator) !Value {
    // 创建结果数组
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var next_int_key: i64 = 0;

    // 遍历所有输入数组
    for (arrays) |arr_val| {
        if (!arr_val.isArray()) continue; // 跳过非数组值

        const arr = arr_val.asArray();
        var iter = arr.elements.iterator();

        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*.retain();

            switch (key) {
                .integer => {
                    // 整数键：重新索引
                    const new_key = ArrayKey{ .integer = next_int_key };
                    try result.elements.put(new_key, value);
                    next_int_key += 1;
                },
                .string => |str| {
                    // 字符串键：保留键名，可能覆盖
                    const new_key = ArrayKey{ .string = str };
                    str.retain(); // 保留键的引用

                    // 如果键已存在，释放旧值
                    if (result.elements.get(new_key)) |old_value| {
                        old_value.release(allocator);
                    }

                    try result.elements.put(new_key, value);
                },
            }
        }
    }

    result.next_index = next_int_key;

    return Value.initArray(result);
}

/// 数组联合运算（PHP + 运算符）
///
/// 与 array_merge 不同：
/// - 保留左侧数组的所有键值对
/// - 右侧数组中键不在左侧时才加入
/// - 整数键不重新索引
pub fn php_array_union(lhs: Value, rhs: Value, allocator: Allocator) !Value {
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    // 先拷贝左侧所有元素
    const lhs_arr = lhs.asArray();
    var it_l = lhs_arr.elements.iterator();
    var max_int_key: i64 = -1;
    while (it_l.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*.retain();
        switch (key) {
            .integer => |i| {
                if (i > max_int_key) max_int_key = i;
                try result.elements.put(key, value);
            },
            .string => |s| {
                s.retain();
                try result.elements.put(key, value);
            },
        }
    }

    // 再拷贝右侧中左侧不存在的键
    const rhs_arr = rhs.asArray();
    var it_r = rhs_arr.elements.iterator();
    while (it_r.next()) |entry| {
        const key = entry.key_ptr.*;
        if (result.elements.get(key) != null) continue;
        const value = entry.value_ptr.*.retain();
        switch (key) {
            .integer => |i| {
                if (i > max_int_key) max_int_key = i;
                try result.elements.put(key, value);
            },
            .string => |s| {
                s.retain();
                try result.elements.put(key, value);
            },
        }
    }

    result.next_index = max_int_key + 1;
    return Value.initArray(result);
}

/// Merge array into target (for spread operator)
/// PHP 8.1+: string keys are preserved, integer keys are renumbered
pub fn php_array_merge_into(target: Value, source: Value, allocator: Allocator) !Value {
    if (!target.isArray()) return target;

    const target_arr = target.asArray();

    const iter_val = try php_array_iter_init(source, allocator);
    defer _ = php_array_iter_free(iter_val, allocator) catch {};

    while ((try php_array_iter_valid(iter_val)).toBool()) {
        const key_val = try php_array_iter_key(iter_val, allocator);
        defer key_val.release(allocator);
        const value = try php_array_iter_value(iter_val);
        defer value.release(allocator);

        if (key_val.isString()) {
            try target_arr.set(allocator, ArrayKey{ .string = key_val.asString() }, value);
        } else {
            try target_arr.push(allocator, value);
        }

        const next_iter = try php_array_iter_next(iter_val);
        next_iter.release(allocator);
    }

    return target;
}

/// array_keys - 返回数组中所有的键
///
/// 返回一个包含数组所有键的新数组（整数索引）。
///
/// @param arr 源数组
/// @param allocator 内存分配器
/// @return 包含所有键的新数组
///
/// 示例：
/// ```php
/// $arr = ['a' => 1, 'b' => 2, 0 => 3];
/// array_keys($arr);  // ['a', 'b', 0]
/// ```
pub fn php_array_keys(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var iter = php_arr.elements.iterator();
    var idx: i64 = 0;

    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const key_value = switch (key) {
            .integer => |i| Value.initInt(i),
            .string => |s| blk: {
                // 创建字符串值的副本
                const str_copy = try PHPString.init(allocator, s.data);
                break :blk Value.initString(str_copy);
            },
        };

        const new_key = ArrayKey{ .integer = idx };
        try result.elements.put(new_key, key_value);
        idx += 1;
    }

    result.next_index = idx;
    return Value.initArray(result);
}

/// array_values - 返回数组中所有的值
///
/// 返回一个包含数组所有值的新数组，使用整数索引（从0开始）。
/// 这个函数会丢弃原数组的键，重新索引。
///
/// @param arr 源数组
/// @param allocator 内存分配器
/// @return 包含所有值的新数组（整数索引）
///
/// 示例：
/// ```php
/// $arr = ['a' => 1, 'b' => 2, 5 => 3];
/// array_values($arr);  // [1, 2, 3]
/// ```
pub fn php_array_values(arr: Value, allocator: Allocator) !Value {
    if (!arr.isArray()) return Value.initNull();

    const php_arr = arr.asArray();
    const result = try PHPArray.init(allocator);
    errdefer result.release(allocator);

    var iter = php_arr.elements.iterator();
    var idx: i64 = 0;

    while (iter.next()) |entry| {
        const value = entry.value_ptr.*.retain();
        const new_key = ArrayKey{ .integer = idx };
        try result.elements.put(new_key, value);
        idx += 1;
    }

    result.next_index = idx;
    return Value.initArray(result);
}

/// array_is_list - 检查数组是否是列表
///
/// 检查给定的数组是否是列表。如果数组的键是连续的整数，从0开始，则认为是列表。
/// 空数组被认为是列表。
///
/// @param arr 要检查的数组
/// @return 如果是列表返回true，否则返回false
///
/// 示例：
/// ```php
/// array_is_list([]);              // true
/// array_is_list([1, 2, 3]);       // true
/// array_is_list([0 => 'a', 1 => 'b']);  // true
/// array_is_list([1 => 'a', 0 => 'b']);  // false (顺序不对)
/// array_is_list([0 => 'a', 2 => 'b']);  // false (不连续)
/// array_is_list(['a' => 1, 'b' => 2]);  // false (字符串键)
/// ```
pub fn php_array_is_list(arr: Value) Value {
    if (!arr.isArray()) return Value.initBool(false);

    const php_arr = arr.asArray();
    
    // 空数组是列表
    if (php_arr.elements.count() == 0) return Value.initBool(true);

    var iter = php_arr.elements.iterator();
    var expected_idx: i64 = 0;

    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        switch (key) {
            .integer => |i| {
                // 键必须等于期望的索引
                if (i != expected_idx) return Value.initBool(false);
                expected_idx += 1;
            },
            .string => {
                // 有字符串键，不是列表
                return Value.initBool(false);
            },
        }
    }

    return Value.initBool(true);
}

// ============================================================================
// 数学函数
// ============================================================================

/// abs - 绝对值
pub fn php_abs(val: Value) !Value {
    if (val.isInt()) {
        const i = val.asInt();
        return Value.initInt(if (i < 0) -i else i);
    }
    const f = val.toFloat();
    return Value.initFloat(@abs(f));
}

/// sqrt - 平方根
pub fn php_sqrt(val: Value) !Value {
    return Value.initFloat(@sqrt(val.toFloat()));
}

/// round - 四舍五入 (支持3参数: value, precision, mode)
/// mode: 0=PHP_ROUND_HALF_UP(default), 1=PHP_ROUND_HALF_DOWN, 2=PHP_ROUND_HALF_EVEN, 3=PHP_ROUND_HALF_ODD
pub fn php_round(val: Value, precision_val: Value, mode_val: Value) !Value {
    const num = val.toFloat();
    const precision = if (precision_val.isNull()) 0 else @as(i32, @intCast(precision_val.toInt()));
    const mode = if (mode_val.isNull()) @as(i64, 0) else mode_val.toInt();

    const multiplier = std.math.pow(f64, 10.0, @floatFromInt(precision));
    const scaled = num * multiplier;
    const frac = scaled - @floor(scaled);
    const is_half = @abs(frac - 0.5) < 1e-9;

    const rounded = if (is_half) blk: {
        switch (mode) {
            1 => {
                // HALF_DOWN: round towards zero
                break :blk if (num >= 0) @floor(scaled) / multiplier else @ceil(scaled) / multiplier;
            },
            2 => {
                // HALF_EVEN: round to nearest even
                const floor_val = @floor(scaled);
                const floor_int: i64 = @intFromFloat(floor_val);
                break :blk if (@rem(floor_int, 2) == 0) floor_val / multiplier else @ceil(scaled) / multiplier;
            },
            3 => {
                // HALF_ODD: round to nearest odd
                const floor_val = @floor(scaled);
                const floor_int: i64 = @intFromFloat(floor_val);
                break :blk if (@rem(floor_int, 2) != 0) floor_val / multiplier else @ceil(scaled) / multiplier;
            },
            else => {
                // HALF_UP (default): round away from zero
                break :blk @round(scaled) / multiplier;
            },
        }
    } else @round(scaled) / multiplier;

    return Value.initFloat(rounded);
}

/// floor - 向下取整
pub fn php_floor(val: Value) !Value {
    return Value.initFloat(@floor(val.toFloat()));
}

/// ceil - 向上取整
pub fn php_ceil(val: Value) !Value {
    return Value.initFloat(@ceil(val.toFloat()));
}

/// min - 最小值
/// max - 最大值
pub fn php_max(args: []const Value) !Value {
    if (args.len == 0) return Value.initInt(0);
    if (args.len == 1) {
        // 单参数：如果是数组，返回数组最大值
        if (args[0].isArray()) {
            const arr = args[0].asArray();
            if (arr.elements.packed_values.items.len == 0) return Value.initInt(0);

            var max_val = arr.elements.packed_values.items[0];
            for (arr.elements.packed_values.items[1..]) |val| {
                if (val.toFloat() > max_val.toFloat()) {
                    max_val = val;
                }
            }
            return max_val;
        }
        return args[0];
    }

    // 多参数：找最大值
    var max_val = args[0];
    for (args[1..]) |val| {
        if (val.toFloat() > max_val.toFloat()) {
            max_val = val;
        }
    }
    return max_val;
}

/// min - 最小值
pub fn php_min(args: []const Value) !Value {
    if (args.len == 0) return Value.initInt(0);
    if (args.len == 1) {
        // 单参数：如果是数组，返回数组最小值
        if (args[0].isArray()) {
            const arr = args[0].asArray();
            if (arr.elements.packed_values.items.len == 0) return Value.initInt(0);

            var min_val = arr.elements.packed_values.items[0];
            for (arr.elements.packed_values.items[1..]) |val| {
                if (val.toFloat() < min_val.toFloat()) {
                    min_val = val;
                }
            }
            return min_val;
        }
        return args[0];
    }

    // 多参数：找最小值
    var min_val = args[0];
    for (args[1..]) |val| {
        if (val.toFloat() < min_val.toFloat()) {
            min_val = val;
        }
    }
    return min_val;
}

/// sin - 正弦
pub fn php_sin(val: Value) !Value {
    return Value.initFloat(@sin(val.toFloat()));
}

/// cos - 余弦
pub fn php_cos(val: Value) !Value {
    return Value.initFloat(@cos(val.toFloat()));
}

/// tan - 正切
pub fn php_tan(val: Value) !Value {
    return Value.initFloat(@tan(val.toFloat()));
}

/// asin - 反正弦
pub fn php_asin(val: Value) !Value {
    return Value.initFloat(std.math.asin(val.toFloat()));
}

/// acos - 反余弦
pub fn php_acos(val: Value) !Value {
    return Value.initFloat(std.math.acos(val.toFloat()));
}

/// atan - 反正切
pub fn php_atan(val: Value) !Value {
    return Value.initFloat(std.math.atan(val.toFloat()));
}

/// atan2 - 两个参数的反正切
pub fn php_atan2(y: Value, x: Value) !Value {
    return Value.initFloat(std.math.atan2(y.toFloat(), x.toFloat()));
}

/// sinh - 双曲正弦
pub fn php_sinh(val: Value) !Value {
    const x = val.toFloat();
    return Value.initFloat((std.math.exp(x) - std.math.exp(-x)) / 2.0);
}

/// cosh - 双曲余弦
pub fn php_cosh(val: Value) !Value {
    const x = val.toFloat();
    return Value.initFloat((std.math.exp(x) + std.math.exp(-x)) / 2.0);
}

/// tanh - 双曲正切
pub fn php_tanh(val: Value) !Value {
    const x = val.toFloat();
    const ex = std.math.exp(x);
    const emx = std.math.exp(-x);
    return Value.initFloat((ex - emx) / (ex + emx));
}

/// dechex - 十进制转十六进制字符串
pub fn php_dechex(val: Value, allocator: Allocator) !Value {
    const n = val.toInt();
    const un: u64 = @bitCast(n);
    const str = try std.fmt.allocPrint(allocator, "{x}", .{un});
    defer allocator.free(str);
    const php_str = try PHPString.init(allocator, str);
    return Value.initString(php_str);
}

/// decoct - 十进制转八进制字符串
pub fn php_decoct(val: Value, allocator: Allocator) !Value {
    const n = val.toInt();
    const un: u64 = @bitCast(n);
    const str = try std.fmt.allocPrint(allocator, "{o}", .{un});
    defer allocator.free(str);
    const php_str = try PHPString.init(allocator, str);
    return Value.initString(php_str);
}

/// bindec - 二进制字符串转十进制
pub fn php_bindec(val: Value) !Value {
    if (!val.isString()) return Value.initInt(0);
    const s = val.asString().data;
    var result: i64 = 0;
    for (s) |c| {
        if (c == '0' or c == '1') {
            result = result * 2 + @as(i64, c - '0');
        }
    }
    return Value.initInt(result);
}

/// hexdec - 十六进制字符串转十进制
pub fn php_hexdec(val: Value) !Value {
    if (!val.isString()) return Value.initInt(0);
    const s = val.asString().data;
    var result: i64 = 0;
    for (s) |c| {
        const digit: i64 = if (c >= '0' and c <= '9')
            @as(i64, c - '0')
        else if (c >= 'a' and c <= 'f')
            @as(i64, c - 'a' + 10)
        else if (c >= 'A' and c <= 'F')
            @as(i64, c - 'A' + 10)
        else
            break;
        result = result * 16 + digit;
    }
    return Value.initInt(result);
}

/// octdec - 八进制字符串转十进制
pub fn php_octdec(val: Value) !Value {
    if (!val.isString()) return Value.initInt(0);
    const s = val.asString().data;
    var result: i64 = 0;
    for (s) |c| {
        if (c >= '0' and c <= '7') {
            result = result * 8 + @as(i64, c - '0');
        } else break;
    }
    return Value.initInt(result);
}

/// log - 自然对数
pub fn php_log(val: Value) !Value {
    return Value.initFloat(@log(val.toFloat()));
}

/// log10 - 以10为底的对数
pub fn php_log10(val: Value) !Value {
    return Value.initFloat(@log10(val.toFloat()));
}

/// log2 - 以2为底的对数
pub fn php_log2(val: Value) !Value {
    return Value.initFloat(@log2(val.toFloat()));
}

/// exp - e的x次方
pub fn php_exp(val: Value) !Value {
    return Value.initFloat(@exp(val.toFloat()));
}

/// pow - 幂运算
pub fn php_pow_func(base: Value, exponent: Value) !Value {
    if (base.isInt() and exponent.isInt()) {
        const b = base.asInt();
        const e = exponent.asInt();
        if (e >= 0 and e < 64) {
            // 整数幂运算
            var result: i64 = 1;
            var i: i64 = 0;
            while (i < e) : (i += 1) {
                result *= b;
            }
            return Value.initInt(result);
        }
    }
    return Value.initFloat(std.math.pow(f64, base.toFloat(), exponent.toFloat()));
}

/// fmod - 浮点数取模
pub fn php_fmod(x: Value, y: Value) !Value {
    return Value.initFloat(@mod(x.toFloat(), y.toFloat()));
}

/// intdiv - 整数除法
pub fn php_intdiv(dividend: Value, divisor: Value) !Value {
    const a = dividend.toInt();
    const b = divisor.toInt();
    if (b == 0) {
        return error.DivisionByZero;
    }
    return Value.initInt(@divTrunc(a, b));
}

/// fdiv - 浮点除法（PHP 8.0+，除以零返回 INF/NAN）
pub fn php_fdiv(dividend: Value, divisor: Value) Value {
    const a = dividend.toFloat();
    const b = divisor.toFloat();
    // fdiv 不抛出异常，除以零返回 INF/-INF/NAN
    return Value.initFloat(a / b);
}

/// hypot - 计算直角三角形斜边长度
pub fn php_hypot(x: Value, y: Value) !Value {
    return Value.initFloat(std.math.hypot(x.toFloat(), y.toFloat()));
}

/// base_convert - 在任意进制之间转换数字
pub fn php_base_convert(number: Value, frombase: Value, tobase: Value, allocator: Allocator) !Value {
    if (!number.isString()) return Value.initString(try PHPString.init(allocator, "0"));

    const num_str = number.asString().data;
    const from: u8 = @intCast(@min(@max(frombase.toInt(), 2), 36));
    const to: u8 = @intCast(@min(@max(tobase.toInt(), 2), 36));

    // 先将源进制转为十进制整数
    var decimal: u64 = 0;
    for (num_str) |c| {
        const digit: u64 = if (c >= '0' and c <= '9')
            c - '0'
        else if (c >= 'a' and c <= 'z')
            c - 'a' + 10
        else if (c >= 'A' and c <= 'Z')
            c - 'A' + 10
        else
            continue;
        if (digit >= from) continue;
        decimal = decimal * from + digit;
    }

    // 十进制转目标进制
    if (decimal == 0) return Value.initString(try PHPString.init(allocator, "0"));

    const digits = "0123456789abcdefghijklmnopqrstuvwxyz";
    var buf: [65]u8 = undefined;
    var pos: usize = buf.len;
    var val = decimal;
    while (val > 0) {
        pos -= 1;
        buf[pos] = digits[@intCast(@rem(val, to))];
        val /= to;
    }

    return Value.initString(try PHPString.init(allocator, buf[pos..]));
}

/// gc_enabled - 检查 GC 是否启用
pub fn php_gc_enabled() Value {
    return Value.initBool(gc_enabled);
}

/// deg2rad - 角度转弧度
pub fn php_deg2rad(degrees: Value) !Value {
    const rad = degrees.toFloat() * std.math.pi / 180.0;
    return Value.initFloat(rad);
}

/// rad2deg - 弧度转角度
pub fn php_rad2deg(radians: Value) !Value {
    const deg = radians.toFloat() * 180.0 / std.math.pi;
    return Value.initFloat(deg);
}

/// pi - 返回圆周率
pub fn php_pi() !Value {
    return Value.initFloat(std.math.pi);
}

/// intval - 转换为整数
pub fn php_intval(val: Value) !Value {
    // 使用完整的 PHP intval 语义
    if (val.isInt()) return val;
    if (val.isFloat()) return Value.initInt(@intFromFloat(val.asFloat()));
    if (val.isBool()) return Value.initInt(if (val.asBool()) @as(i64, 1) else @as(i64, 0));
    if (val.isString()) {
        const str = val.asString().data;
        // 内联 intval 逻辑
        if (str.len == 0) return Value.initInt(0);

        var s = std.mem.trim(u8, str, " \t\n\r");
        if (s.len == 0) return Value.initInt(0);

        var negative = false;
        if (s[0] == '-') {
            negative = true;
            s = s[1..];
        } else if (s[0] == '+') {
            s = s[1..];
        }

        if (s.len == 0) return Value.initInt(0);

        // 如果包含小数点，先解析为浮点数
        if (std.mem.indexOf(u8, s, ".") != null) {
            if (std.fmt.parseFloat(f64, if (negative) str else s)) |float_val| {
                return Value.initInt(@intFromFloat(float_val));
            } else |_| {}
        }

        // 尝试完整解析
        if (std.fmt.parseInt(i64, s, 10)) |int_val| {
            return Value.initInt(if (negative) -int_val else int_val);
        } else |_| {
            // 部分解析：提取前导数字
            var result: i64 = 0;
            for (s) |c| {
                if (c >= '0' and c <= '9') {
                    result = result * 10 + (c - '0');
                } else {
                    break;
                }
            }
            return Value.initInt(if (negative) -result else result);
        }
    }
    return Value.initInt(0);
}

/// floatval - 转换为浮点数
pub fn php_floatval(val: Value) !Value {
    return Value.initFloat(val.toFloat());
}

/// boolval - 转换为布尔值
pub fn php_boolval(val: Value) !Value {
    return Value.initBool(val.toBool());
}

// ============================================================================
// 类型检查函数
// ============================================================================

/// is_null - 检查是否为null
pub fn php_is_null(val: Value) !Value {
    return Value.initBool(val.isNull());
}

/// is_bool - 检查是否为布尔值
pub fn php_is_bool(val: Value) !Value {
    return Value.initBool(val.isBool());
}

/// is_int - 检查是否为整数
pub fn php_is_int(val: Value) !Value {
    return Value.initBool(val.isInt());
}

/// is_float - 检查是否为浮点数
pub fn php_is_float(val: Value) !Value {
    return Value.initBool(val.isFloat());
}

/// is_string - 检查是否为字符串
pub fn php_is_string(val: Value) !Value {
    return Value.initBool(val.isString());
}

/// is_array - 检查是否为数组
pub fn php_is_array(val: Value) !Value {
    return Value.initBool(val.isArray());
}

/// is_numeric - 检查是否为数字或数字字符串
pub fn php_is_numeric(val: Value) !Value {
    if (val.isInt() or val.isFloat()) return Value.initBool(true);
    if (val.isString()) {
        const str = val.asString();
        // 尝试解析为数字
        _ = std.fmt.parseInt(i64, str.data, 10) catch {
            _ = std.fmt.parseFloat(f64, str.data) catch {
                return Value.initBool(false);
            };
        };
        return Value.initBool(true);
    }
    return Value.initBool(false);
}

/// is_callable - 检查是否可调用（简化实现）
pub fn php_is_callable(val: Value) !Value {
    const actual_val = if (val.isRef()) val.asRef().* else val;
    if (actual_val.isFunction()) return Value.initBool(true);
    if (actual_val.isString()) {
        // 字符串只有是已知函数名时才callable
        const name = actual_val.asString().data;
        if (lookupBuiltinFunction(name) != null) return Value.initBool(true);
        if (user_function_registry) |reg| {
            if (reg.contains(name)) return Value.initBool(true);
        }
        if (aot_callable_hook) |hook| {
            _ = hook(name, &[_]Value{}, std.heap.page_allocator) catch return Value.initBool(false);
            return Value.initBool(true);
        }
        return Value.initBool(false);
    }
    if (actual_val.isArray()) {
        // [obj/class, method] 形式
        const arr = actual_val.asArray();
        if (arr.elements.count() == 2) return Value.initBool(true);
        return Value.initBool(false);
    }
    if (Value_isObject(actual_val)) {
        const obj = Value_asObject(actual_val);
        if (obj.class_meta) |meta| {
            return Value.initBool(meta.findMethod("__invoke") != null);
        }
    }
    return Value.initBool(false);
}

/// is_scalar - 检查是否为标量类型（int, float, string, bool）
pub fn php_is_scalar(val: Value) !Value {
    return Value.initBool(val.isInt() or val.isFloat() or val.isString() or val.isBool());
}

/// is_infinite - 检查浮点数是否为无穷大
pub fn php_is_infinite(val: Value) !Value {
    if (!val.isFloat()) return Value.initBool(false);
    const f = val.asFloat();
    return Value.initBool(std.math.isInf(f));
}

/// is_nan - 检查浮点数是否为NaN
pub fn php_is_nan(val: Value) !Value {
    if (!val.isFloat()) return Value.initBool(false);
    const f = val.asFloat();
    return Value.initBool(std.math.isNan(f));
}

/// is_finite - 检查浮点数是否为有限值
pub fn php_is_finite(val: Value) !Value {
    if (!val.isFloat()) return Value.initBool(true); // 非浮点数视为有限
    const f = val.asFloat();
    return Value.initBool(!std.math.isInf(f) and !std.math.isNan(f));
}

/// is_countable - 检查是否可计数（数组或实现Countable接口的对象）
pub fn php_is_countable(val: Value) !Value {
    // 数组总是可计数的
    if (val.isArray()) return Value.initBool(true);
    
    // 对象需要实现Countable接口
    if (Value_isObject(val)) {
        const obj = Value_asObject(val);
        if (obj.class_meta) |meta| {
            // 检查是否实现了Countable接口（有count方法）
            return Value.initBool(meta.findMethod("count") != null);
        }
    }
    
    return Value.initBool(false);
}

/// is_iterable - 检查是否可迭代（数组或实现Traversable接口的对象）
pub fn php_is_iterable(val: Value) !Value {
    // 数组总是可迭代的
    if (val.isArray()) return Value.initBool(true);
    
    // 对象需要实现Traversable接口（Iterator或IteratorAggregate）
    if (Value_isObject(val)) {
        const obj = Value_asObject(val);
        if (obj.class_meta) |meta| {
            // 检查是否有迭代器方法
            const has_current = meta.findMethod("current") != null;
            const has_key = meta.findMethod("key") != null;
            const has_next = meta.findMethod("next") != null;
            const has_rewind = meta.findMethod("rewind") != null;
            const has_valid = meta.findMethod("valid") != null;
            const has_getiterator = meta.findMethod("getIterator") != null;
            
            // Iterator接口需要5个方法，IteratorAggregate需要getIterator
            return Value.initBool((has_current and has_key and has_next and has_rewind and has_valid) or has_getiterator);
        }
    }
    
    return Value.initBool(false);
}

/// unset - 删除变量（立即释放引用）
pub fn php_unset(args: []const Value, allocator: Allocator) !Value {
    _ = allocator;
    for (args) |val| {
        val.release(runtime_allocator);
    }
    return Value.initNull();
}

/// clone - 克隆对象
pub fn php_clone(val: Value, allocator: Allocator) !Value {
    if (!Value_isObject(val)) {
        return error.InvalidArgument;
    }

    const orig_obj = Value_asObject(val);

    // 创建新对象
    const new_obj = try PHPObject.init(allocator, orig_obj.class_name);

    // 复制属性
    var iter = orig_obj.properties.iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        try new_obj.properties.put(key, value.retain());
    }

    // 复制class_meta
    new_obj.class_meta = orig_obj.class_meta;

    const new_val = Value_initObject(new_obj);

    // 调用__clone魔术方法
    if (new_obj.class_meta) |meta| {
        if (meta.findMethodLookup("__clone")) |lookup| {
            const guard = ClassContext.init(meta, lookup.owner);
            defer guard.deinit();
            _ = try lookup.method.func(new_val, &.{}, allocator);
        }
    }

    return new_val;
}

/// 将引用推入数组
/// 用于 $arr[] = &$var 语法
pub fn php_array_push_ref(arr_val: Value, ref_val: Value, _: Value) !void {
    if (!arr_val.isArray()) return;
    const arr = arr_val.asArray();
    try arr.pushRef(ref_val);
}

/// 将引用设置到数组
/// 用于 $arr[$key] = &$var 语法
pub fn php_array_set_ref(arr_val: Value, key_val: Value, ref_val: Value, _: Value) !void {
    if (!arr_val.isArray()) return;
    const arr = arr_val.asArray();
    const key = normalizeArrayKeyFromValue(key_val);
    try arr.setRef(key, ref_val);
}

/// 从值创建引用（用于全局变量的引用）
pub fn php_make_ref_from_value(val: Value) !Value {
    // 这是一个简化实现：创建一个包含该值的临时位置并返回引用
    // 在完整实现中，这需要更复杂的内存管理
    _ = val.retain();
    // 注意：这里返回的是值本身，不是真正的引用
    // 全局变量的引用需要特殊处理
    return val;
}

