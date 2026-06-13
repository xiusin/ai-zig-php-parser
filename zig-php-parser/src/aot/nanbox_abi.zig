//! NaN-boxed value encoding scheme for PHPValue
//!
//! IEEE 754 double-precision layout:
//!   Bit 63     : sign
//!   Bits 62-52 : exponent (11 bits)
//!   Bits 51-0  : mantissa (52 bits)
//!
//! NaN: exponent = 0x7FF (all 1s), mantissa != 0
//!   Quiet NaN : mantissa bit 51 = 1
//!
//! Our encoding uses specific quiet NaN patterns (top 16 bits = 0x7FFC or 0xFFFC)
//! to encode non-float values. Hardware NaNs use different mantissa patterns.
//!
//! Encoding summary:
//!   Float  : stored as bitcast, NaN canonicalized to 0x7FFC000000000000
//!   Int    : 0xFFFCxxxx_xxxxxxxx  (sign bit set + QNAN + lower 48 bits)
//!   Null   : 0x7FFC0000_00000001
//!   False  : 0x7FFC0000_00000002
//!   True   : 0x7FFC0000_00000003
//!   String : 0x7FFC8xxx_xxxxxxxx  (QNAN + TYPE_STRING + pointer)
//!   Array  : 0x7FFD0xxx_xxxxxxxx  (QNAN + TYPE_ARRAY + pointer)
//!   Object : 0x7FFD8xxx_xxxxxxxx  (QNAN + TYPE_OBJECT + pointer)
//!   Func   : 0x7FFE0xxx_xxxxxxxx  (QNAN + TYPE_FUNCTION + pointer)
//!   BigInt : 0x7FFF0xxx_xxxxxxxx  (QNAN + TYPE_BIGINT + pointer)

pub const SIGN_BIT: u64 = 0x8000000000000000;
pub const QNAN: u64 = 0x7FFC000000000000;

pub const TAG_NIL: u64 = 1;
pub const TAG_FALSE: u64 = 2;
pub const TAG_TRUE: u64 = 3;

pub const TAG_INT_MARKER: u64 = SIGN_BIT | QNAN;
pub const TAG_PTR: u64 = QNAN;

pub const INT48_MASK: u64 = 0x0000FFFFFFFFFFFF;
pub const ADDR_MASK: u64 = 0x00007FFFFFFFFFFF;

pub const TYPE_MASK: u64 = 0x0003800000000000;
pub const TYPE_STRING: u64 = 0x0000800000000000;
pub const TYPE_ARRAY: u64 = 0x0001000000000000;
pub const TYPE_OBJECT: u64 = 0x0001800000000000;
pub const TYPE_FUNCTION: u64 = 0x0002000000000000;
pub const TYPE_REF: u64 = 0x0002800000000000;
pub const TYPE_BIGINT: u64 = 0x0003000000000000;

/// Mask for our NaN-boxed tag pattern (top 16 bits).
const TAG_PATTERN_MASK: u64 = 0xFFFF000000000000;

/// Check if a 64-bit value carries our NaN-boxed tag pattern.
/// Returns true if top 16 bits are 0x7FFC or 0xFFFC.
pub inline fn hasNanBoxTag(v: u64) bool {
    const top: u16 = @as(u16, @truncate(v >> 48));
    switch (top) {
        0x7FFC, 0xFFFC => return true,
        else => return false,
    }
}

// ============================================================================
// Encoding functions
// ============================================================================

/// Encode an i64 into a NaN-boxed u64. The integer must fit in 48 bits
/// (range -2^47 .. 2^47-1).
pub inline fn encodeInt(i: i64) u64 {
    return TAG_INT_MARKER | (@as(u64, @bitCast(i)) & INT48_MASK);
}

/// Decode a NaN-boxed u64 back to i64. Sign-extends from 48 bits.
pub inline fn decodeInt(v: u64) i64 {
    const signed = if ((v & 0x0000800000000000) != 0)
        (v | 0xFFFF000000000000)
    else
        v;
    return @as(i64, @bitCast(signed));
}

/// Encode an f64 into a NaN-boxed u64.
/// If the float is a NaN, it is canonicalized to QNAN to avoid conflicts
/// with our tagged value patterns.
pub inline fn encodeFloat(f: f64) u64 {
    const bits: u64 = @bitCast(f);
    // Check if it's a NaN (exponent all 1s, mantissa non-zero)
    if ((bits & 0x7FF0000000000000) == 0x7FF0000000000000 and
        (bits & 0x000FFFFFFFFFFFFF) != 0)
    {
        return QNAN; // canonical NaN
    }
    return bits;
}

/// Decode a NaN-boxed u64 back to f64.
pub inline fn decodeFloat(v: u64) f64 {
    return @as(f64, @bitCast(v));
}

/// Encode a bool into a NaN-boxed u64.
pub inline fn encodeBool(b: bool) u64 {
    return QNAN | if (b) TAG_TRUE else TAG_FALSE;
}

/// Encode null into a NaN-boxed u64.
pub inline fn encodeNull() u64 {
    return QNAN | TAG_NIL;
}

/// Encode a heap pointer with a type tag into a NaN-boxed u64.
/// `addr` is the raw pointer address, `type_tag` is one of TYPE_STRING,
/// TYPE_ARRAY, TYPE_OBJECT, etc.
pub inline fn encodePtr(addr: usize, type_tag: u64) u64 {
    return TAG_PTR | type_tag | (@as(u64, addr) & ADDR_MASK);
}

/// Decode the pointer address from a NaN-boxed u64.
pub inline fn decodePtr(v: u64) usize {
    return @as(usize, v & ADDR_MASK);
}

// ============================================================================
// Type check / discrimination functions
// ============================================================================

/// Check if value encodes a 48-bit integer.
pub inline fn isInt(v: u64) bool {
    return (v & TAG_PATTERN_MASK) == TAG_INT_MARKER;
}

/// Check if value encodes a double (and is NOT one of our tagged values).
pub inline fn isFloat(v: u64) bool {
    return !hasNanBoxTag(v);
}

/// Check if value encodes a bool (true or false).
pub inline fn isBool(v: u64) bool {
    if ((v & TAG_PATTERN_MASK) != QNAN) return false;
    const tag = v ^ QNAN;
    return tag == TAG_TRUE or tag == TAG_FALSE;
}

/// Check if value encodes null.
pub inline fn isNull(v: u64) bool {
    return v == (QNAN | TAG_NIL);
}

/// Check if value encodes a string pointer.
pub inline fn isString(v: u64) bool {
    return (v & (TAG_PATTERN_MASK | TYPE_MASK)) == (TAG_PTR | TYPE_STRING);
}

/// Check if value encodes an array pointer.
pub inline fn isArray(v: u64) bool {
    return (v & (TAG_PATTERN_MASK | TYPE_MASK)) == (TAG_PTR | TYPE_ARRAY);
}

/// Check if value encodes an object pointer.
pub inline fn isObject(v: u64) bool {
    return (v & (TAG_PATTERN_MASK | TYPE_MASK)) == (TAG_PTR | TYPE_OBJECT);
}

/// Check if value encodes a heap-allocated type (string, array, object,
/// function, bigint).
pub inline fn isHeapType(v: u64) bool {
    return isString(v) or isArray(v) or isObject(v);
}

/// Extract the type tag bits from a pointer-encoded value.
pub inline fn getPtrType(v: u64) u64 {
    return v & TYPE_MASK;
}

/// Extract a bool value from an encoded u64 (caller must ensure isBool).
pub inline fn decodeBool(v: u64) bool {
    return (v ^ QNAN) == TAG_TRUE;
}