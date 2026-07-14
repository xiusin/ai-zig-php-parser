const std = @import("std");

// ============================================================================
// 字节码指令
// ============================================================================

pub const OpCode = enum(u8) {
    // 栈操作 (0x00-0x0F)
    nop = 0x00,
    push_nil = 0x01,
    push_true = 0x02,
    push_false = 0x03,
    push_int = 0x04, // 后跟 i32
    push_float = 0x05, // 后跟 f64
    push_const = 0x06, // 后跟常量索引
    push_local = 0x07, // 后跟局部变量索引
    store_local = 0x08,
    pop = 0x09,
    dup = 0x0A,
    swap = 0x0B,

    // 整数算术 (0x10-0x1F) - 类型特化
    add_i = 0x10,
    sub_i = 0x11,
    mul_i = 0x12,
    div_i = 0x13,
    mod_i = 0x14,
    neg_i = 0x15,
    inc_i = 0x16,
    dec_i = 0x17,

    // 浮点算术 (0x20-0x2F)
    add_f = 0x20,
    sub_f = 0x21,
    mul_f = 0x22,
    div_f = 0x23,
    neg_f = 0x25,

    // 通用算术 (0x30-0x3F) - 带类型检查
    add = 0x30,
    sub = 0x31,
    mul = 0x32,
    div = 0x33,
    mod = 0x34,
    neg = 0x35,

    // 比较 (0x40-0x4F)
    eq = 0x40,
    ne = 0x41,
    lt = 0x42,
    le = 0x43,
    gt = 0x44,
    ge = 0x45,
    eq_i = 0x46,
    lt_i = 0x47,
    gt_i = 0x48,

    // 位操作 (0x50-0x5F)
    band = 0x50,
    bor = 0x51,
    bxor = 0x52,
    bnot = 0x53,
    shl = 0x54,
    shr = 0x55,

    // 逻辑 (0x60-0x6F)
    land = 0x60,
    lor = 0x61,
    lnot = 0x62,

    // 控制流 (0x70-0x7F)
    jmp = 0x70, // 无条件跳转
    jz = 0x71, // 为假跳转
    jnz = 0x72, // 为真跳转
    call = 0x73, // 函数调用
    ret = 0x74, // 返回
    ret_nil = 0x75, // 返回 nil
    halt = 0x7F,

    // 超级指令 (0x80-0x8F) - 合并常见序列
    load_add_i = 0x80, // push_local + add_i
    load_sub_i = 0x81,
    load_inc_store = 0x82, // push_local + inc_i + store_local
    load_dec_store = 0x83,
    push_0 = 0x84, // push_int 0
    push_1 = 0x85, // push_int 1
    push_m1 = 0x86, // push_int -1
    dup_add_i = 0x87, // dup + add_i

    // 数组/对象 (0x90-0x9F)
    new_array = 0x90,
    array_get = 0x91,
    array_set = 0x92,
    array_push = 0x93,
    obj_get = 0x94,
    obj_set = 0x95,
    obj_call = 0x96,

    // 字符串 (0xA0-0xAF)
    concat = 0xA0,
    strlen = 0xA1,

    // 内置函数 (0xB0-0xBF)
    echo = 0xB0,
    print = 0xB1,

    // 调试 (0xF0-0xFF)
    debug = 0xF0,
    line = 0xF1, // 行号信息
};
