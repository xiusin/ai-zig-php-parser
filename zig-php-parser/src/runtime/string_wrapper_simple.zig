const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const VM = @import("vm.zig").VM;

/// StringWrapper - 简化版，方法直接调用stdlib函数
pub const StringWrapper = struct {
    vm: *VM,
    value: Value,

    pub fn init(vm: *VM, value: Value) StringWrapper {
        return .{ .vm = vm, .value = value };
    }

    /// 转大写 - 调用strtoupper
    pub fn toUpper(self: *StringWrapper) !Value {
        const args = [_]Value{self.value};
        return self.vm.callFunctionByName("strtoupper", &args);
    }

    /// 转小写 - 调用strtolower
    pub fn toLower(self: *StringWrapper) !Value {
        const args = [_]Value{self.value};
        return self.vm.callFunctionByName("strtolower", &args);
    }

    /// 去除空白 - 调用trim
    pub fn trim(self: *StringWrapper) !Value {
        const args = [_]Value{self.value};
        return self.vm.callFunctionByName("trim", &args);
    }

    /// 字符串长度 - 调用strlen
    pub fn length(self: *StringWrapper) !Value {
        const args = [_]Value{self.value};
        return self.vm.callFunctionByName("strlen", &args);
    }

    /// 字符串替换 - 调用str_replace
    pub fn replace(self: *StringWrapper, search: Value, replacement: Value) !Value {
        const args = [_]Value{ search, replacement, self.value };
        return self.vm.callFunctionByName("str_replace", &args);
    }

    /// 子字符串 - 调用substr
    pub fn substring(self: *StringWrapper, start: Value, len: ?Value) !Value {
        if (len) |l| {
            const args = [_]Value{ self.value, start, l };
            return self.vm.callFunctionByName("substr", &args);
        } else {
            const args = [_]Value{ self.value, start };
            return self.vm.callFunctionByName("substr", &args);
        }
    }

    /// 查找位置 - 调用strpos
    pub fn indexOf(self: *StringWrapper, needle: Value) !Value {
        const args = [_]Value{ self.value, needle };
        return self.vm.callFunctionByName("strpos", &args);
    }

    /// 分割字符串 - 调用explode
    pub fn split(self: *StringWrapper, delimiter: Value) !Value {
        const args = [_]Value{ delimiter, self.value };
        return self.vm.callFunctionByName("explode", &args);
    }
};
