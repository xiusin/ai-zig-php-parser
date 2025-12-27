const c = @cImport(@cInclude("ucontext.h"));
const std = @import("std");

pub const Context = c.ucontext_t;

/// Gets the current context.
pub fn get(ctx: *Context) void {
    if (c.getcontext(ctx) != 0) {
        @panic("getcontext failed");
    }
}

/// Saves the current CPU context into 'from' and restores the context from 'to'.
pub fn swap(from: *Context, to: *const Context) void {
    if (c.swapcontext(from, to) != 0) {
        @panic("swapcontext failed");
    }
}

/// Creates a new context that will execute `func`.
///
/// This function uses a common workaround for the `makecontext` C API, which
/// officially only supports integer arguments. Pointers are split into two
/// 32-bit integers and passed to a trampoline function, which then reconstructs
/// the pointers and calls the actual target function.
///
/// NOTE: This implementation is architecture-specific and assumes a 64-bit
/// architecture (LP64) where pointers are 64 bits and ints are 32 bits.
pub fn make(
    ctx: *Context,
    stack: []u8,
    trampoline: extern fn() void,
    func: *const anyopaque,
    arg1: *const anyopaque,
    arg2: *const anyopaque,
) void {
    get(ctx);
    ctx.uc_stack.ss_sp = stack.ptr;
    ctx.uc_stack.ss_size = stack.len;
    ctx.uc_link = null; // When this context returns, the process will exit. Coroutines should always switch context out.

    const func_addr = @ptrToInt(func);
    const arg1_addr = @ptrToInt(arg1);
    const arg2_addr = @ptrToInt(arg2);

    const hi32 = comptime (u32)(0xFFFFFFFF);
    const lo32 = comptime (u32)(0xFFFFFFFF);

    // Split 64-bit pointers into 32-bit integer arguments for makecontext.
    const func_hi = @as(c_int, @intCast(func_addr >> 32));
    const func_lo = @as(c_int, @intCast(func_addr & lo32));
    const arg1_hi = @as(c_int, @intCast(arg1_addr >> 32));
    const arg1_lo = @as(c_int, @intCast(arg1_addr & lo32));
    const arg2_hi = @as(c_int, @intCast(arg2_addr >> 32));
    const arg2_lo = @as(c_int, @intCast(arg2_addr & lo32));

    c.makecontext(ctx, trampoline, 6, func_hi, func_lo, arg1_hi, arg1_lo, arg2_hi, arg2_lo);
}
