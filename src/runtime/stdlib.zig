const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const exceptions = @import("exceptions.zig");
const ExceptionFactory = exceptions.ExceptionFactory;

// Forward declaration for VM
const VM = @import("vm.zig").VM;

const fn_dispatch = @import("fn_dispatch.zig");

pub const StandardLibrary = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !StandardLibrary {
        return StandardLibrary{ .allocator = allocator };
    }

    pub fn deinit(self: *StandardLibrary) void {
        _ = self;
    }

    /// 快速路径内置函数调用 — 使用 fn_dispatch 的 O(1) 查找 + O(1) 分发
    /// 流程：fn_dispatch.lookup (StaticStringMap O(1)) → validateArgs → COMPTIME_HANDLER_TABLE[id] O(1) 分发
    pub fn callBuiltinFast(vm: *VM, name: []const u8, args: []const Value) anyerror!?Value {
        // 1. O(1) 查找：使用 fn_dispatch 的 StaticStringMap（编译时完美哈希）
        const id = fn_dispatch.lookup(name) orelse return null;

        // 2. 统一参数校验（dispatch 层处理，函数实现无需重复）
        fn_dispatch.validateArgs(id, args.len) catch |err| switch (err) {
            error.TooFewArguments => {
                const meta = fn_dispatch.getMeta(id).?;
                const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, meta.min_args, @intCast(args.len), name, "builtin", 0);
                _ = try vm.throwException(exception);
                return error.ArgumentCountMismatch;
            },
            error.TooManyArguments => {
                const meta = fn_dispatch.getMeta(id).?;
                const exception = try ExceptionFactory.createArgumentCountError(vm.allocator, meta.max_args, @intCast(args.len), name, "builtin", 0);
                _ = try vm.throwException(exception);
                return error.ArgumentCountMismatch;
            },
        };

        // 3. O(1) 直接分发 — 通过 COMPTIME_HANDLER_TABLE[id] 直接调用
        //    vm 转为 *anyopaque 传入，handler 内部通过 @ptrCast 恢复为 *VM
        const vm_ptr: *anyopaque = @ptrCast(vm);
        return fn_dispatch.dispatch(vm_ptr, id, args);
    }
};
