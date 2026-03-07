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
pub const TYPE_REF: u64 = 0x0002800000000000;  // 修复：使用未占用的类型码

pub inline fn encodeInt(i: i64) u64 {
    return TAG_INT_MARKER | (@as(u64, @bitCast(i)) & INT48_MASK);
}

pub inline fn decodeInt(v: u64) i64 {
    const signed = if ((v & 0x0000800000000000) != 0) (v | 0xFFFF000000000000) else v;
    return @as(i64, @bitCast(signed));
}

pub inline fn encodePtr(addr: usize, type_tag: u64) u64 {
    return TAG_PTR | type_tag | (@as(u64, addr) & ADDR_MASK);
}

pub inline fn decodePtr(v: u64) usize {
    return @as(usize, v & ADDR_MASK);
}
