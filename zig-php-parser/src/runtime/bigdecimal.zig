//! ============================================================================
//! 高精度十进制运算 (BigDecimal)
//! ============================================================================
//!
//! 功能：提供高精度十进制算术运算，适用于金融计算
//!
//! 为什么需要BigDecimal：
//! ┌─────────────────────────────────────────────────────────────────┐
//! │  浮点数精度问题：                                                │
//! │  0.1 + 0.2 = 0.30000000000000004  (IEEE 754浮点数)             │
//! │                                                                  │
//! │  BigDecimal精确计算：                                            │
//! │  0.1 + 0.2 = 0.3  (精确结果)                                    │
//! └─────────────────────────────────────────────────────────────────┘
//!
//! 内部表示：
//! ┌─────────────────────────────────────────────────────────────────┐
//! │  数值: -123.456                                                  │
//! │                                                                  │
//! │  digits: [1, 2, 3, 4, 5, 6]  (十进制数字数组)                   │
//! │  scale: 3                     (小数位数)                        │
//! │  sign: false                  (负数)                            │
//! │                                                                  │
//! │  实际值 = -123456 × 10^(-3) = -123.456                          │
//! └─────────────────────────────────────────────────────────────────┘
//!
//! 核心特性：
//! - 支持最多1000位数字
//! - 引用计数内存管理
//! - 小数字缓存优化（0-9）
//! - 支持加减乘除和比较运算
//!
//! 使用示例：
//! ```zig
//! const a = try BigDecimal.init(allocator, "123.456");
//! const b = try BigDecimal.init(allocator, "789.012");
//! const sum = try a.add(b);  // 912.468
//! ```
//!
//! 对应PHP函数：bcadd, bcsub, bcmul, bcdiv, bccomp, bcscale
//! ============================================================================

const std = @import("std");
const gc = @import("gc.zig");

