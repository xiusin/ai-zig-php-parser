const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const VM = @import("vm.zig").VM;

/// String类型的内置方法 - 直接调用stdlib函数
pub const StringMethods = struct {
    /// 转大写
    pub fn toUpper(vm: *VM, target: Value) !Value {
        const args = [_]Value{target};
        return vm.callFunctionByName("strtoupper", &args);
    }

    /// 转小写
    pub fn toLower(vm: *VM, target: Value) !Value {
        const args = [_]Value{target};
        return vm.callFunctionByName("strtolower", &args);
    }

    /// 去除空白
    pub fn trim(vm: *VM, target: Value) !Value {
        const args = [_]Value{target};
        return vm.callFunctionByName("trim", &args);
    }

    /// 字符串长度
    pub fn length(vm: *VM, target: Value) !Value {
        const args = [_]Value{target};
        return vm.callFunctionByName("strlen", &args);
    }

    /// 字符串替换
    pub fn replace(vm: *VM, target: Value, method_args: []const Value) !Value {
        if (method_args.len < 2) return error.InvalidArgumentCount;
        const args = [_]Value{ method_args[0], method_args[1], target };
        return vm.callFunctionByName("str_replace", &args);
    }

    /// 子字符串
    pub fn substring(vm: *VM, target: Value, method_args: []const Value) !Value {
        if (method_args.len == 0) return error.InvalidArgumentCount;
        if (method_args.len == 1) {
            const args = [_]Value{ target, method_args[0] };
            return vm.callFunctionByName("substr", &args);
        } else {
            const args = [_]Value{ target, method_args[0], method_args[1] };
            return vm.callFunctionByName("substr", &args);
        }
    }

    /// 查找位置
    pub fn indexOf(vm: *VM, target: Value, method_args: []const Value) !Value {
        if (method_args.len == 0) return error.InvalidArgumentCount;
        const args = [_]Value{ target, method_args[0] };
        return vm.callFunctionByName("strpos", &args);
    }

    /// 分割字符串
    pub fn split(vm: *VM, target: Value, method_args: []const Value) !Value {
        if (method_args.len == 0) return error.InvalidArgumentCount;
        const args = [_]Value{ method_args[0], target };
        return vm.callFunctionByName("explode", &args);
    }
};

/// Array类型的内置方法 - 直接调用stdlib函数
pub const ArrayMethods = struct {
    /// 追加元素
    pub fn push(vm: *VM, target: Value, method_args: []const Value) !Value {
        var args = try std.ArrayList(Value).initCapacity(vm.allocator, 1 + method_args.len);
        defer args.deinit(vm.allocator);
        try args.append(vm.allocator, target);
        for (method_args) |arg| {
            try args.append(vm.allocator, arg);
        }
        return vm.callFunctionByName("array_push", args.items);
    }

    /// 弹出元素
    pub fn pop(vm: *VM, target: Value) !Value {
        const args = [_]Value{target};
        return vm.callFunctionByName("array_pop", &args);
    }

    /// 移除首元素
    pub fn shift(vm: *VM, target: Value) !Value {
        const args = [_]Value{target};
        return vm.callFunctionByName("array_shift", &args);
    }

    /// 开头插入
    pub fn unshift(vm: *VM, target: Value, method_args: []const Value) !Value {
        var args = try std.ArrayList(Value).initCapacity(vm.allocator, 1 + method_args.len);
        defer args.deinit(vm.allocator);
        try args.append(vm.allocator, target);
        for (method_args) |arg| {
            try args.append(vm.allocator, arg);
        }
        return vm.callFunctionByName("array_unshift", args.items);
    }

    /// 合并数组
    pub fn merge(vm: *VM, target: Value, method_args: []const Value) !Value {
        var args = try std.ArrayList(Value).initCapacity(vm.allocator, 1 + method_args.len);
        defer args.deinit(vm.allocator);
        try args.append(vm.allocator, target);
        for (method_args) |arg| {
            try args.append(vm.allocator, arg);
        }
        return vm.callFunctionByName("array_merge", args.items);
    }

    /// 反转数组
    pub fn reverse(vm: *VM, target: Value) !Value {
        const args = [_]Value{target};
        return vm.callFunctionByName("array_reverse", &args);
    }

    /// 获取键
    pub fn keys(vm: *VM, target: Value) !Value {
        const args = [_]Value{target};
        return vm.callFunctionByName("array_keys", &args);
    }

    /// 获取值
    pub fn values(vm: *VM, target: Value) !Value {
        const args = [_]Value{target};
        return vm.callFunctionByName("array_values", &args);
    }

    /// 过滤数组
    pub fn filter(vm: *VM, target: Value, method_args: []const Value) !Value {
        var args = try std.ArrayList(Value).initCapacity(vm.allocator, 1 + method_args.len);
        defer args.deinit(vm.allocator);
        try args.append(vm.allocator, target);
        for (method_args) |arg| {
            try args.append(vm.allocator, arg);
        }
        return vm.callFunctionByName("array_filter", args.items);
    }

    /// 映射数组
    pub fn map(vm: *VM, target: Value, method_args: []const Value) !Value {
        var args = try std.ArrayList(Value).initCapacity(vm.allocator, 1 + method_args.len);
        defer args.deinit(vm.allocator);
        for (method_args) |arg| {
            try args.append(vm.allocator, arg);
        }
        try args.append(vm.allocator, target);
        return vm.callFunctionByName("array_map", args.items);
    }

    /// 数组长度
    pub fn count(vm: *VM, target: Value) !Value {
        _ = vm; // 未使用 vm 参数
        if (target.getTag() == .array) {
            const array_count = target.getAsArray().data.count();
            return Value.initInt(@intCast(array_count));
        }
        return Value.initInt(0);
    }

    /// 检查数组是否为空
    pub fn isEmpty(vm: *VM, target: Value) !Value {
        _ = vm; // 未使用 vm 参数
        if (target.getTag() == .array) {
            const array_count = target.getAsArray().data.count();
            return Value.initBool(array_count == 0);
        }
        return Value.initBool(false);
    }
};