/// 高精度十进制数
pub const BigDecimal = struct {
    /// Digits stored in base-10, most significant digit first
    digits: []u8,
    /// Number of decimal places
    scale: u32,
    /// Sign: true for positive, false for negative
    sign: bool,
    /// Allocator for memory management
    allocator: std.mem.Allocator,
    /// Reference count for memory management
    ref_count: std.atomic.Value(usize),

    const Self = @This();

    /// Maximum number of digits supported
    pub const MAX_DIGITS = 1000;
    
    /// Default scale for operations
    pub const DEFAULT_SCALE = 10;
    
    /// Small number cache for frequently used values (0-9)
    var small_number_cache: [10]?*BigDecimal = [_]?*BigDecimal{null} ** 10;
    var cache_mutex = std.Thread.Mutex{};

    /// Get cached small number or create new one
    pub fn getSmallNumber(allocator: std.mem.Allocator, digit: u8) !*BigDecimal {
        if (digit > 9) return error.InvalidDigit;
        
        cache_mutex.lock();
        defer cache_mutex.unlock();
        
        if (small_number_cache[digit]) |cached| {
            _ = cached.ref_count.fetchAdd(1, .acq_rel);
            return cached;
        }
        
        // Create and cache the small number
        const bd = try allocator.create(BigDecimal);
        bd.* = BigDecimal{
            .digits = try allocator.dupe(u8, &[_]u8{digit}),
            .scale = 0,
            .sign = true,
            .allocator = allocator,
            .ref_count = std.atomic.Value(usize).init(2), // One for cache, one for caller
        };
        
        small_number_cache[digit] = bd;
        return bd;
    }

    /// Initialize BigDecimal from string representation
    pub fn init(allocator: std.mem.Allocator, value: []const u8) !*BigDecimal {
        if (value.len == 0) {
            return error.InvalidInput;
        }

        const bd = try allocator.create(BigDecimal);
        bd.allocator = allocator;
        bd.ref_count = std.atomic.Value(usize).init(1);
        
        // Parse sign
        var start_idx: usize = 0;
        bd.sign = true;
        if (value[0] == '-') {
            bd.sign = false;
            start_idx = 1;
        } else if (value[0] == '+') {
            start_idx = 1;
        }

        // Find decimal point
        var decimal_pos: ?usize = null;
        for (value[start_idx..], start_idx..) |char, i| {
            if (char == '.') {
                if (decimal_pos != null) {
                    allocator.destroy(bd);
                    return error.InvalidInput; // Multiple decimal points
                }
                decimal_pos = i;
            } else if (char < '0' or char > '9') {
                allocator.destroy(bd);
                return error.InvalidInput; // Invalid character
            }
        }

        // Calculate scale and extract digits
        if (decimal_pos) |pos| {
            bd.scale = @intCast(value.len - pos - 1);
        } else {
            bd.scale = 0;
        }

        // Extract digits (remove decimal point)
        var digit_count: usize = 0;
        for (value[start_idx..]) |char| {
            if (char != '.') {
                digit_count += 1;
            }
        }

        if (digit_count == 0) {
            allocator.destroy(bd);
            return error.InvalidInput;
        }

        bd.digits = try allocator.alloc(u8, digit_count);
        var digit_idx: usize = 0;
        for (value[start_idx..]) |char| {
            if (char != '.') {
                bd.digits[digit_idx] = char - '0';
                digit_idx += 1;
            }
        }

        // Remove leading zeros
        bd.removeLeadingZeros();
        
        return bd;
    }

    /// Initialize BigDecimal from integer
    pub fn fromInt(allocator: std.mem.Allocator, value: i64) !*BigDecimal {
        const abs_value = if (value < 0) @as(u64, @intCast(-value)) else @as(u64, @intCast(value));
        
        // Convert to string first
        var buffer: [32]u8 = undefined;
        const str = try std.fmt.bufPrint(&buffer, "{d}", .{abs_value});
        
        const bd = try allocator.create(BigDecimal);
        bd.allocator = allocator;
        bd.ref_count = std.atomic.Value(usize).init(1);
        bd.sign = value >= 0;
        bd.scale = 0;
        
        bd.digits = try allocator.alloc(u8, str.len);
        for (str, 0..) |char, i| {
            bd.digits[i] = char - '0';
        }
        
        return bd;
    }

    /// Initialize BigDecimal from float (with potential precision loss warning)
    pub fn fromFloat(allocator: std.mem.Allocator, value: f64) !*BigDecimal {
        if (std.math.isNan(value) or std.math.isInf(value)) {
            return error.InvalidInput;
        }

        // Convert float to string with sufficient precision
        var buffer: [64]u8 = undefined;
        const str = try std.fmt.bufPrint(&buffer, "{d:.15}", .{value});
        
        return try init(allocator, str);
    }

    /// Create a zero BigDecimal
    pub fn zero(allocator: std.mem.Allocator) !*BigDecimal {
        return try init(allocator, "0");
    }

    /// Create a one BigDecimal
    pub fn one(allocator: std.mem.Allocator) !*BigDecimal {
        return try init(allocator, "1");
    }

    /// Increment reference count
    pub fn retain(self: *BigDecimal) *BigDecimal {
        _ = self.ref_count.fetchAdd(1, .monotonic);
        return self;
    }

    /// Decrement reference count and deallocate if zero
    pub fn release(self: *BigDecimal) void {
        const old_count = self.ref_count.fetchSub(1, .monotonic);
        if (old_count == 1) {
            self.deinit();
        }
    }

    /// Deallocate BigDecimal
    pub fn deinit(self: *BigDecimal) void {
        self.allocator.free(self.digits);
        self.allocator.destroy(self);
    }

    /// Remove leading zeros from digits
    fn removeLeadingZeros(self: *BigDecimal) void {
        var start: usize = 0;
        while (start < self.digits.len - 1 and self.digits[start] == 0) {
            start += 1;
        }
        
        if (start > 0) {
            const new_len = self.digits.len - start;
            std.mem.copyForwards(u8, self.digits[0..new_len], self.digits[start..]);
            self.digits = self.allocator.realloc(self.digits, new_len) catch self.digits[0..new_len];
        }

        // If all digits are zero, set to positive zero
        if (self.digits.len == 1 and self.digits[0] == 0) {
            self.sign = true;
            self.scale = 0;
        }
    }

    /// Check if BigDecimal is zero
    pub fn isZero(self: *const BigDecimal) bool {
        return self.digits.len == 1 and self.digits[0] == 0;
    }

    /// Check if BigDecimal is positive
    pub fn isPositive(self: *const BigDecimal) bool {
        return self.sign and !self.isZero();
    }

    /// Check if BigDecimal is negative
    pub fn isNegative(self: *const BigDecimal) bool {
        return !self.sign and !self.isZero();
    }

    /// Get the absolute value
    pub fn abs(self: *const BigDecimal) !*BigDecimal {
        if (self.sign) {
            return self.clone();
        }
        
        const result = try self.clone();
        result.sign = true;
        return result;
    }

    /// Clone the BigDecimal
    pub fn clone(self: *const BigDecimal) !*BigDecimal {
        const new_bd = try self.allocator.create(BigDecimal);
        new_bd.allocator = self.allocator;
        new_bd.ref_count = std.atomic.Value(usize).init(1);
        new_bd.sign = self.sign;
        new_bd.scale = self.scale;
        
        new_bd.digits = try self.allocator.alloc(u8, self.digits.len);
        @memcpy(new_bd.digits, self.digits);
        
        return new_bd;
    }

    /// Convert to string representation
    pub fn toString(self: *const BigDecimal) ![]u8 {
        var result = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        defer result.deinit(self.allocator);

        // Add sign
        if (!self.sign) {
            try result.append(self.allocator, '-');
        }

        // Handle zero case
        if (self.isZero()) {
            try result.append(self.allocator, '0');
            if (self.scale > 0) {
                try result.append(self.allocator, '.');
                for (0..self.scale) |_| {
                    try result.append(self.allocator, '0');
                }
            }
            return try result.toOwnedSlice();
        }

        // Add integer part
        const integer_digits = if (self.digits.len > self.scale) self.digits.len - self.scale else 0;
        
        if (integer_digits == 0) {
            try result.append(self.allocator, '0');
        } else {
            for (self.digits[0..integer_digits]) |digit| {
                try result.append(self.allocator, '0' + digit);
            }
        }

        // Add decimal part
        if (self.scale > 0) {
            try result.append(self.allocator, '.');
            
            // Add leading zeros if needed
            if (integer_digits == 0 and self.digits.len < self.scale) {
                for (0..self.scale - self.digits.len) |_| {
                    try result.append(self.allocator, '0');
                }
            }
            
            // Add fractional digits
            const fractional_start = if (integer_digits > 0) integer_digits else 0;
            for (self.digits[fractional_start..]) |digit| {
                try result.append(self.allocator, '0' + digit);
            }
        }

        return try result.toOwnedSlice();
    }

    /// Set the scale (number of decimal places)
    pub fn setScale(self: *BigDecimal, scale: u32) void {
        if (scale == self.scale) return;
        
        if (scale > self.scale) {
            // Increase scale - add trailing zeros
            const new_digits = self.allocator.realloc(self.digits, self.digits.len + (scale - self.scale)) catch return;
            self.digits = new_digits;
            
            // Add zeros at the end
            for (self.digits.len - (scale - self.scale)..self.digits.len) |i| {
                self.digits[i] = 0;
            }
        } else {
            // Decrease scale - truncate digits
            const digits_to_remove = self.scale - scale;
            if (digits_to_remove >= self.digits.len) {
                // All digits would be removed, set to zero
                self.digits[0] = 0;
                self.digits = self.allocator.realloc(self.digits, 1) catch self.digits[0..1];
            } else {
                const new_len = self.digits.len - digits_to_remove;
                self.digits = self.allocator.realloc(self.digits, new_len) catch self.digits[0..new_len];
            }
        }
        
        self.scale = scale;
        self.removeLeadingZeros();
    }

    /// Normalize two BigDecimals to have the same scale
    fn normalize(self: *const BigDecimal, other: *const BigDecimal) !struct { a: *BigDecimal, b: *BigDecimal } {
        const max_scale = @max(self.scale, other.scale);
        
        var a = try self.clone();
        var b = try other.clone();
        
        a.setScale(max_scale);
        b.setScale(max_scale);
        
        return .{ .a = a, .b = b };
    }

    /// Addition operation
    pub fn add(self: *const BigDecimal, other: *const BigDecimal) !*BigDecimal {
        // Handle zero cases
        if (self.isZero()) return try other.clone();
        if (other.isZero()) return try self.clone();

        // Normalize scales
        const normalized = try self.normalize(other);
        defer normalized.a.release();
        defer normalized.b.release();

        // Same sign: add magnitudes
        if (self.sign == other.sign) {
            return try addMagnitudes(normalized.a, normalized.b, self.sign);
        }
        
        // Different signs: subtract magnitudes
        const cmp = compareMagnitudes(normalized.a, normalized.b);
        if (cmp == 0) {
            return try BigDecimal.zero(self.allocator);
        } else if (cmp > 0) {
            return try subtractMagnitudes(normalized.a, normalized.b, self.sign);
        } else {
            return try subtractMagnitudes(normalized.b, normalized.a, other.sign);
        }
    }

    /// Subtraction operation
    pub fn subtract(self: *const BigDecimal, other: *const BigDecimal) !*BigDecimal {
        // Handle zero cases
        if (other.isZero()) return try self.clone();
        if (self.isZero()) {
            const result = try other.clone();
            result.sign = !other.sign;
            return result;
        }

        // Normalize scales
        const normalized = try self.normalize(other);
        defer normalized.a.release();
        defer normalized.b.release();

        // Different signs: add magnitudes
        if (self.sign != other.sign) {
            return try addMagnitudes(normalized.a, normalized.b, self.sign);
        }
        
        // Same sign: subtract magnitudes
        const cmp = compareMagnitudes(normalized.a, normalized.b);
        if (cmp == 0) {
            return try BigDecimal.zero(self.allocator);
        } else if (cmp > 0) {
            return try subtractMagnitudes(normalized.a, normalized.b, self.sign);
        } else {
            return try subtractMagnitudes(normalized.b, normalized.a, !self.sign);
        }
    }

    /// Multiplication operation
    pub fn multiply(self: *const BigDecimal, other: *const BigDecimal) !*BigDecimal {
        // Handle zero cases
        if (self.isZero() or other.isZero()) {
            return try BigDecimal.zero(self.allocator);
        }

        // Handle one cases
        if (self.digits.len == 1 and self.digits[0] == 1 and self.scale == 0) {
            const result = try other.clone();
            result.sign = self.sign == other.sign;
            return result;
        }
        if (other.digits.len == 1 and other.digits[0] == 1 and other.scale == 0) {
            const result = try self.clone();
            result.sign = self.sign == other.sign;
            return result;
        }

        const result_scale = self.scale + other.scale;
        const result_sign = self.sign == other.sign;

        // Multiply digit arrays
        var result_digits = try self.allocator.alloc(u8, self.digits.len + other.digits.len);
        @memset(result_digits, 0);

        for (self.digits, 0..) |a_digit, i| {
            var carry: u8 = 0;
            for (other.digits, 0..) |b_digit, j| {
                const product = @as(u16, a_digit) * @as(u16, b_digit) + result_digits[i + j] + carry;
                result_digits[i + j] = @intCast(product % 10);
                carry = @intCast(product / 10);
            }
            if (carry > 0) {
                result_digits[i + other.digits.len] += carry;
            }
        }

        // Reverse digits (we computed them backwards)
        std.mem.reverse(u8, result_digits);

        const result = try self.allocator.create(BigDecimal);
        result.allocator = self.allocator;
        result.ref_count = std.atomic.Value(usize).init(1);
        result.sign = result_sign;
        result.scale = result_scale;
        result.digits = result_digits;

        result.removeLeadingZeros();
        return result;
    }

    /// Division operation
    pub fn divide(self: *const BigDecimal, other: *const BigDecimal) !*BigDecimal {
        if (other.isZero()) {
            return BigDecimalError.DivisionByZero;
        }

        if (self.isZero()) {
            return try BigDecimal.zero(self.allocator);
        }

        // For simplicity, we'll implement long division with a fixed precision
        const precision = @max(self.scale, other.scale) + DEFAULT_SCALE;
        
        // Scale up dividend to get desired precision
        var dividend = try self.clone();
        defer dividend.release();
        dividend.setScale(dividend.scale + precision);

        var divisor = try other.clone();
        defer divisor.release();

        const result_sign = self.sign == other.sign;
        var quotient_digits = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        defer quotient_digits.deinit(self.allocator);

        // Perform long division
        var remainder = try dividend.clone();
        defer remainder.release();
        remainder.sign = true; // Work with positive values

        var temp_divisor = try divisor.abs();
        defer temp_divisor.release();

        while (!remainder.isZero() and quotient_digits.items.len < MAX_DIGITS) {
            var digit: u8 = 0;
            while (compareMagnitudes(remainder, temp_divisor) >= 0) {
                const temp = try subtractMagnitudes(remainder, temp_divisor, true);
                remainder.release();
                remainder = temp;
                digit += 1;
                if (digit >= 10) break;
            }
            try quotient_digits.append(self.allocator, digit);

            // Multiply remainder by 10 for next iteration
            if (!remainder.isZero()) {
                const new_digits = try self.allocator.alloc(u8, remainder.digits.len + 1);
                @memcpy(new_digits[0..remainder.digits.len], remainder.digits);
                new_digits[remainder.digits.len] = 0;
                self.allocator.free(remainder.digits);
                remainder.digits = new_digits;
            }
        }

        if (quotient_digits.items.len == 0) {
            try quotient_digits.append(self.allocator, 0);
        }

        const result = try self.allocator.create(BigDecimal);
        result.allocator = self.allocator;
        result.ref_count = std.atomic.Value(usize).init(1);
        result.sign = result_sign;
        result.scale = precision;
        result.digits = try quotient_digits.toOwnedSlice();

        result.removeLeadingZeros();
        return result;
    }

    /// Comparison operation
    /// Returns: -1 if self < other, 0 if self == other, 1 if self > other
    pub fn compare(self: *const BigDecimal, other: *const BigDecimal) i8 {
        // Handle sign differences
        if (self.sign != other.sign) {
            return if (self.sign) @as(i8, 1) else @as(i8, -1);
        }

        // Both have same sign
        const magnitude_cmp = compareMagnitudes(self, other);
        
        if (self.sign) {
            return magnitude_cmp;
        } else {
            return -magnitude_cmp;
        }
    }

    /// Compare magnitudes (absolute values) of two BigDecimals
    fn compareMagnitudes(a: *const BigDecimal, b: *const BigDecimal) i8 {
        // Normalize scales for comparison
        const normalized = a.normalize(b) catch return 0;
        defer normalized.a.release();
        defer normalized.b.release();

        const a_norm = normalized.a;
        const b_norm = normalized.b;

        // Compare lengths first
        if (a_norm.digits.len > b_norm.digits.len) return 1;
        if (a_norm.digits.len < b_norm.digits.len) return -1;

        // Same length, compare digit by digit
        for (a_norm.digits, b_norm.digits) |a_digit, b_digit| {
            if (a_digit > b_digit) return 1;
            if (a_digit < b_digit) return -1;
        }

        return 0; // Equal
    }

    /// Add magnitudes of two BigDecimals (assumes same scale)
    fn addMagnitudes(a: *const BigDecimal, b: *const BigDecimal, result_sign: bool) !*BigDecimal {
        const max_len = @max(a.digits.len, b.digits.len);
        var result_digits = try a.allocator.alloc(u8, max_len + 1);
        @memset(result_digits, 0);

        var carry: u8 = 0;
        var i: usize = 0;
        
        while (i < max_len or carry > 0) {
            var sum: u8 = carry;
            
            if (i < a.digits.len) {
                sum += a.digits[a.digits.len - 1 - i];
            }
            if (i < b.digits.len) {
                sum += b.digits[b.digits.len - 1 - i];
            }
            
            result_digits[result_digits.len - 1 - i] = sum % 10;
            carry = sum / 10;
            i += 1;
        }

        const result = try a.allocator.create(BigDecimal);
        result.allocator = a.allocator;
        result.ref_count = std.atomic.Value(usize).init(1);
        result.sign = result_sign;
        result.scale = a.scale;
        result.digits = result_digits;

        result.removeLeadingZeros();
        return result;
    }

    /// Subtract magnitudes of two BigDecimals (assumes a >= b and same scale)
    fn subtractMagnitudes(a: *const BigDecimal, b: *const BigDecimal, result_sign: bool) !*BigDecimal {
        var result_digits = try a.allocator.alloc(u8, a.digits.len);
        @memcpy(result_digits, a.digits);

        var borrow: u8 = 0;
        var i: usize = 0;
        
        while (i < b.digits.len or borrow > 0) {
            var diff: i16 = @as(i16, result_digits[result_digits.len - 1 - i]) - borrow;
            
            if (i < b.digits.len) {
                diff -= b.digits[b.digits.len - 1 - i];
            }
            
            if (diff < 0) {
                diff += 10;
                borrow = 1;
            } else {
                borrow = 0;
            }
            
            result_digits[result_digits.len - 1 - i] = @intCast(diff);
            i += 1;
        }

        const result = try a.allocator.create(BigDecimal);
        result.allocator = a.allocator;
        result.ref_count = std.atomic.Value(usize).init(1);
        result.sign = result_sign;
        result.scale = a.scale;
        result.digits = result_digits;

        result.removeLeadingZeros();
        return result;
    }

    /// Equality check
    pub fn equals(self: *const BigDecimal, other: *const BigDecimal) bool {
        return self.compare(other) == 0;
    }

    /// Less than check
    pub fn lessThan(self: *const BigDecimal, other: *const BigDecimal) bool {
        return self.compare(other) < 0;
    }

    /// Less than or equal check
    pub fn lessThanOrEqual(self: *const BigDecimal, other: *const BigDecimal) bool {
        return self.compare(other) <= 0;
    }

    /// Greater than check
    pub fn greaterThan(self: *const BigDecimal, other: *const BigDecimal) bool {
        return self.compare(other) > 0;
    }

    /// Greater than or equal check
    pub fn greaterThanOrEqual(self: *const BigDecimal, other: *const BigDecimal) bool {
        return self.compare(other) >= 0;
    }

    /// Round to specified decimal places
    pub fn round(self: *const BigDecimal, scale: u32) !*BigDecimal {
        if (scale >= self.scale) {
            return try self.clone();
        }

        const result = try self.clone();
        const digits_to_remove = self.scale - scale;
        
        if (digits_to_remove >= result.digits.len) {
            // All digits would be removed, result is zero
            result.allocator.free(result.digits);
            result.digits = try result.allocator.alloc(u8, 1);
            result.digits[0] = 0;
            result.scale = scale;
            result.sign = true;
            return result;
        }

        // Check if we need to round up
        const round_digit_idx = result.digits.len - digits_to_remove;
        var should_round_up = false;
        
        if (round_digit_idx < result.digits.len) {
            should_round_up = result.digits[round_digit_idx] >= 5;
        }

        // Truncate digits
        const new_len = result.digits.len - digits_to_remove;
        result.digits = result.allocator.realloc(result.digits, new_len) catch result.digits[0..new_len];
        result.scale = scale;

        // Apply rounding if needed
        if (should_round_up) {
            var carry: u8 = 1;
            var i: usize = result.digits.len;
            
            while (i > 0 and carry > 0) {
                i -= 1;
                const sum = result.digits[i] + carry;
                result.digits[i] = sum % 10;
                carry = sum / 10;
            }
            
            // If we still have carry, we need to add a digit
            if (carry > 0) {
                const new_digits = try result.allocator.alloc(u8, result.digits.len + 1);
                new_digits[0] = carry;
                @memcpy(new_digits[1..], result.digits);
                result.allocator.free(result.digits);
                result.digits = new_digits;
            }
        }

        result.removeLeadingZeros();
        return result;
    }
};

/// Error types for BigDecimal operations
pub const BigDecimalError = error{
    InvalidInput,
    DivisionByZero,
    Overflow,
    OutOfMemory,
};